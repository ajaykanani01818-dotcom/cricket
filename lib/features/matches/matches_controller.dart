import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/services/cricket_services.dart';
import '../../core/utils/match_transform.dart';
import '../common/match_parsing.dart';

enum MatchesTab { live, upcoming, completed }

const completedPageSize = 10;

String matchesErrorMessage(Object e) =>
    e is ApiException && e.message.trim().isNotEmpty ? friendlyError(e) : 'Failed to load';

/// RN: `info ? info.page * info.perPage < info.total : newList.length >= PAGE_SIZE`.
bool computeHasMore(PageInfo? info, int received, {int pageSize = completedPageSize}) =>
    info != null ? info.page * info.perPage < info.total : received >= pageSize;

/// Per-tab state.
class TabData {
  List<MatchSummary> matches = const [];
  bool loading = true;
  String? error;
}

/// Ported from RN MatchesScreen state + fetchers.
class MatchesController extends ChangeNotifier {
  MatchesController({MatchService? service}) : _s = service ?? MatchService.instance;
  final MatchService _s;

  final Map<MatchesTab, TabData> tabs = {for (final t in MatchesTab.values) t: TabData()};
  TabData operator [](MatchesTab t) => tabs[t]!;

  bool refreshing = false;

  // Completed pagination.
  int completedPage = 1;
  bool completedHasMore = true;
  bool completedLoadingMore = false;

  /// Set when a load-more page fails: the list stays visible and the footer
  /// offers a retry (RN replaced the whole list with the error card).
  String? loadMoreError;

  // Generation counters: a refresh invalidates in-flight responses, so a slow
  // older page can never overwrite/append to newer data.
  final Map<MatchesTab, int> _gen = {for (final t in MatchesTab.values) t: 0};
  bool _disposed = false;

  int _bump(MatchesTab t) => _gen[t] = _gen[t]! + 1;

  void start() {
    fetchUpcoming();
    fetchLive();
    fetchCompleted();
  }

  Future<void> fetchUpcoming() => _run(MatchesTab.upcoming, () async => parseMatchList((await _s.getUpcomingMatches()).data));

  /// /match/live, falling back to /match/recent filtered to live matches.
  Future<void> fetchLive() => _run(MatchesTab.live, () async {
        try {
          return parseMatchList((await _s.getLiveMatches()).data);
        } catch (_) {
          return parseMatchList((await _s.getRecentMatches()).data).where((m) => m.isLive).toList();
        }
      });

  Future<void> _run(MatchesTab tab, Future<List<MatchSummary>> Function() load) async {
    final gen = _bump(tab);
    final d = this[tab];
    d.loading = true;
    d.error = null;
    _notify();
    try {
      final list = await load();
      if (_disposed || gen != _gen[tab]) return;
      d.matches = list;
    } catch (e) {
      if (_disposed || gen != _gen[tab]) return;
      d.error = matchesErrorMessage(e);
    } finally {
      if (!_disposed && gen == _gen[tab]) {
        d.loading = false;
        _notify();
      }
    }
  }

  /// First page of completed matches (initial load / retry / refresh).
  Future<void> fetchCompleted() async {
    final gen = _bump(MatchesTab.completed);
    final d = this[MatchesTab.completed];
    d.loading = true;
    d.error = null;
    completedLoadingMore = false;
    loadMoreError = null;
    _notify();
    try {
      final res = await _s.getCompletedMatches(page: 1, perPage: completedPageSize);
      final list = parseMatchList(res.data);
      if (_disposed || gen != _gen[MatchesTab.completed]) return;
      d.matches = list;
      completedPage = 1;
      completedHasMore = computeHasMore(res.pageInfo, list.length);
    } catch (e) {
      if (_disposed || gen != _gen[MatchesTab.completed]) return;
      d.error = matchesErrorMessage(e);
    } finally {
      if (!_disposed && gen == _gen[MatchesTab.completed]) {
        d.loading = false;
        _notify();
      }
    }
  }

  /// Next completed page. No-op while a page (or the first page) is loading,
  /// when there is nothing more, or when the list is empty — so scroll events
  /// can call it freely without firing duplicate page loads.
  Future<void> loadMoreCompleted() async {
    final d = this[MatchesTab.completed];
    if (completedLoadingMore || !completedHasMore || d.loading || d.matches.isEmpty || d.error != null) return;
    final gen = _gen[MatchesTab.completed]!;
    final next = completedPage + 1;
    completedLoadingMore = true;
    loadMoreError = null;
    _notify();
    try {
      final res = await _s.getCompletedMatches(page: next, perPage: completedPageSize);
      final list = parseMatchList(res.data);
      if (_disposed || gen != _gen[MatchesTab.completed]) return;
      // De-dupe by id in case the server's pages shifted between requests.
      final seen = {for (final m in d.matches) m.id};
      d.matches = [...d.matches, ...list.where((m) => m.id.isEmpty || seen.add(m.id))];
      completedPage = next;
      completedHasMore = computeHasMore(res.pageInfo, list.length);
    } catch (e) {
      if (_disposed || gen != _gen[MatchesTab.completed]) return;
      loadMoreError = matchesErrorMessage(e);
    } finally {
      if (!_disposed && gen == _gen[MatchesTab.completed]) {
        completedLoadingMore = false;
        _notify();
      }
    }
  }

  /// Pull-to-refresh: all three tabs, pagination reset.
  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    completedPage = 1;
    completedHasMore = true;
    _notify();
    try {
      await Future.wait([fetchUpcoming(), fetchLive(), fetchCompleted()]);
    } finally {
      refreshing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
