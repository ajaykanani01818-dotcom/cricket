import 'dart:async';

import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/live/live_screen.dart';
import 'package:crickbex/features/search/search_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_test_router.dart';
import '../common/helpers.dart';

Future<GoRouter> _pump(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  api.install();
  final r = appTestRouter(live: const LiveScreen(), initialLocation: '/live');
  await tester.pumpWidget(routerApp(r));
  return r;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SearchIndex.instance = SearchIndex();
    MinuteClock.nowFn = () => DateTime.utc(2026, 11, 18, 1);
  });
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  test('sorting rule: groups in provider order, in play before paused', () {
    final ms = parseMatchList([
      liveMatchJson(key: 'a', series: 'X')..['status'] = 'STUMPS',
      liveMatchJson(key: 'b', series: 'Y'),
      liveMatchJson(key: 'c', series: 'X'),
      liveMatchJson(key: 'd', series: 'X')..['status'] = 'INNINGS_BREAK',
      liveMatchJson(key: 'e', series: ''),
    ]);
    final g = sortLiveGroups(ms);
    expect(g.map((e) => e.$1), ['X', 'Y', 'Other matches']);
    expect(g.first.$2.map((m) => m.id), ['c', 'a', 'd']);
  });

  testWidgets('skeleton → grouped list with count, last updated, chase lines', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeApi({
      '/match/live': FakeApi.gated(
        gate,
        FakeApi.ok(
          body([
            liveMatchJson(key: 'L1', series: 'Series A')..['status'] = 'STUMPS',
            liveMatchJson(key: 'L2', series: 'Series B'),
            liveMatchJson(key: 'L3', series: 'Series A'),
          ]),
        ),
      ),
    });
    final r = await _pump(tester, api);
    await tester.pump();
    expect(find.byKey(const ValueKey('skeleton_list')), findsOneWidget);
    gate.complete();
    await settle(tester);
    expect(find.text('3 live'), findsOneWidget);
    expect(find.byKey(const ValueKey('live_updated')), findsOneWidget);
    expect(find.textContaining('Refreshes every 20 seconds'), findsOneWidget);
    expect(find.text('Series A'), findsOneWidget);
    expect(find.text('2 matches'), findsOneWidget);
    expect(find.text('Series B'), findsOneWidget);
    // In play (L3) sorts above stumps (L1) inside Series A.
    final y3 = tester
        .getTopLeft(find.byKey(const ValueKey('live_match_L3')))
        .dy;
    final y1 = tester
        .getTopLeft(find.byKey(const ValueKey('live_match_L1')))
        .dy;
    expect(y3, lessThan(y1));
    expect(find.text('Stumps'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live_match_L2')));
    await settle(tester);
    expect(r.state.uri.path, '/live/match/L2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nothing live: next start countdown + latest results', (
    tester,
  ) async {
    final r = await _pump(
      tester,
      FakeApi({
        '/match/live': FakeApi.ok(body(const [])),
        '/match/upcoming': FakeApi.fixture('match_upcoming'),
        '/match/recent': FakeApi.fixture('match_recent'),
      }),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('live_empty')), findsOneWidget);
    expect(find.text('Next to start'), findsOneWidget);
    expect(find.byKey(const ValueKey('live_next_w2bXPRS')), findsOneWidget);
    expect(find.text('2h 30m'), findsOneWidget);
    expect(find.text('Latest results'), findsOneWidget);
    expect(find.byKey(const ValueKey('live_result_LCoO4aA')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    await settle(tester);
    expect(r.state.uri.path, '/matches');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('error → Try again recovers; failed poll keeps the list', (
    tester,
  ) async {
    var fail = true;
    final api = FakeApi({
      '/match/live': (req) => fail
          ? FakeApi.status(500)(req)
          : FakeApi.ok(body([liveMatchJson(key: 'L1')]))(req),
    });
    await _pump(tester, api);
    await settle(tester);
    expect(find.byKey(const ValueKey('live_error')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    await settle(tester);
    expect(find.byKey(const ValueKey('live_match_L1')), findsOneWidget);
    fail = true;
    await tester.pump(kLivePollInterval);
    await settle(tester);
    expect(api.count('/match/live'), 3);
    expect(find.byKey(const ValueKey('live_match_L1')), findsOneWidget);
    expect(find.byKey(const ValueKey('live_error')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('polls every 20 s only while visible', (tester) async {
    final api = FakeApi({
      '/match/live': FakeApi.ok(body([liveMatchJson(key: 'L1')])),
    });
    final r = await _pump(tester, api);
    await settle(tester);
    expect(api.count('/match/live'), 1);
    await tester.pump(kLivePollInterval);
    await settle(tester);
    expect(api.count('/match/live'), 2);
    r.go('/home');
    await settle(tester);
    await tester.pump(const Duration(seconds: 90));
    expect(api.count('/match/live'), 2);
    r.go('/live');
    await settle(tester);
    expect(api.count('/match/live'), 3);
    await tester.pumpWidget(const SizedBox());
  });
}
