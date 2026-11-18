import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/services/cricket_services.dart';
import 'series_models.dart';

/// State for ONE status tab of the Series list (ONGOING / UPCOMING / COMPLETED).
///
/// Each tab owns its own controller, so a slow ONGOING response can never land
/// in the COMPLETED list. Inside a tab, a generation counter discards responses
/// that were overtaken by a newer refresh (and load-more pages that started
/// before a refresh).
class SeriesTabController extends ChangeNotifier {
  SeriesTabController(this.status, {this.service, this.perPage = 24});

  final String status;
  final int perPage;

  /// Defaults to [MatchService.instance] (resolved per call so tests can swap it).
  final MatchService? service;
  MatchService get _svc => service ?? MatchService.instance;

  List<SeriesItem> items = const [];
  String? error;
  bool loading = false;
  bool fetched = false;
  bool loadingMore = false;
  String? loadMoreError;
  bool hasMore = false;
  int _page = 0;
  int _gen = 0;
  bool _disposed = false;

  /// RN: shimmer until the tab has been fetched once.
  bool get showShimmer => !fetched && error == null;

  bool _computeHasMore(ApiResponse res, int page, int received) {
    if (received == 0) return false;
    final info = res.pageInfo;
    if (info != null && info.totalPages > 0) return page < info.totalPages;
    return received >= perPage;
  }

  /// Loads page 1. Without [force] it is a no-op once fetched (RN fetchedTabsRef)
  /// or while a page-1 request is already in flight.
  Future<void> load({bool force = false}) async {
    if (!force && (fetched || loading)) return;
    final gen = ++_gen;
    loading = true;
    loadingMore = false;
    loadMoreError = null;
    error = null;
    _notify();
    try {
      final res = await _svc.getSeries(status: status, page: 1, perPage: perPage);
      if (_disposed || gen != _gen) return;
      final list = parseSeriesList(res.data);
      final seen = <String>{};
      items = [for (final s in list) if (seen.add(s.id)) s];
      _page = 1;
      hasMore = _computeHasMore(res, 1, list.length);
      fetched = true;
    } catch (e) {
      if (_disposed || gen != _gen) return;
      error = friendlyError(e);
    } finally {
      if (!_disposed && gen == _gen) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> refresh() => load(force: true);

  /// Next page for infinite scroll. Never runs twice at once, never past the last page.
  Future<void> loadMore() async {
    if (!fetched || loading || loadingMore || !hasMore) return;
    final gen = _gen;
    final nextPage = _page + 1;
    loadingMore = true;
    loadMoreError = null;
    _notify();
    try {
      final res = await _svc.getSeries(status: status, page: nextPage, perPage: perPage);
      if (_disposed || gen != _gen) return;
      final list = parseSeriesList(res.data);
      final seen = {for (final s in items) s.id};
      final fresh = [for (final s in list) if (seen.add(s.id)) s];
      items = [...items, ...fresh];
      _page = nextPage;
      // A page with nothing new means the server is repeating itself — stop.
      hasMore = fresh.isNotEmpty && _computeHasMore(res, nextPage, list.length);
    } catch (e) {
      if (_disposed || gen != _gen) return;
      loadMoreError = friendlyError(e);
    } finally {
      if (!_disposed && gen == _gen) {
        loadingMore = false;
        _notify();
      }
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

/// Series detail sub-views, in pager order (RN VIEW_ORDER).
enum SeriesView { fixtures, points, stats, squads }

class SeriesViewState {
  Object? data; // parsed view-model
  String? error;
  bool loading = false;
  bool fetched = false;
  int gen = 0;

  bool get showShimmer => loading && !fetched;
}

/// Per-view loading for Series Detail. Each view loads once per series;
/// switching back reuses it (pull/retry use force). 404 / "doesn't exist"
/// → "not available" (coming soon) instead of a technical error.
class SeriesDetailController extends ChangeNotifier {
  SeriesDetailController({required this.seriesId, this.seriesName, this.service});

  String seriesId;
  String? seriesName;
  final MatchService? service;
  MatchService get _svc => service ?? MatchService.instance;
  bool _disposed = false;

  final Map<SeriesView, SeriesViewState> _states = {for (final v in SeriesView.values) v: SeriesViewState()};

  /// null until squads load (RN squadCount).
  int? squadCount;

  SeriesViewState state(SeriesView v) => _states[v]!;

  /// RN: reset everything when the route's seriesId changes.
  void resetFor(String newSeriesId, String? name) {
    seriesId = newSeriesId;
    seriesName = name;
    for (final v in SeriesView.values) {
      final old = _states[v]!;
      _states[v] = SeriesViewState()..gen = old.gen + 1;
    }
    squadCount = null;
    _notify();
  }

  Future<ApiResponse> _fetch(SeriesView v) => switch (v) {
        SeriesView.fixtures => _svc.getSeriesFixtures(seriesId),
        SeriesView.points => _svc.getSeriesPointsTable(seriesId),
        SeriesView.stats => _svc.getSeriesStats(seriesId),
        SeriesView.squads => _svc.getSeriesSquads(seriesId),
      };

  Object _parse(SeriesView v, dynamic data) => switch (v) {
        SeriesView.fixtures => parseSeriesFixtures(data, seriesTitle: seriesName),
        SeriesView.points => parsePointsTable(data),
        SeriesView.stats => parseSeriesStats(data),
        SeriesView.squads => parseSquads(data),
      };

  Object _comingSoon(SeriesView v) => switch (v) {
        SeriesView.fixtures => const <SeriesFixture>[],
        SeriesView.points => const <PointsGroup>[],
        SeriesView.stats => const SeriesStatsData(comingSoon: true),
        SeriesView.squads => const <SquadTeam>[],
      };

  Future<void> load(SeriesView v, {bool force = false}) async {
    if (seriesId.isEmpty) return;
    final s = _states[v]!;
    if (!force && (s.fetched || s.loading)) return;
    final gen = ++s.gen;
    final requestSeriesId = seriesId;
    bool stale() => _disposed || _states[v] != s || gen != s.gen || requestSeriesId != seriesId;
    s.loading = true;
    s.error = null;
    _notify();
    try {
      final res = await _fetch(v);
      if (stale()) return;
      s.data = _parse(v, res.data);
      s.fetched = true;
      if (v == SeriesView.squads) squadCount = (s.data as List).length;
    } catch (e) {
      if (stale()) return;
      if (e is ApiException && e.isNotFound) {
        // Data genuinely not published yet for this series — quiet empty state.
        s.data = _comingSoon(v);
        s.fetched = true;
        s.error = null;
      } else {
        s.error = friendlyError(e);
      }
    } finally {
      if (!stale()) {
        s.loading = false;
        _notify();
      }
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
