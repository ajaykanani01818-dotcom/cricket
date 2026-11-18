import 'dart:async';

import 'package:crickbex/features/series/series_controllers.dart';
import 'package:crickbex/features/series/series_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'series_test_helpers.dart';

void main() {
  group('SeriesTabController', () {
    test('loads page 1 once, sends status/page/perPage', () async {
      final api = FakeApi((req) => jsonResponse(seriesPage('ONGOING', 0, 24, total: 1000)));
      final c = SeriesTabController('ONGOING', service: api.service);
      expect(c.showShimmer, isTrue);
      await Future.wait([c.load(), c.load()]); // concurrent duplicate is ignored
      await c.load(); // already fetched → no-op
      expect(api.requests, hasLength(1));
      final q = api.requests.single.queryParameters;
      expect(q, {'page': '1', 'perPage': '24', 'status': 'ONGOING'});
      expect(c.items, hasLength(24));
      expect(c.fetched, isTrue);
      expect(c.showShimmer, isFalse);
      expect(c.hasMore, isTrue);
    });

    test('loadMore appends, dedupes, never duplicates a page, stops at last page', () async {
      final pending = <int, Completer<http.Response>>{};
      final api = FakeApi((req) {
        final page = int.parse(req.url.queryParameters['page']!);
        if (page == 1) return jsonResponse(seriesPage('COMPLETED', 0, 24, total: 50, page: 1));
        return (pending[page] = Completer<http.Response>()).future;
      });
      final c = SeriesTabController('COMPLETED', service: api.service);
      await c.load();
      final f1 = c.loadMore();
      final f2 = c.loadMore(); // in flight → ignored
      await Future<void>.delayed(Duration.zero);
      expect(api.count((u) => u.queryParameters['page'] == '2'), 1);
      // page 2 overlaps one id from page 1 (dedupe)
      pending[2]!.complete(jsonResponse(seriesPage('COMPLETED', 23, 24, total: 50, page: 2)));
      await Future.wait([f1, f2]);
      expect(c.items, hasLength(47));
      expect(c.items.map((e) => e.id).toSet(), hasLength(47));
      expect(c.hasMore, isTrue); // 2 < ceil(50/24)=3
      final f3 = c.loadMore();
      await Future<void>.delayed(Duration.zero);
      pending[3]!.complete(jsonResponse(seriesPage('COMPLETED', 47, 3, total: 50, page: 3)));
      await f3;
      expect(c.items, hasLength(50));
      expect(c.hasMore, isFalse);
      await c.loadMore();
      expect(api.count((u) => u.queryParameters['page'] == '4'), 0);
    });

    test('without pageInfo: short page means last page; empty page stops', () async {
      final api = FakeApi((req) => jsonResponse({'data': (seriesPage('UPCOMING', 0, 5)['data'])}));
      final c = SeriesTabController('UPCOMING', service: api.service);
      await c.load();
      expect(c.hasMore, isFalse);
      final api2 = FakeApi((req) => jsonResponse({'data': []}));
      final c2 = SeriesTabController('UPCOMING', service: api2.service);
      await c2.load();
      expect(c2.items, isEmpty);
      expect(c2.hasMore, isFalse);
      expect(c2.fetched, isTrue);
    });

    test('error then retry recovers; loadMore error keeps items', () async {
      var fail = true;
      final api = FakeApi((req) {
        if (fail) return jsonResponse({'message': 'Boom'}, 500);
        final page = int.parse(req.url.queryParameters['page']!);
        if (page == 2) return jsonResponse({'message': 'Nope'}, 500);
        return jsonResponse(seriesPage('ONGOING', 0, 24, total: 1000));
      });
      final c = SeriesTabController('ONGOING', service: api.service);
      await c.load();
      expect(c.error, 'Boom');
      expect(c.showShimmer, isFalse);
      fail = false;
      await c.load(force: true);
      expect(c.error, isNull);
      expect(c.items, hasLength(24));
      await c.loadMore();
      expect(c.loadMoreError, 'Nope');
      expect(c.items, hasLength(24));
      expect(c.loadingMore, isFalse);
    });

    test('refresh overtakes an in-flight load-more (stale page dropped)', () async {
      Completer<http.Response>? page2;
      var refreshed = false;
      final api = FakeApi((req) {
        final page = req.url.queryParameters['page'];
        if (page == '2') return (page2 = Completer<http.Response>()).future;
        return jsonResponse(seriesPage('ONGOING', refreshed ? 100 : 0, 24, total: 1000));
      });
      final c = SeriesTabController('ONGOING', service: api.service);
      await c.load();
      final more = c.loadMore();
      await Future<void>.delayed(Duration.zero);
      refreshed = true;
      await c.refresh();
      page2!.complete(jsonResponse(seriesPage('ONGOING', 24, 24)));
      await more;
      expect(c.items.first.id, 'ONGOING-100');
      expect(c.items, hasLength(24));
      expect(c.loadingMore, isFalse);
    });

    test('response after dispose is ignored', () async {
      final done = Completer<http.Response>();
      final api = FakeApi((req) => done.future);
      final c = SeriesTabController('ONGOING', service: api.service);
      final f = c.load();
      c.dispose();
      done.complete(jsonResponse(seriesPage('ONGOING', 0, 3)));
      await f; // must not throw (notifyListeners after dispose)
      expect(c.items, isEmpty);
    });
  });

  group('SeriesDetailController', () {
    test('loads each view once, parses, sets squad count', () async {
      final api = FakeApi((req) {
        final p = req.url.path;
        if (p.endsWith('/squad')) return jsonResponse(fixtureJson('series_squad.json'));
        if (p.endsWith('/point-table')) return jsonResponse(fixtureJson('series_point_table.json'));
        if (p.endsWith('/stats')) return jsonResponse(fixtureJson('series_stats.json'));
        return jsonResponse(fixtureJson('series_fixtures.json'));
      });
      final c = SeriesDetailController(seriesId: 'S1', seriesName: 'Name', service: api.service);
      await c.load(SeriesView.fixtures);
      await c.load(SeriesView.fixtures);
      expect(api.requests.single.path, '/series/S1');
      expect(c.state(SeriesView.fixtures).data, isA<List<SeriesFixture>>());
      await c.load(SeriesView.squads);
      expect(c.squadCount, 2);
      await c.load(SeriesView.points);
      expect((c.state(SeriesView.points).data as List<PointsGroup>).single.rows, hasLength(6));
      await c.load(SeriesView.stats);
      expect(api.requests.last.path, '/series/S1/stats');
      expect(c.state(SeriesView.stats).data, isA<SeriesStatsData>());
    });

    test('404 → coming soon (no error); 500 → error message', () async {
      final api = FakeApi((req) => req.url.path.endsWith('/stats')
          ? jsonResponse({'message': 'Not found'}, 404)
          : jsonResponse({'message': "Series doesn't exist"}, 400));
      final c = SeriesDetailController(seriesId: 'S1', service: api.service);
      await c.load(SeriesView.stats);
      expect(c.state(SeriesView.stats).error, isNull);
      expect((c.state(SeriesView.stats).data as SeriesStatsData).comingSoon, isTrue);
      await c.load(SeriesView.points);
      expect(c.state(SeriesView.points).data, isEmpty);

      final api2 = FakeApi((req) => jsonResponse({'message': 'Server down'}, 500));
      final c2 = SeriesDetailController(seriesId: 'S1', service: api2.service);
      await c2.load(SeriesView.fixtures);
      expect(c2.state(SeriesView.fixtures).error, 'Server down');
      expect(c2.state(SeriesView.fixtures).fetched, isFalse);
    });

    test('series change drops responses for the old series', () async {
      final slow = Completer<http.Response>();
      final api = FakeApi((req) => req.url.path == '/series/OLD' ? slow.future : jsonResponse({'data': []}));
      final c = SeriesDetailController(seriesId: 'OLD', service: api.service);
      final f = c.load(SeriesView.fixtures);
      await Future<void>.delayed(Duration.zero);
      c.resetFor('NEW', 'New');
      await c.load(SeriesView.fixtures);
      slow.complete(jsonResponse(fixtureJson('series_fixtures.json')));
      await f;
      expect(c.state(SeriesView.fixtures).data, isEmpty);
      expect(c.state(SeriesView.fixtures).loading, isFalse);
    });

    test('empty seriesId never requests', () async {
      final api = FakeApi((req) => jsonResponse({'data': []}));
      final c = SeriesDetailController(seriesId: '', service: api.service);
      await c.load(SeriesView.fixtures);
      expect(api.requests, isEmpty);
    });
  });
}
