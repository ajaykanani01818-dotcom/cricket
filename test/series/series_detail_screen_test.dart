import 'dart:async';

import 'package:crickbex/core/services/cricket_services.dart';
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
              builder: (_, s) => SeriesDetailScreen(
                seriesId: s.pathParameters['id']!,
                seriesName: s.extra is String ? s.extra as String : null,
              ),
            ),
            GoRoute(path: 'match/:id', builder: (_, s) => Scaffold(body: Text('MATCH ${s.pathParameters['id']}'))),
            GoRoute(path: 'player/:id', builder: (_, s) => Scaffold(body: Text('PLAYER ${s.pathParameters['id']}'))),
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
    await tester.tap(find.byKey(ValueKey('tab_$key')));
    await settleNetwork(tester, 10);
  }

  testWidgets('shimmer → fixtures, hero title, only fixtures fetched', (tester) async {
    final gate = Completer<http.Response>();
    final api = await pumpDetail(tester, (req) => gate.future);
    await tester.pump();
    expect(find.byKey(const ValueKey('series_detail_shimmer')), findsOneWidget);
    expect(find.text(_name), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Squads'), findsOneWidget);
    gate.complete(_realFixtures(http.Request('GET', Uri.parse('http://test/series/YcK6usv'))));
    await settleNetwork(tester);
    expect(find.byKey(const ValueKey('series_detail_shimmer')), findsNothing);
    expect(find.text('Arabian Aces'), findsWidgets);
    expect(find.text('1st match'), findsOneWidget);
    expect(find.text('Finished'), findsWidgets);
    expect(find.text('Arabian Aces won by 7 wickets'), findsOneWidget);
    expect(api.requests.map((u) => u.path), ['/series/YcK6usv']);
  });

  testWidgets('fixture tap and View Scorecard open the match (no double push)', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    final card = find.byKey(const ValueKey('series_fixture_6afb1aef31bbe1ca5642823c'));
    await tester.tap(card);
    await tester.tap(card, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('MATCH 03OiKOD'), findsOneWidget);
    GoRouter.of(tester.element(find.text('MATCH 03OiKOD'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('series_fixture_scorecard_6afb1aef31bbe1ca5642823c')));
    await tester.pumpAndSettle();
    expect(find.text('MATCH 03OiKOD'), findsOneWidget);
  });

  testWidgets('upcoming fixture shows Upcoming chip + countdown; void reason shown', (tester) async {
    final future = DateTime.now().toUtc().add(const Duration(days: 2, hours: 5));
    await pumpDetail(
      tester,
      (req) => jsonResponse({
        'data': [
          {
            '_id': 'u1',
            'sb_match_key': 'M1',
            'status': 'NOT_STARTED',
            'startDate': future.toIso8601String(),
            'teams': {'t1': {'name': 'India'}, 't2': {'name': 'Australia'}},
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
    expect(find.text('STARTS IN'), findsOneWidget);
    expect(find.text('2d 4h'), findsOneWidget);
    expect(find.text('MCG'), findsOneWidget);
    expect(find.text('Abandoned'), findsOneWidget);
    expect(find.text('Abandoned due to rain'), findsOneWidget);
    expect(find.text('TBD'), findsNWidgets(2));
    expect(find.text('View Scorecard'), findsNothing);
    // fixture without sb_match_key/_id is not tappable
    await tester.tap(find.byKey(const ValueKey('series_fixture_fixture-1')));
    await tester.pump();
    expect(find.textContaining('MATCH'), findsNothing);
  });

  testWidgets('empty fixtures', (tester) async {
    await pumpDetail(tester, (req) => jsonResponse({'data': []}));
    await settleNetwork(tester);
    expect(find.text('No fixtures available'), findsOneWidget);
  });

  testWidgets('error + Try Again recovers', (tester) async {
    var fail = true;
    await pumpDetail(tester, (req) => fail ? jsonResponse({'message': 'Server down'}, 500) : _realFixtures(req));
    await settleNetwork(tester);
    expect(find.text('Server down'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('series_detail_retry')));
    await settleNetwork(tester);
    expect(find.text('Arabian Aces'), findsWidgets);
  });

  testWidgets('points tab loads lazily and renders the table', (tester) async {
    final api = await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    expect(api.count((u) => u.path.endsWith('/point-table')), 0);
    await openTab(tester, 'points');
    expect(api.count((u) => u.path.endsWith('/point-table')), 1);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('ARA'), findsOneWidget);
    expect(find.text('NRR'), findsOneWidget);
    expect(find.text('0.42'), findsOneWidget);
    // back to Results reuses cache
    await openTab(tester, 'fixtures');
    await openTab(tester, 'points');
    expect(api.count((u) => u.path.endsWith('/point-table')), 1);
    expect(api.count((u) => u.path == '/series/YcK6usv'), 1);
  });

  testWidgets('points 404 → "No points table available"', (tester) async {
    await pumpDetail(
        tester, (req) => req.url.path.endsWith('/point-table') ? jsonResponse({'message': 'nf'}, 404) : _realFixtures(req));
    await settleNetwork(tester);
    await openTab(tester, 'points');
    expect(find.text('No points table available'), findsOneWidget);
  });

  testWidgets('stats tab renders leaderboards; player tap opens player', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await openTab(tester, 'stats');
    expect(find.text('T10'), findsOneWidget);
    expect(find.text('Most Runs'), findsOneWidget);
    final firstRow = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_stat_most_runs_1_'));
    expect(firstRow, findsOneWidget);
    final key = (tester.widget(firstRow).key as ValueKey<String>).value.replaceFirst('series_stat_most_runs_1_', '');
    await tester.tap(firstRow);
    await tester.pumpAndSettle();
    expect(find.text('PLAYER $key'), findsOneWidget);
  });

  testWidgets('stats 404 → Coming Soon', (tester) async {
    await pumpDetail(tester, (req) => req.url.path.endsWith('/stats') ? jsonResponse({'message': 'nf'}, 404) : _realFixtures(req));
    await settleNetwork(tester);
    await openTab(tester, 'stats');
    expect(find.byKey(const ValueKey('series_stats_coming_soon')), findsOneWidget);
    expect(find.text('Coming Soon'), findsOneWidget);
  });

  testWidgets('stats with no formats → empty message', (tester) async {
    await pumpDetail(
        tester, (req) => req.url.path.endsWith('/stats') ? jsonResponse({'data': {'seriesId': 'x'}}) : _realFixtures(req));
    await settleNetwork(tester);
    await openTab(tester, 'stats');
    expect(find.text('No stats for this series yet'), findsOneWidget);
  });

  testWidgets('squads: count in tab, accordion expand, player tap', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await openTab(tester, 'squads');
    expect(find.text('Squads (2)'), findsOneWidget);
    expect(find.text('Dunith Wellalage'), findsNothing); // collapsed
    final header = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_squad_team_'));
    expect(header, findsNWidgets(2));
    await tester.tap(header.first);
    await tester.pump();
    expect(find.text('Dunith Wellalage'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    await tester.tap(find.text('Dunith Wellalage'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYER dunith_wellalage'), findsOneWidget);
  });

  testWidgets('squads accordion: opening one team closes the other', (tester) async {
    await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await openTab(tester, 'squads');
    final header = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_squad_team_'));
    await tester.tap(header.first);
    await tester.pump();
    expect(find.text('Role'), findsOneWidget);
    await tester.tap(header.first);
    await tester.pump();
    expect(find.text('Role'), findsNothing);
  });

  testWidgets('swiping pages loads the next view', (tester) async {
    final api = await pumpDetail(tester, _realFixtures);
    await settleNetwork(tester);
    await tester.fling(find.byKey(const ValueKey('series_detail_pager')), const Offset(-500, 0), 1500);
    await settleNetwork(tester, 12);
    expect(api.count((u) => u.path.endsWith('/point-table')), 1);
    expect(find.text('ARA'), findsOneWidget);
  });

  testWidgets('pull-to-refresh refetches the current view', (tester) async {
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

  testWidgets('no series name → no title, still loads', (tester) async {
    final api = FakeApi(_realFixtures);
    MatchService.instance = api.service;
    await tester.pumpWidget(MaterialApp(home: const SeriesDetailScreen(seriesId: 'abc')));
    await settleNetwork(tester);
    expect(find.byKey(const ValueKey('series_detail_title')), findsNothing);
    expect(api.requests.single.path, '/series/abc');
  });
}
