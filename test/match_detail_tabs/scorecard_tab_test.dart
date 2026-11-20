import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/tabs/scorecard_tab.dart';
import 'package:crickbex/features/match_detail/tabs/tab_scorecard_parse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

JsonMap scorecardData() => J.map(fixture('match_scorecard')['data']);

void main() {
  testWidgets('loading skeleton without rows; empty payload → not available', (tester) async {
    await tester.pumpWidget(host(const MatchScorecardTab(scorecard: null, loading: true)));
    expect(find.byKey(const ValueKey('scorecard_loading')), findsOneWidget);
    await tester.pumpWidget(host(const MatchScorecardTab(scorecard: null, loading: false)));
    expect(find.text('Scorecard not available'), findsOneWidget);
    await tester.pumpWidget(host(const MatchScorecardTab(scorecard: {'result': {'innings': []}}, loading: false)));
    expect(find.text('Scorecard not available'), findsOneWidget);
  });

  testWidgets('opens on the latest innings; switches innings with chips', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    await tester.pump();
    expect(find.text('South Africa'), findsOneWidget);
    expect(find.text('287/4'), findsOneWidget);
    expect(find.text('62.0 ov'), findsOneWidget);
    expect(find.text('BAN 1st'), findsOneWidget);
    expect(find.text('RSA 1st'), findsOneWidget);
    expect(find.text('Aiden Markram'), findsWidgets);
    expect(find.byKey(const ValueKey('scorecard_yet_to_bat')), findsOneWidget);
    expect(find.textContaining('Wiaan Mulder'), findsOneWidget);
    // "not out" is a word, not a colour.
    expect(find.text('not out'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('scorecard_inning_option_0')));
    await tester.pump();
    expect(find.text('Bangladesh'), findsOneWidget);
    expect(find.text('400 all out'), findsOneWidget);
    expect(find.text('8 b, 10 lb, 1 wd, 1 nb, 0 p', findRichText: true), findsNothing);
    expect(find.textContaining('8 b, 10 lb, 1 wd, 1 nb, 0 p', findRichText: true), findsOneWidget);
    expect(find.text('c Marco Jansen b Kagiso Rabada'), findsOneWidget);
    expect(find.byKey(const ValueKey('scorecard_target')), findsNothing); // targetRuns null
  });

  testWidgets('fall of wickets + derived partnerships (labelled derived)', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    expect(find.byKey(const ValueKey('scorecard_fow')), findsOneWidget);
    expect(find.byKey(const ValueKey('scorecard_partnerships')), findsOneWidget);
    expect(find.text('1st wkt 5'), findsOneWidget);
    expect(find.text('2nd wkt 202'), findsOneWidget);
    expect(find.textContaining('Derived from the fall of wickets'), findsOneWidget);
    expect(derivedPartnerships(const [ScFow(id: 'a', name: 'x', score: '5/1', over: '1'), ScFow(id: 'b', name: 'y', score: 'n/a', over: '2')]), [5, null]);
  });

  testWidgets('narrow screen: batting table scrolls sideways instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    expect(tester.takeException(), isNull);
    final batting = find.byKey(const ValueKey('scorecard_batting'));
    expect(find.descendant(of: batting, matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal)), findsOneWidget);
  });

  testWidgets('selection survives a same-content poll; shorter payload falls back to latest', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    await tester.tap(find.byKey(const ValueKey('scorecard_inning_option_0')));
    await tester.pump();
    final before = tester.widget(find.byKey(const ValueKey('scorecard_body')));
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    expect(identical(tester.widget(find.byKey(const ValueKey('scorecard_body'))), before), isTrue);
    expect(find.text('400 all out'), findsOneWidget);

    final changed = scorecardData();
    J.map(J.maps(J.at(changed, 'result.innings'))[0]['teamInfo'])['runs'] = 404;
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: changed, loading: false)));
    expect(find.text('404 all out'), findsOneWidget);

    final one = scorecardData();
    final r = J.map(one['result']);
    r['innings'] = J.list(r['innings']).skip(1).toList();
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: one, loading: false)));
    expect(find.text('287/4'), findsOneWidget);
  });

  testWidgets('target line, missing fields and long names do not crash (dark)', (tester) async {
    await tester.pumpWidget(host(
      const MatchScorecardTab(scorecard: {
        'result': {
          'targetRuns': 251,
          'innings': [
            {
              'teamInfo': {'teamName': 'A very very long team name that keeps going and going forever and ever'},
              'batting': [
                {'playerName': 'Someone With An Extraordinarily Long Name Indeed Yes', 'isOut': false},
              ],
            }
          ],
        }
      }, loading: false),
      brightness: Brightness.dark,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Target 251'), findsOneWidget);
    expect(find.text('Bowling details not available.'), findsOneWidget);
    expect(find.byKey(const ValueKey('scorecard_fow')), findsNothing);
  });
}
