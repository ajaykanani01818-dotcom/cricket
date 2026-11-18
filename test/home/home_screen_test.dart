import 'dart:async';

import 'package:crickbex/features/common/live_match_card.dart';
import 'package:crickbex/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

Future<GoRouter> _pumpHome(WidgetTester tester, FakeApi api, {bool settleNow = true}) async {
  tester.view.physicalSize = const Size(800, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  api.install();
  final router = testRouter(home: const HomeScreen(), matches: const Scaffold(body: Text('tab:matches')));
  await tester.pumpWidget(routerApp(router));
  if (settleNow) await settle(tester);
  return router;
}

/// Unmount so the 30s poll timer and shimmer animations are disposed.
Future<void> _unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('loading shimmer → all sections with data', (tester) async {
    final gate = Completer<void>();
    final api = FakeApi({...defaultRoutes(), '/match/recent': FakeApi.gated(gate, FakeApi.fixture('match_recent'))});
    await _pumpHome(tester, api, settleNow: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('home_shimmer')), findsOneWidget);
    expect(find.text('CRICKBEX'), findsOneWidget);

    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('home_shimmer')), findsNothing);
    expect(find.text('Live Matches'), findsOneWidget);
    expect(find.byKey(const ValueKey('home_live_card_LCoO4aA')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_live_dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_player_shubman_gill')), findsOneWidget);
    expect(find.text('Mens Asia Cup Rising Stars 2026'), findsOneWidget);
    // Max 4 series rows (fixture has 8).
    expect(find.text('England tour of South Africa 2026-27'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('empty states for every section', (tester) async {
    final empty = FakeApi.ok(body([]));
    await _pumpHome(tester, FakeApi({'/match/recent': empty, '/match/upcoming': empty, '/series/upcoming': empty, '/rank/player': empty}));
    expect(find.text('No live matches right now'), findsOneWidget);
    expect(find.text('No upcoming matches scheduled'), findsOneWidget);
    expect(find.text('No rankings available'), findsOneWidget);
    expect(find.text('No upcoming series'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('live section error → Try Again recovers', (tester) async {
    var fail = true;
    final api = FakeApi({
      ...defaultRoutes(),
      '/match/recent': (r) => fail ? FakeApi.status(500)(r) : FakeApi.fixture('match_recent')(r),
    });
    await _pumpHome(tester, api);
    expect(find.byKey(const ValueKey('home_live_error')), findsOneWidget);
    expect(find.text('Server exploded'), findsOneWidget);
    // Other sections are unaffected.
    expect(find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('home_live_retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home_live_card_LCoO4aA')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('upcoming / rankings / series errors each retry independently', (tester) async {
    var fail = true;
    Responder flaky(String fixture) => (r) => fail ? FakeApi.status(503, 'Down')(r) : FakeApi.fixture(fixture)(r);
    final api = FakeApi({
      ...defaultRoutes(),
      '/match/upcoming': flaky('match_upcoming'),
      '/rank/player': flaky('rank_player'),
      '/series/upcoming': flaky('series_upcoming'),
    });
    await _pumpHome(tester, api);
    expect(find.byKey(const ValueKey('home_upcoming_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_rankings_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_series_error')), findsOneWidget);
    expect(find.text('Down'), findsNWidgets(3));
    fail = false;
    await tester.tap(find.byKey(const ValueKey('home_upcoming_retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_rankings_retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home_player_shubman_gill')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_series_retry')));
    await settle(tester);
    expect(find.text('Mens Asia Cup Rising Stars 2026'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('crafted LIVE match: blue card with LIVE badge + chase line', (tester) async {
    final recent = fixtureJson('match_recent')['data'] as List;
    await _pumpHome(tester, FakeApi({...defaultRoutes(), '/match/recent': FakeApi.ok(body([liveMatchJson(), ...recent]))}));
    final card = find.byKey(const ValueKey('home_live_card_LIVE01'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const ValueKey('common_live_badge'))), findsOneWidget);
    expect(find.text('UAE Bulls need 87 runs in 35 balls'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('navigation: match, player, series detail, See all tabs; double tap pushes once', (tester) async {
    final router = await _pumpHome(tester, FakeApi(defaultRoutes()));

    await tester.tap(find.byKey(const ValueKey('home_live_card_LCoO4aA')));
    await tester.tap(find.byKey(const ValueKey('home_live_card_LCoO4aA')), warnIfMissed: false);
    await settle(tester);
    expect(location(router), '/live/match/LCoO4aA');
    expect(find.text('match:LCoO4aA'), findsOneWidget);
    router.pop();
    await settle(tester);
    expect(location(router), '/live', reason: 'only one route was pushed');

    await tester.pump(const Duration(seconds: 1)); // guard cooldown
    await tester.tap(find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')));
    await settle(tester);
    expect(location(router), '/live/match/w2bXPRS');
    router.pop();
    await settle(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('home_player_shubman_gill')));
    await settle(tester);
    expect(location(router), '/live/player/shubman_gill');
    router.pop();
    await settle(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('home_series_6afc9d2c31bbe1ca564b0c71')));
    await settle(tester);
    expect(location(router), '/live/series-detail/sddbjDn');
    expect(find.text('series:sddbjDn:Mens Asia Cup Rising Stars 2026'), findsOneWidget);
    router.pop();
    await settle(tester);

    // "See all" (live) / "Full schedule" → Matches tab; Rankings → Ranking tab; Tournaments → Series.
    await tester.tap(find.text('See all').first);
    await settle(tester);
    expect(location(router), '/matches');
    router.go('/live');
    await settle(tester);
    await tester.tap(find.text('Full schedule'));
    await settle(tester);
    expect(location(router), '/matches');
    router.go('/live');
    await settle(tester);
    await tester.tap(find.text('See all').at(1));
    await settle(tester);
    expect(location(router), '/ranking');
    router.go('/live');
    await settle(tester);
    await tester.tap(find.text('See all').at(2));
    await settle(tester);
    expect(location(router), '/series');
    await _unmount(tester);
  });

  testWidgets('series without sb_series_key resolves via catalog/probe', (tester) async {
    final api = FakeApi({
      ...defaultRoutes(),
      '/series/upcoming': FakeApi.ok(body([
        {'_id': 'raw1', 'name': 'Odd Series', 'startDate': '2026-12-01T00:00:00Z', 'endDate': '2026-12-10T00:00:00Z'},
      ])),
      '/series': FakeApi.ok(body([
        {'name': 'Odd Series', '_id': 'raw1', 'sb_series_key': 'SBX'},
      ])),
      '/series/SBX': FakeApi.fixture('series_fixtures'),
    });
    final router = await _pumpHome(tester, api);
    await tester.tap(find.byKey(const ValueKey('home_series_raw1')));
    await settle(tester);
    expect(location(router), '/live/series-detail/SBX');
    // Catalog sb_series_key is tried first (RN unshift order) and resolves.
    expect(api.count('/series/SBX'), 1);
    expect(api.count('/series/raw1'), 0);
    await _unmount(tester);
  });

  testWidgets('pull-to-refresh reloads live matches', (tester) async {
    final api = FakeApi(defaultRoutes());
    await _pumpHome(tester, api);
    expect(api.count('/match/recent'), 1);
    // RefreshIndicator arms after dragging 25% of the (tall test) viewport.
    await pullToRefresh(tester, find.byKey(const ValueKey('home_scroll')), 1300);
    await settle(tester, frames: 30);
    expect(api.count('/match/recent'), 2);
    expect(find.byKey(const ValueKey('home_live_card_LCoO4aA')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('top players: category pills and format dropdown', (tester) async {
    final api = FakeApi({
      ...defaultRoutes(),
      '/rank/player': (req) {
        final q = req.url.queryParameters;
        final key = '${q['matchType']}_${q['type']}'.toLowerCase();
        return http.Response(body([
          {'name': 'Player $key', 'points': 900, 'order': 1, 'playerKey': key},
        ]), 200);
      },
    });
    await _pumpHome(tester, api);
    expect(find.byKey(const ValueKey('home_player_odi_batsman')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_category_bowlers')));
    await tester.pump();
    expect(find.byKey(const ValueKey('home_player_odi_bowler')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_category_allRounders')));
    await tester.pump();
    expect(find.byKey(const ValueKey('home_player_odi_all_rounder')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home_format_dropdown')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home_format_T20')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home_player_t20_all_rounder')), findsOneWidget);
    expect(find.text('T20'), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('auto-refresh every 30s, paused behind a detail route and on other tabs, never overlapping', (tester) async {
    Completer<void>? gate;
    final api = FakeApi({
      ...defaultRoutes(),
      '/match/recent': (r) async {
        final g = gate;
        if (g != null) await g.future;
        return FakeApi.fixture('match_recent')(r);
      },
    });
    final router = await _pumpHome(tester, api);
    expect(api.count('/match/recent'), 1);
    await tester.pump(const Duration(seconds: 30));
    await settle(tester);
    expect(api.count('/match/recent'), 2);

    // Detail route on top → paused.
    await tester.tap(find.byKey(const ValueKey('home_live_card_LCoO4aA')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 95));
    expect(api.count('/match/recent'), 2);
    // Back → immediate refresh, then resumes.
    router.pop();
    await settle(tester);
    expect(api.count('/match/recent'), 3);

    // Other tab → paused.
    StatefulNavigationShell.of(tester.element(find.byType(HomeScreen))).goBranch(1);
    await settle(tester);
    await tester.pump(const Duration(seconds: 95));
    expect(api.count('/match/recent'), 3);
    router.go('/live');
    await settle(tester);
    expect(api.count('/match/recent'), 4);

    await _unmount(tester);
  });

  testWidgets('a slow live request is never stacked by later poll ticks', (tester) async {
    HomeScreen.pollInterval = const Duration(seconds: 4);
    addTearDown(() => HomeScreen.pollInterval = const Duration(seconds: 30));
    Completer<void>? gate;
    final api = FakeApi({
      ...defaultRoutes(),
      '/match/recent': (r) async {
        final g = gate;
        if (g != null) await g.future;
        return FakeApi.fixture('match_recent')(r);
      },
    });
    await _pumpHome(tester, api);
    expect(api.count('/match/recent'), 1);
    gate = Completer<void>();
    await tester.pump(const Duration(seconds: 4)); // tick → request #2 (hangs)
    await tester.pump(const Duration(seconds: 4)); // skipped
    await tester.pump(const Duration(seconds: 4)); // skipped
    expect(api.count('/match/recent'), 2);
    // Pull-to-refresh joins the in-flight request too.
    gate.complete();
    gate = null;
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(api.count('/match/recent'), 3);
    await _unmount(tester);
  });

  testWidgets('carousel swipe moves the active dot', (tester) async {
    await _pumpHome(tester, FakeApi(defaultRoutes()));
    AnimatedContainer dot(int i) => tester.widget<AnimatedContainer>(
        find.descendant(of: find.byKey(const ValueKey('home_live_dots')), matching: find.byType(AnimatedContainer)).at(i));
    expect(dot(0).constraints?.maxWidth, 20);
    await tester.drag(find.byKey(const ValueKey('home_live_carousel')), const Offset(-(liveCardWidth + liveCardMargin) * 2, 0));
    await settle(tester);
    expect(dot(0).constraints?.maxWidth, 6);
    expect(dot(2).constraints?.maxWidth, 20);
    await _unmount(tester);
  });

  testWidgets('malformed payloads never crash the screen', (tester) async {
    await _pumpHome(
        tester,
        FakeApi({
          '/match/recent': FakeApi.ok('{"data": [1, {"teams": "x"}, {}]}'),
          '/match/upcoming': FakeApi.ok('{"data": {"oops": true}}'),
          '/series/upcoming': FakeApi.ok('{"data": [{"name": 5}]}'),
          '/rank/player': FakeApi.ok('{"data": null}'),
        }));
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveMatchCard), findsNWidgets(2));
    expect(find.text('No upcoming matches scheduled'), findsOneWidget);
    await _unmount(tester);
  });
}
