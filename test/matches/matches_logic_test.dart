import 'dart:async';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/matches/matches_controller.dart';
import 'package:crickbex/features/matches/matches_tab_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../common/helpers.dart';

/// Page 2 of /match/completed: 3 matches with distinct ids, total 13.
String completedPage2() {
  final rows = J.maps(fixtureJson('match_completed')['data']).take(3).toList();
  for (var i = 0; i < rows.length; i++) {
    rows[i]['sb_match_key'] = 'P2_$i';
    rows[i]['seriesName'] = 'Page Two Series';
  }
  return body(rows, pageInfo: {'total': 13, 'perPage': 10, 'page': 2, 'totalPages': 2});
}

Responder completedPaged({Completer<void>? page2Gate, bool failPage2 = false}) => (req) async {
      final page = req.url.queryParameters['page'];
      if (page == '1') return FakeApi.fixture('match_completed')(req);
      if (page2Gate != null) await page2Gate.future;
      if (failPage2) return http.Response('{"message":"Page failed"}', 500);
      return http.Response(completedPage2(), 200);
    };

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('computeHasMore', () {
    expect(computeHasMore(const PageInfo(total: 13, perPage: 10, page: 1), 10), isTrue);
    expect(computeHasMore(const PageInfo(total: 13, perPage: 10, page: 2), 3), isFalse);
    expect(computeHasMore(null, 10), isTrue);
    expect(computeHasMore(null, 4), isFalse);
  });

  test('matchesErrorMessage', () {
    expect(matchesErrorMessage(const ApiException(500, 'Boom')), 'Boom');
    expect(matchesErrorMessage(const ApiException(500, ' ')), 'Failed to load');
    expect(matchesErrorMessage(StateError('x')), 'Failed to load');
  });

  group('buildMatchListData', () {
    test('groups consecutive matches by series and interleaves ads', () {
      final list = parseMatchList(fixtureJson('match_completed')['data']);
      final items = buildMatchListData(MatchesTab.completed, list);
      final headers = items.whereType<SeriesHeaderItem>().map((e) => e.seriesName).toList();
      // Consecutive identical series share one header.
      for (var i = 1; i < headers.length; i++) {
        expect(headers[i] == headers[i - 1], isFalse);
      }
      expect(items.whereType<MatchItem>(), hasLength(10));
      // Ads after match 3, 6, 9.
      expect(items.whereType<NativeAdItem>(), hasLength(3));
      expect(items.map((e) => e.key).toSet(), hasLength(items.length), reason: 'keys are unique');
      expect(items.first, isA<SeriesHeaderItem>());
    });

    test('no ads when disabled; blank series → "Other matches"; duplicate ids still unique keys', () {
      final m = parseMatchList([
        {'sb_match_key': 'a'},
        {'sb_match_key': 'a'},
      ]);
      final items = buildMatchListData(MatchesTab.live, m, showNativeSlots: false);
      expect((items.first as SeriesHeaderItem).seriesName, 'Other matches');
      expect(items.whereType<NativeAdItem>(), isEmpty);
      expect(items.map((e) => e.key).toSet(), hasLength(3));
      expect(buildMatchListData(MatchesTab.live, const []), isEmpty);
    });
  });

  group('MatchesController', () {
    test('start loads all three tabs', () async {
      FakeApi({...defaultRoutes(), '/match/completed': completedPaged()}).install();
      final c = MatchesController()..start();
      expect(c[MatchesTab.live].loading, isTrue);
      await _flush();
      expect(c[MatchesTab.live].matches, isEmpty);
      expect(c[MatchesTab.live].loading, isFalse);
      expect(c[MatchesTab.upcoming].matches, hasLength(6));
      expect(c[MatchesTab.completed].matches, hasLength(10));
      expect(c.completedHasMore, isTrue);
      c.dispose();
    });

    test('live falls back to /match/recent filtered to live matches', () async {
      final recent = fixtureJson('match_recent')['data'] as List;
      FakeApi({
        ...defaultRoutes(),
        '/match/live': FakeApi.status(500),
        '/match/recent': FakeApi.ok(body([liveMatchJson(), ...recent])),
      }).install();
      final c = MatchesController();
      await c.fetchLive();
      expect(c[MatchesTab.live].matches.single.id, 'LIVE01');
      expect(c[MatchesTab.live].error, isNull);
      c.dispose();
    });

    test('live: both endpoints failing → error', () async {
      FakeApi({'/match/live': FakeApi.status(500), '/match/recent': FakeApi.status(502, 'Gateway')}).install();
      final c = MatchesController();
      await c.fetchLive();
      expect(c[MatchesTab.live].error, 'Gateway');
      c.dispose();
    });

    test('load-more appends next page once even when called repeatedly, then stops', () async {
      final gate = Completer<void>();
      final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged(page2Gate: gate)})..install();
      final c = MatchesController();
      await c.fetchCompleted();
      final a = c.loadMoreCompleted();
      c.loadMoreCompleted();
      c.loadMoreCompleted();
      expect(c.completedLoadingMore, isTrue);
      gate.complete();
      await a;
      await _flush();
      expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1));
      expect(c[MatchesTab.completed].matches, hasLength(13));
      expect(c.completedPage, 2);
      expect(c.completedHasMore, isFalse);
      await c.loadMoreCompleted();
      expect(api.count('/match/completed'), 2, reason: 'no request past the last page');
      c.dispose();
    });

    test('refresh during a load-more discards the stale page', () async {
      final gate = Completer<void>();
      FakeApi({...defaultRoutes(), '/match/completed': completedPaged(page2Gate: gate)}).install();
      final c = MatchesController();
      await c.fetchCompleted();
      final more = c.loadMoreCompleted();
      final refresh = c.refresh();
      await _flush();
      gate.complete();
      await Future.wait([more, refresh]);
      expect(c[MatchesTab.completed].matches, hasLength(10));
      expect(c.completedPage, 1);
      expect(c.completedLoadingMore, isFalse);
      expect(c.refreshing, isFalse);
      c.dispose();
    });

    test('failed load-more keeps the list and can be retried', () async {
      var fail = true;
      FakeApi({
        ...defaultRoutes(),
        '/match/completed': (req) => completedPaged(failPage2: fail)(req),
      }).install();
      final c = MatchesController();
      await c.fetchCompleted();
      await c.loadMoreCompleted();
      expect(c.loadMoreError, 'Page failed');
      expect(c[MatchesTab.completed].matches, hasLength(10));
      expect(c[MatchesTab.completed].error, isNull);
      fail = false;
      await c.loadMoreCompleted();
      expect(c.loadMoreError, isNull);
      expect(c[MatchesTab.completed].matches, hasLength(13));
      c.dispose();
    });

    test('no load-more on empty list or first-page error; page-size fallback without pageInfo', () async {
      FakeApi({'/match/completed': FakeApi.ok(body(J.maps(fixtureJson('match_completed')['data']).take(4).toList()))}).install();
      final c = MatchesController();
      await c.fetchCompleted();
      expect(c.completedHasMore, isFalse, reason: '4 < page size and no pageInfo');

      FakeApi({'/match/completed': FakeApi.status(500)}).install();
      final c2 = MatchesController();
      await c2.fetchCompleted();
      expect(c2[MatchesTab.completed].error, isNotNull);
      await c2.loadMoreCompleted();
      expect(c2.completedLoadingMore, isFalse);
      c.dispose();
      c2.dispose();
    });

    test('dispose mid-request is safe', () async {
      final gate = Completer<void>();
      FakeApi({for (final e in defaultRoutes().entries) e.key: FakeApi.gated(gate, e.value)}).install();
      final c = MatchesController()..start();
      c.dispose();
      gate.complete();
      await _flush();
    });
  });
}
