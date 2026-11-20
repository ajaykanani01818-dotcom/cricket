import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/discover/discover_screen.dart';
import 'package:crickbex/features/players/player_detail_screen.dart';
import 'package:crickbex/features/players/players_screen.dart';
import 'package:crickbex/features/rankings/ranking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../players/test_helpers.dart';
import '../support/screen_matrix.dart';

/// Responsive matrix for the Discover hub, Rankings, Players and the player
/// profile, inside a shell-like scaffold with a 64 dp bottom bar and fixture
/// data. Report-only by default; make overflows fail with:
///   flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

Widget _app(MatrixCase c, String location) {
  Widget shell(Widget child) => Scaffold(
    body: child,
    bottomNavigationBar: const SizedBox(
      height: 64,
      child: ColoredBox(color: Color(0xFFED800C)),
    ),
  );
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/discover',
        builder: (_, _) => shell(const DiscoverScreen()),
        routes: [
          GoRoute(
            path: 'rankings',
            builder: (_, _) => shell(const RankingScreen()),
          ),
          GoRoute(
            path: 'players',
            builder: (_, _) => shell(const PlayersScreen()),
          ),
          GoRoute(path: 'series', builder: (_, _) => shell(const SizedBox())),
          GoRoute(
            path: 'player/:k',
            builder: (_, s) =>
                shell(PlayerDetailScreen(playerKey: s.pathParameters['k']!)),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    darkTheme: buildAppTheme(brightness: Brightness.dark),
    builder: (context, child) => PaletteSync(child: child!),
    routerConfig: router,
  );
}

Future<void> _setUp(MatrixCase _) async {
  SharedPreferences.setMockInitialValues({});
  FakeApi(discoverFixtures);
}

int _cases() =>
    kMatrixViewports.length *
    kMatrixTextScales.length *
    kMatrixBrightness.length;

Future<void> _scrollDown(WidgetTester t, Finder list) async {
  if (list.evaluate().isEmpty) return;
  for (var i = 0; i < 4; i++) {
    await t.drag(list, const Offset(0, -500), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => ThemeController.instance.debugReset());

  testWidgets('discover hub matrix', (t) async {
    final r = await pumpScreenMatrix(
      t,
      name: 'discover',
      failOnOverflow: _strict,
      setUp: _setUp,
      build: (c) => _app(c, '/discover'),
      interact: (t, c) =>
          _scrollDown(t, find.byKey(const ValueKey('discover_list'))),
    );
    expect(r.cases, hasLength(_cases()));
  });

  testWidgets('rankings matrix (teams, then all-rounders with search box)', (
    t,
  ) async {
    final r = await pumpScreenMatrix(
      t,
      name: 'rankings',
      failOnOverflow: _strict,
      setUp: _setUp,
      build: (c) => _app(c, '/discover/rankings'),
      interact: (t, c) async {
        await _scrollDown(t, find.byKey(const ValueKey('rankings_list')));
        final tab = find.byKey(const ValueKey('tab_allRounders'));
        await t.ensureVisible(tab);
        await t.tap(tab, warnIfMissed: false);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 60));
        }
      },
    );
    expect(r.cases, hasLength(_cases()));
  });

  testWidgets('players matrix (browse, then search results)', (t) async {
    final r = await pumpScreenMatrix(
      t,
      name: 'players',
      failOnOverflow: _strict,
      setUp: _setUp,
      build: (c) => _app(c, '/discover/players'),
      interact: (t, c) async {
        await _scrollDown(t, find.byKey(const ValueKey('players_list')));
        await t.enterText(
          find.byKey(const ValueKey('players_search')),
          'jaiswal',
        );
        await t.pump(PlayersScreen.searchDebounce);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      },
    );
    expect(r.cases, hasLength(_cases()));
  });

  testWidgets('player profile matrix', (t) async {
    final r = await pumpScreenMatrix(
      t,
      name: 'player_profile',
      failOnOverflow: _strict,
      setUp: _setUp,
      build: (c) => _app(c, '/discover/player/aiden_markram'),
      interact: (t, c) =>
          _scrollDown(t, find.byKey(const ValueKey('player_detail_scroll'))),
    );
    expect(r.cases, hasLength(_cases()));
  });
}
