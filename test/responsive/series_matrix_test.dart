import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:crickbex/features/matches/matches_screen.dart';
import 'package:crickbex/features/series/series_detail_screen.dart';
import 'package:crickbex/features/series/series_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';
import '../support/screen_matrix.dart';

/// Series list and series hub (every tab) above a fixed bottom bar.
/// Strict mode: flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

Map<String, Responder> _routes() => {
  ...defaultRoutes(),
  '/series': FakeApi.fixture('series_list'),
  '/series/YcK6usv': FakeApi.fixture('series_fixtures'),
  '/series/YcK6usv/point-table': FakeApi.fixture('series_point_table'),
  '/series/YcK6usv/stats': FakeApi.fixture('series_stats'),
  '/series/YcK6usv/squad': FakeApi.fixture('series_squad'),
};

Widget _app(String location) => MaterialApp.router(
  debugShowCheckedModeBanner: false,
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  builder: (context, child) => PaletteSync(child: child!),
  routerConfig: _router(location),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) return;
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first, warnIfMissed: false);
  await defaultMatrixSettle(tester);
}

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
  Future<void> setUp(_) async {
    SharedPreferences.setMockInitialValues({});
    FakeApi(_routes()).install();
  }

  testWidgets('series list: viewport x textScale x brightness matrix', (tester) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'series_list',
      failOnOverflow: _strict,
      setUp: setUp,
      build: (c) => _app('/discover/series'),
      interact: (tester, c) async {
        await _tap(tester, 'tab_UPCOMING');
        await _tap(tester, 'tab_COMPLETED');
      },
    );
    expect(report.cases, isNotEmpty);
  });

  testWidgets('series detail: viewport x textScale x brightness matrix (all tabs)', (tester) async {
    final report = await pumpScreenMatrix(
      tester,
      name: 'series_detail',
      failOnOverflow: _strict,
      setUp: setUp,
      build: (c) => _app('/discover/series-detail/YcK6usv'),
      interact: (tester, c) async {
        await _tap(tester, 'tab_points');
        await _tap(tester, 'series_points_row_ARA');
        await _tap(tester, 'tab_squads');
        final team = find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('series_squad_team_'),
        );
        if (team.evaluate().isNotEmpty) {
          await tester.tap(team.first, warnIfMissed: false);
          await defaultMatrixSettle(tester);
        }
        await _tap(tester, 'tab_stats');
        await _tap(tester, 'series_stats_more_most_runs');
      },
    );
    expect(report.cases, isNotEmpty);
  });
}
