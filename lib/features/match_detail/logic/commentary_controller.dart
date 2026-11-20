import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/cricket_services.dart';
import 'live_poller.dart';
import 'match_detail_logic.dart';

/// State for the Commentary tab (RN CommentaryTabContent), hoisted out of the
/// widget so switching tabs does not drop loaded pages or refetch.
///  - first page on [ensureLoaded], then "Load more" appends (deduped);
///  - never issues two requests for the same page;
///  - while live, a silent page-1 refresh merges new balls in front of the
///    loaded pages (deduped by innings + over + ball + timestamp);
///  - scroll-position rule (PRD §8.4): while [holdNew] is on (the user has
///    scrolled into the feed) new balls are held back and counted in
///    [pendingCount]; [showPending] applies them (the screen then scrolls to
///    the top of the feed), so a refresh never moves what the user reads.
class CommentaryController extends ChangeNotifier {
  CommentaryController({
    required this.matchId,
    required this.service,
    required ValueListenable<bool> visibility,
    this.pageSize = commentaryPageSize,
    Duration pollInterval = const Duration(seconds: 10),
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

  /// See class doc.
  bool holdNew = false;

  /// New deliveries waiting behind the "N new balls" pill.
  int pendingCount = 0;
  CommentaryPage? _pending;

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
      if (silent && balls.isNotEmpty) {
        final known = {for (final b in balls) b.key};
        final fresh = p.balls.where((b) => !known.contains(b.key)).toList();
        if (fresh.isEmpty) {
          _pending = null;
          pendingCount = 0;
          return; // unchanged: no rebuild
        }
        if (holdNew) {
          _pending = p;
          pendingCount = fresh.where((b) => b.type == 'ball').length;
          if (pendingCount == 0) pendingCount = fresh.length;
          return;
        }
      }
      _apply(p);
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

  void _apply(CommentaryPage p) {
    firstPage = p;
    _pending = null;
    pendingCount = 0;
    if (page > 1 && balls.isNotEmpty) {
      // Keep loaded pages: new page-1 items go in front.
      balls = mergeCommentary(p.balls, balls);
    } else {
      balls = mergeCommentary(const [], p.balls);
      page = 1;
      hasMore = commentaryHasMore(received: p.balls.length, page: 1, totalCount: p.totalCount, pageSize: pageSize);
    }
    error = null;
    _recompute();
  }

  /// Applies held-back balls (the "N new balls" pill).
  void showPending() {
    final p = _pending;
    if (p == null || _disposed) return;
    _apply(p);
    _notify();
  }

  /// The screen reports whether the user is reading further down the feed.
  void setHold(bool hold) {
    if (hold == holdNew) return;
    holdNew = hold;
    if (!hold && _pending != null) showPending();
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
    visible = filtered
        .where((b) => b.isBallWithCommentary || (filter == CommentaryFilter.all && b.isInfo))
        .toList(growable: false);
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
