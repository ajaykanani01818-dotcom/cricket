import 'dart:async';

import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/home/home_controller.dart';
import 'package:crickbex/features/home/home_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../common/helpers.dart';

HomeController _controller() => HomeController(matchService: MatchService.instance, rankingService: RankingService.instance);

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  group('models', () {
    test('parseTopPlayers: top 5, labels, malformed rows', () {
      final p = parseTopPlayers(fixtureJson('rank_player')['data']);
      expect(p, hasLength(5));
      expect(p.first.playerKey, 'shubman_gill');
      expect(p.first.orderLabel, '1');
      expect(p.first.pointsLabel, '801');
      final odd = parseTopPlayers([
        {'name': 'X', 'points': '12345', 'order': '2'},
        {},
        'junk',
      ]);
      expect(odd, hasLength(2));
      expect(odd.first.playerKey, '');
      expect(odd.first.pointsLabel, '12,345');
      expect(odd.first.order, 2);
      expect(odd[1].name, 'Unknown');
      expect(odd[1].pointsLabel, '0');
      expect(odd[1].orderLabel, '-');
      expect(parseTopPlayers(null), isEmpty);
    });

    test('TopPlayers.of category', () {
      const a = TopPlayer(playerKey: 'a', name: 'A'), b = TopPlayer(playerKey: 'b', name: 'B');
      const t = TopPlayers(batters: [a], bowlers: [b]);
      expect(t.of(PlayerCategory.batters), [a]);
      expect(t.of(PlayerCategory.bowlers), [b]);
      expect(t.of(PlayerCategory.allRounders), isEmpty);
    });

    test('parseUpcomingSeriesList: real fixture + firstMatch + malformed', () {
      final list = parseUpcomingSeriesList(fixtureJson('series_upcoming')['data']);
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

  group('HomeController', () {
    test('perf regression: silent poll with unchanged data does not notify; changed data does', () async {
      var body = fixtureText('match_recent');
      final api = FakeApi({...defaultRoutes(), '/match/recent': (req) => FakeApi.ok(body)(req)})..install();
      final c = _controller()..start();
      await _flush();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.poll();
      await _flush();
      expect(notifications, 0, reason: 'identical payload must not rebuild the Live section');
      expect(api.count('/match/recent'), 2);

      body = body.replaceFirst('"status"', '"status_changed_marker":1,"status"');
      c.poll();
      await _flush();
      expect(notifications, 1, reason: 'a changed payload notifies exactly once');
      expect(c.loadingListenable.value, isFalse);
      c.dispose();
    });

    test('start loads every section; rankings fetched for 3 roles', () async {
      final api = FakeApi(defaultRoutes())..install();
      final c = _controller()..start();
      expect(c.loading, isTrue);
      await _flush();
      expect(c.loading, isFalse);
      expect(c.liveMatches, hasLength(10));
      expect(c.upcoming.data, hasLength(6));
      expect(c.upcomingSeries.data, hasLength(8));
      expect(c.rankings.data!.batters, hasLength(5));
      final types = api.log.where((u) => u.path == '/rank/player').map((u) => '${u.queryParameters['type']}/${u.queryParameters['matchType']}');
      expect(types, unorderedEquals(['BATSMAN/ODI', 'BOWLER/ODI', 'ALL_ROUNDER/ODI']));
      c.dispose();
    });

    test('live requests never overlap: polls and pull-to-refresh join the in-flight one', () async {
      final gate = Completer<void>();
      final api = FakeApi({...defaultRoutes(), '/match/recent': FakeApi.gated(gate, FakeApi.fixture('match_recent'))})..install();
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
    });

    test('initial error shows server message; failed background poll keeps cards', () async {
      var fail = true;
      FakeApi({
        ...defaultRoutes(),
        '/match/recent': (req) => fail ? FakeApi.status(500, 'Server exploded')(req) : FakeApi.fixture('match_recent')(req),
      }).install();
      final c = _controller();
      await c.fetchLive(showLoading: true);
      expect(c.error, 'Server exploded');
      fail = false;
      await c.fetchLive(showLoading: true);
      expect(c.error, isNull);
      expect(c.liveMatches, hasLength(10));
      fail = true;
      c.poll();
      await _flush();
      expect(c.error, isNull);
      expect(c.liveMatches, hasLength(10));
      c.dispose();
    });

    test('non-API errors get the generic message', () async {
      FakeApi({'/match/recent': (_) => throw StateError('boom')}).install();
      final c = _controller();
      await c.fetchLive(showLoading: true);
      // MockClient wraps thrown errors as ClientException → network error.
      expect(c.error, isNotNull);
      expect(homeErrorMessage(StateError('x'), 'f'), 'An unexpected error occurred');
      c.dispose();
    });

    test('format change reloads rankings with the new matchType; stale responses ignored', () async {
      final slow = Completer<void>();
      final api = FakeApi({
        ...defaultRoutes(),
        '/rank/player': (req) async {
          if (req.url.queryParameters['matchType'] == 'ODI') await slow.future;
          final name = '${req.url.queryParameters['matchType']}-${req.url.queryParameters['type']}';
          return http.Response(body([
            {'name': name, 'points': 1, 'order': 1, 'playerKey': name},
          ]), 200);
        },
      })
        ..install();
      final c = _controller();
      final odi = c.rankings.load();
      c.setMatchType('TEST');
      expect(c.matchType, 'TEST');
      await _flush();
      slow.complete();
      await odi;
      expect(c.rankings.data!.batters.single.name, 'TEST-BATSMAN');
      expect(c.rankings.data!.allRounders.single.name, 'TEST-ALL_ROUNDER');
      expect(api.log.where((u) => u.queryParameters['matchType'] == 'TEST'), hasLength(3));
      c.setMatchType('TEST'); // no-op
      expect(api.log.where((u) => u.queryParameters['matchType'] == 'TEST'), hasLength(3));
      c.dispose();
    });

    test('dispose before responses arrive is safe', () async {
      final gate = Completer<void>();
      FakeApi({for (final e in defaultRoutes().entries) e.key: FakeApi.gated(gate, e.value)}).install();
      final c = _controller()..start();
      c.dispose();
      gate.complete();
      await _flush();
    });
  });
}
