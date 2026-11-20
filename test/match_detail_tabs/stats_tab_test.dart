import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/match_detail/tabs/stats_tab.dart';
import 'package:crickbex/features/match_detail/tabs/tab_scorecard_parse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

http.Response? statsRoute(http.Request r) {
  final p = r.url.path;
  if (p.endsWith('/analytics')) return okJson(fixture('match_analytics'));
  if (p.endsWith('/scoring-rate')) return okJson(fixture('match_scoring_rate'));
  if (p.endsWith('/boundaries')) return okJson(fixture('match_boundaries'));
  return null;
}

ScorecardView scorecard() => parseScorecard(J.map(fixture('match_scorecard')['data']));

void main() {
  final original = MatchService.instance;
  tearDown(() => MatchService.instance = original);

  testWidgets('loading → comparison table, charts with text equivalents, economy bars', (tester) async {
    final calls = installService(statsRoute);
    await tester.pumpWidget(host(MatchStatsTab(matchId: 'm1', isLive: false, scorecard: scorecard())));
    expect(find.byKey(const ValueKey('stats_loading')), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(calls.toSet(), {'/match/m1/analytics', '/match/m1/scoring-rate', '/match/m1/boundaries'});
    expect(find.text('BAN 1st'), findsWidgets);
    expect(find.text('4.63'), findsOneWidget);
    expect(find.text('3.95'), findsOneWidget);
    expect(find.text('66.5'), findsOneWidget);
    // Latest innings selected; wickets from the scorecard fall of wickets.
    expect(find.byKey(const ValueKey('stats_manhattan_t1_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('stats_worm_t1_1')), findsOneWidget);
    expect(find.textContaining('Highest over:'), findsOneWidget);
    expect(find.textContaining('Wickets in overs 2, 44'), findsOneWidget);
    expect(find.textContaining('after 10'), findsOneWidget);
    expect(find.text('61.2% (232 of 379 balls)'), findsOneWidget);
    expect(find.text('37 (36 fours, 1 six)'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats_economy_t1_1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stats_innings_0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('stats_manhattan_t2_1')), findsOneWidget);

    // Tapping a bar reads the over out.
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('stats_manhattan_t2_1'))) + const Offset(40, 120));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^Over \d+: \d+ runs, total \d+')), findsOneWidget);
  });

  testWidgets('one endpoint failing: its figures show as not available, never 0', (tester) async {
    installService((r) => r.url.path.endsWith('/boundaries') ? serverError() : statsRoute(r));
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.text('4.63'), findsOneWidget);
    expect(find.text('–'), findsWidgets);
    expect(find.byKey(const ValueKey('stats_boundaries')), findsNothing);
  });

  testWidgets('all endpoints failing → error + retry recovers', (tester) async {
    var fail = true;
    installService((r) => fail ? serverError() : statsRoute(r));
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('stats_error')), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('stats_body')), findsOneWidget);
  });

  testWidgets('empty payloads → not available state', (tester) async {
    installService((r) => okJson({'message': 'ok', 'data': {}}));
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('stats_empty')), findsOneWidget);
  });

  testWidgets('live: polls silently every 30 s; not live: no polling', (tester) async {
    final calls = installService(statsRoute);
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: true)));
    await tester.pump();
    await tester.pump();
    expect(calls.length, 3);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(calls.length, 6);
    expect(find.byKey(const ValueKey('stats_loading')), findsNothing);
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump(const Duration(minutes: 2));
    expect(calls.length, 6);
  });

  test('loadMatchStats rethrows only when all three fail', () async {
    installService((r) => r.url.path.endsWith('/analytics') ? serverError() : statsRoute(r));
    final v = await loadMatchStats(MatchService.instance, 'm1');
    expect(v.innings, hasLength(2));
    expect(v.innings.first.dotPercent, isNull);
    installService((r) => serverError());
    expect(loadMatchStats(MatchService.instance, 'm1'), throwsA(anything));
  });

  test('text equivalents', () {
    expect(manhattanSummary([2, 18, 4], [2]), 'Highest over: 18 runs (over 2). 24 runs in 3 overs. Wickets in overs 2.');
    expect(wormSummary([1, 2, 3]), '6 runs after 3 overs.');
  });
}
