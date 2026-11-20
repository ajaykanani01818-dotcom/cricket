import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/match_detail/match_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../match_detail/helpers.dart';
import '../support/screen_matrix.dart';

/// Responsive matrix for the Match Centre: every header state at 320-1440
/// dp x text 1.0 / 1.3 / 2.0 x light / dark, with fixture data. For the live
/// Test the run also collapses the header and visits every tab.
/// Report-only by default; strict:
///   flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

Widget _app(FakeApi api, String matchId) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      builder: (context, child) => PaletteSync(child: child!),
      home: MatchDetailScreen(matchId: matchId, matchService: api.matches, playerService: api.players),
    );

Future<void> _visitTabs(WidgetTester tester, MatrixCase c) async {
  final scroll = find.descendant(of: find.byKey(const ValueKey('match_detail_scroll')), matching: find.byType(Scrollable)).first;
  await tester.drag(scroll, const Offset(0, -900), warnIfMissed: false);
  await defaultMatrixSettle(tester);
  for (final t in MatchTab.values) {
    final f = find.byKey(ValueKey('match_detail_tab_${t.name}')).hitTestable();
    if (f.evaluate().isEmpty) continue;
    await tester.tap(f.first, warnIfMissed: false);
    await defaultMatrixSettle(tester);
  }
}

void _matrix(String name, FakeApi Function() api, String matchId, {bool tabs = false}) {
  testWidgets('match centre ($name): viewport x textScale x brightness matrix', (tester) async {
    late FakeApi current;
    final report = await pumpScreenMatrix(
      tester,
      name: 'match_centre_$name',
      failOnOverflow: _strict,
      setUp: (_) async {
        SharedPreferences.setMockInitialValues({});
        current = api();
      },
      build: (c) => _app(current, matchId),
      interact: tabs ? _visitTabs : null,
    );
    expect(report.cases, hasLength(kMatrixViewports.length * kMatrixTextScales.length * kMatrixBrightness.length));
  });
}

void main() {
  _matrix('test_live', () => FakeApi()..detail = ((_) => ok(liveDetailData()..['status'] = 'LIVE')), '3QJ-e3k', tabs: true);
  _matrix('test_stumps', FakeApi.new, '3QJ-e3k');
  _matrix(
    't20_chase',
    () => FakeApi(matchId: 'LIVE01')
      ..detail = ((_) => ok(t20ChaseDetail()))
      ..live = ((_) => ok(t20ChaseLive()))
      ..scorecard = ((_) => err(404, 'Match scorecard not found!!')),
    'LIVE01',
  );
  _matrix(
    'odi_first_innings',
    () => FakeApi(matchId: 'w2bXPRS')
      ..detail = ((_) => ok(odiFirstInningsDetail()))
      ..live = ((_) => ok(odiFirstInningsLive())),
    'w2bXPRS',
  );
  _matrix('upcoming', () => FakeApi(matchId: 'w2bXPRS')..detail = ((_) => ok(upcomingDetail())), 'w2bXPRS');
  _matrix('completed', () => FakeApi()..detail = ((_) => ok(completedDetailData())), '3QJ-e3k', tabs: true);
  _matrix(
    'abandoned',
    () => FakeApi(matchId: 'w2bXPRS')..detail = ((_) => ok(upcomingDetail()..['status'] = 'ABANDONED')),
    'w2bXPRS',
  );
  _matrix(
    'long_names',
    () {
      final d = completedDetailData();
      J.map(J.at(d, 'teams.t1'))['name'] = 'An Extremely Long Team Name That Goes On And On Forever XI';
      d['seriesName'] = 'A ridiculously long series name ' * 4;
      return FakeApi()..detail = ((_) => ok(d));
    },
    '3QJ-e3k',
  );
}
