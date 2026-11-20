import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:flutter/material.dart';
import 'package:crickbex/features/matches/matches_screen.dart';
import 'package:crickbex/features/series/series_detail_screen.dart';
import 'package:crickbex/features/series/series_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';
import '../support/screen_matrix.dart';

/// Matches tab above a fixed bottom bar, every viewport x text scale x
/// brightness, visiting Live (with a live match), Upcoming (day strip,
/// countdowns) and Results (filters on). Strict mode:
///   flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

/// Minimal stand-in for the app shell: the screen above a fixed 64 dp
/// bottom bar (same geometry as AppShell). Keeps this matrix independent of
/// screens other agents are editing (the real router imports all of them).
GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    ShellRoute(
      builder: (context, state, child) => Scaffold(
        body: child,
        bottomNavigationBar: ColoredBox(
          color: const Color(0xFFED800C),
          child: SafeArea(top: false, child: const SizedBox(height: 64, width: double.infinity)),
        ),
      ),
      routes: [
        GoRoute(path: '/matches', builder: (_, _) => const MatchesScreen()),
        GoRoute(path: '/discover/series', builder: (_, _) => const SeriesScreen()),
        GoRoute(
          path: '/discover/series-detail/:id',
          builder: (_, s) => SeriesDetailScreen(seriesId: s.pathParameters['id']!, seriesName: 'Abu Dhabi T10 League 2026'),
        ),
      ],
    ),
  ],
);

void main() {
  setUp(() => MinuteClock.nowFn = () => DateTime.utc(2026, 11, 18, 1, 0));
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  testWidgets('matches screen: viewport x textScale x brightness matrix', (tester) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'matches',
      failOnOverflow: _strict,
      setUp: (_) async {
        SharedPreferences.setMockInitialValues({});
        FakeApi({
          ...defaultRoutes(),
          '/match/live': FakeApi.ok(
            body([
              liveMatchJson(),
              liveMatchJson(key: 'LIVE02', series: 'A very long series name that will not fit on a small phone 2026'),
            ]),
          ),
        }).install();
      },
      build: (c) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        builder: (context, child) => PaletteSync(child: child!),
        routerConfig: _router('/matches'),
      ),
      interact: (tester, c) async {
        Future<void> tap(String key) async {
          final f = find.byKey(ValueKey(key));
          if (f.evaluate().isEmpty) return;
          await tester.ensureVisible(f.first);
          await tester.pump();
          await tester.tap(f.first, warnIfMissed: false);
          await defaultMatrixSettle(tester);
        }

        await tap('tab_upcoming');
        await tap('matches_day_today');
        await tap('tab_completed');
        await tap('matches_format_t20');
        await tap('matches_filter_women');
        await tap('matches_format_test'); // filtered-empty state
        await tap('matches_clear_filters');
      },
    );
    expect(report.cases, hasLength(kMatrixViewports.length * kMatrixTextScales.length * kMatrixBrightness.length));
  });
}
