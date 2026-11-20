import 'dart:convert';

import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/search/recent_searches.dart';
import 'package:crickbex/features/search/search_index.dart';
import 'package:crickbex/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_test_router.dart';
import '../common/helpers.dart';
import '../support/screen_matrix.dart';

/// Search (pushed on Home, inside the real AppShell) over the matrix: the
/// recent-searches state, and results for a query that hits matches,
/// series and players.
/// Strict mode: flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

Widget _app(MatrixCase c) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  builder: (context, child) => PaletteSync(child: child!),
  routerConfig: appTestRouter(initialLocation: '/home/search', realShell: true),
);

Future<void> _setUp(MatrixCase _) async {
  SharedPreferences.setMockInitialValues({
    RecentSearches.prefsKey: jsonEncode([
      'Australia',
      'A rather long search about Papua New Guinea Women',
    ]),
  });
  SearchIndex.instance = SearchIndex();
  FakeApi({
    ...defaultRoutes(),
    '/match/live': FakeApi.ok(
      body([liveMatchJson(key: 'LV', series: 'Australia Cup')]),
    ),
    '/series': FakeApi.fixture('series_list'),
    '/players/trending': FakeApi.fixture('players_trending'),
  }).install();
}

void main() {
  setUp(() => MinuteClock.nowFn = () => DateTime.utc(2026, 11, 18, 1));
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  testWidgets('search: recent searches matrix', (tester) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'search_recent',
      failOnOverflow: _strict,
      setUp: _setUp,
      build: _app,
    );
    expect(report.cases, isNotEmpty);
  });

  testWidgets('search: results matrix', (tester) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'search_results',
      failOnOverflow: _strict,
      setUp: _setUp,
      build: _app,
      interact: (tester, c) async {
        await tester.enterText(
          find.byKey(const ValueKey('search_field')),
          'australia',
        );
        await tester.pump(SearchScreen.debounce);
        await defaultMatrixSettle(tester);
      },
    );
    expect(report.cases, isNotEmpty);
  });
}
