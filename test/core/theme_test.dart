import 'package:crickbex/app.dart';
import 'package:crickbex/core/router/app_router.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/core/widgets/theme_mode_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A const widget that reads the LEGACY static palette in build: proves the
/// forced element rebuild reaches const subtrees.
class _LegacyProbe extends StatelessWidget {
  const _LegacyProbe();
  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('probe'),
    color: AppColors.bg,
    child: const SizedBox(width: 10, height: 10),
  );
}

void main() {
  group('contrast (WCAG)', () {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      final mode = p.brightness.name;
      for (final t in p.textTokens.entries) {
        for (final s in p.surfaceTokens.entries) {
          test('$mode ${t.key} on ${s.key} ≥ 4.5:1', () {
            expect(
              contrast(t.value, s.value),
              greaterThanOrEqualTo(4.5),
              reason: '${t.value} on ${s.value}',
            );
          });
        }
      }
      test(
        '$mode onBrand on brand ≥ 4.5:1 and white on brand is forbidden (< 3)',
        () {
          expect(contrast(p.onBrand, p.brand), greaterThanOrEqualTo(4.5));
          expect(contrast(const Color(0xFFFFFFFF), p.brand), lessThan(3));
        },
      );
      test(
        '$mode ink and brandText on brandTint (composited on surface) ≥ 4.5:1',
        () {
          final tint = Color.alphaBlend(p.brandTint, p.surface);
          expect(contrast(p.ink, tint), greaterThanOrEqualTo(4.5));
          expect(contrast(p.brandText, tint), greaterThanOrEqualTo(4.5));
        },
      );
      test(
        '$mode surface text on ink (inverted chips, snackbar, W bead) ≥ 4.5:1',
        () {
          expect(contrast(p.surface, p.ink), greaterThanOrEqualTo(4.5));
        },
      );
    }

    test('spec hex values', () {
      expect(AppPalette.light.brand, const Color(0xFFED800C));
      expect(AppPalette.dark.brand, const Color(0xFFED800C));
      expect(AppPalette.light.brandText, const Color(0xFFA65300));
      expect(AppPalette.dark.brandText, const Color(0xFFFF9A3C));
      expect(AppPalette.light.canvas, const Color(0xFFF4F4F3));
      expect(AppPalette.dark.canvas, const Color(0xFF17130F));
    });
  });

  group('buildAppTheme', () {
    test('carries the palette and brightness', () {
      final l = buildAppTheme(), d = buildAppTheme(brightness: Brightness.dark);
      expect(l.extension<AppPalette>(), AppPalette.light);
      expect(d.extension<AppPalette>(), AppPalette.dark);
      expect(d.brightness, Brightness.dark);
      expect(d.scaffoldBackgroundColor, AppPalette.dark.canvas);
      expect(l.colorScheme.primary, AppPalette.light.brand);
      expect(l.colorScheme.onPrimary, AppPalette.light.onBrand);
      expect(l.textTheme.bodyMedium!.fontFamily, AppFont.family);
    });

    test('score styles: Archivo wdth 72, wght 800, tabular figures', () {
      for (final s in [
        AppText.scoreHero,
        AppText.scoreCard,
        AppText.scoreRow,
      ]) {
        expect(s.fontFamily, AppFont.family);
        expect(s.fontWeight, FontWeight.w800);
        expect(
          s.fontVariations,
          containsAll(const [
            FontVariation('wght', 800),
            FontVariation('wdth', 72),
          ]),
        );
        expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      expect(AppText.reading.fontSize, 15);
      expect(AppText.reading.height, 1.45);
    });
  });

  group('ThemeController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ThemeController.instance.debugReset();
    });
    tearDown(() => ThemeController.instance.debugReset());

    test('defaults to System; persists and reloads the choice', () async {
      final c = ThemeController.instance;
      await c.load();
      expect(c.mode, ThemeMode.system);
      await c.setMode(ThemeMode.dark);
      expect(
        (await SharedPreferences.getInstance()).getString(
          ThemeController.prefsKey,
        ),
        'dark',
      );
      expect(AppPalette.active, AppPalette.dark);
      c.debugReset();
      await c.load();
      expect(c.mode, ThemeMode.dark);
      expect(c.effectiveBrightness, Brightness.dark);
      expect(ThemeController.parse('nonsense'), ThemeMode.system);
    });

    testWidgets(
      'runtime switch: instant, keeps the navigation stack, updates const legacy widgets',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view.physicalSize = const Size(400, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        FakeApi(defaultRoutes()).install();
        final c = ThemeController.instance;
        await c.load();
        final router = buildRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          CrickbexApp(router: router, themeController: c, requireEnv: false),
        );
        await settle(tester);

        // Navigate: Discover tab → Series (pushed on the Discover stack).
        await tester.tap(find.byKey(const ValueKey('tab_bar_discover')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('discover_series')));
        await settle(tester);
        expect(router.state.uri.path, '/discover/series');

        await c.setMode(ThemeMode.dark);
        await tester.pump();
        expect(router.state.uri.path, '/discover/series', reason: 'stack kept');
        expect(
          Theme.of(
            tester.element(find.byKey(const ValueKey('app_shell'))),
          ).brightness,
          Brightness.dark,
        );
        expect(
          tester
              .widget<Scaffold>(find.byKey(const ValueKey('app_shell')))
              .backgroundColor,
          AppPalette.dark.canvas,
        );
        // Back still pops within Discover.
        router.pop();
        await settle(tester);
        expect(router.state.uri.path, '/discover');

        await c.setMode(ThemeMode.light);
        await tester.pump();
        expect(AppPalette.active, AppPalette.light);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'const widget reading AppColors repaints on switch (forced rebuild)',
      (tester) async {
        final c = ThemeController.instance;
        await c.load();
        await tester.pumpWidget(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => MaterialApp(
              theme: buildAppTheme(),
              darkTheme: buildAppTheme(brightness: Brightness.dark),
              themeMode: c.mode,
              home: const Scaffold(
                body: Column(children: [_LegacyProbe(), ThemeModeSelector()]),
              ),
            ),
          ),
        );
        ColoredBox probe() =>
            tester.widget<ColoredBox>(find.byKey(const ValueKey('probe')));
        expect(probe().color, AppPalette.light.canvas);
        await tester.tap(find.byKey(const ValueKey('segment_ThemeMode.dark')));
        await tester.pump();
        expect(c.mode, ThemeMode.dark);
        expect(probe().color, AppPalette.dark.canvas);
      },
    );

    testWidgets('System mode follows the platform brightness', (tester) async {
      final c = ThemeController.instance;
      await c.load();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pump();
      expect(c.effectiveBrightness, Brightness.dark);
      expect(AppPalette.active, AppPalette.dark);
    });
  });
}
