import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/cricket_services.dart';
import 'live_poller.dart';
import 'match_detail_logic.dart';

/// State for the Commentary tab (RN CommentaryTabContent), hoisted out of the
/// widget so switching tabs does not drop loaded pages or refetch.
///  - first page on [ensureLoaded], then "Load more" appends (deduped);
///  - never issues two requests for the same page;
///  - while live, a silent page-1 refresh every 20s, but only while the user
///    is still on page 1 (a page-1 replace would wipe their loaded pages).
class CommentaryController extends ChangeNotifier {
  CommentaryController({
    required this.matchId,
    required this.service,
    required ValueListenable<bool> visibility,
    this.pageSize = commentaryPageSize,
    Duration pollInterval = const Duration(seconds: 20),
  }) {
    _poller = Poller(interval: pollInterval, task: () => _loadFirst(silent: true), visibility: visibility);
  }

  final String matchId;
  final MatchService service;
  final int pageSize;
  late final Poller _poller;

  bool loading = false;
  bool loadingMore = false;
  String? error;
  List<CommentaryBall> balls = const [];
  CommentaryPage? firstPage; // carries team names
  int page = 1;
  bool hasMore = true;
  bool started = false;

  CommentaryFilter filter = CommentaryFilter.all;
  String team = 'all';

  /// Derived — recomputed only when data / filters change (never in build).
  List<CommentaryBall> filtered = const [];
  List<CommentaryBall> visible = const []; // filtered ∩ ball-with-commentary
  List<String> teams = const [];

  bool _inFlight = false;
  int _gen = 0;
  bool _disposed = false;

  bool get hasData => balls.isNotEmpty;

  void ensureLoaded() {
    if (started) return;
    started = true;
    _loadFirst(silent: false);
  }

  /// Live polling — enable only while the tab is active and the match is live.
  void setPolling(bool on) => _poller.setEnabled(on);
  bool get isPolling => _poller.enabled;

  Future<void> retry() => _loadFirst(silent: false);

  Future<void> _loadFirst({required bool silent}) async {
    if (_inFlight || _disposed) return;
    // Skip the poll once the user has loaded further pages.
    if (silent && page != 1) return;
    _inFlight = true;
    final gen = ++_gen;
    if (!silent) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      final res = await service.getMatchCommentary(matchId, page: 1, perPage: pageSize);
      if (_disposed || gen != _gen) return;
      final p = CommentaryPage.fromJson(res.dataMap);
      if (silent && page != 1) return;
      firstPage = p;
      balls = mergeCommentary(const [], p.balls);
      page = 1;
      hasMore = commentaryHasMore(received: p.balls.length, page: 1, totalCount: p.totalCount, pageSize: pageSize);
      error = null;
      _recompute();
    } catch (e) {
      if (_disposed || gen != _gen) return;
      if (e is ApiException && e.isNotFound) {
        // Commentary genuinely doesn't exist yet for this match — quiet empty state, not an error.
        error = null;
        balls = const [];
        firstPage = null;
        hasMore = false;
        _recompute();
      } else if (!silent || balls.isEmpty) {
        error = friendlyError(e);
      }
    } finally {
      _inFlight = false;
      if (!_disposed && gen == _gen) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (_disposed || loadingMore || !hasMore || loading) return;
    if (_inFlight) return; // a page-1 poll is running; user can tap again
    _inFlight = true;
    final gen = ++_gen;
    final next = page + 1;
    loadingMore = true;
    _notify();
    try {
      final res = await service.getMatchCommentary(matchId, page: next, perPage: pageSize);
      if (_disposed || gen != _gen) return;
      final p = CommentaryPage.fromJson(res.dataMap, indexOffset: balls.length);
      balls = mergeCommentary(balls, p.balls);
      firstPage ??= p;
      page = next;
      hasMore = commentaryHasMore(received: p.balls.length, page: next, totalCount: p.totalCount, pageSize: pageSize);
      error = null;
      _recompute();
    } catch (e) {
      if (_disposed || gen != _gen) return;
      if (e is ApiException && e.isNotFound) {
        hasMore = false;
      } else {
        error = friendlyError(e);
      }
    } finally {
      _inFlight = false;
      if (!_disposed && gen == _gen) {
        loadingMore = false;
        _notify();
      }
    }
  }

  void setFilter(CommentaryFilter f) {
    if (f == filter) return;
    filter = f;
    _recompute();
    _notify();
  }

  void setTeam(String t) {
    if (t == team) return;
    team = t;
    _recompute();
    _notify();
  }

  void _recompute() {
    teams = uniqueInningsKeys(balls);
    filtered = filterCommentary(balls, team: team, filter: filter);
    visible = filtered.where((b) => b.isBallWithCommentary).toList(growable: false);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    super.dispose();
  }
}
