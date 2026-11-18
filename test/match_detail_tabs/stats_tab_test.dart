import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/match_detail/tabs/match_section_title.dart';
import 'package:crickbex/features/match_detail/tabs/stats_tab.dart';
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

void main() {
  final original = MatchService.instance;
  tearDown(() => MatchService.instance = original);

  testWidgets('loading → values from the real fixtures', (tester) async {
    final calls = installService(statsRoute);
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    expect(find.byKey(const ValueKey('stats_loading')), findsOneWidget);
    expect(find.text('Loading statistics...'), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(calls.toSet(), {'/match/m1/analytics', '/match/m1/scoring-rate', '/match/m1/boundaries'});
    expect(find.text('Scoring Rate'), findsOneWidget);
    expect(find.text('4.63'), findsOneWidget);
    expect(find.text('3.95'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('52'), findsOneWidget);
    expect(find.text('61.2%'), findsOneWidget);
    expect(find.text('66.5%'), findsOneWidget);
    expect(find.byType(MatchSectionTitle), findsNWidgets(3));
  });

  testWidgets('one endpoint failing still renders (zeros for it)', (tester) async {
    installService((r) => r.url.path.endsWith('/boundaries') ? serverError() : statsRoute(r));
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('stats_error')), findsNothing);
    expect(find.text('4.63'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(6));
  });

  testWidgets('all endpoints failing → error; Retry recovers', (tester) async {
    var fail = true;
    installService((r) => fail ? serverError() : statsRoute(r));
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('stats_error')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    await tester.pump();
    await tester.pump();
    expect(find.text('4.63'), findsOneWidget);
  });

  testWidgets('live polling refreshes values every 15s and stops on dispose', (tester) async {
    var rate = 4.63;
    final calls = installService((r) {
      if (r.url.path.endsWith('/scoring-rate')) {
        return okJson({
          'data': {
            'teams': {
              'team1': {
                'innings': {
                  't1_1': {'scoringRate': rate}
                }
              }
            }
          }
        });
      }
      return statsRoute(r);
    });
    await tester.pumpWidget(host(const MatchStatsTab(matchId: 'm1', isLive: true)));
    await tester.pump();
    await tester.pump();
    expect(find.text('4.63'), findsOneWidget);
    rate = 5.1;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.text('5.10'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats_loading')), findsNothing);
    expect(calls, hasLength(6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(calls, hasLength(6));
  });

  testWidgets('works inside a parent scroll view', (tester) async {
    installService(statsRoute);
    await tester.pumpWidget(scrollHost(const MatchStatsTab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Dot Ball Percentage'), findsOneWidget);
  });

  test('loadMatchStats rethrows only when all three fail', () async {
    installService((r) => serverError());
    await expectLater(loadMatchStats(MatchService.instance, 'x'), throwsA(anything));
    installService((r) => r.url.path.endsWith('/analytics') ? statsRoute(r) : serverError());
    final v = await loadMatchStats(MatchService.instance, 'x');
    expect(v.dotBall1, '61.2%');
    expect(v.scoringRate1, '0.00');
  });

  testWidgets('MatchSectionTitle variants render; currentOver pulses', (tester) async {
    await tester.pumpWidget(host(const Column(children: [
      MatchSectionTitle(icon: Icons.bar_chart, label: 'Default'),
      MatchSectionTitle(icon: Icons.sports_cricket, label: 'Stat', variant: 'stat'),
      MatchSectionTitle(icon: Icons.bolt, label: 'Current over', variant: 'currentOver'),
    ])));
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Stat'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
    final fade = tester.widget<FadeTransition>(
        find.descendant(of: find.byType(MatchSectionTitle).last, matching: find.byType(FadeTransition)));
    final o1 = fade.opacity.value;
    await tester.pump(const Duration(milliseconds: 400));
    expect(fade.opacity.value, isNot(o1));
    // Switching away from currentOver stops the animation.
    await tester.pumpWidget(host(const MatchSectionTitle(icon: Icons.bolt, label: 'x')));
    expect(find.descendant(of: find.byType(MatchSectionTitle), matching: find.byType(FadeTransition)), findsNothing);
  });
}
