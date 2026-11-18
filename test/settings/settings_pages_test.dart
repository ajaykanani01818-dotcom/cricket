import 'dart:async';

import 'package:crickbex/features/ads/ads.dart';
import 'package:crickbex/features/review/review.dart';
import 'package:crickbex/features/settings/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/fake_ads_backend.dart';

List<RouteBase> _info() => [
      GoRoute(path: 'more', builder: (_, _) => const MoreScreen()),
      GoRoute(path: 'privacy', builder: (_, _) => const PrivacyPolicyScreen()),
      GoRoute(path: 'terms', builder: (_, _) => const TermsScreen()),
      GoRoute(path: 'about', builder: (_, _) => const AboutUsScreen()),
      GoRoute(path: 'contact', builder: (_, _) => const ContactUsScreen()),
      GoRoute(path: 'app-info', builder: (_, _) => const AppInfoScreen()),
    ];

GoRouter _router(String initial) => GoRouter(initialLocation: initial, routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen(), routes: _info()),
      GoRoute(path: '/live', builder: (_, _) => const Scaffold(body: Text('home')), routes: _info()),
    ]);

void main() {
  final opened = <Uri>[];
  late bool openResult;
  late ReviewController review;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'CrickBex', packageName: 'com.crickbex.dark', version: '1.2.3', buildNumber: '7', buildSignature: '');
    opened.clear();
    openResult = true;
    LinkLauncher.opener = (uri) async {
      opened.add(uri);
      return openResult;
    };
    review = ReviewController(openStoreListing: () async => true, exitApp: () {});
    AdsManager.instance.debugReset();
  });

  tearDown(() => AdsManager.instance.debugReset());

  Future<GoRouter> pumpApp(WidgetTester tester, String location, {bool withReview = true}) async {
    final router = _router(location);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: withReview ? (context, child) => ReviewHost(controller: review, child: child!) : null,
    ));
    await tester.pump();
    return router;
  }

  group('SettingsScreen', () {
    testWidgets('title, rate row and menu; rows navigate', (tester) async {
      final r = await pumpApp(tester, '/settings');
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('Rate CrickBex'), findsOneWidget);
      expect(find.text('Contact Us'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings_item_contact')));
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsOneWidget);
      expect(r.canPop(), isTrue);
      await tester.tap(find.byKey(const ValueKey('settings_back')));
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsNothing);
      expect(r.canPop(), isFalse);

      await tester.tap(find.byKey(const ValueKey('settings_item_privacy')));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    });

    testWidgets('rate row opens the rating modal', (tester) async {
      await pumpApp(tester, '/settings');
      await tester.tap(find.byKey(const ValueKey('settings_rate')));
      await tester.pump();
      expect(find.text('Enjoying CrickBex?'), findsOneWidget);
    });

    testWidgets('no review host → rate row hidden', (tester) async {
      await pumpApp(tester, '/settings', withReview: false);
      expect(find.text('Rate CrickBex'), findsNothing);
      expect(find.text('Contact Us'), findsOneWidget);
    });

    testWidgets('double tap pushes the page only once', (tester) async {
      final r = await pumpApp(tester, '/settings');
      await tester.tap(find.byKey(const ValueKey('settings_item_contact')));
      await tester.tap(find.byKey(const ValueKey('settings_item_contact')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings_back')));
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsNothing, reason: 'only one page was pushed');
      expect(r.canPop(), isFalse);
    });

    testWidgets('ads not ready → no banner widgets take space', (tester) async {
      await pumpApp(tester, '/settings');
      expect(find.byType(ScreenBannerAd), findsNothing);
    });
  });

  group('MoreScreen', () {
    testWidgets('sections, menu, navigation and back', (tester) async {
      final r = await pumpApp(tester, '/live/more');
      expect(find.text('More'), findsOneWidget);
      expect(find.text('We’d love your feedback'), findsOneWidget);
      expect(find.text('Legal & support'), findsOneWidget);
      final scrollable = find.descendant(of: find.byKey(const ValueKey('more_list')), matching: find.byType(Scrollable));
      for (final t in ['Privacy Policy', 'Terms & Conditions', 'About Us', 'Contact Us', 'App Info']) {
        await tester.scrollUntilVisible(find.text(t), 100, scrollable: scrollable);
        expect(find.text(t), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('more_rewarded')), findsNothing, reason: 'ads not ready');

      await tester.tap(find.byKey(const ValueKey('more_item_terms')));
      await tester.pumpAndSettle();
      expect(find.byType(TermsScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings_back')));
      await tester.pumpAndSettle();
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(r.canPop(), isTrue, reason: 'More itself was pushed on /live');
    });

    testWidgets('Send Feedback opens a mailto with %20 subject', (tester) async {
      await pumpApp(tester, '/live/more');
      await tester.tap(find.byKey(const ValueKey('more_feedback')));
      await tester.pump();
      expect(opened.single.toString(), 'mailto:crickbex@gmail.com?subject=CrickBex%20Feedback');
    });

    testWidgets('rewarded row: visible when ads ready; tap loads, rewards, grants no-ads', (tester) async {
      final backend = FakeAdsBackend()..rewardedGate = Completer<void>();
      AdsManager.instance.debugReset(backend: backend, ready: true);
      await pumpApp(tester, '/live/more');
      await tester.pump();
      expect(find.text('Watch ad – no ads for 30 min'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('more_rewarded')));
      await tester.pump();
      expect(find.text('Loading ad...'), findsOneWidget);
      backend.rewardedGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(backend.rewardeds.single.shows, 1);
      expect(AdsManager.instance.noAdsActive, isTrue);
      expect(find.text('Watch ad – no ads for 30 min'), findsOneWidget);
      await AdsManager.instance.noAds.clear();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('legal pages', () {
    testWidgets('Terms: shimmer then content', (tester) async {
      await pumpApp(tester, '/live/terms');
      expect(find.byKey(const ValueKey('legal_shimmer')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('legal_shimmer')), findsNothing);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('1. Acceptance of Terms'), findsOneWidget);
      expect(find.text('Last updated: February 2025'), findsOneWidget);
      await tester.drag(find.byKey(const ValueKey('legal_scroll')), const Offset(0, -2000));
      await tester.pump();
      expect(find.text('8. Contact'), findsOneWidget);
    });

    testWidgets('About: shimmer then logo + sections', (tester) async {
      await pumpApp(tester, '/live/about');
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Who We Are'), findsOneWidget);
      expect(find.text('• Player profiles and statistics'), findsOneWidget);
      expect(find.text('Live Scores & Updates'), findsOneWidget);
    });

    testWidgets('Privacy: native rendering of bundled policy + online link', (tester) async {
      await pumpApp(tester, '/live/privacy');
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Last updated: July 2026'), findsOneWidget);
      expect(find.text('1. Overview'), findsOneWidget);
      expect(find.textContaining('<'), findsNothing, reason: 'no raw HTML leaks');
      await tester.drag(find.byKey(const ValueKey('legal_scroll')), const Offset(0, -4000));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('privacy_open_online')));
      await tester.pump();
      expect(opened.single.toString(), 'https://crickbex.com/privacy-policy');
    });

    testWidgets('Contact: email and website links; failure shows a snackbar', (tester) async {
      await pumpApp(tester, '/live/contact');
      await tester.tap(find.byKey(const ValueKey('contact_email')));
      await tester.pump();
      expect(opened.last.toString(), 'mailto:crickbex@gmail.com');
      await tester.tap(find.byKey(const ValueKey('contact_web')));
      await tester.pump();
      expect(opened.last.toString(), 'https://crickbex.com/contact');

      openResult = false;
      await tester.tap(find.byKey(const ValueKey('contact_web')));
      await tester.pump();
      expect(find.text("Couldn't open the link"), findsOneWidget);
    });

    testWidgets('Contact: a throwing launcher never crashes', (tester) async {
      LinkLauncher.opener = (_) => throw StateError('no handler');
      await pumpApp(tester, '/live/contact');
      await tester.tap(find.byKey(const ValueKey('contact_email')));
      await tester.pump();
      expect(find.text("Couldn't open the link"), findsOneWidget);
    });

    testWidgets('App Info: version from package info, platform, copyright', (tester) async {
      await pumpApp(tester, '/live/app-info');
      await tester.pump();
      expect(find.text('CrickBex'), findsOneWidget);
      expect(find.text('1.2.3'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('© ${DateTime.now().year} CrickBex. All rights reserved.'), findsOneWidget);
    });

    testWidgets('App Info: empty version degrades to "-"', (tester) async {
      PackageInfo.setMockInitialValues(appName: '', packageName: '', version: '', buildNumber: '', buildSignature: '');
      await pumpApp(tester, '/live/app-info');
      await tester.pump();
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('pages fit on a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final p in ['/settings', '/live/more', '/live/terms', '/live/about', '/live/contact', '/live/app-info', '/live/privacy']) {
        await pumpApp(tester, p);
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull, reason: p);
      }
    });

    testWidgets('legal pages without a router: back uses Navigator', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ContactUsScreen())),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Contact Us'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings_back')));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });
  });
}
