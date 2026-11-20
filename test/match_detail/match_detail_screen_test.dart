import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/widgets/score_text.dart';
import 'package:crickbex/core/widgets/seam_strip.dart';
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

Future<GoRouter> pumpScreen(WidgetTester tester, FakeApi api, {String matchId = id, ThemeMode mode = ThemeMode.light}) async {
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
  await tester.pumpWidget(MaterialApp.router(
    theme: buildAppTheme(),
    darkTheme: buildAppTheme(brightness: Brightness.dark),
    themeMode: mode,
    routerConfig: router,
  ));
  return router;
}

Future<void> settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String textOf(WidgetTester tester, String key) {
  final w = tester.widget(find.byKey(ValueKey(key)));
  if (w is ScoreText) return stripJoiners(w.text);
  return stripJoiners((w as Text).data ?? '');
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  // Header / tab bar controls live in the pinned header: ensureVisible
  // would scroll the page instead.
  const pinned = ['match_detail_tab_', 'match_detail_over_'];
  if (!pinned.any(key.startsWith)) {
    await tester.ensureVisible(f);
    await tester.pump();
  }
  await tester.tap(f);
  await tester.pump();
}

Finder get mainScrollable =>
    find.descendant(of: find.byKey(const ValueKey('match_detail_scroll')), matching: find.byType(Scrollable)).first;

JsonMap liveStatusDetail() => liveDetailData()..['status'] = 'LIVE';

