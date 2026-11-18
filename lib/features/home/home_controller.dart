import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/services/cricket_services.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/async_value.dart';
import '../common/match_parsing.dart';
import 'home_models.dart';

/// Format filter for Top Players (RN FORMAT_OPTIONS; default MATCH_TYPE[0] = ODI).
const homeFormatOptions = [('ODI', 'ODI'), ('TEST', 'Test'), ('T20', 'T20')];

String homeErrorMessage(Object e, String fallback) {
  if (e is ApiException) return e.message.trim().isEmpty ? fallback : friendlyError(e);
  return 'An unexpected error occurred';
}

/// Ported from RN `useHomeData`. Owns all Home data; the screen owns the
/// visibility-aware poller and calls [poll].
class HomeController extends ChangeNotifier {
  HomeController({MatchService? matchService, RankingService? rankingService})
      : _match = matchService ?? MatchService.instance,
        _rank = rankingService ?? RankingService.instance {
    upcoming = Loadable(() async => parseMatchList((await _match.getUpcomingMatches()).data));
    rankings = Loadable(_loadRankings);
    upcomingSeries = Loadable(() async => parseUpcomingSeriesList((await _match.getUpcomingSeries()).data));
  }

  final MatchService _match;
  final RankingService _rank;

  // ── "Live" matches (RN uses /match/recent for this section) ──
  List<MatchSummary> liveMatches = const [];
  bool loading = true;
  String? error;
  bool isRefreshing = false;
  Future<void>? _liveInFlight;

  /// Fingerprint of the last /match/recent payload: silent polls that return
  /// identical data don't notify (no rebuild of the Live section).
  int? _liveSignature;

  /// Drives only the full-screen shimmer, so data updates don't rebuild the
  /// whole Home tree.
  final ValueNotifier<bool> loadingListenable = ValueNotifier<bool>(true);
  bool get liveRequestInFlight => _liveInFlight != null;

  late final Loadable<List<MatchSummary>> upcoming;
  late final Loadable<TopPlayers> rankings;
  late final Loadable<List<UpcomingSeriesItem>> upcomingSeries;
  String matchType = homeFormatOptions.first.$1;
  final String gender = 'MALE';

  Timer? _secondaryTimer;
  bool _disposed = false;

  /// Initial fetch — critical data first, secondary data staggered 150ms
  /// (RN: avoid saturating the network on slow connections).
  void start() {
    fetchLive(showLoading: true);
    upcoming.load();
    _secondaryTimer = Timer(const Duration(milliseconds: 150), () {
      if (_disposed) return;
      rankings.load();
      upcomingSeries.load();
      // RN also fetched hero-banner top batters here, but HomeScreen no longer
      // renders HeroBanner — dropped to save 3 requests per launch.
    });
  }

  /// [showLoading]: full-screen shimmer (initial load / Try Again).
  /// [manual]: pull-to-refresh (drives [isRefreshing]).
  /// Never stacks requests: while one is in flight every caller joins it.
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
    final f = _doFetchLive(showLoading: showLoading, manual: manual);
    _liveInFlight = f;
    return f.whenComplete(() => _liveInFlight = null);
  }

  Future<void> _doFetchLive({required bool showLoading, required bool manual}) async {
    if (showLoading) {
      loading = true;
      loadingListenable.value = true;
    } else if (manual) {
      isRefreshing = true;
    }
    final silent = !showLoading && !manual;
    if (!silent) {
      error = null;
      _notify(); // silent polls have no visible "start" state
    }
    var changed = !silent;
    try {
      final res = await _match.getRecentMatches();
      if (_disposed) return;
      final sig = jsonEncode(res.data).hashCode;
      if (sig != _liveSignature || error != null) {
        _liveSignature = sig;
        liveMatches = parseMatchList(res.data);
        changed = true;
      }
      error = null;
    } catch (e) {
      if (_disposed) return;
      // A failed background poll keeps the cards already on screen instead of
      // flashing an error (RN replaced them with the error card).
      if (!silent || liveMatches.isEmpty) {
        error = homeErrorMessage(e, 'Failed to fetch matches');
        changed = true;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        loadingListenable.value = false;
        if (manual) isRefreshing = false;
        if (changed) _notify();
      }
    }
  }

  /// Auto-refresh tick: skipped while a request is already running.
  void poll() {
    if (_liveInFlight != null) return;
    fetchLive();
  }

  Future<TopPlayers> _loadRankings() async {
    final type = matchType;
    final r = await Future.wait([
      _rank.getPlayerRankings(gender: gender, matchType: type, type: 'BATSMAN'),
      _rank.getPlayerRankings(gender: gender, matchType: type, type: 'BOWLER'),
      _rank.getPlayerRankings(gender: gender, matchType: type, type: 'ALL_ROUNDER'),
    ]);
    return TopPlayers(batters: parseTopPlayers(r[0].data), bowlers: parseTopPlayers(r[1].data), allRounders: parseTopPlayers(r[2].data));
  }

  void setMatchType(String type) {
    if (type == matchType) return;
    matchType = type;
    _notify();
    // Loadable ignores the stale response if the user switches again quickly.
    rankings.load();
  }

  String? sectionError(Loadable l, String fallback) => l.error == null ? null : homeErrorMessage(l.error!, fallback);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _secondaryTimer?.cancel();
    loadingListenable.dispose();
    upcoming.dispose();
    rankings.dispose();
    upcomingSeries.dispose();
    super.dispose();
  }
}
