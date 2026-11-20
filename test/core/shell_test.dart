import 'package:crickbex/app.dart';
import 'package:crickbex/core/router/app_nav.dart';
import 'package:crickbex/core/router/app_router.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/core/widgets/app_bottom_bar.dart';
import 'package:crickbex/features/discover/discover_screen.dart';
import 'package:crickbex/features/home/home_screen.dart';
import 'package:crickbex/features/live/live_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double bottomInset = 0,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  FakeApi(defaultRoutes()).install();
  final router = buildRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
  await settle(tester);
  return router;
}

void main() {
  setUp(() => ThemeController.instance.debugReset());

  testWidgets('five tabs in order: Home, Live, Matches, Discover, Settings', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    expect(router.state.uri.path, '/home');
    expect(find.byType(HomeScreen), findsOneWidget);
    final bar = tester.widget<AppBottomBar>(find.byType(AppBottomBar));
    expect(bar.items.map((i) => i.label), [
      'Home',
      'Live',
      'Matches',
      'Discover',
      'Settings',
    ]);
    expect(tabRoots, ['/home', '/live', '/matches', '/discover', '/settings']);

    for (final (key, path) in [
      ('live', '/live'),
      ('matches', '/matches'),
      ('discover', '/discover'),
      ('settings', '/settings'),
      ('home', '/home'),
    ]) {
      await tester.tap(find.byKey(ValueKey('tab_bar_$key')));
      await settle(tester);
      expect(router.state.uri.path, path);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final w in [320.0, 390.0, 412.0, 820.0, 1440.0]) {
    testWidgets(
      'bar is fixed, full width and flush to the bottom edge at ${w.toInt()} px (inset filled)',
      (tester) async {
        const inset = 24.0;
        final h = w >= 820 ? 900.0 : 780.0;
        await _pumpShell(tester, size: Size(w, h), bottomInset: inset);
        final bar = tester.getRect(
          find.byKey(const ValueKey('app_bottom_bar')),
        );
        expect(bar.left, 0);
        expect(bar.width, w);
        expect(bar.bottom, h, reason: 'no gap below the bar');
        expect(
          bar.height,
          AppBottomBar.barHeight + inset,
          reason: 'the inset is filled with the bar colour',
        );
        expect(
          tester
              .widget<Material>(find.byKey(const ValueKey('app_bottom_bar')))
              .color,
          AppPalette.light.brand,
        );
        // Content ends above the bar (extendBody false).
        final home = tester.getRect(find.byType(HomeScreen));
        expect(home.bottom, lessThanOrEqualTo(bar.top));
        // Scrolling the content never moves the bar.
        await tester.drag(find.byType(HomeScreen), const Offset(0, -400));
        await settle(tester);
        expect(
          tester.getRect(find.byKey(const ValueKey('app_bottom_bar'))),
          bar,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('bar labels do not overflow at 320 px × text 2.0', (
    tester,
  ) async {
    await _pumpShell(tester, size: const Size(320, 640), textScale: 2);
    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byKey(const ValueKey('app_bottom_bar')));
    expect(bar.bottom, 640);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Android back: pops the tab stack, then returns Home; Home root asks to confirm exit',
    (tester) async {
      final router = await _pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('tab_bar_discover')));
      await settle(tester);
      expect(find.byType(DiscoverScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discover_rankings')));
      await settle(tester);
      expect(router.state.uri.path, '/discover/rankings');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(router.state.uri.path, '/discover');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        router.state.uri.path,
        '/home',
        reason: 'back at a tab root goes Home',
      );

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(router.state.uri.path, '/home');
      expect(find.text('Press back again to exit'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'legacy tab paths redirect into Discover; details push on the current tab',
    (tester) async {
      final router = await _pumpShell(tester);
      router.go('/series');
      await settle(tester);
      expect(router.state.uri.path, '/discover/series');
      router.go('/ranking');
      await settle(tester);
      expect(router.state.uri.path, '/discover/rankings');
      router.go('/players');
      await settle(tester);
      expect(router.state.uri.path, '/discover/players');

      router.go('/live');
      await settle(tester);
      final ctx = tester.element(find.byType(LiveScreen));
      AppNav.match<void>(ctx, 'ABC');
      await settle(tester);
      expect(router.state.uri.path, '/live/match/ABC');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('app launches straight to Home (no splash, no onboarding)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FakeApi(defaultRoutes()).install();
    await tester.pumpWidget(const CrickbexApp(requireEnv: false));
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('startup_onboarding')), findsNothing);
    expect(find.byKey(const ValueKey('startup_splash')), findsNothing);
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
