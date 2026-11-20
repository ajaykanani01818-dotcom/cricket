import 'dart:async';

import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/home/home_controller.dart';
import 'package:crickbex/features/home/home_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/search/search_index.dart';

import '../common/helpers.dart';

HomeController _controller() =>
    HomeController(matchService: MatchService.instance);

Map<String, Responder> _routes() => {
  ...defaultRoutes(),
  '/match/live': FakeApi.ok(body(const [])),
};

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  group('models', () {
    test('parseUpcomingSeriesList: real fixture + firstMatch + malformed', () {
      final list = parseUpcomingSeriesList(
        fixtureJson('series_upcoming')['data'],
      );
      expect(list, hasLength(8));
      expect(list.first.name, 'Mens Asia Cup Rising Stars 2026');
      expect(list.first.sbSeriesKey, 'sddbjDn');
      expect(list.first.dateRange, contains('Nov 19'));
      expect(list.first.hasFirstMatch, isFalse);

      final odd = parseUpcomingSeriesList([
        {
          '_id': 'x1',
          'name': 'With match',
          'startDate': 'bad',
          'firstMatch': {
            'seriesId': 'fm1',
            'teams': {
              't1': {'short_name': 'IND', 'logo': 'https://x/ind.png'},
              't2': {'name': 'Australia'},
            },
          },
        },
        {'name': 'No id'},
        {},
        7,
      ]);
      expect(odd, hasLength(2));
      expect(odd.first.dateRange, '- – -');
      expect(odd.first.team1?.label, 'IND');
      expect(odd.first.team2?.label, 'Australia');
      expect(odd.first.idCandidates, [null, 'x1', 'fm1']);
      expect(odd[1].id, 'series-1');
    });
  });

  group('list rules', () {
    test(
      'mergeLive: /match/live first, in-progress recent items added, deduped',
      () {
        final live = parseMatchList([liveMatchJson(key: 'A')]);
        final recent = parseMatchList([
          liveMatchJson(key: 'A'),
          liveMatchJson(key: 'B')..['status'] = 'STUMPS',
          ...fixtureJson('match_recent')['data'] as List,
        ]);
        expect(mergeLive(live, recent).map((m) => m.id), ['A', 'B']);
      },
    );

    test('latestResults: finished only, newest first', () {
      final r = latestResults(
        parseMatchList([
          liveMatchJson(key: 'X'),
          ...fixtureJson('match_recent')['data'] as List,
        ]),
      );
      expect(r, hasLength(10));
      expect(r.first.id, 'LCoO4aA');
      for (var i = 1; i < r.length; i++) {
        expect(r[i - 1].startTime!.isBefore(r[i].startTime!), isFalse);
      }
    });

    test('startingSoon: upcoming by status, soonest first, undated last', () {
      final list = parseMatchList([
        {
          'sb_match_key': 'late',
          'status': 'NOT_STARTED',
          'startDate': '2026-11-20T10:00:00Z',
        },
        {'sb_match_key': 'none', 'status': 'NOT_STARTED', 'startDate': ''},
        {
          'sb_match_key': 'early',
          'status': 'NOT_STARTED',
          'startDate': '2026-11-19T10:00:00Z',
          'isLive': true,
        },
        {
          'sb_match_key': 'done',
          'status': 'COMPLETED',
          'startDate': '2026-11-18T10:00:00Z',
        },
      ]);
      expect(startingSoon(list).map((m) => m.id), ['early', 'late', 'none']);
    });
  });

  group('HomeController', () {
    setUp(() => SearchIndex.instance = SearchIndex());

    test(
      'silent poll with unchanged data does not notify; changed data does',
      () async {
        var recentBody = fixtureText('match_recent');
        final api = FakeApi({
          ..._routes(),
          '/match/recent': (req) => FakeApi.ok(recentBody)(req),
        })..install();
        final c = _controller()..start();
        await _flush();
        var notifications = 0;
        c.addListener(() => notifications++);

        c.poll();
        await _flush();
        expect(notifications, 0, reason: 'identical payloads must not rebuild');
        expect(api.count('/match/recent'), 2);
        expect(api.count('/match/live'), 2);

        recentBody = recentBody.replaceFirst(
          '"status"',
          '"status_changed_marker":1,"status"',
        );
        c.poll();
        await _flush();
        expect(
          notifications,
          1,
          reason: 'a changed payload notifies exactly once',
        );
        expect(c.loadingListenable.value, isFalse);
        c.dispose();
      },
    );

    test(
      'start loads live, results, upcoming and series; no rankings requests',
      () async {
        final api = FakeApi(_routes())..install();
        final c = _controller()..start();
        expect(c.loading, isTrue);
        await _flush();
        expect(c.loading, isFalse);
        expect(c.liveMatches, isEmpty);
        expect(c.results, hasLength(10));
        expect(c.lastUpdated, isNotNull);
        expect(c.upcoming.data, hasLength(6));
        expect(c.upcomingSeries.data, hasLength(8));
        expect(api.count('/rank/player'), 0);
        expect(
          SearchIndex.instance.search('UAE Bulls').matches,
          isNotEmpty,
          reason: 'feeds local search',
        );
        c.dispose();
      },
    );

    test('featured over: match-by-id only while a match is in play', () async {
      final api = FakeApi({
        ..._routes(),
        '/match/live': FakeApi.ok(body([liveMatchJson(key: 'L1')])),
        '/match/L1': FakeApi.fixture('match_detail'),
      })..install();
      final c = _controller()..start();
      await _flush();
      expect(c.featuredOver?.matchId, 'L1');
      expect(c.featuredOver?.balls, ['0', '4', '0', '0', '1', '0']);
      expect(c.featuredOver?.overNumber, 61);
      expect(api.count('/match/L1'), 1);
      c.dispose();
    });

    test('upcoming refreshes every 4th poll', () async {
      final api = FakeApi(_routes())..install();
      final c = _controller()..start();
      await _flush();
      for (var i = 0; i < 4; i++) {
        c.poll();
        await _flush();
      }
      expect(api.count('/match/upcoming'), 2);
      c.dispose();
    });

    test(
      'requests never overlap: polls and pull-to-refresh join the in-flight one',
      () async {
        final gate = Completer<void>();
        final api = FakeApi({
          ..._routes(),
          '/match/recent': FakeApi.gated(gate, FakeApi.fixture('match_recent')),
        })..install();
        final c = _controller();
        final first = c.fetchLive(showLoading: true);
        c.poll();
        c.poll();
        final manual = c.fetchLive(manual: true);
        expect(c.isRefreshing, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(api.count('/match/recent'), 1);
        gate.complete();
        await Future.wait([first, manual]);
        expect(c.isRefreshing, isFalse);
        expect(c.liveRequestInFlight, isFalse);
        c.poll();
        await _flush();
        expect(api.count('/match/recent'), 2);
        c.dispose();
      },
    );

    test(
      'error only when both sources fail; failed background poll keeps data',
      () async {
        var fail = true;
        Responder flaky(Responder ok) =>
            (req) =>
                fail ? FakeApi.status(500, 'Server exploded')(req) : ok(req);
        FakeApi({
          ..._routes(),
          '/match/recent': flaky(FakeApi.fixture('match_recent')),
          '/match/live': flaky(FakeApi.ok(body(const []))),
        }).install();
        final c = _controller();
        await c.fetchLive(showLoading: true);
        expect(c.error, 'Server exploded');
        fail = false;
        await c.fetchLive(showLoading: true);
        expect(c.error, isNull);
        expect(c.results, hasLength(10));
        fail = true;
        c.poll();
        await _flush();
        expect(c.error, isNull);
        expect(c.results, hasLength(10));
        c.dispose();
      },
    );

    test('non-API errors get the generic message', () async {
      FakeApi({
        '/match/recent': (_) => throw StateError('boom'),
        '/match/live': (_) => throw StateError('boom'),
      }).install();
      final c = _controller();
      await c.fetchLive(showLoading: true);
      expect(c.error, isNotNull);
      expect(
        homeErrorMessage(StateError('x'), 'f'),
        'An unexpected error occurred',
      );
      c.dispose();
    });

    test('dispose before responses arrive is safe', () async {
      final gate = Completer<void>();
      FakeApi({
        for (final e in _routes().entries) e.key: FakeApi.gated(gate, e.value),
      }).install();
      final c = _controller()..start();
      c.dispose();
      gate.complete();
      await _flush();
    });
  });
}
