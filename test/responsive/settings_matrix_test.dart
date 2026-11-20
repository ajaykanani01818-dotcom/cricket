import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/ads/ads.dart';
import 'package:crickbex/features/review/review.dart';
import 'package:crickbex/features/settings/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/screen_matrix.dart';

/// Responsive matrix for Settings and every page reached from it
/// (viewport x text scale x brightness), scrolled top to bottom so every row
/// is laid out. Report-only by default; strict with
///   flutter test test/responsive --dart-define=SCREEN_MATRIX_STRICT=true
const _strict = bool.fromEnvironment('SCREEN_MATRIX_STRICT');

const _pages = {
  'settings': '/settings',
  'settings_privacy': '/settings/privacy',
  'settings_terms': '/settings/terms',
  'settings_contact': '/settings/contact',
  'settings_about': '/settings/about',
  'settings_app_info': '/settings/app-info',
  'settings_more': '/settings/more',
};

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsScreen(),
      routes: [
        GoRoute(path: 'more', builder: (_, _) => const MoreScreen()),
        GoRoute(
          path: 'privacy',
          builder: (_, _) => const PrivacyPolicyScreen(),
        ),
        GoRoute(path: 'terms', builder: (_, _) => const TermsScreen()),
        GoRoute(path: 'about', builder: (_, _) => const AboutUsScreen()),
        GoRoute(path: 'contact', builder: (_, _) => const ContactUsScreen()),
        GoRoute(path: 'app-info', builder: (_, _) => const AppInfoScreen()),
      ],
    ),
  ],
);

Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  // The outermost (first) scrollable is the page list.
  final target = scrollables.first;
  for (var i = 0; i < 25; i++) {
    final state = tester.state<ScrollableState>(target);
    final pos = state.position;
    if (pos.pixels >= pos.maxScrollExtent) break;
    pos.jumpTo(
      (pos.pixels + pos.viewportDimension * 0.8).clamp(0, pos.maxScrollExtent),
    );
    await tester.pump();
  }
}

void main() {
  for (final MapEntry(key: name, value: location) in _pages.entries) {
    testWidgets('$name: viewport x textScale x brightness matrix', (
      tester,
    ) async {
      final report = await pumpScreenMatrix(
        tester,
        name: name,
        failOnOverflow: _strict,
        setUp: (_) async {
          SharedPreferences.setMockInitialValues({});
          ThemeController.instance.debugReset();
          AdsManager.instance.debugReset();
          AppVersion.debugReset();
          PackageInfo.setMockInitialValues(
            appName: 'Cric Ticker',
            packageName: 'com.cricticker.app',
            version: '1.0.0',
            buildNumber: '12',
            buildSignature: '',
          );
        },
        build: (c) {
          final router = _router(location);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            darkTheme: buildAppTheme(brightness: Brightness.dark),
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => PaletteSync(
              child: ReviewHost(
                controller: ReviewController(exitApp: () {}),
                child: child!,
              ),
            ),
            routerConfig: router,
          );
        },
        interact: (tester, _) => _scrollThrough(tester),
      );
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
}
