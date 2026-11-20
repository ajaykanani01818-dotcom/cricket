import 'dart:async';

import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/core/widgets/tabs.dart';
import 'package:crickbex/features/series/series_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'series_test_helpers.dart';

const _name = 'Abu Dhabi T10 League 2026';

GoRouter _router() => GoRouter(
  initialLocation: '/series/series-detail/YcK6usv',
  initialExtra: _name,
  routes: [
    GoRoute(
      path: '/series',
      builder: (_, _) => const Scaffold(body: Text('SERIES LIST')),
      routes: [
        GoRoute(
          path: 'series-detail/:id',
          builder: (_, s) =>
              SeriesDetailScreen(seriesId: s.pathParameters['id']!, seriesName: s.extra is String ? s.extra as String : null),
        ),
        GoRoute(
          path: 'match/:id',
          builder: (_, s) => Scaffold(body: Text('MATCH ${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: 'player/:id',
          builder: (_, s) => Scaffold(body: Text('PLAYER ${s.pathParameters['id']}')),
        ),
      ],
    ),
  ],
);

http.Response _realFixtures(http.Request req) {
  final p = req.url.path;
  if (p.endsWith('/squad')) return jsonResponse(fixtureJson('series_squad.json'));
  if (p.endsWith('/point-table')) return jsonResponse(fixtureJson('series_point_table.json'));
  if (p.endsWith('/stats')) return jsonResponse(fixtureJson('series_stats.json'));
  return jsonResponse(fixtureJson('series_fixtures.json'));
}

void main() {
  late MatchService original;
  setUp(() => original = MatchService.instance);
  tearDown(() => MatchService.instance = original);

  Future<FakeApi> pumpDetail(WidgetTester tester, FutureOr<http.Response> Function(http.Request) handler) async {
    final api = FakeApi(handler);
    MatchService.instance = api.service;
    await tester.pumpWidget(routerApp(_router()));
    return api;
  }

  Future<void> openTab(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey('tab_$key')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('tab_$key')));
    await settleNetwork(tester, 10);
  }

  testWidgets('skeleton → fixtures grouped as results, header facts, only fixtures fetched', (tester) async {
    final gate = Completer<http.Response>();
    final api = await pumpDetail(tester, (req) => gate.future);
    await tester.pump();
    expect(find.byKey(const ValueKey('series_detail_shimmer')), findsOneWidget);
    expect(find.text(_name), findsOneWidget);
    for (final t in ['Fixtures', 'Points table', 'Squads', 'Stats']) {
      expect(find.text(t), findsOneWidget);
    }
    gate.complete(_realFixtures(http.Request('GET', Uri.parse('http://test/series/YcK6usv'))));
    await settleNetwork(tester);
    expect(find.byKey(const ValueKey('series_detail_shimmer')), findsNothing);
    expect(find.text('Results'), findsOneWidget, reason: 'section header');
    expect(find.text('Arabian Aces'), findsWidgets);
    expect(find.text('Arabian Aces won by 7 wickets'), findsOneWidget);
    expect(find.text('4 matches'), findsOneWidget);
    expect(find.text('T10'), findsWidgets);
    expect(find.text('Finished'), findsNothing);
    expect(api.requests.map((u) => u.path), ['/series/YcK6usv']);
  });

  testWidgets('fixture tap opens the match (no double push)', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    final row = find.byKey(const ValueKey('series_fixture_6afb1aef31bbe1ca5642823c'));
    await tester.tap(row);
    await tester.tap(row, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('MATCH 03OiKOD'), findsOneWidget);
  });

  testWidgets('upcoming fixture: Upcoming section + sentence-case countdown; void reason shown; untappable without id', (tester) async {
    final soon = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    await pumpDetail(
      tester,
      (req) => jsonResponse({
        'data': [
          {
            '_id': 'u1',
            'sb_match_key': 'M1',
            'status': 'NOT_STARTED',
            'startDate': soon.toIso8601String(),
            'teams': {
              't1': {'name': 'India'},
              't2': {'name': 'Australia'},
            },
            'ground': 'MCG',
          },
          {
            'status': 'ABANDONED',
            'result': {'message': 'Abandoned due to rain'},
            'startDate': '2026-01-01T00:00:00Z',
          },
        ],
      }),
    );
    await settleNetwork(tester);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.textContaining('Starts in 5h'), findsOneWidget);
    expect(find.textContaining('STARTS IN'), findsNothing);
    expect(find.text('Abandoned due to rain'), findsOneWidget);
    expect(find.text('To be decided'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('series_fixture_fixture-1')));
    await tester.pump();
    expect(find.textContaining('MATCH'), findsNothing);
  });

  testWidgets('empty fixtures tell people what happens next', (tester) async {
    await pumpDetail(tester, (req) => jsonResponse({'data': []}));
    await settleNetwork(tester);
    expect(find.text('No fixtures published yet'), findsOneWidget);
  });

  testWidgets('error + Try again recovers', (tester) async {
    var fail = true;
    await pumpDetail(tester, (req) => fail ? jsonResponse({'message': 'Server down'}, 500) : _realFixtures(req));
    await settleNetwork(tester);
    expect(find.text("Fixtures didn't load"), findsOneWidget);
    expect(find.text('Server down'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('series_detail_retry')));
    await settleNetwork(tester);
    expect(find.text('Arabian Aces'), findsWidgets);
  });

  testWidgets('points table: lazy load, provider columns, signed NRR, form, no computed highlights', (tester) async {
    final api = await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    expect(api.count((u) => u.path.endsWith('/point-table')), 0);
    await openTab(tester, 'points');
    expect(api.count((u) => u.path.endsWith('/point-table')), 1);
    for (final h in ['Team', 'P', 'W', 'L', 'T', 'NR', 'Pts', 'NRR', 'Form']) {
      expect(find.text(h), findsWidgets, reason: h);
    }
    expect(find.text('ARA'), findsOneWidget);
    expect(find.text('+0.422'), findsOneWidget);
    expect(find.text('-0.605'), findsOneWidget);
    expect(find.text('Q'), findsNothing, reason: 'provider sends no qualify flags, so nothing is marked');
    expect(find.textContaining('Top'), findsNothing);
    expect(find.textContaining('Standings as published'), findsOneWidget);
    // Tap a team → its results.
    await tester.tap(find.byKey(const ValueKey('series_points_row_ARA')));
    await tester.pump();
    expect(find.byKey(const ValueKey('series_points_results_ara')), findsOneWidget);
    expect(find.text('v UT, lost by 51 runs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('series_points_results_close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('series_points_results_ara')), findsNothing);
    // back to Fixtures reuses cache
    await openTab(tester, 'fixtures');
    await openTab(tester, 'points');
    expect(api.count((u) => u.path.endsWith('/point-table')), 1);
    expect(api.count((u) => u.path == '/series/YcK6usv'), 1);
  });

  testWidgets('points table at 320 px scrolls horizontally without overflow, also at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await openTab(tester, 'points');
    expect(tester.takeException(), isNull);
    final scroll = find.byKey(const ValueKey('series_points_scroll_Group'));
    expect(scroll, findsOneWidget);
    final pos = tester.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable))).position;
    expect(pos.maxScrollExtent, greaterThan(0), reason: 'the table is wider than 320 px');
    await tester.drag(scroll, const Offset(-400, 0));
    await tester.pump();
    expect(pos.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('points 404 → empty state that points to fixtures', (tester) async {
    await pumpDetail(tester, (req) => req.url.path.endsWith('/point-table') ? jsonResponse({'message': 'nf'}, 404) : _realFixtures(req));
    await settleNetwork(tester);
    await openTab(tester, 'points');
    expect(find.text('No points table for this series'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('series_points_see_fixtures')));
    await settleNetwork(tester, 12);
    expect(find.text('Arabian Aces won by 7 wickets'), findsOneWidget);
  });

  testWidgets('malformed points rows: missing values show "–", never 0', (tester) async {
    await pumpDetail(
      tester,
      (req) => req.url.path.endsWith('/point-table')
          ? jsonResponse({
              'data': {
                'series': {
                  'pointsTable': [
                    {
                      'name': 'Group A',
                      'teams': [
                        {'shortName': 'XX', 'key': 'xx'},
                        'junk',
                      ],
                    },
                    {
                      'name': 'Group B',
                      'teams': [
                        {'shortName': 'YY', 'won': 2, 'points': 4, 'qualify': 'Q'},
                      ],
                    },
                  ],
                },
              },
            })
          : _realFixtures(req),
    );
    await settleNetwork(tester);
    await openTab(tester, 'points');
    expect(tester.takeException(), isNull);
    expect(find.text('Group A'), findsOneWidget);
    expect(find.text('Group B'), findsOneWidget);
    expect(find.text('–'), findsWidgets);
    expect(find.text('Q'), findsOneWidget, reason: 'provider flag is shown');
  });

  testWidgets('stats tab: leaders top 3, show all, player tap', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await openTab(tester, 'stats');
    expect(find.text('Most runs'), findsOneWidget);
    final runRows = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_stat_most_runs_'),
    );
    expect(runRows, findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('series_stats_more_most_runs')));
    await tester.pump();
    expect(runRows.evaluate().length, greaterThan(3));
    final firstRow = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_stat_most_runs_1_'),
    );
    final key = (tester.widget(firstRow).key as ValueKey<String>).value.replaceFirst('series_stat_most_runs_1_', '');
    await tester.tap(firstRow);
    await tester.pumpAndSettle();
    expect(find.text('PLAYER $key'), findsOneWidget);
  });

  testWidgets('stats 404 → not published yet, with a way back to fixtures', (tester) async {
    await pumpDetail(tester, (req) => req.url.path.endsWith('/stats') ? jsonResponse({'message': 'nf'}, 404) : _realFixtures(req));
    await settleNetwork(tester);
    await openTab(tester, 'stats');
    expect(find.byKey(const ValueKey('series_stats_coming_soon')), findsOneWidget);
    expect(find.text("Stats aren't published for this series yet"), findsOneWidget);
  });

  testWidgets('stats with no formats → empty message', (tester) async {
    await pumpDetail(
      tester,
      (req) => req.url.path.endsWith('/stats')
          ? jsonResponse({
              'data': {'seriesId': 'x'},
            })
          : _realFixtures(req),
    );
    await settleNetwork(tester);
    await openTab(tester, 'stats');
    expect(find.text('No stats for this series yet'), findsOneWidget);
  });

  testWidgets('squads: count in tab, one team open at a time, player tap', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await openTab(tester, 'squads');
    expect(find.text('Squads (2)'), findsOneWidget);
    expect(find.text('Dunith Wellalage'), findsNothing); // collapsed
    final header = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_squad_team_'),
    );
    expect(header, findsNWidgets(2));
    await tester.tap(header.first);
    await tester.pump();
    expect(find.text('Dunith Wellalage'), findsOneWidget);
    expect(find.text('Bowler'), findsWidgets);
    await tester.tap(header.first);
    await tester.pump();
    expect(find.text('Dunith Wellalage'), findsNothing);
    await tester.tap(header.first);
    await tester.pump();
    await tester.tap(find.text('Dunith Wellalage'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYER dunith_wellalage'), findsOneWidget);
  });

  testWidgets('scrollable tab row (large text) still spans the full width', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    final tabs = find.byType(SectionTabs);
    expect(tester.widget<SectionTabs>(tabs).scrollable, isTrue);
    final box = find.descendant(of: tabs, matching: find.byType(Container)).first;
    expect(tester.getSize(box).width, 760, reason: 'capped band, full band width');
    expect(tester.getTopLeft(box).dx, 120);
  });

  testWidgets('swiping pages loads the next tab', (tester) async {
    final api = await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await tester.fling(find.byKey(const ValueKey('series_detail_pager')), const Offset(-500, 0), 1500);
    await settleNetwork(tester, 12);
    expect(api.count((u) => u.path.endsWith('/point-table')), 1);
    expect(find.text('ARA'), findsOneWidget);
  });

  testWidgets('pull-to-refresh refetches the current tab', (tester) async {
    final api = await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await tester.fling(find.byKey(const ValueKey('series_fixtures_list')), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settleNetwork(tester);
    expect(api.count((u) => u.path == '/series/YcK6usv'), 2);
    expect(find.text('Arabian Aces'), findsWidgets);
  });

  testWidgets('back button pops to the series list', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await tester.tap(find.byKey(const ValueKey('series_detail_back')));
    await tester.pumpAndSettle();
    expect(find.text('SERIES LIST'), findsOneWidget);
  });

  testWidgets('no series name (deep link) → title from the fixtures, still loads', (tester) async {
    final api = FakeApi(_realFixtures);
    MatchService.instance = api.service;
    await tester.pumpWidget(MaterialApp(home: const SeriesDetailScreen(seriesId: 'abc')));
    await settleNetwork(tester);
    expect(find.text('Abu Dhabi T10 League 2026'), findsOneWidget);
    expect(api.requests.single.path, '/series/abc');
  });
}
