import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/services/cricket_services.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/async_value.dart';
import '../common/match_parsing.dart';
import '../search/search_index.dart';
import 'home_models.dart';

String homeErrorMessage(Object e, String fallback) {
  if (e is ApiException) {
    return e.message.trim().isEmpty ? fallback : friendlyError(e);
  }
  return 'An unexpected error occurred';
}

/// The current over of the featured live match (from match-by-id).
class FeaturedOver {
  const FeaturedOver(this.matchId, this.balls, this.overNumber);
  final String matchId;
  final List<String> balls;
  final int? overNumber;
}

/// Merges `/match/live` with the in-progress items of `/match/recent`
/// (deduped by id, live list first), keeping only matches whose `status`
/// says they are in progress.
List<MatchSummary> mergeLive(
  List<MatchSummary> live,
  List<MatchSummary> recent,
) {
  final seen = <String>{};
  return [
    for (final m in [...live, ...recent])
      if (m.isInProgress && (m.id.isEmpty || seen.add(m.id))) m,
  ];
}

/// Finished matches, newest start first.
List<MatchSummary> latestResults(List<MatchSummary> recent) {
  final out = [
    for (final m in recent)
      if (m.isFinished) m,
  ];
  out.sort((a, b) {
    final x = a.startTime, y = b.startTime;
    if (x == null || y == null) return 0;
    return y.compareTo(x);
  });
  return out;
}

/// Upcoming matches (by `status`), soonest first; unparseable dates last.
List<MatchSummary> startingSoon(List<MatchSummary> upcoming) {
  final out = [
    for (final m in upcoming)
      if (m.isUpcoming) m,
  ];
  out.sort((a, b) {
    final x = a.startTime, y = b.startTime;
    if (x == null) return y == null ? 0 : 1;
    if (y == null) return -1;
    return x.compareTo(y);
  });
  return out;
}

/// Owns all Home data; the screen owns the visibility-aware poller and
/// calls [poll] (every 30 s while Home is visible and the app is in the
/// foreground).
///
/// One poll = `/match/live` + `/match/recent` (+ match-by-id for the
/// featured live card's current over); `/match/upcoming` refreshes every
/// [upcomingEveryNPolls] polls. Requests never overlap: polls and
/// pull-to-refresh join the one in flight.
class HomeController extends ChangeNotifier {
  HomeController({MatchService? matchService})
    : _match = matchService ?? MatchService.instance {
    upcoming = Loadable(() async {
      final list = parseMatchList((await _match.getUpcomingMatches()).data);
      SearchIndex.instance.addMatches(list);
      return list;
    });
    upcomingSeries = Loadable(
      () async =>
          parseUpcomingSeriesList((await _match.getUpcomingSeries()).data),
    );
  }

  final MatchService _match;

  static const upcomingEveryNPolls = 4;

  /// Matches in progress (live + stumps / breaks), provider order.
  List<MatchSummary> liveMatches = const [];

  /// Finished matches from `/match/recent`, newest first.
  List<MatchSummary> results = const [];
  FeaturedOver? featuredOver;

  bool loading = true;

  /// Both live sources failed (nothing to show).
  String? error;

  /// `/match/recent` failed while live data loaded.
  String? resultsError;
  bool isRefreshing = false;

  /// Time of the last successful live refresh.
  DateTime? lastUpdated;
  Future<void>? _liveInFlight;
  int _polls = 0;

  /// Fingerprint of the last payloads: silent polls that return identical
  /// data don't notify (no rebuild).
  int? _liveSignature;

  /// Drives only the full-screen skeleton, so data updates don't rebuild
  /// the whole Home tree.
  final ValueNotifier<bool> loadingListenable = ValueNotifier<bool>(true);
  bool get liveRequestInFlight => _liveInFlight != null;

  late final Loadable<List<MatchSummary>> upcoming;
  late final Loadable<List<UpcomingSeriesItem>> upcomingSeries;

  Timer? _secondaryTimer;
  bool _disposed = false;

  /// Initial fetch: scores first, the series strip 150 ms later.
  void start() {
    _restoreCache().whenComplete(() {
      if (!_disposed) fetchLive(showLoading: liveMatches.isEmpty && results.isEmpty);
    });
    upcoming.load();
    _secondaryTimer = Timer(const Duration(milliseconds: 150), () {
      if (_disposed) return;
      upcomingSeries.load();
    });
  }

  static const _cacheKey = 'home_cache_v1';