/// The live fixture plus [extra] deliveries (newest first) in the next over.
JsonMap liveWithNewBalls(List<String> values, {int wickets = 4, String? wicketName}) {
  final l = deepCopy(J.map(fixture('match_live')['data']));
  final balls = J.list(l['balls']);
  for (var i = 0; i < values.length; i++) {
    balls.insert(0, {
      'type': 'ball',
      'overNumber': 62,
      'ballNumber': i + 1,
      'value': values[i],
      'inningsIndex': 't1_1',
      'commentaryTimestamp': 1794843300000 + i * 1000,
      'commentary': '<p>New ball ${i + 1}</p>',
    });
  }
  final score = J.map(l['score']);
  J.map(J.at(score, 'teams.team1'))['inningsStats'] = {'runs': 287 + values.where((v) => v != 'WK').length, 'wickets': wickets, 'overs': '62.${values.length}'};
  if (wicketName != null) {
    score['lastWicket'] = {'name': wicketName, 'run': '19', 'ball': '55', 'info': 'b Taskin Ahmed', 'score': '287/5', 'over': '62.1'};
  }
  return l;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('header states', () {
    testWidgets('Test at stumps: frozen score, trail line, status note, Seam strip; no live pulse', (tester) async {
      final api = FakeApi();
      await pumpScreen(tester, api);
      expect(find.byKey(const ValueKey('match_detail_shimmer')), findsOneWidget);
      await settle(tester);

      expect(find.byKey(const ValueKey('match_detail_shimmer')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_live_badge')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('match_detail_status_badge')), matching: find.text('Stumps')), findsOneWidget);
      expect(textOf(tester, 'match_detail_score_team1'), '287/4'); // live inningsStats win over the stale API score
      expect(textOf(tester, 'match_detail_score_team2'), '400');
      expect(textOf(tester, 'match_detail_situation'), 'South Africa trail by 113');
      expect(find.text('CRR 4.63'), findsOneWidget);
      expect(find.textContaining('Stumps on Day 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_over_strip')), findsOneWidget);
      expect(find.text('Over 62'), findsOneWidget);
      expect(find.text('Bangladesh tour of South Africa 2026'), findsOneWidget);
      expect(find.textContaining('balls left'), findsNothing, reason: 'no limited-overs fields on a Test');
      expect(api.count('scorecard'), 1, reason: 'header needs the innings list');
    });

    testWidgets('T20 chase: plain-language equation, live pill, derived target noted in Info', (tester) async {
      final api = FakeApi(matchId: 'LIVE01')
        ..detail = ((_) => ok(t20ChaseDetail()))
        ..live = ((_) => ok(t20ChaseLive()))
        ..scorecard = ((_) => err(404, 'Match scorecard not found!!'));
      await pumpScreen(tester, api, matchId: 'LIVE01');
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_live_badge')), findsOneWidget);
      expect(textOf(tester, 'match_detail_score_team1'), '45/2');
      expect(textOf(tester, 'match_detail_situation'), 'UAE Bulls need 87 runs');
      expect(textOf(tester, 'match_detail_subline'), 'About 95 balls left (est.)');
      expect(find.text('Target 132'), findsOneWidget);
      expect(find.textContaining('need 0'), findsNothing);

      await tapKey(tester, 'match_detail_tab_info');
      await settle(tester, 3);
      expect(textOf(tester, 'match_detail_target_note'), contains('derived: first-innings runs + 1'));
    });

    testWidgets('ODI first innings: no equation, no projection without maxOvers; other side has no score', (tester) async {
      final api = FakeApi(matchId: 'w2bXPRS')
        ..detail = ((_) => ok(odiFirstInningsDetail()))
        ..live = ((_) => ok(odiFirstInningsLive()))
        ..scorecard = ((_) => ok(scorecardWith(innings: [inningsJson('England', 'ENG', 126, 2, '19.0')], order: ['t2_1', 't1_1'])['result']));
      await pumpScreen(tester, api, matchId: 'w2bXPRS');
      await settle(tester);
      expect(textOf(tester, 'match_detail_score_team2'), '126/2');
      expect(find.byKey(const ValueKey('match_detail_score_team1')), findsNothing, reason: 'AUS have not batted: no fake 0');
      expect(find.byKey(const ValueKey('match_detail_situation')), findsNothing);
      expect(find.text('CRR 6.63'), findsOneWidget);
      expect(find.textContaining('At this rate'), findsNothing);
    });

    testWidgets('upcoming: countdown, local time, venue; no live fetch; Summary tab is not offered; Info is reachable', (tester) async {
      final api = FakeApi(matchId: 'w2bXPRS')..detail = ((_) => ok(upcomingDetail()));
      await pumpScreen(tester, api, matchId: 'w2bXPRS');
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_countdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_start_time')), findsOneWidget);
      expect(find.text('Bellerive Oval, Hobart, Australia'), findsWidgets, reason: 'header + Info tab');
      expect(find.byKey(const ValueKey('match_detail_score_team1')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_over_strip')), findsNothing);
      expect(api.count('live'), 0);
      expect(api.count('scorecard'), 0);
      // Summary only exists for completed matches: not offered before the match,
      // and there is no commentary yet, so the page opens on Info.
      expect(find.byKey(const ValueKey('match_detail_tab_summary')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_info_tab')), findsOneWidget);
      expect(api.count('commentary'), 0, reason: 'no commentary request for a match that has not started');
    });

    testWidgets('completed: result headline, winner emphasised, player of the match; no polling', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(completedDetailData()));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(textOf(tester, 'match_detail_result'), 'South Africa won by 5 wickets');
      expect(find.byKey(const ValueKey('match_detail_winner_team1')), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_winner_team2')), findsNothing);
      expect(textOf(tester, 'match_detail_mom_name'), 'Aiden Markram');
      expect(find.byKey(const ValueKey('match_detail_over_strip')), findsNothing);
      expect(api.count('live'), 0);
      final n = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, n, reason: 'finished match must not poll');
    });

    testWidgets('abandoned: label only, no scores', (tester) async {
      final api = FakeApi(matchId: 'w2bXPRS')..detail = ((_) => ok(upcomingDetail()..['status'] = 'ABANDONED'));
      await pumpScreen(tester, api, matchId: 'w2bXPRS');
      await settle(tester);
      expect(textOf(tester, 'match_detail_situation'), 'Abandoned');
      expect(find.byKey(const ValueKey('match_detail_score_team1')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_score_team2')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_countdown')), findsNothing);
      expect(api.count('live'), 0);
    });

    testWidgets('malformed detail renders TBD teams and no invented scores', (tester) async {
      final api = FakeApi()
        ..detail = ((_) => ok({'_id': 'x', 'status': 'LIVE', 'teams': {'t1': {}, 't2': 'bad'}, 'currentOver': 'nope', 'weather': null}))
        ..live = ((_) => ok({'score': 'nope'}))
        ..scorecard = ((_) => err(404, 'Match scorecard not found!!'));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.text('TBD'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('match_detail_score_team1')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_series_link')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_batting')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('live match without ball-by-ball data: no (empty) Summary tab, lands on Commentary', (tester) async {
      // Seen on real data: a live T20 before the first ball (UAEW 0/0,
      // PNGW yet to bat) had no live payload and rendered an empty Summary.
      final api = FakeApi()
        ..detail = ((_) => ok(liveStatusDetail()))
        ..live = ((_) => err(404, 'Match not found!!'))
        ..scorecard = ((_) => err(404, 'Match scorecard not found!!'));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_tab_summary')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_summary_tab')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_tab_commentary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Seam strip, sticky bar, feedback motion', () {
    testWidgets('strip swipes / taps to earlier overs', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byType(SeamStrip), findsOneWidget);
      expect(textOf(tester, 'match_detail_over_title'), 'Over 62');
      await tapKey(tester, 'match_detail_over_older');
      expect(textOf(tester, 'match_detail_over_title'), 'Over 61');
      await tester.fling(find.byKey(const ValueKey('match_detail_over_strip')), const Offset(300, 0), 1500);
      await tester.pump();
      expect(textOf(tester, 'match_detail_over_title'), 'Over 60');
      await tester.fling(find.byKey(const ValueKey('match_detail_over_strip')), const Offset(-300, 0), 1500);
      await tester.pump();
      expect(textOf(tester, 'match_detail_over_title'), 'Over 61');
    });

    testWidgets('header collapses into a sticky bar with short score, status and last ball', (tester) async {
      final api = FakeApi()
        ..detail = ((_) => ok(liveStatusDetail()))
        ..commentary = ((_) => ok(commentaryPage(count: 60, totalCount: 60)));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_collapsed_bar')), findsNothing);
      await tester.drag(mainScrollable, const Offset(0, -700));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('match_detail_collapsed_bar')), findsOneWidget);
      expect(textOf(tester, 'match_detail_collapsed_score'), 'RSA 287/4 (62.0)');
      expect(find.byKey(const ValueKey('match_detail_collapsed_last_ball')), findsOneWidget);
      // Tabs stay reachable while collapsed.
      expect(find.byKey(const ValueKey('match_detail_tab_scorecard')).hitTestable(), findsOneWidget);
      await tester.drag(mainScrollable, const Offset(0, 900));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('match_detail_collapsed_bar')), findsNothing);
    });

    testWidgets('one new wicket ball: digit roll + wicket band; catch-up: neither', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_wicket_band')), findsNothing, reason: 'never on first render');

      api.live = (_) => ok(liveWithNewBalls(['WK'], wickets: 5, wicketName: 'Temba Bavuma'));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ScoreText>(find.byKey(const ValueKey('match_detail_score_team1'))).animate, isTrue);
      expect(textOf(tester, 'match_detail_score_team1'), '287/5');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('match_detail_wicket_band')), findsOneWidget);
      expect(find.text('Wicket: Temba Bavuma 19 (55), b Taskin Ahmed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('match_detail_wicket_band')), findsNothing);

      // Three balls in one poll (app was backgrounded): no replay.
      api.live = (_) => ok(liveWithNewBalls(['WK', '1', 'WK'], wickets: 6, wicketName: 'Kyle Verreynne'));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ScoreText>(find.byKey(const ValueKey('match_detail_score_team1'))).animate, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('match_detail_wicket_band')), findsNothing);
    });
  });

  group('tabs', () {
    testWidgets('Summary / Commentary / Scorecard / Stats / Info in a fixed order, kept alive, no refetch', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(completedDetailData()));
      await pumpScreen(tester, api);
      await settle(tester);
      final xs = [for (final t in MatchTab.values) tester.getTopLeft(find.byKey(ValueKey('match_detail_tab_${t.name}'))).dx];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(MatchTab.values.map((t) => t.label), ['Summary', 'Commentary', 'Scorecard', 'Stats', 'Info']);
      expect(find.byKey(const ValueKey('match_detail_summary_tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_digest_0')), findsOneWidget);

      await tapKey(tester, 'match_detail_tab_scorecard');
      await settle(tester, 2);
      final sc = tester.widget<MatchScorecardTab>(find.byType(MatchScorecardTab));
      expect(sc.scorecard, isNotNull);
      expect(find.byKey(const ValueKey('scorecard_body')), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_summary_tab')), findsNothing);

      await tapKey(tester, 'match_detail_tab_stats');
      await settle(tester, 3);
      expect(tester.widget<MatchStatsTab>(find.byType(MatchStatsTab)).matchId, id);
      expect(find.byKey(const ValueKey('stats_body')), findsOneWidget);
      expect(find.byType(MatchScorecardTab), findsNothing);
      expect(find.byType(MatchScorecardTab, skipOffstage: false), findsOneWidget);

      await tapKey(tester, 'match_detail_tab_info');
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('match_detail_info_tab')), findsOneWidget);
      expect(find.text('Bangladesh opt to bat'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_weather')), findsOneWidget);
      expect(tester.widget<MatchPlayingXITab>(find.byType(MatchPlayingXITab)).isLive, isFalse);

      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester, 3);
      expect(find.text('61.6', skipOffstage: false), findsOneWidget);

      await tapKey(tester, 'match_detail_tab_summary');
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('match_detail_summary_tab')), findsOneWidget);
      expect(api.count('scorecard'), 1);
      expect(api.count('detail'), 1);
      expect(api.count('commentary'), 1);
    });

    testWidgets('Summary tab only for a completed match; live opens on Commentary', (tester) async {
      final live = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      await pumpScreen(tester, live);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_tab_summary')), findsNothing);
      expect(find.byKey(const ValueKey('match_detail_summary_tab')), findsNothing);
      for (final t in [MatchTab.commentary, MatchTab.scorecard, MatchTab.stats, MatchTab.info]) {
        expect(find.byKey(ValueKey('match_detail_tab_${t.name}')), findsOneWidget, reason: t.label);
      }
    });

    testWidgets('completed match keeps the Summary tab and opens on it', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(completedDetailData()));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_tab_summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_summary_tab')), findsOneWidget);
    });
  });

  group('commentary', () {
    testWidgets('loads lazily once, key-moment filters, keeps state across tab switches', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(completedDetailData()));
      final gate = Completer<http.Response>();
      api.commentary = (_) => gate.future;
      await pumpScreen(tester, api);
      await settle(tester);
      expect(api.count('commentary'), 0);

      await tapKey(tester, 'match_detail_tab_commentary');
      expect(find.byKey(const ValueKey('match_detail_commentary_loading')), findsOneWidget);
      gate.complete(ok(J.map(fixture('match_commentary')['data'])));
      await settle(tester);
      expect(find.text('61.6', skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_over_end_62'), skipOffstage: false), findsOneWidget);

      await tapKey(tester, 'match_detail_commentary_filter_wickets');
      expect(find.text('58.6', skipOffstage: false), findsOneWidget);
      expect(find.text('61.6', skipOffstage: false), findsNothing);
      await tapKey(tester, 'match_detail_commentary_filter_boundaries');
      expect(find.text('61.2', skipOffstage: false), findsOneWidget);
      await tapKey(tester, 'match_detail_commentary_filter_all');

      await tapKey(tester, 'match_detail_tab_summary');
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester, 2);
      expect(api.count('commentary'), 1, reason: 'tab switch must not refetch');
    });

    testWidgets('refresh while reading: no jump, "N new balls" pill, deduped on apply', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      var page = commentaryPage(count: 60, totalCount: 60);
      api.commentary = (_) => ok(page);
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);
      expect(api.count('commentary'), 1);

      // Read further down the feed.
      await tester.scrollUntilVisible(find.text('197.6'), 400, scrollable: mainScrollable);
      await settle(tester, 3);
      final anchor = find.text('197.6');
      expect(anchor, findsOneWidget);
      final y = tester.getTopLeft(anchor).dy;

      // 6 new deliveries arrive (over 201) plus the same 54 older ones.
      final fresh = commentaryPage(count: 6, totalCount: 0, startOver: 201);
      page = {...page, 'balls': [...J.list(fresh['balls']), ...J.list(page['balls']).take(54)]};
      await tester.pump(const Duration(seconds: 10));
      await settle(tester, 2);
      expect(api.count('commentary'), greaterThanOrEqualTo(2));
      expect(tester.getTopLeft(anchor).dy, y, reason: 'the feed must not move under the reader');
      expect(find.text('6 new balls'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('match_detail_commentary_new_pill')));
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('match_detail_commentary_new_pill')), findsNothing);
      expect(find.text('201.6'), findsOneWidget);
      expect(find.text('200.6', skipOffstage: false), findsOneWidget, reason: 'no duplicates after merge');
    });

    testWidgets('404 → "Commentary not available"; 500 → error + retry', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(completedDetailData()));
      api.commentary = (_) => err(404, 'Commentary not found');
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);
      expect(find.text('Commentary not available'), findsOneWidget);

      api.commentary = (_) => err(500);
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_commentary');
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_commentary_error')), findsOneWidget);
      api.commentary = (_) => ok(J.map(fixture('match_commentary')['data']));
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('61.6', skipOffstage: false), findsOneWidget);
    });
  });

  group('polling', () {
    testWidgets('detail + live every 10 s; never overlaps; stops when the match ends', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(api.count('detail'), 1);
      expect(api.count('live'), 1);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(api.count('detail'), 2);
      expect(api.count('live'), 2);

      final slow = Completer<http.Response>();
      api.live = (_) => slow.future;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(api.count('live'), 3);
      await tester.pump(const Duration(minutes: 1));
      expect(api.count('live'), 3);
      slow.complete(ok(J.map(fixture('match_live')['data'])));
      await tester.pump();

      api.live = (_) => ok(J.map(fixture('match_live')['data']));
      api.detail = (_) => ok(completedDetailData());
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_live_badge')), findsNothing);
      expect(api.count('player'), 1);
      final n = api.calls.length;
      await tester.pump(const Duration(minutes: 3));
      expect(api.calls.length, n);
    });

    testWidgets('unchanged poll responses do not rebuild the header score', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      await pumpScreen(tester, api);
      await settle(tester);
      final before = tester.widget(find.byKey(const ValueKey('match_detail_score_team1')));
      await tester.pump(const Duration(seconds: 10));
      await settle(tester, 2);
      expect(identical(tester.widget(find.byKey(const ValueKey('match_detail_score_team1'))), before), isTrue);
    });

    testWidgets('pauses while backgrounded; refreshes on resume', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
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

    testWidgets('pauses while another route covers it; series link is tap-guarded', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      final router = await pumpScreen(tester, api);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('match_detail_series_link')));
      await tester.tap(find.byKey(const ValueKey('match_detail_series_link')), warnIfMissed: false);
      await settle(tester, 10);
      expect(find.text('series ser-1 Bangladesh tour of South Africa 2026'), findsOneWidget);
      final n = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, n, reason: 'covered route must not poll');
      router.pop();
      await settle(tester, 10);
      expect(find.byKey(const ValueKey('match_detail_series_link')), findsOneWidget, reason: 'only one route was pushed');
      expect(api.count('detail'), 2, reason: 'immediate refresh after being uncovered');
      router.pop();
      await settle(tester, 10);
      expect(find.text('home'), findsOneWidget);
      final m = api.calls.length;
      await tester.pump(const Duration(minutes: 2));
      expect(api.calls.length, m, reason: 'disposed screen must not poll');
    });

    testWidgets('scorecard polls every 10 s only on its tab', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(liveStatusDetail()));
      await pumpScreen(tester, api);
      await settle(tester);
      final base = api.count('scorecard');
      await tapKey(tester, 'match_detail_tab_scorecard');
      await settle(tester, 2);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(api.count('scorecard'), greaterThan(base));
      final on = api.count('scorecard');
      await tapKey(tester, 'match_detail_tab_commentary');
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(api.count('scorecard'), on, reason: 'off the tab only the 60 s header refresh runs');
    });
  });

  group('rewarded gates, errors', () {
    testWidgets('scorecard and line-ups are gated when the rewarded placement is ready', (tester) async {
      AdsManager.instance.debugReset(backend: const NoopAdsBackend(), ready: true);
      addTearDown(() => AdsManager.instance.debugReset());
      final api = FakeApi()..detail = ((_) => ok(completedDetailData()));
      await pumpScreen(tester, api);
      await settle(tester);
      await tapKey(tester, 'match_detail_tab_scorecard');
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('match_detail_reward_gate_scorecard')), findsOneWidget);
      expect(find.byType(MatchScorecardTab), findsNothing);
      await tapKey(tester, 'match_detail_tab_info');
      await settle(tester, 2);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('match_detail_reward_gate_playing_xi')), 300, scrollable: mainScrollable);
      expect(find.byType(MatchPlayingXITab, skipOffstage: false), findsNothing, reason: 'gated section must not mount/fetch');
      await tester.tap(find.byKey(const ValueKey('match_detail_reward_gate_playing_xi_button')));
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('match_detail_reward_gate_playing_xi')), findsOneWidget);
      expect(api.count('playing11'), 0);
    });

    testWidgets('server 500 → error view; Try again recovers; Go back pops', (tester) async {
      final api = FakeApi()..detail = ((_) => err(500, 'Internal'));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.byKey(const ValueKey('match_detail_error')), findsOneWidget);
      expect(find.text('Internal'), findsOneWidget);
      api.detail = (_) => ok(completedDetailData());
      await tester.tap(find.byKey(const ValueKey('match_detail_retry')));
      await settle(tester);
      expect(find.text('South Africa won by 5 wickets'), findsOneWidget);
    });

    testWidgets('network error message; Go back pops', (tester) async {
      final api = FakeApi()..detail = ((_) => throw http.ClientException('offline'));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.text('Unable to reach the server. Check your connection and try again.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('match_detail_go_back')));
      await settle(tester, 8);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('empty data and missing id', (tester) async {
      final api = FakeApi()..detail = ((_) => ok(null));
      await pumpScreen(tester, api);
      await settle(tester);
      expect(find.text('Match details are not available'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const MatchDetailScreen(matchId: '')));
      expect(find.text('Match ID is required'), findsOneWidget);
      expect(find.byKey(const ValueKey('match_detail_retry')), findsNothing);
    });

    testWidgets('very long names at 320 dp and dark theme do not overflow', (tester) async {
      final api = FakeApi();
      final d = completedDetailData();
      (d['teams'] as Map)['t1']['name'] = 'An Extremely Long Team Name That Goes On And On Forever XI';
      d['seriesName'] = 'A ridiculously long series name ' * 4;
      api.detail = (_) => ok(d);
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpScreen(tester, api, mode: ThemeMode.dark);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
