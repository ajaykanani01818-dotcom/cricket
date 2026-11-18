import 'dart:async';

import 'package:crickbex/features/common/live_match_card.dart';
import 'package:crickbex/features/common/upcoming_match_card.dart';
import 'package:crickbex/features/matches/matches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';
import 'matches_logic_test.dart' show completedPaged;

Future<GoRouter> _pumpMatches(WidgetTester tester, FakeApi api, {bool settleNow = true, Size size = const Size(800, 1400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  api.install();
  final router = testRouter(home: const Scaffold(body: Text('tab:live')), matches: const MatchesScreen(), initialLocation: '/matches');
  await tester.pumpWidget(routerApp(router));
  if (settleNow) await settle(tester);
  return router;
}

Future<void> _unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> _selectTab(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('tab_$key')));
  await settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shimmer → Live tab empty state (no live matches in local data)', (tester) async {
    final gate = Completer<void>();
    await _pumpMatches(tester, FakeApi({...defaultRoutes(), '/match/live': FakeApi.gated(gate, FakeApi.fixture('match_live_list'))}),
        settleNow: false);
    await tester.pump();
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.byKey(const ValueKey('matches_shimmer')), findsWidgets);
    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('matches_empty_live')), findsOneWidget);
    expect(find.text('No live matches right now'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('tab switching by tap and by swipe; upcoming grouped by series', (tester) async {
    await _pumpMatches(tester, FakeApi({...defaultRoutes(), '/match/completed': completedPaged()}));
    await _selectTab(tester, 'upcoming');
    expect(find.text('ENGLAND TOUR OF AUSTRALIA 2026'), findsWidgets); // header band (+ card series line)
    expect(find.byType(UpcomingMatchCard), findsWidgets);
    expect(find.text('STARTS IN'), findsWidgets);

    await tester.fling(find.byKey(const ValueKey('matches_pager')), const Offset(-600, 0), 2000);
    await settle(tester);
    expect(find.byKey(const ValueKey('common_result_row')), findsWidgets, reason: 'Recent tab shows results');

    await tester.fling(find.byKey(const ValueKey('matches_pager')), const Offset(600, 0), 2000);
    await settle(tester);
    expect(find.text('STARTS IN'), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('crafted LIVE match on the Live tab: full-width live card, tap opens detail', (tester) async {
    final router = await _pumpMatches(tester, FakeApi({...defaultRoutes(), '/match/live': FakeApi.ok(body([liveMatchJson()]))}));
    expect(find.byType(LiveMatchCard), findsOneWidget);
    expect(find.byKey(const ValueKey('common_live_badge')), findsOneWidget);
    expect(find.text('UAE Bulls need 87 runs in 35 balls'), findsOneWidget);
    await tester.tap(find.byType(LiveMatchCard));
    await tester.tap(find.byType(LiveMatchCard), warnIfMissed: false);
    await settle(tester);
    expect(location(router), '/matches/match/LIVE01');
    router.pop();
    await settle(tester);
    expect(location(router), '/matches');
    await _unmount(tester);
  });

  testWidgets('Live tab falls back to /match/recent filtered by live when /match/live fails', (tester) async {
    final recent = fixtureJson('match_recent')['data'] as List;
    await _pumpMatches(
        tester,
        FakeApi({
          ...defaultRoutes(),
          '/match/live': FakeApi.status(500),
          '/match/recent': FakeApi.ok(body([...recent, liveMatchJson(key: 'LIVE02')])),
        }));
    expect(find.byType(LiveMatchCard), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('error state + Try Again per tab', (tester) async {
    var fail = true;
    Responder flaky(Responder ok) => (r) => fail ? FakeApi.status(500, 'Server exploded')(r) : ok(r);
    final api = FakeApi({
      '/match/live': flaky(FakeApi.ok(body([liveMatchJson()]))),
      '/match/recent': FakeApi.status(500, 'Server exploded'),
      '/match/upcoming': flaky(FakeApi.fixture('match_upcoming')),
      '/match/completed': flaky(completedPaged()),
    });
    await _pumpMatches(tester, api);
    expect(find.byKey(const ValueKey('matches_error_live')), findsOneWidget);
    expect(find.text('Server exploded'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('matches_retry_live')));
    await settle(tester);
    expect(find.byType(LiveMatchCard), findsOneWidget);

    await _selectTab(tester, 'upcoming');
    expect(find.byKey(const ValueKey('matches_error_upcoming')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('matches_retry_upcoming')));
    await settle(tester);
    expect(find.text('STARTS IN'), findsWidgets);

    await _selectTab(tester, 'completed');
    expect(find.byKey(const ValueKey('matches_error_completed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('matches_retry_completed')));
    await settle(tester);
    expect(find.byKey(const ValueKey('common_result_row')), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('Recent: scrolling to the end loads page 2 exactly once, then "No more matches"', (tester) async {
    final gate = Completer<void>();
    final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged(page2Gate: gate)});
    await _pumpMatches(tester, api, size: const Size(800, 900));
    await _selectTab(tester, 'completed');
    final list = find.byKey(const PageStorageKey('matches_list_completed'));
    expect(list, findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), isEmpty);

    // Several scroll gestures towards the end while page 2 is in flight.
    for (var i = 0; i < 4; i++) {
      await tester.drag(list, const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('matches_loading_more')), findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1));

    gate.complete();
    await settle(tester);
    await tester.drag(list, const Offset(0, -5000));
    await settle(tester);
    expect(find.text('PAGE TWO SERIES'), findsWidgets); // header band + card series lines
    expect(find.byKey(const ValueKey('matches_no_more')), findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1));
    expect(api.log.where((u) => u.queryParameters['page'] == '3'), isEmpty);
    await _unmount(tester);
  });

  testWidgets('Recent: failed next page keeps the list and the footer retries', (tester) async {
    var fail = true;
    final api = FakeApi({...defaultRoutes(), '/match/completed': (r) => completedPaged(failPage2: fail)(r)});
    await _pumpMatches(tester, api, size: const Size(800, 900));
    await _selectTab(tester, 'completed');
    final list = find.byKey(const PageStorageKey('matches_list_completed'));
    await tester.drag(list, const Offset(0, -6000));
    await settle(tester);
    await tester.drag(list, const Offset(0, -6000));
    await settle(tester);
    expect(find.byKey(const ValueKey('matches_load_more_error')), findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1), reason: 'no automatic retry loop');
    expect(find.byKey(const ValueKey('matches_error_completed')), findsNothing);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('matches_load_more_retry')));
    await settle(tester);
    await tester.drag(list, const Offset(0, -6000));
    await settle(tester);
    expect(find.byKey(const ValueKey('matches_no_more')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('pull-to-refresh refetches all tabs and resets paging', (tester) async {
    final api = FakeApi({...defaultRoutes(), '/match/live': FakeApi.ok(body([liveMatchJson()]))});
    await _pumpMatches(tester, api);
    expect(api.count('/match/live'), 1);
    await pullToRefresh(tester, find.byKey(const PageStorageKey('matches_list_live')), 450);
    await settle(tester, frames: 30);
    expect(api.count('/match/live'), 2);
    expect(api.count('/match/upcoming'), 2);
    expect(api.count('/match/completed'), 2);
    expect(api.log.last.queryParameters['page'] ?? '1', '1');
    await _unmount(tester);
  });

  testWidgets('empty Upcoming / Recent show "No matches in this section"', (tester) async {
    final empty = FakeApi.ok(body([]));
    await _pumpMatches(tester, FakeApi({'/match/live': empty, '/match/upcoming': empty, '/match/completed': empty}));
    await _selectTab(tester, 'upcoming');
    expect(find.byKey(const ValueKey('matches_empty_upcoming')), findsOneWidget);
    await _selectTab(tester, 'completed');
    expect(find.byKey(const ValueKey('matches_empty_completed')), findsOneWidget);
    expect(find.text('No matches in this section'), findsWidgets);
    await _unmount(tester);
  });
}