  /// Shows the last successful scores instantly (stale-while-revalidate) so a
  /// cold start never waits on the network to paint Home.
  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final live = parseMatchList(m['live']);
      final recent = parseMatchList(m['recent']);
      if (live.isEmpty && recent.isEmpty) return;
      liveMatches = mergeLive(live, recent);
      results = latestResults(recent);
      loading = false;
      loadingListenable.value = false;
      _notify();
    } catch (_) {}
  }

  Future<void> _saveCache(Object? live, Object? recent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({'live': live, 'recent': recent}));
    } catch (_) {}
  }

  /// [showLoading]: full-screen skeleton (initial load / Try again).
  /// [manual]: pull-to-refresh (drives [isRefreshing]; also refreshes the
  /// upcoming list). Never stacks requests: callers join the in-flight one.
  Future<void> fetchLive({bool showLoading = false, bool manual = false}) {
    final inFlight = _liveInFlight;
    if (inFlight != null) {
      if (manual && !isRefreshing) {
        isRefreshing = true;
        _notify();
        return inFlight.whenComplete(() {
          isRefreshing = false;
          _notify();
        });
      }
      return inFlight;
    }
    if (manual) upcoming.load(silent: true);
    final f = _doFetchLive(showLoading: showLoading, manual: manual);
    _liveInFlight = f;
    return f.whenComplete(() => _liveInFlight = null);
  }

  Future<ApiResponse?> _try(Future<ApiResponse> Function() call) async {
    try {
      return await call();
    } catch (e) {
      _lastError = e;
      return null;
    }
  }

  Object? _lastError;

  Future<void> _doFetchLive({
    required bool showLoading,
    required bool manual,
  }) async {
    if (showLoading) {
      loading = true;
      loadingListenable.value = true;
    } else if (manual) {
      isRefreshing = true;
    }
    final silent = !showLoading && !manual;
    if (!silent) {
      error = null;
      _notify();
    }
    var changed = !silent;
    _lastError = null;
    final res = await Future.wait([
      _try(_match.getLiveMatches),
      _try(_match.getRecentMatches),
    ]);
    if (_disposed) return;
    final liveRes = res[0], recentRes = res[1];
    if (liveRes == null && recentRes == null) {
      // A failed background poll keeps what is on screen.
      if (!silent || (liveMatches.isEmpty && results.isEmpty)) {
        error = homeErrorMessage(_lastError!, 'Scores did not load');
        changed = true;
      }
    } else {
      lastUpdated = DateTime.now();
      if (liveRes != null && recentRes != null) {
        unawaited(_saveCache(liveRes.data, recentRes.data));
      }
      final sig = Object.hash(
        liveRes == null ? null : jsonEncode(liveRes.data),
        recentRes == null ? null : jsonEncode(recentRes.data),
      );
      final newResultsError = recentRes == null
          ? homeErrorMessage(_lastError!, 'Results did not load')
          : null;
      if (sig != _liveSignature ||
          error != null ||
          newResultsError != resultsError) {
        _liveSignature = sig;
        final live = liveRes == null
            ? const <MatchSummary>[]
            : parseMatchList(liveRes.data);
        final recent = recentRes == null
            ? const <MatchSummary>[]
            : parseMatchList(recentRes.data);
        liveMatches = mergeLive(live, recent);
        if (recentRes != null) results = latestResults(recent);
        resultsError = newResultsError;
        SearchIndex.instance
          ..addMatches(live)
          ..addMatches(recent);
        changed = true;
      }
      error = null;
    }
    if (!_disposed) {
      loading = false;
      loadingListenable.value = false;
      if (manual) isRefreshing = false;
      if (changed) _notify();
    }
    unawaited(_refreshFeaturedOver());
  }

  /// Current over for the first live match (one request per poll, only
  /// while a match is in play). Silent: no ball data = no strip.
  Future<void> _refreshFeaturedOver() async {
    final first = liveMatches.where((m) => m.isInPlay).firstOrNull;
    if (first == null || first.id.isEmpty) {
      if (featuredOver != null) {
        featuredOver = null;
        _notify();
      }
      return;
    }
    try {
      final res = await _match.getMatchById(first.id);
      if (_disposed) return;
      final data = J.map(res.data);
      final balls = [
        for (final b in J.maps(J.at(data, 'currentOver.balls')))
          if (J.text(b['value']) != null) J.text(b['value'])!,
      ];
      final next = balls.isEmpty
          ? null
          : FeaturedOver(
              first.id,
              balls,
              J.integer(J.at(data, 'currentOver.overNumber')),
            );
      final prev = featuredOver;
      final same =
          prev?.matchId == next?.matchId &&
          prev?.overNumber == next?.overNumber &&
          listEquals(prev?.balls, next?.balls);
      if (!same) {
        featuredOver = next;
        _notify();
      }
    } catch (_) {
      // Keep the previous strip; the card works without it.
    }
  }

  /// Auto-refresh tick: skipped while a request is already running.
  void poll() {
    if (_liveInFlight != null) return;
    _polls++;
    if (_polls % upcomingEveryNPolls == 0) upcoming.load(silent: true);
    fetchLive();
  }

  String? sectionError(Loadable l, String fallback) =>
      l.error == null ? null : homeErrorMessage(l.error!, fallback);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _secondaryTimer?.cancel();
    loadingListenable.dispose();
    upcoming.dispose();
    upcomingSeries.dispose();
    super.dispose();
  }
}
