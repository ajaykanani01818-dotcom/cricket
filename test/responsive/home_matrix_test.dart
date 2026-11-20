import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/home/home_screen.dart';
import 'package:crickbex/features/search/search_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_test_router.dart';
import '../common/helpers.dart';
import '../support/screen_matrix.dart';

/// Responsive matrix over the Home tab inside the real AppShell, with fixture
/// data: two live matches (the raised card + a row), upcoming, results. Report-only by default (the report is printed and written to
/// build/screen_matrix/home.txt); make overflows fail with:
///   flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

void main() {
  testWidgets('home screen: viewport x textScale x brightness matrix', (
    tester,
  ) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'home',
      failOnOverflow: _strict,
      setUp: (_) async {
        SharedPreferences.setMockInitialValues({});
        SearchIndex.instance = SearchIndex();
        MinuteClock.nowFn = () => DateTime.utc(2026, 11, 18, 1);
        FakeApi({
          ...defaultRoutes(),
          '/match/live': FakeApi.ok(
            body([
              liveMatchJson(key: 'L1'),
              liveMatchJson(key: 'L2', series: 'Other Cup')
                ..['status'] = 'STUMPS',
            ]),
          ),
          '/match/L1': FakeApi.fixture('match_detail'),
        }).install();
      },
      build: (c) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        builder: (context, child) => PaletteSync(child: child!),
        routerConfig: appTestRouter(home: const HomeScreen(), realShell: true),
      ),
    );
    MinuteClock.nowFn = DateTime.now;
    expect(
      report.cases,
      hasLength(
        kMatrixViewports.length *
            kMatrixTextScales.length *
            kMatrixBrightness.length,
      ),
    );
  });
}
