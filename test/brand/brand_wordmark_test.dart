import 'dart:io';

import 'package:crickbex/core/brand/brand.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/widgets/titles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _assetOf(WidgetTester tester) {
  final img = tester.widget<Image>(find.byType(Image));
  final provider = img.image as ResizeImage;
  return (provider.imageProvider as AssetImage).assetName;
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  Brightness? override,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(brightness: brightness),
    home: Scaffold(
      body: Center(child: BrandWordmark(height: 32, brightness: override)),
    ),
  ),
);

void main() {
  testWidgets('light theme → logo_light, dark theme → logo_dark', (
    tester,
  ) async {
    await _pump(tester, brightness: Brightness.light);
    expect(_assetOf(tester), Brand.logoLight);
    expect(find.byKey(const ValueKey('brand_wordmark_light')), findsOneWidget);

    await _pump(tester, brightness: Brightness.dark);
    await tester.pump(const Duration(milliseconds: 300)); // theme lerp
    expect(_assetOf(tester), Brand.logoDark);
    expect(find.byKey(const ValueKey('brand_wordmark_dark')), findsOneWidget);
  });

  testWidgets('brightness override wins over the theme', (tester) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      override: Brightness.dark,
    );
    expect(_assetOf(tester), Brand.logoDark);
  });

  testWidgets('size, cacheWidth sized to display, semantics label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await _pump(tester, brightness: Brightness.light);
    final size = tester.getSize(find.byType(BrandWordmark));
    expect(size.height, 32);
    expect(size.width, closeTo(32 * Brand.logoAspect, 0.01));
    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect((provider as ResizeImage).width, (32 * Brand.logoAspect * 3).ceil());
    expect(find.bySemanticsLabel(Brand.appName), findsOneWidget);
    handle.dispose();
  });

  testWidgets('broken asset falls back to the name in text', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _FailingBundle(),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: Center(child: BrandWordmark())),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text(Brand.appName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('brand asset files exist and are registered', () {
    for (final a in [
      Brand.logoLight,
      Brand.logoDark,
      Brand.logoMark,
      Brand.iconMark,
      Brand.splashBackground,
    ]) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/brand/'),
    );
    expect(File('assets/images/brand-wordmark.svg').existsSync(), isFalse);
  });
}

class _FailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => key.startsWith('assets/brand/')
      ? throw FlutterError('asset missing: $key')
      : rootBundle.load(key);
}
