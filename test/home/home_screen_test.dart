import 'dart:async';

import 'package:crickbex/core/brand/brand.dart';
import 'package:crickbex/core/router/app_nav.dart';
import 'package:crickbex/core/widgets/titles.dart';
import 'package:crickbex/features/common/live_match_card.dart';
import 'package:crickbex/features/common/match_row.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/home/home_screen.dart';
import 'package:crickbex/features/search/search_index.dart';
import 'package:crickbex/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_test_router.dart';
import '../common/helpers.dart';

/// The fixtures' first upcoming match starts 2026-11-18 03:30Z.
final _now = DateTime.utc(2026, 11, 18, 1, 0);

Map<String, Responder> _routes() => {
  ...defaultRoutes(),
  '/match/live': FakeApi.ok(body(const [])),
};

Map<String, Responder> _liveRoutes() => {
  ..._routes(),
  '/match/live': FakeApi.ok(
    body([
      liveMatchJson(key: 'L1'),
      liveMatchJson(key: 'L2', series: 'Other Cup'),
    ]),
  ),
  '/match/L1': FakeApi.fixture('match_detail'),
};

Future<GoRouter> _pumpHome(
  WidgetTester tester,
  FakeApi api, {
  bool settleNow = true,
  Size size = const Size(800, 4200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  api.install();
  final router = appTestRouter(home: const HomeScreen());
  await tester.pumpWidget(routerApp(router));
  if (settleNow) await settle(tester);
  return router;
}

/// Unmount so the poll timer and live pulse are disposed.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SearchIndex.instance = SearchIndex();
    MinuteClock.nowFn = () => _now;
  });
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  testWidgets('skeleton while loading, then live empty + soon + results', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeApi({
      ..._routes(),
      '/match/recent': FakeApi.gated(gate, FakeApi.fixture('match_recent')),
      '/match/live': FakeApi.gated(gate, FakeApi.ok(body(const []))),
    });
    await _pumpHome(tester, api, settleNow: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('home_shimmer')), findsOneWidget);
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(find.text('CrickBex'), findsNothing);
    expect(find.byKey(const ValueKey('app_bar_search')), findsOneWidget);

    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('home_shimmer')), findsNothing);
    expect(find.text('Live now'), findsOneWidget);
    // Nothing live: the next start counts down instead of a blank section.
    expect(find.byKey(const ValueKey('home_live_empty')), findsOneWidget);
    expect(find.text('No matches are live right now'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_next_start_countdown')),
      findsOneWidget,
    );
    expect(find.text('in 2h 30m'), findsOneWidget);
    expect(find.text('Starting soon'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')),
      findsOneWidget,
    );
    expect(find.text('Latest results'), findsOneWidget);
    expect(find.byKey(const ValueKey('home_result_LCoO4aA')), findsOneWidget);
    // Max 5 results (fixture has 10).
    expect(find.byType(MatchRow), findsNWidgets(5 + 5));
    expect(find.text('Upcoming series'), findsOneWidget);
    expect(find.text('Mens Asia Cup Rising Stars 2026'), findsOneWidget);
    // No raw status words anywhere.
    for (final raw in ['LIVE', 'COMPLETED', 'NOT_STARTED', 'Live Matches']) {
      expect(find.text(raw), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('countdowns tick per minute on the shared clock', (tester) async {
    await _pumpHome(tester, FakeApi(_routes()));
    expect(find.text('in 2h 30m'), findsOneWidget);
    MinuteClock.nowFn = () => _now.add(const Duration(minutes: 31));
    MinuteClock.instance.debugTick();
    await tester.pump();
    expect(find.text('in 1h 59m'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('live: raised card with seam strip + other live as rows', (
    tester,
  ) async {
    final api = FakeApi(_liveRoutes());
    await _pumpHome(tester, api);
    final card = find.byKey(const ValueKey('home_live_card_L1'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('common_live_badge')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('common_live_seam')),
      ),
      findsOneWidget,
    );
    expect(find.text('Over 61'), findsOneWidget);
    expect(find.text('UAE Bulls need 87 runs in 35 balls'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('home_live_row_L2')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_live_empty')), findsNothing);
    expect(find.textContaining('2 matches'), findsOneWidget);
    expect(api.count('/match/L1'), 1, reason: 'one detail request per poll');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('in-progress items of /match/recent count as live', (
    tester,
  ) async {
    final recent = fixtureJson('match_recent')['data'] as List;
    await _pumpHome(
      tester,
      FakeApi({
        ..._routes(),
        '/match/live': FakeApi.status(500),
        '/match/recent': FakeApi.ok(body([liveMatchJson(), ...recent])),
      }),
    );
    expect(find.byKey(const ValueKey('home_live_card_LIVE01')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_live_error')), findsNothing);
    await _unmount(tester);
  });

  testWidgets('empty everywhere still points to the next action', (
    tester,
  ) async {
    final empty = FakeApi.ok(body(const []));
    final router = await _pumpHome(
      tester,
      FakeApi({
        '/match/recent': empty,
        '/match/live': empty,
        '/match/upcoming': empty,
        '/series/upcoming': empty,
      }),
    );
    expect(find.byKey(const ValueKey('home_live_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_next_start')), findsNothing);
    expect(find.byKey(const ValueKey('home_upcoming_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_results_empty')), findsOneWidget);
    expect(find.text('Upcoming series'), findsNothing, reason: 'quiet: hidden');
    await tester.tap(find.byKey(const ValueKey('home_live_empty_action')));
    await settle(tester);
    expect(location(router), '/matches');
    await _unmount(tester);
  });

  testWidgets('live error → Try again recovers; sections fail alone', (
    tester,
  ) async {
    var fail = true;
    Responder flaky(Responder ok) =>
        (r) => fail ? FakeApi.status(500)(r) : ok(r);
    final api = FakeApi({
      ..._routes(),
      '/match/recent': flaky(FakeApi.fixture('match_recent')),
      '/match/live': flaky(FakeApi.ok(body(const []))),
      '/match/upcoming': flaky(FakeApi.fixture('match_upcoming')),
    });
    await _pumpHome(tester, api);
    expect(find.byKey(const ValueKey('home_live_error')), findsOneWidget);
    expect(find.text('Server exploded'), findsWidgets);
    expect(find.byKey(const ValueKey('home_upcoming_error')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('home_live_retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('home_live_error')), findsNothing);
    expect(find.byKey(const ValueKey('home_result_LCoO4aA')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_upcoming_retry')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('results fail alone: inline error, live still shown', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      FakeApi({..._liveRoutes(), '/match/recent': FakeApi.status(503, 'Down')}),
    );
    expect(find.byKey(const ValueKey('home_live_card_L1')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_results_error')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('tab jumps land on the right tab; search opens on Home', (
    tester,
  ) async {
    final router = await _pumpHome(tester, FakeApi(_liveRoutes()));
    Future<void> back() async {
      router.go('/home');
      await settle(tester);
    }

    await tester.tap(find.text('All live'));
    await settle(tester);
    expect(location(router), '/live');
    await back();

    await tester.tap(find.text('Schedule'));
    await settle(tester);
    expect(location(router), '/matches');
    await back();

    await tester.tap(find.text('All results'));
    await settle(tester);
    expect(location(router), '/matches');
    await back();

    await tester.tap(find.text('All series'));
    await settle(tester);
    expect(location(router), '/discover/series');
    await back();

    await tester.tap(find.byKey(const ValueKey('app_bar_search')));
    await settle(tester);
    expect(location(router), '/home/search');
    expect(find.byType(SearchScreen), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'regression: the Live now card still opens after the match page was left via a tab switch',
    (tester) async {
      // Leaving the pushed match page by switching tabs (the stack is reset)
      // never completes the push Future. That used to leave Home's tap guard
      // locked, so Home cards did nothing until another tab was used.
      final router = await _pumpHome(tester, FakeApi(_liveRoutes()));
      final card = find.byKey(const ValueKey('home_live_card_L1'));
      await tester.tap(card);
      await settle(tester);
      expect(location(router), '/home/match/L1');

      router.go('/live'); // tab switch: the Home stack's push is abandoned
      await settle(tester);
      router.go('/home');
      await settle(tester);
      expect(location(router), '/home');

      for (var i = 0; i < AppNav.pushFrames + 5; i++) {
        await tester.pump(const Duration(milliseconds: 50)); // frames + guard cooldown
      }
      await tester.tap(find.byKey(const ValueKey('home_live_card_L1')));
      await settle(tester);
      expect(location(router), '/home/match/L1', reason: 'card must open again');
      await _unmount(tester);
    },
  );

  testWidgets(
    'rows and cards open Match Centre on the Home stack; double tap pushes once',
    (tester) async {
      final router = await _pumpHome(tester, FakeApi(_liveRoutes()));
      final card = find.byKey(const ValueKey('home_live_card_L1'));
      await tester.tap(card);
      await tester.tap(card, warnIfMissed: false);
      await settle(tester);
      expect(location(router), '/home/match/L1');
      router.pop();
      await settle(tester);
      expect(location(router), '/home', reason: 'only one route was pushed');

      await tester.pump(const Duration(seconds: 1)); // guard cooldown
      await tester.tap(
        find.byKey(const ValueKey('home_upcoming_card_w2bXPRS')),
      );
      await settle(tester);
      expect(location(router), '/home/match/w2bXPRS');
      router.pop();
      await settle(tester);

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('home_result_LCoO4aA')));
      await settle(tester);
      expect(location(router), '/home/match/LCoO4aA');
      router.pop();
      await settle(tester);

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(
        find.byKey(const ValueKey('home_series_6afc9d2c31bbe1ca564b0c71')),
      );
      await settle(tester);
      expect(location(router), '/home/series-detail/sddbjDn');
      expect(
        find.text('series:sddbjDn:Mens Asia Cup Rising Stars 2026'),
        findsOneWidget,
      );
      await _unmount(tester);
    },
  );

  testWidgets('series without sb_series_key resolves via catalog/probe', (
    tester,
  ) async {
    final api = FakeApi({
      ..._routes(),
      '/series/upcoming': FakeApi.ok(
        body([
          {
            '_id': 'raw1',
            'name': 'Odd Series',
            'startDate': '2026-12-01T00:00:00Z',
            'endDate': '2026-12-10T00:00:00Z',
          },
        ]),
      ),
      '/series': FakeApi.ok(
        body([
          {'name': 'Odd Series', '_id': 'raw1', 'sb_series_key': 'SBX'},
        ]),
      ),
      '/series/SBX': FakeApi.fixture('series_fixtures'),
    });
    final router = await _pumpHome(tester, api);
    await tester.tap(find.byKey(const ValueKey('home_series_raw1')));
    await settle(tester);
    expect(location(router), '/home/series-detail/SBX');
    await _unmount(tester);
  });

  testWidgets('pull-to-refresh reloads live, recent and upcoming', (
    tester,
  ) async {
    final api = FakeApi(_routes());
    await _pumpHome(tester, api);
    expect(api.count('/match/recent'), 1);
    expect(api.count('/match/live'), 1);
    await pullToRefresh(
      tester,
      find.byKey(const ValueKey('home_scroll')),
      1300,
    );
    await settle(tester, frames: 30);
    expect(api.count('/match/recent'), 2);
    expect(api.count('/match/live'), 2);
    expect(api.count('/match/upcoming'), 2);
    expect(find.byKey(const ValueKey('home_result_LCoO4aA')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'polls every 30 s; paused behind a detail route and on other tabs',
    (tester) async {
      final api = FakeApi(_routes());
      final router = await _pumpHome(tester, api);
      expect(api.count('/match/live'), 1);
      await tester.pump(const Duration(seconds: 30));
      await settle(tester);
      expect(api.count('/match/live'), 2);
      expect(api.count('/match/recent'), 2);

      await tester.tap(find.byKey(const ValueKey('home_result_LCoO4aA')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 95));
      expect(api.count('/match/live'), 2, reason: 'paused behind a detail');
      router.pop();
      await settle(tester);
      expect(
        api.count('/match/live'),
        3,
        reason: 'immediate refresh on return',
      );

      StatefulNavigationShell.of(
        tester.element(find.byType(HomeScreen)),
      ).goBranch(2);
      await settle(tester);
      await tester.pump(const Duration(seconds: 95));
      expect(api.count('/match/live'), 3, reason: 'paused on another tab');
      router.go('/home');
      await settle(tester);
      expect(api.count('/match/live'), 4);
      await _unmount(tester);
    },
  );

  testWidgets('a slow request is never stacked by later poll ticks', (
    tester,
  ) async {
    HomeScreen.pollInterval = const Duration(seconds: 4);
    addTearDown(() => HomeScreen.pollInterval = const Duration(seconds: 30));
    Completer<void>? gate;
    final api = FakeApi({
      ..._routes(),
      '/match/recent': (r) async {
        final g = gate;
        if (g != null) await g.future;
        return FakeApi.fixture('match_recent')(r);
      },
    });
    await _pumpHome(tester, api);
    expect(api.count('/match/recent'), 1);
    gate = Completer<void>();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    expect(api.count('/match/recent'), 2);
    gate.complete();
    gate = null;
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(api.count('/match/recent'), 3);
    await _unmount(tester);
  });

  testWidgets('two columns on wide screens, no overflow on a small phone', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      FakeApi(_liveRoutes()),
      size: const Size(1440, 900),
    );
    final live = tester.getTopLeft(find.text('Live now'));
    final results = tester.getTopLeft(find.text('Latest results'));
    expect(results.dx, greaterThan(live.dx + 300));
    expect(results.dy, lessThan(live.dy + 50));
    await _unmount(tester);

    await _pumpHome(tester, FakeApi(_liveRoutes()), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveMatchCard), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('malformed payloads never crash the screen', (tester) async {
    await _pumpHome(
      tester,
      FakeApi({
        '/match/live': FakeApi.ok('{"data": "nope"}'),
        '/match/recent': FakeApi.ok(
          '{"data": [1, {"teams": "x", "status": "LIVE"}, {}]}',
        ),
        '/match/upcoming': FakeApi.ok('{"data": {"oops": true}}'),
        '/series/upcoming': FakeApi.ok('{"data": [{"name": 5}]}'),
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveMatchCard), findsOneWidget);
    expect(find.byKey(const ValueKey('home_upcoming_empty')), findsOneWidget);
    expect(
      find.text(Brand.appName),
      findsNothing,
      reason: 'wordmark, not text',
    );
    await _unmount(tester);
  });
}
