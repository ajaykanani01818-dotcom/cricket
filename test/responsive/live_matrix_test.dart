import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/live/live_screen.dart';
import 'package:crickbex/features/search/search_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_test_router.dart';
import '../common/helpers.dart';
import '../support/screen_matrix.dart';

/// Live tab (inside the real AppShell) over the viewport x text scale x
/// brightness matrix: once with live matches (grouped, a Test at stumps,
/// long names) and once with nothing live (next start + results).
/// Strict mode: flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

Widget _app(MatrixCase c) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  builder: (context, child) => PaletteSync(child: child!),
  routerConfig: appTestRouter(
    live: const LiveScreen(),
    initialLocation: '/live',
    realShell: true,
  ),
);

void main() {
  setUp(() => MinuteClock.nowFn = () => DateTime.utc(2026, 11, 18, 1));
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  testWidgets('live screen with matches: matrix', (tester) async {
    final long = liveMatchJson(
      key: 'LONG',
      series: 'A very long series name ' * 4,
    );
    (long['teams'] as Map)['t1']['name'] = 'Papua New Guinea Women Emerging';
    final report = await pumpScreenMatrix(
      tester,
      name: 'live',
      failOnOverflow: _strict,
      setUp: (_) async {
        SharedPreferences.setMockInitialValues({});
        SearchIndex.instance = SearchIndex();
        FakeApi({
          '/match/live': FakeApi.ok(
            body([
              liveMatchJson(key: 'L1', series: 'Series A'),
              liveMatchJson(key: 'L2', series: 'Series A')
                ..['status'] = 'STUMPS'
                ..['format'] = 'TEST',
              long,
            ]),
          ),
        }).install();
      },
      build: _app,
    );
    expect(report.cases, isNotEmpty);
  });

  testWidgets('live screen with nothing live: matrix', (tester) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'live_empty',
      failOnOverflow: _strict,
      setUp: (_) async {
        SharedPreferences.setMockInitialValues({});
        SearchIndex.instance = SearchIndex();
        FakeApi({
          '/match/live': FakeApi.ok(body(const [])),
          '/match/upcoming': FakeApi.fixture('match_upcoming'),
          '/match/recent': FakeApi.fixture('match_recent'),
        }).install();
      },
      build: _app,
    );
    expect(report.cases, isNotEmpty);
  });
}
