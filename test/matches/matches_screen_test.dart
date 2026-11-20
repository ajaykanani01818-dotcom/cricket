import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/matches/match_filters.dart';
import 'package:crickbex/features/matches/match_row.dart';
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
  final router = testRouter(
    home: const Scaffold(body: Text('tab:live')),
    matches: const MatchesScreen(),
    initialLocation: '/matches',
  );
  await tester.pumpWidget(routerApp(router));
  if (settleNow) await settle(tester);
  return router;
}

Future<void> _unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settle(tester);
}

Finder _rowsOf(String tab) => find.byWidgetPredicate(
  (w) => w is MatchRow && w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('match-$tab-'),
);

void main() {
  // Pin the clock: the first upcoming fixture starts 2026-11-18 03:30Z, so
  // the "Starts in" countdown (shown within 24 h) is deterministic.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MinuteClock.nowFn = () => DateTime.utc(2026, 11, 18, 1, 0);
  });
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  testWidgets('search icon in the top bar opens the search route', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FakeApi(defaultRoutes()).install();
    final router = GoRouter(
      initialLocation: '/matches',
      routes: [
        GoRoute(
          path: '/matches',
          builder: (_, _) => const MatchesScreen(),
          routes: [
            GoRoute(
              path: 'search',
              builder: (_, _) => const Scaffold(body: Text('page:search')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(routerApp(router));
    await settle(tester);
    final icon = find.byKey(const ValueKey('matches_search'));
    expect(icon, findsOneWidget);
    expect(tester.getSize(icon).height, greaterThanOrEqualTo(48));
    await tester.tap(icon);
    await tester.tap(icon, warnIfMissed: false);
    await settle(tester);
    expect(location(router), '/matches/search');
    expect(find.text('page:search'), findsOneWidget);
    router.pop();
    await settle(tester);
    expect(location(router), '/matches');
    await _unmount(tester);
  });

  testWidgets('skeleton, then the empty Live state sends people to Upcoming', (tester) async {
    final gate = Completer<void>();
    await _pumpMatches(
      tester,
      FakeApi({...defaultRoutes(), '/match/live': FakeApi.gated(gate, FakeApi.fixture('match_live_list'))}),
      settleNow: false,
    );
    await tester.pump();
    expect(find.text('Matches'), findsOneWidget);
    expect(find.byKey(const ValueKey('matches_shimmer')), findsWidgets);
    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('matches_empty_live')), findsOneWidget);
    expect(find.text('No live matches right now'), findsOneWidget);
    expect(find.byKey(const ValueKey('matches_day_strip')), findsNothing, reason: 'no day strip on Live');
    await _tap(tester, 'matches_empty_action_live');
    expect(find.text('Starts in 2h 30m'), findsOneWidget);
    expect(find.byKey(const ValueKey('matches_day_strip')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('segments: tap and swipe; upcoming grouped under sticky series headers with sentence-case countdown', (tester) async {
    await _pumpMatches(tester, FakeApi({...defaultRoutes(), '/match/completed': completedPaged()}));
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    await _tap(tester, 'tab_upcoming');
    expect(find.text('England tour of Australia 2026'), findsOneWidget, reason: 'series header, as the provider names it');
    expect(find.text('Womens Emerging Nations T20 Trophy 2026'), findsOneWidget, reason: '4 matches, one header');
    expect(find.text('Starts in 2h 30m'), findsOneWidget);
    expect(find.textContaining('STARTS IN'), findsNothing);
    expect(_rowsOf('upcoming'), findsWidgets);

    await tester.fling(find.byKey(const ValueKey('matches_pager')), const Offset(-600, 0), 2000);
    await settle(tester);
    expect(find.text('UAE Bulls won by 6 wickets'), findsOneWidget, reason: 'Results show the result line');
    expect(find.text('Abu Dhabi T10 League 2026'), findsOneWidget, reason: 'non-consecutive T10 matches share one header');

    await tester.fling(find.byKey(const ValueKey('matches_pager')), const Offset(600, 0), 2000);
    await settle(tester);
    expect(find.text('Starts in 2h 30m'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('LIVE match on the Live tab: flat row with live pill and chase line, tap opens detail', (tester) async {
    final router = await _pumpMatches(
      tester,
      FakeApi({
        ...defaultRoutes(),
        '/match/live': FakeApi.ok(body([liveMatchJson()])),
      }),
    );
    final row = _rowsOf('live');
    expect(row, findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('UAE Bulls need 87 runs in 35 balls'), findsOneWidget);
    await tester.tap(row);
    await tester.tap(row, warnIfMissed: false);
    await settle(tester);
    expect(location(router), '/matches/match/LIVE01');
    router.pop();
    await settle(tester);
    expect(location(router), '/matches');
    await _unmount(tester);
  });

  testWidgets('Live tab falls back to /match/recent filtered by status when /match/live fails', (tester) async {
    final recent = fixtureJson('match_recent')['data'] as List;
    await _pumpMatches(
      tester,
      FakeApi({
        ...defaultRoutes(),
        '/match/live': FakeApi.status(500),
        '/match/recent': FakeApi.ok(body([...recent, liveMatchJson(key: 'LIVE02')])),
      }),
    );
    expect(_rowsOf('live'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('error state + Try again per tab', (tester) async {
    var fail = true;
    Responder flaky(Responder ok) =>
        (r) => fail ? FakeApi.status(500, 'Server exploded')(r) : ok(r);
    final api = FakeApi({
      '/match/live': flaky(FakeApi.ok(body([liveMatchJson()]))),
      '/match/recent': FakeApi.status(500, 'Server exploded'),
      '/match/upcoming': flaky(FakeApi.fixture('match_upcoming')),
      '/match/completed': flaky(completedPaged()),
    });
    await _pumpMatches(tester, api);
    expect(find.byKey(const ValueKey('matches_error_live')), findsOneWidget);
    expect(find.text("Live matches didn't load"), findsOneWidget);
    expect(find.text('Server exploded'), findsOneWidget);
    fail = false;
    await _tap(tester, 'matches_retry_live');
    expect(_rowsOf('live'), findsOneWidget);

    await _tap(tester, 'tab_upcoming');
    expect(find.byKey(const ValueKey('matches_error_upcoming')), findsOneWidget);
    await _tap(tester, 'matches_retry_upcoming');
    expect(find.text('Starts in 2h 30m'), findsOneWidget);

    await _tap(tester, 'tab_completed');
    expect(find.byKey(const ValueKey('matches_error_completed')), findsOneWidget);
    await _tap(tester, 'matches_retry_completed');
    expect(_rowsOf('completed'), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('Results: scrolling to the end loads page 2 exactly once, then the end note', (tester) async {
    final gate = Completer<void>();
    final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged(page2Gate: gate)});
    await _pumpMatches(tester, api, size: const Size(800, 900));
    await _tap(tester, 'tab_completed');
    final list = find.byKey(const PageStorageKey('matches_list_completed'));
    expect(list, findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), isEmpty);

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
    expect(find.text('Page Two Series'), findsOneWidget);
    expect(find.byKey(const ValueKey('matches_no_more')), findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1));
    expect(api.log.where((u) => u.queryParameters['page'] == '3'), isEmpty);
    await _unmount(tester);
  });

  testWidgets('Results: failed next page keeps the list and the footer retries', (tester) async {
    var fail = true;
    final api = FakeApi({...defaultRoutes(), '/match/completed': (r) => completedPaged(failPage2: fail)(r)});
    await _pumpMatches(tester, api, size: const Size(800, 900));
    await _tap(tester, 'tab_completed');
    final list = find.byKey(const PageStorageKey('matches_list_completed'));
    await tester.drag(list, const Offset(0, -6000));
    await settle(tester);
    await tester.drag(list, const Offset(0, -6000));
    await settle(tester);
    expect(find.byKey(const ValueKey('matches_load_more_error')), findsOneWidget);
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1), reason: 'no automatic retry loop');
    expect(find.byKey(const ValueKey('matches_error_completed')), findsNothing);
    fail = false;
    await _tap(tester, 'matches_load_more_retry');
    await tester.drag(list, const Offset(0, -6000));
    await settle(tester);
    expect(find.byKey(const ValueKey('matches_no_more')), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('pull-to-refresh refetches all tabs and resets paging', (tester) async {
    final api = FakeApi({
      ...defaultRoutes(),
      '/match/live': FakeApi.ok(body([liveMatchJson()])),
    });
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

  testWidgets('empty Upcoming / Results tell people what to do', (tester) async {
    final empty = FakeApi.ok(body([]));
    final api = FakeApi({'/match/live': empty, '/match/upcoming': empty, '/match/completed': empty});
    await _pumpMatches(tester, api);
    await _tap(tester, 'tab_upcoming');
    expect(find.byKey(const ValueKey('matches_empty_upcoming')), findsOneWidget);
    expect(find.text('No upcoming matches listed'), findsOneWidget);
    await _tap(tester, 'tab_completed');
    expect(find.byKey(const ValueKey('matches_empty_completed')), findsOneWidget);
    expect(find.text('No results yet'), findsOneWidget);
    final before = api.count('/match/completed');
    await _tap(tester, 'matches_empty_action_completed');
    expect(api.count('/match/completed'), before + 1);
    expect(find.byKey(const ValueKey('matches_filter_women')), findsNothing, reason: 'no women\'s data → no Women chip');
    await _unmount(tester);
  });

  testWidgets('format and Women chips filter Results client-side, with no extra requests', (tester) async {
    final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged()});
    await _pumpMatches(tester, api, size: const Size(800, 900));
    await _tap(tester, 'tab_completed');
    final calls = api.log.length;
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), isEmpty);

    await _tap(tester, 'matches_format_odi');
    expect(find.text('England A won by 88 runs'), findsOneWidget);
    expect(find.text('UAE Bulls won by 6 wickets'), findsNothing);
    expect(_rowsOf('completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('matches_load_more_button')), findsOneWidget, reason: 'paging is explicit while filtering');

    await _tap(tester, 'matches_format_t20');
    await _tap(tester, 'matches_filter_women');
    expect(find.text('Womens Big Bash League 2026'), findsOneWidget);
    expect(find.text('Nepal Premier League 2026'), findsNothing);

    await _tap(tester, 'matches_format_test');
    expect(find.byKey(const ValueKey('matches_filtered_empty_completed')), findsOneWidget);
    expect(find.text("No women's Test results"), findsOneWidget);
    expect(api.log.length, calls, reason: 'filters never send requests');

    await _tap(tester, 'matches_clear_filters');
    expect(find.text('UAE Bulls won by 6 wickets'), findsOneWidget);
    expect(api.log.length, calls);

    // The explicit button does page in more.
    await _tap(tester, 'matches_format_odi');
    await _tap(tester, 'matches_load_more_button');
    expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1));
    await _unmount(tester);
  });

  testWidgets('day strip filters loaded lists by local day, without requests', (tester) async {
    final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged()});
    await _pumpMatches(tester, api);
    await _tap(tester, 'tab_upcoming');
    final calls = api.log.length;
    final today = dayOf(MinuteClock.now());
    final upcoming = parseMatchList(fixtureJson('match_upcoming')['data']);
    final todayCount = upcoming.where((m) => matchDay(m) == today).length;

    for (final k in ['all', 'yesterday', 'today', 'tomorrow', 'pick']) {
      expect(find.byKey(ValueKey('matches_day_$k')), findsOneWidget);
    }
    await _tap(tester, 'matches_day_today');
    if (todayCount == 0) {
      expect(find.byKey(const ValueKey('matches_filtered_empty_upcoming')), findsOneWidget);
    } else {
      expect(_rowsOf('upcoming'), findsNWidgets(todayCount));
    }
    await _tap(tester, 'matches_day_yesterday');
    expect(find.byKey(const ValueKey('matches_filtered_empty_upcoming')), findsOneWidget);
    expect(find.text('No upcoming matches yesterday'), findsOneWidget);

    // Same day filter applies to Results.
    await _tap(tester, 'tab_completed');
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final results = parseMatchList(fixtureJson('match_completed')['data']);
    final yCount = results.where((m) => matchDay(m) == yesterday).length;
    expect(_rowsOf('completed'), yCount == 0 ? findsNothing : findsNWidgets(yCount));

    expect(api.log.length, calls, reason: 'day changes never send requests');
    await _tap(tester, 'matches_day_all');
    expect(_rowsOf('completed'), findsWidgets);
    await _unmount(tester);
  });

  testWidgets('calendar picker selects a custom day', (tester) async {
    final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged()});
    await _pumpMatches(tester, api);
    await _tap(tester, 'tab_completed');
    final calls = api.log.length;
    await tester.tap(find.byKey(const ValueKey('matches_day_pick')));
    await settle(tester);
    expect(find.text('Show matches on'), findsOneWidget);
    // Pick the 16th of the current month (the clock is pinned to Nov 2026).
    await tester.tap(find.text('16'));
    await tester.tap(find.text('Show'));
    await settle(tester);
    final day = DateTime(2026, 11, 16);
    final expected = parseMatchList(fixtureJson('match_completed')['data']).where((m) => matchDay(m) == day).length;
    expect(find.text('Mon 16 Nov'), findsOneWidget, reason: 'the picked day shows on the chip');
    expect(_rowsOf('completed'), expected == 0 ? findsNothing : findsNWidgets(expected));
    expect(api.log.length, calls);
    await _unmount(tester);
  });

  testWidgets('malformed items render safely (no fake zeros, no crash)', (tester) async {
    final api = FakeApi({
      '/match/live': FakeApi.ok(
        body([
          1,
          'junk',
          {'status': 'LIVE', 'teams': 'junk'},
          {
            'status': 'STUMPS',
            'sb_match_key': 'S1',
            'seriesName': 'Test series',
            'format': 'TEST',
            'teams': {
              't1': {'name': 'Pakistan', 'score': '135/4 (42.0)'},
              't2': {'name': 'Sri Lanka', 'score': ''},
            },
          },
        ]),
      ),
      '/match/upcoming': FakeApi.ok(
        body([
          {
            'status': 'NOT_STARTED',
            'startDate': 'not a date',
            'teams': {
              't1': {'name': 'A', 'score': '0/0'},
            },
          },
        ]),
      ),
      '/match/completed': FakeApi.ok(body({'unexpected': true})),
    });
    await _pumpMatches(tester, api, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('Stumps'), findsOneWidget);
    expect(find.text('Test'), findsWidgets);
    expect(find.text('To be decided'), findsWidgets);
    await _tap(tester, 'tab_upcoming');
    expect(find.text('0/0'), findsNothing, reason: 'an upcoming match has no score');
    await _tap(tester, 'tab_completed');
    expect(find.byKey(const ValueKey('matches_empty_completed')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final raw = J.maps(fixtureJson('match_upcoming')['data']);
    expect(raw, isNotEmpty);
    await _unmount(tester);
  });
}
