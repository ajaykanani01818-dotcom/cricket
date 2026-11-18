import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/tabs/match_section_title.dart';
import 'package:crickbex/features/match_detail/tabs/scorecard_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

JsonMap scorecardData() => J.map(fixture('match_scorecard')['data']);

void main() {
  testWidgets('loading without rows shows spinner; empty payload shows empty text', (tester) async {
    await tester.pumpWidget(host(const MatchScorecardTab(scorecard: null, loading: true)));
    expect(find.byKey(const ValueKey('scorecard_loading')), findsOneWidget);
    expect(find.text('Loading scorecard...'), findsOneWidget);

    await tester.pumpWidget(host(const MatchScorecardTab(scorecard: null, loading: false)));
    expect(find.text('No scorecard data available'), findsOneWidget);

    await tester.pumpWidget(host(const MatchScorecardTab(scorecard: {'result': {'innings': []}}, loading: false)));
    expect(find.text('No scorecard data available'), findsOneWidget);
  });

  testWidgets('renders first innings from the real fixture', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    await tester.pump();
    expect(find.byKey(const ValueKey('scorecard_hero_team')), findsOneWidget);
    expect(find.text('Bangladesh'), findsWidgets);
    expect(find.text('400/10', findRichText: true), findsOneWidget);
    expect(find.text('Innings 1 · BAN'), findsOneWidget);
    expect(find.text('101.2 overs'), findsOneWidget);
    expect(find.text('8 b, 10 lb, 1 wd, 1 nb, 0 p'), findsOneWidget);
    expect(find.text('Mahfijul Islam'), findsOneWidget);
    expect(find.text('Ebadot Hossain *'), findsOneWidget); // not out marker
    expect(find.text('c Marco Jansen b Kagiso Rabada'), findsOneWidget);
    expect(find.byType(MatchSectionTitle), findsWidgets);
    expect(find.byKey(const ValueKey('scorecard_target')), findsNothing); // targetRuns null
    // Data present → loading flag does not hide it (silent poll).
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: true)));
    expect(find.byKey(const ValueKey('scorecard_loading')), findsNothing);
    expect(find.text('Mahfijul Islam'), findsOneWidget);
  });

  testWidgets('inning dropdown switches innings and closes', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    await tester.tap(find.byKey(const ValueKey('scorecard_inning_dropdown')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scorecard_inning_menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('scorecard_inning_option_1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scorecard_inning_option_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scorecard_inning_menu')), findsNothing);
    expect(find.text('Innings 2 · RSA'), findsOneWidget);
    expect(find.text('Aiden Markram'), findsOneWidget);
    expect(find.byKey(const ValueKey('scorecard_yet_to_bat')), findsOneWidget);

    // Tap outside closes the menu without changing the selection.
    await tester.tap(find.byKey(const ValueKey('scorecard_inning_dropdown')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scorecard_inning_menu')), findsOneWidget);
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scorecard_inning_menu')), findsNothing);
    expect(find.text('Innings 2 · RSA'), findsOneWidget);
  });

  testWidgets('selection survives a poll; shorter payload clamps the index', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    await tester.tap(find.byKey(const ValueKey('scorecard_inning_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scorecard_inning_option_1')));
    await tester.pumpAndSettle();

    // New map identity, same content.
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    expect(find.text('Innings 2 · RSA'), findsOneWidget);

    // Only one innings now → falls back to the first.
    final one = scorecardData();
    final result = J.map(one['result']);
    result['innings'] = J.list(result['innings']).take(1).toList();
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: one, loading: false)));
    expect(find.text('Innings 1 · BAN'), findsOneWidget);
  });

  testWidgets('same-content poll reuses the built subtree; changed content updates', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    final before = tester.widget(find.byKey(const ValueKey('scorecard_batting')));
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    expect(identical(tester.widget(find.byKey(const ValueKey('scorecard_batting'))), before), isTrue);

    final changed = scorecardData();
    final inn = J.maps(J.at(changed, 'result.innings'))[0];
    J.map(inn['teamInfo'])['runs'] = 404;
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: changed, loading: false)));
    expect(find.text('404/10', findRichText: true), findsOneWidget);
  });

  testWidgets('scroll position is kept across polls (bounded host)', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final pos = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(pos, greaterThan(0));
    final changed = scorecardData();
    J.map(J.maps(J.at(changed, 'result.innings'))[0]['teamInfo'])['runs'] = 401;
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: changed, loading: false)));
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, pos);
  });

  testWidgets('works inside a parent scroll view (unbounded height)', (tester) async {
    await tester.pumpWidget(scrollHost(MatchScorecardTab(scorecard: scorecardData(), loading: false)));
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsNothing);
    expect(find.text('Mahfijul Islam'), findsWidgets); // batting + fall of wickets
    expect(find.byKey(const ValueKey('scorecard_fow')), findsOneWidget);
  });

  testWidgets('target card, missing fields and long names do not crash', (tester) async {
    await tester.pumpWidget(host(MatchScorecardTab(scorecard: {
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
    }, loading: false)));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('scorecard_target')), findsOneWidget);
    expect(find.text('251'), findsOneWidget);
    expect(find.text('No bowling data'), findsOneWidget);
    expect(find.byKey(const ValueKey('scorecard_fow')), findsNothing);
    expect(find.text('Innings 1'), findsWidgets);
  });
}
