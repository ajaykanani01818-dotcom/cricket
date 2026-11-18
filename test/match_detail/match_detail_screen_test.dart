import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/ads/ads_backend.dart';
import 'package:crickbex/features/ads/ads_manager.dart';
import 'package:crickbex/features/match_detail/logic/match_detail_logic.dart';
import 'package:crickbex/features/match_detail/match_detail_screen.dart';
import 'package:crickbex/features/match_detail/tabs/playing_xi_tab.dart';
import 'package:crickbex/features/match_detail/tabs/scorecard_tab.dart';
import 'package:crickbex/features/match_detail/tabs/stats_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

const id = '3QJ-e3k';

Future<GoRouter> pumpScreen(WidgetTester tester, FakeApi api, {String matchId = id}) async {
  final router = GoRouter(
    initialLocation: '/live/match/$matchId',
    routes: [
      GoRoute(
        path: '/live',
        builder: (_, _) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'match/:matchId',
            builder: (_, s) => MatchDetailScreen(
              matchId: s.pathParameters['matchId']!,
              matchService: api.matches,
              playerService: api.players,
            ),
          ),
          GoRoute(path: 'player/:k', builder: (_, s) => Scaffold(body: Text('player ${s.pathParameters['k']}'))),
          GoRoute(path: 'series-detail/:sid', builder: (_, s) => Scaffold(body: Text('series ${s.pathParameters['sid']} ${s.extra}'))),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  return router;
}

Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String textOf(WidgetTester tester, String key) => stripJoiners(tester.widget<Text>(find.byKey(ValueKey(key))).data ?? '');

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  // Tabs live in the pinned header (always visible); ensureVisible on a pinned
  // header would scroll the page instead.
  if (!key.startsWith('match_detail_tab_')) {
    await tester.ensureVisible(f);
    await tester.pump();
  }
  await tester.tap(f);
  await tester.pump();
}

Finder get mainScrollable =>
    find.descendant(of: find.byKey(const ValueKey('match_detail_scroll')), matching: find.byType(Scrollable)).first;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('completed match', () {
    testWidgets('shimmer → header, result, Player of the Match, scorecard-backed Live tab; no polling', (tester) async {
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      await pumpScreen(tester, api);
      expect(find.byKey(const ValueKey('match_detail_shimmer')), findsOneWidget);
      await settle(tester);

      expect(find.byKey(const ValueKey('match_detail_shimmer')), findsNothing);
      expect(find.text('South Africa'), findsWidgets);
      expect(find.text('Bangladesh'), findsWidgets);
      expect(find.text('Bangladesh tour of South Africa 2026'), findsOneWidget);
      expect(find.text('TEST · The Wanderers Stadium, Johannesburg, South Africa'), findsOneWidget);
      expect(find.text('Bangladesh opt to bat'), findsOneWidget);
      expect(textOf(tester, 'match_detail_score_team1'), '386/7 (90.0)');
      expect(textOf(tester, 'match_detail_score_team2'), '400/10 (101.2)');
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_live_badge')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_role_team1')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_current_over')), findsNothing);
      expect(textOf(tester, 'match_detail_mom_name'), 'Aiden Markram');

      // Live tab of a finished match uses the scorecard's last innings
      expect(find.byKey(const ValueKey('match_detail_batting')), findsOneWidget);
      expect(find.text('c Litton Das b Hasan Mahmud'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_bowling')), findsOneWidget);
      expect(find.text('Taskin Ahmed'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_weather')), findsOneWidget);
      expect(find.text('Cloudy'), findsOneWidget);

      expect(api.count('detail'), 1);
      expect(api.count('live'), 0);
      expect(api.count('scorecard'), 1);
      expect(api.count('player'), 1);

      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, 3, reason: 'finished match must not poll');
    });

    testWidgets('Player of the Match tap opens player; series link opens series (guarded against double tap)', (tester) async {
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      final router = await pumpScreen(tester, api);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('match_detail_mom_card')));
      await settle(tester);
      expect(find.text('player aiden_markram'), findsOneWidget);
      router.pop();
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('match_detail_series_link')));
      await tester.tap(find.byKey(const ValueKey('match_detail_series_link')), warnIfMissed: false);
      await settle(tester);
      expect(find.text('series ser-1 Bangladesh tour of South Africa 2026'), findsOneWidget);
      router.pop();
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_series_link')), findsOneWidget, reason: 'only one route was pushed');
    });

    testWidgets('MoM card hidden when player info fails', (tester) async {
      final api = FakeApi();
      api.detail = (_) => ok(completedDetailData());
      api.player = (_) => err(404, 'Player not found');
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_mom_card')), findsNothing);
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
    });

    testWidgets('tab switching: scorecard prefetched once, tabs kept alive, no refetch', (tester) async {
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      await pumpScreen(tester, api);
      await settle(tester);

      await tapKey(tester, 'match_detail_tab_scorecard');
      await settle(tester, 2);
      final sc = tester.widget<MatchScorecardTab>(find.byType(MatchScorecardTab));
      expect(sc.scorecard, isNotNull);
      expect(J.map(sc.scorecard!['result'])['innings'], isA<List>());
      expect(sc.loading, isFalse);
      expect(find.byKey(const ValueKey('match_detail_live_tab')), findsNothing);

      await tapKey(tester, 'match_detail_tab_stats');
      expect(tester.widget<MatchStatsTab>(find.byType(MatchStatsTab)).matchId, id);
      expect(find.byType(MatchScorecardTab), findsNothing); // offstage
      expect(find.byType(MatchScorecardTab, skipOffstage: false), findsOneWidget); // but alive

      await tapKey(tester, 'match_detail_tab_playingXI');
      final xi = tester.widget<MatchPlayingXITab>(find.byType(MatchPlayingXITab));
      expect(xi.isLive, isFalse);

      await tapKey(tester, 'match_detail_tab_scorecard');
      await tapKey(tester, 'match_detail_tab_live');
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('match_detail_live_tab')), findsOneWidget);
      expect(api.count('scorecard'), 1);
      expect(api.count('detail'), 1);
    });

    testWidgets('pull-to-refresh refetches detail and (finished) scorecard', (tester) async {
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      await pumpScreen(tester, api);
      await settle(tester);
      await tester.fling(mainScrollable, const Offset(0, 500), 1200);
      await tester.pump();
      await settle(tester, 12);
      expect(api.count('detail'), 2);
      expect(api.count('scorecard'), 2);
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
    });
  });

  group('commentary tab', () {
    testWidgets('loads lazily once, filters, keeps state across tab switches', (tester) async {
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      final gate = Completer<http.Response>();
      api.commentary = (_) => gate.future;
      await pumpScreen(tester, api);
      await settle(tester);
      expect(api.count('commentary'), 0);

      await tapKey(tester, 'match_detail_tab_commentary');
      expect(find.text('Loading commentary...'), findsOneWidget);
      gate.complete(ok(J.map(fixture('match_commentary')['data'])));
      await settle(tester);
      expect(api.count('commentary'), 1);
      expect(find.text('61.6', skipOffstage: false), findsOneWidget); // newest first
      expect(find.byKey(const ValueKey('match_detail_commentary_load_more')), findsNothing); // 30 < 60

      await tapKey(tester, 'match_detail_commentary_filter_wicket');
      expect(find.text('58.6', skipOffstage: false), findsOneWidget);
      expect(find.text('61.6', skipOffstage: false), findsNothing);
      await tapKey(tester, 'match_detail_commentary_filter_six');
      expect(find.byKey(const ValueKey('match_detail_commentary_no_match'), skipOffstage: false), findsOneWidget);
      await tapKey(tester, 'match_detail_commentary_filter_all');
      expect(find.byKey(const ValueKey('match_detail_commentary_team_t1_1')), findsOneWidget);
      expect(find.text('South Africa'), findsWidgets);

      await tapKey(tester, 'match_detail_tab_live');
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester, 2);
      expect(api.count('commentary'), 1, reason: 'tab switch must not refetch');
      expect(find.text('61.6', skipOffstage: false), findsOneWidget);
    });

    testWidgets('Load more requests page 2 exactly once and appends', (tester) async {
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      final page2 = Completer<http.Response>();
      api.commentary = (req) =>
          req.url.queryParameters['page'] == '1' ? ok(commentaryPage(count: 60, totalCount: 70)) : page2.future;
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);

      final loadMore = find.byKey(const ValueKey('match_detail_commentary_load_more'));
      await tester.scrollUntilVisible(loadMore, 600, scrollable: mainScrollable, maxScrolls: 200);
      await tester.tap(loadMore);
      await tester.pump();
      expect(find.byKey(const ValueKey('match_detail_commentary_loading_more')), findsOneWidget);
      expect(api.callsOf('commentary').where((u) => u.queryParameters['page'] == '2').length, 1);
      page2.complete(ok(commentaryPage(count: 10, totalCount: 70, startOver: 150)));
      await settle(tester);
      expect(loadMore, findsNothing); // 10 < 60 → no more
      expect(api.callsOf('commentary').length, 2);
      await tester.scrollUntilVisible(find.text('149.5'), 600, scrollable: mainScrollable, maxScrolls: 200);
      expect(find.text('149.5'), findsOneWidget);
    });

    testWidgets('404 → "Commentary not available"; 500 → error + Retry', (tester) async {
      final api = FakeApi();
      api.detail = (_) => ok(completedDetailData());
      api.commentary = (_) => err(404, 'Commentary not found');
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);
      expect(find.text('Commentary not available'), findsOneWidget);

      api.commentary = (_) => err(500);
      // a new screen instance to hit the error path
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_commentary_error')), findsOneWidget);
      api.commentary = (_) => ok(J.map(fixture('match_commentary')['data']));
      await tapKey(tester, 'match_detail_commentary_retry');
      await settle(tester);
      expect(find.text('61.6', skipOffstage: false), findsOneWidget);
    });
  });

  group('live match (crafted from fixtures)', () {
    testWidgets('live header, roles, live scores, current over, batting pair, bowler, recent overs', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);

      expect(find.byKey(const ValueKey('match_detail_live_badge')), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('match_detail_role_team1')), matching: find.byType(Text))).data, 'BAT');
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('match_detail_role_team2')), matching: find.byType(Text))).data, 'BOWL');
      expect(textOf(tester, 'match_detail_score_team1'), '287/4 (62.0)'); // live inningsStats win over API score
      expect(find.byKey(const ValueKey('match_detail_current_over')), findsOneWidget);
      expect(find.text('Current Over (61)'), findsOneWidget);
      expect(find.text('5 runs • 0 wickets'), findsOneWidget);
      expect(find.text('Ryan Rickelton *'), findsOneWidget);
      expect(find.text('Temba Bavuma'), findsOneWidget);
      expect(find.text('Taskin Ahmed'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_live_commentary')), findsOneWidget);
      expect(find.textContaining('·  Hasan Mahmud', skipOffstage: false), findsNothing);
      await tapKey(tester, 'match_detail_recent_overs_toggle');
      expect(find.textContaining('·  Hasan Mahmud', skipOffstage: false), findsWidgets);
      expect(api.count('player'), 0);
    });

    testWidgets('polls detail + live every 15s; never overlaps; stops when match ends', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);
      expect(api.count('detail'), 1);
      expect(api.count('live'), 1);

      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(api.count('detail'), 2);
      expect(api.count('live'), 2);

      // slow live response → no overlapping polls
      final slow = Completer<http.Response>();
      api.live = (_) => slow.future;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(api.count('live'), 3);
      await tester.pump(const Duration(minutes: 1));
      expect(api.count('live'), 3);
      expect(api.count('detail'), 3);
      slow.complete(ok(J.map(fixture('match_live')['data'])));
      await tester.pump();

      // match finishes on the next poll → polling stops, scorecard + MoM load
      api.live = (_) => ok(J.map(fixture('match_live')['data']));
      api.detail = (_) => ok(completedDetailData());
      await tester.pump(const Duration(seconds: 15));
      await settle(tester);
      expect(api.count('detail'), 4);
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_live_badge')), findsNothing);
      expect(api.count('scorecard'), 1);
      expect(api.count('player'), 1);
      final n = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, n);
    });

    testWidgets('unchanged poll responses do not rebuild the header', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);
      final before = tester.widget(find.byKey(const ValueKey('match_detail_score_team1')));
      await tester.pump(const Duration(seconds: 15));
      await settle(tester, 2);
      expect(identical(tester.widget(find.byKey(const ValueKey('match_detail_score_team1'))), before), isTrue);

      final changed = J.map(fixture('match_live')['data']);
      J.map(J.at(changed, 'score.teams.team1'))['inningsStats'] = {'runs': 291, 'wickets': 4, 'overs': '62.4'};
      api.live = (_) => ok(changed);
      await tester.pump(const Duration(seconds: 15));
      await settle(tester, 2);
      expect(textOf(tester, 'match_detail_score_team1'), '291/4 (62.4)');
    });

    testWidgets('pauses while app is backgrounded; refreshes on resume', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final n = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, n);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(api.count('detail'), 2);
      expect(api.count('live'), 2);
    });

    testWidgets('pauses while another route covers it; resumes on pop; stops after dispose', (tester) async {
      final api = FakeApi();
      final router = await pumpScreen(tester, api);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('match_detail_series_link')));
      await settle(tester, 10);
      expect(find.text('series ser-1 Bangladesh tour of South Africa 2026'), findsOneWidget);
      final n = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, n, reason: 'covered route must not poll');

      router.pop();
      await settle(tester, 10);
      expect(api.count('detail'), 2, reason: 'immediate refresh after being uncovered');

      router.pop(); // leave the match screen
      await settle(tester, 10);
      expect(find.text('home'), findsOneWidget);
      final m = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, m, reason: 'disposed screen must not poll');
    });

    testWidgets('scorecard tab polls every 10s only while it is the active tab', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_scorecard');
      await settle(tester, 2);
      expect(api.count('scorecard'), 1);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(api.count('scorecard'), 2);
      await tapKey(tester, 'match_detail_tab_live');
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(api.count('scorecard'), 2);
    });

    testWidgets('keeps last batting pair when a poll briefly omits both batters', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);
      final noBatters = J.map(fixture('match_live')['data']);
      J.map(noBatters['score'])
        ..remove('striker')
        ..remove('nonStriker');
      api.live = (_) => ok(noBatters);
      await tester.pump(const Duration(seconds: 15));
      await settle(tester, 2);
      expect(find.text('Ryan Rickelton *'), findsOneWidget);
    });

    testWidgets('commentary tab polls page 1 every 20s while live', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);
      expect(api.count('commentary'), 1);
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(api.count('commentary'), 2);
      await tapKey(tester, 'match_detail_tab_live');
      await tester.pump(const Duration(seconds: 60));
      expect(api.count('commentary'), 2, reason: 'no commentary polling off-tab');
    });
  });

  group('rewarded gates', () {
    testWidgets('scorecard / playing XI are gated when the rewarded placement is enabled and ads are ready', (tester) async {
      AdsManager.instance.debugReset(backend: const NoopAdsBackend(), ready: true);
      addTearDown(() => AdsManager.instance.debugReset());
      final api = FakeApi()..detail = (_) => ok(completedDetailData());
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_scorecard');
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('match_detail_reward_gate_scorecard')), findsOneWidget);
      expect(find.text('Unlock Full Scoreboard'), findsOneWidget);
      expect(find.byType(MatchScorecardTab), findsNothing);
      await tapKey(tester, 'match_detail_tab_playingXI');
      await settle(tester, 2);
      expect(find.text('Unlock Playing XI'), findsOneWidget);
      expect(find.byType(MatchPlayingXITab, skipOffstage: false), findsNothing, reason: 'gated tab must not mount/fetch');
      // no fill (Noop backend) → stays locked, no crash
      await tester.tap(find.byKey(const ValueKey('match_detail_reward_gate_playing_xi_button')));
      await settle(tester, 2);
      expect(find.text('Unlock Playing XI'), findsOneWidget);
    });
  });

  group('errors & edge cases', () {
    testWidgets('server 500 → error view; Retry recovers', (tester) async {
      final api = FakeApi()..detail = (_) => err(500, 'Internal');
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_error')), findsOneWidget);
      expect(find.text('Internal'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_go_back')), findsOneWidget);
      api.detail = (_) => ok(completedDetailData());
      await tester.tap(find.byKey(const ValueKey('match_detail_retry')));
      await settle(tester);
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
    });

    testWidgets('network error message; Go Back pops', (tester) async {
      final api = FakeApi()..detail = (_) => throw http.ClientException('offline');
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.text('Unable to reach the server. Check your connection and try again.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('match_detail_go_back')));
      await settle(tester, 8);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('empty data → "Failed to load match details"', (tester) async {
      final api = FakeApi()..detail = (_) => ok(null);
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.text('Failed to load match details'), findsOneWidget);
    });

    testWidgets('missing matchId', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MatchDetailScreen(matchId: '')));
      expect(find.text('Match ID is required'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_retry')), findsNothing);
    });

    testWidgets('malformed detail (no teams/scores/series) renders placeholders', (tester) async {
      final api = FakeApi()
        ..detail = (_) => ok({
              '_id': 'x',
              'status': 'NOT_STARTED',
              'teams': {'t1': {}, 't2': 'bad'},
              'currentOver': 'nope',
              'weather': null,
            });
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.text('TBD'), findsNWidgets(2));
      expect(textOf(tester, 'match_detail_score_team1'), '-');
      expect(find.byKey(const ValueKey('match_detail_series_link')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_batting')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('very long names do not overflow', (tester) async {
      final api = FakeApi();
      final d = completedDetailData();
      (d['teams'] as Map)['t1']['name'] = 'An Extremely Long Team Name That Goes On And On Forever XI';
      d['seriesName'] = 'A ridiculously long series name ' * 4;
      api.detail = (_) => ok(d);
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpScreen(tester, api);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
