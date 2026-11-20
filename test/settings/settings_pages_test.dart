import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:crickbex/core/brand/brand.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/features/ads/ads.dart';
import 'package:crickbex/features/review/review.dart';
import 'package:crickbex/features/settings/settings_pages.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

GoRouter _router(String initial, {Widget? settings}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/settings',
      builder: (_, _) => settings ?? const SettingsScreen(),
      routes: _info(),
    ),
    GoRoute(
      path: '/live',
      builder: (_, _) => const Scaffold(body: Text('home')),
      routes: _info(),
    ),
  ],
);

/// Every legacy brand string that must never reach the UI again.
final _legacy = RegExp(r'crick\s?bex', caseSensitive: false);

void main() {
  final opened = <Uri>[];
  late bool openResult;
  late ReviewController review;
  late int storeOpens;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeController.instance.debugReset();
    AppVersion.debugReset();
    PackageInfo.setMockInitialValues(
      appName: 'Cric Ticker',
      packageName: 'com.cricticker.app',
      version: '1.2.3',
      buildNumber: '7',
      buildSignature: '',
    );
    opened.clear();
    openResult = true;
    storeOpens = 0;
    LinkLauncher.opener = (uri) async {
      opened.add(uri);
      return openResult;
    };
    review = ReviewController(
      openStoreListing: () async {
        storeOpens++;
        return true;
      },
      requestReview: () async => true,
      exitApp: () {},
    );
    AdsManager.instance.debugReset();
  });

  tearDown(() {
    AdsManager.instance.debugReset();
    ThemeController.instance.debugReset();
  });

  Future<GoRouter> pumpApp(
    WidgetTester tester,
    String location, {
    Widget? settings,
  }) async {
    final router = _router(location, settings: settings);
    addTearDown(router.dispose);
    final c = ThemeController.instance;
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => MaterialApp.router(
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(brightness: Brightness.dark),
          themeMode: c.mode,
          themeAnimationDuration: Duration.zero,
          routerConfig: router,
          builder: (context, child) =>
              ReviewHost(controller: review, child: child!),
        ),
      ),
    );
    await tester.pump();
    return router;
  }

  Finder settingsScrollable() => find
      .descendant(
        of: find.byKey(const ValueKey('settings_list')),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: settingsScrollable());
    await tester.pump();
  }

  /// All visible text on screen, including rich text and selectable text.
  String allText(WidgetTester tester) {
    final b = StringBuffer();
    for (final w in tester.widgetList(find.byType(RichText))) {
      b.writeln((w as RichText).text.toPlainText());
    }
    for (final w in tester.widgetList(find.byType(EditableText))) {
      b.writeln((w as EditableText).controller.text);
    }
    return b.toString();
  }

  group('Settings: appearance', () {
    testWidgets('System / Light / Dark rows; System selected by default', (
      tester,
    ) async {
      await pumpApp(tester, '/settings');
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      for (final m in ['system', 'light', 'dark']) {
        expect(find.byKey(ValueKey('settings_theme_$m')), findsOneWidget);
      }
      final sem = tester.getSemantics(
        find.byKey(const ValueKey('settings_theme_system')),
      );
      expect(sem.flagsCollection.isChecked, CheckedState.isTrue);
    });

    testWidgets(
      'choosing Dark applies immediately and persists; Light switches back',
      (tester) async {
        await pumpApp(tester, '/settings');
        final c = ThemeController.instance;
        Color bg() => tester
            .widget<Scaffold>(find.byType(Scaffold).first)
            .backgroundColor!;
        expect(bg(), AppPalette.light.canvas);

        await tester.tap(find.byKey(const ValueKey('settings_theme_dark')));
        await tester.pump();
        expect(c.mode, ThemeMode.dark);
        expect(AppPalette.active, AppPalette.dark);
        expect(
          bg(),
          AppPalette.dark.canvas,
          reason: 'applied without a restart',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(ThemeController.prefsKey), 'dark');
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('settings_theme_dark')))
              .flagsCollection
              .isChecked,
          CheckedState.isTrue,
        );

        await tester.tap(find.byKey(const ValueKey('settings_theme_light')));
        await tester.pump();
        expect(c.mode, ThemeMode.light);
        expect(bg(), AppPalette.light.canvas);
        expect(prefs.getString(ThemeController.prefsKey), 'light');
      },
    );

    testWidgets('stored choice survives a restart (load)', (tester) async {
      SharedPreferences.setMockInitialValues({
        ThemeController.prefsKey: 'dark',
      });
      await ThemeController.instance.load();
      await pumpApp(tester, '/settings');
      expect(ThemeController.instance.mode, ThemeMode.dark);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('settings_theme_dark')))
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
    });

    testWidgets('switching theme keeps the navigation stack', (tester) async {
      final r = await pumpApp(tester, '/settings/privacy');
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      await ThemeController.instance.setMode(ThemeMode.dark);
      await tester.pump();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(r.canPop(), isTrue);
    });
  });

  group('Settings: support, rating, legal, about', () {
    testWidgets(
      'shows the support email as selectable text; Send email opens mailto with the feedback subject',
      (tester) async {
        await pumpApp(tester, '/settings');
        await scrollTo(
          tester,
          find.byKey(const ValueKey('settings_email_text')),
        );
        final sel = tester.widget<SelectableText>(
          find.byKey(const ValueKey('settings_email_text')),
        );
        expect(sel.data, 'ajaykanani01818@gmail.com');
        expect(Brand.supportEmail, 'ajaykanani01818@gmail.com');

        await tester.tap(find.byKey(const ValueKey('settings_email_send')));
        await tester.pump();
        expect(
          opened.single.toString(),
          'mailto:ajaykanani01818@gmail.com?subject=Cric%20Ticker%20Feedback',
        );

        await scrollTo(tester, find.byKey(const ValueKey('settings_feedback')));
        await tester.tap(find.byKey(const ValueKey('settings_feedback')));
        await tester.pump();
        expect(
          opened.last.toString(),
          'mailto:ajaykanani01818@gmail.com?subject=Cric%20Ticker%20Feedback',
        );
      },
    );

    testWidgets('Copy address puts the email on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpApp(tester, '/settings');
      await scrollTo(tester, find.byKey(const ValueKey('settings_email_copy')));
      await tester.tap(find.byKey(const ValueKey('settings_email_copy')));
      await tester.pump();
      expect(copied, Brand.supportEmail);
      expect(find.text('Email address copied'), findsOneWidget);
    });

    testWidgets('no email app → snackbar says how to proceed', (tester) async {
      openResult = false;
      await pumpApp(tester, '/settings');
      await scrollTo(tester, find.byKey(const ValueKey('settings_email_send')));
      await tester.tap(find.byKey(const ValueKey('settings_email_send')));
      await tester.pump();
      expect(
        find.text('No email app found. Copy the address instead.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Rate Cric Ticker opens the store listing directly (no star dialog)',
      (tester) async {
        await pumpApp(tester, '/settings');
        await scrollTo(tester, find.byKey(const ValueKey('settings_rate')));
        expect(find.text('Rate Cric Ticker'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('settings_rate')));
        await tester.pump();
        expect(storeOpens, 1);
        expect(find.byIcon(Icons.star_rounded), findsNothing);
        expect(find.textContaining('Enjoying'), findsNothing);
      },
    );

    test(
      'store listing URL is the Play listing (iOS: App Store search while the id is null)',
      () {
        expect(
          storeListingUri(platform: TargetPlatform.android).toString(),
          Brand.playStoreUrl,
        );
        expect(Brand.playStoreUrl, contains('id=com.cricticker.app'));
        expect(
          storeListingUri(platform: TargetPlatform.iOS).toString(),
          Brand.appStoreSearchUrl,
        );
      },
    );

    testWidgets(
      'legal rows navigate; about block shows name, version, description, coverage note',
      (tester) async {
        final r = await pumpApp(tester, '/settings');
        await scrollTo(
          tester,
          find.byKey(const ValueKey('settings_coverage_note')),
        );
        expect(find.text(Brand.appName), findsWidgets);
        expect(find.text('Version 1.2.3 (7)'), findsOneWidget);
        expect(find.text(kAppDescription), findsOneWidget);
        expect(
          find.text(
            'Coverage depends on the data available from our providers.',
          ),
          findsOneWidget,
        );

        await scrollTo(
          tester,
          find.byKey(const ValueKey('settings_item_privacy')),
        );
        await tester.tap(find.byKey(const ValueKey('settings_item_privacy')));
        await tester.pumpAndSettle();
        expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
        r.pop();
        await tester.pumpAndSettle();
        await scrollTo(
          tester,
          find.byKey(const ValueKey('settings_item_terms')),
        );
        await tester.tap(find.byKey(const ValueKey('settings_item_terms')));
        await tester.pumpAndSettle();
        expect(find.byType(TermsScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('screen_title_back')));
        await tester.pumpAndSettle();
        expect(r.canPop(), isFalse);
      },
    );

    testWidgets('double tap pushes a page only once', (tester) async {
      final r = await pumpApp(tester, '/settings');
      await scrollTo(
        tester,
        find.byKey(const ValueKey('settings_item_contact')),
      );
      await tester.tap(find.byKey(const ValueKey('settings_item_contact')));
      await tester.tap(
        find.byKey(const ValueKey('settings_item_contact')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ContactUsScreen), findsOneWidget);
      r.pop();
      await tester.pumpAndSettle();
      expect(r.canPop(), isFalse, reason: 'only one page was pushed');
    });

    testWidgets(
      'null Brand fields (phone, address, social) are hidden, no placeholders',
      (tester) async {
        expect(Brand.phone, isNull);
        expect(Brand.address, isNull);
        await pumpApp(tester, '/settings');
        for (final k in [
          'contact_phone',
          'contact_address',
          'contact_twitter',
          'contact_instagram',
          'contact_facebook',
        ]) {
          expect(
            find.byKey(ValueKey(k), skipOffstage: false),
            findsNothing,
            reason: k,
          );
        }
        for (final t in [
          'Phone',
          'Address',
          'Instagram',
          'Facebook',
          'X (Twitter)',
          'Not available',
          'Coming soon',
        ]) {
          expect(find.text(t, skipOffstage: false), findsNothing, reason: t);
        }
      },
    );

    testWidgets('non-null contact fields are shown', (tester) async {
      const info = ContactInfo(
        email: 'help@example.com',
        phone: '+91 98765 43210',
        address: '1 Test Road',
        instagramUrl: 'https://instagram.com/x',
      );
      await pumpApp(
        tester,
        '/settings',
        settings: const SettingsScreen(contact: info),
      );
      await scrollTo(tester, find.byKey(const ValueKey('contact_instagram')));
      expect(find.byKey(const ValueKey('contact_phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('contact_address')), findsOneWidget);
      expect(find.byKey(const ValueKey('contact_twitter')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('contact_phone')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('contact_phone')));
      await tester.pump();
      expect(opened.last.toString(), 'tel:+919876543210');
    });

    testWidgets('no legacy brand text anywhere in Settings', (tester) async {
      await pumpApp(tester, '/settings');
      final buf = StringBuffer();
      for (var i = 0; i < 8; i++) {
        buf.write(allText(tester));
        await tester.drag(settingsScrollable(), const Offset(0, -300));
        await tester.pump();
      }
      expect(_legacy.hasMatch(buf.toString()), isFalse);
      expect(buf.toString(), isNot(contains('crickbex@gmail.com')));
    });

    testWidgets('ads not ready → no banner widgets', (tester) async {
      await pumpApp(tester, '/settings');
      expect(find.byType(ScreenBannerAd), findsNothing);
    });
  });

  group('legal pages', () {
    Future<String> readWholePage(WidgetTester tester) async {
      final buf = StringBuffer();
      for (var i = 0; i < 30; i++) {
        buf.write(allText(tester));
        await tester.drag(
          find.byKey(const ValueKey('legal_scroll')),
          const Offset(0, -400),
        );
        await tester.pump();
      }
      return buf.toString();
    }

    testWidgets('Privacy policy shows the hosted wording, links, and Open on web', (
      tester,
    ) async {
      await pumpApp(tester, '/live/privacy');
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Effective 18 November 2026'), findsOneWidget);
      final text = await readWholePage(tester);
      for (final s in [
        'You do not need an account. We never ask for your name, phone number, email address or location.',
        'We do not sell your personal information.',
        'The app may display ads served by Google AdMob.',
        'Cric Ticker is a general-audience sports app and is not directed at children under 13.',
        'Questions or requests about privacy: ajaykanani01818@gmail.com',
      ]) {
        expect(text, contains(s));
      }
      expect(text, isNot(contains('<')), reason: 'no raw HTML leaks');
      expect(_legacy.hasMatch(text), isFalse);
      await tester.tap(find.byKey(const ValueKey('privacy_open_online')));
      await tester.pump();
      expect(opened.last.toString(), Brand.privacyUrl);
    });

    testWidgets('Terms of use shows the hosted wording and Open on web', (
      tester,
    ) async {
      await pumpApp(tester, '/live/terms');
      expect(find.text('Terms of use'), findsOneWidget);
      final text = await readWholePage(tester);
      for (final s in [
        'These terms apply when you use the Cric Ticker app or this website.',
        'Cricket data comes from third-party sources and may be delayed, incomplete or occasionally wrong.',
        'Cric Ticker is for information and entertainment only.',
        'It is not affiliated with, endorsed by or sponsored by the ICC',
        'Questions about these terms: ajaykanani01818@gmail.com',
      ]) {
        expect(text, contains(s));
      }
      await tester.tap(find.byKey(const ValueKey('terms_open_online')));
      await tester.pump();
      expect(opened.last.toString(), Brand.termsUrl);
    });

    testWidgets(
      'links inside the documents: sibling page in-app, mailto outside',
      (tester) async {
        await pumpApp(tester, '/live/terms');
        VoidCallback? tapOf(String sentence, String linkText) {
          for (final w in tester.widgetList<RichText>(
            find.byType(RichText, skipOffstage: false),
          )) {
            if (!w.text.toPlainText().contains(sentence)) continue;
            VoidCallback? found;
            w.text.visitChildren((span) {
              if (span is TextSpan &&
                  span.text == linkText &&
                  span.recognizer is TapGestureRecognizer) {
                found = (span.recognizer! as TapGestureRecognizer).onTap;
                return false;
              }
              return true;
            });
            return found;
          }
          return null;
        }

        final mail = tapOf(
          'Questions about these terms',
          'ajaykanani01818@gmail.com',
        );
        expect(mail, isNotNull);
        mail!();
        await tester.pump();
        expect(opened.last.toString(), 'mailto:ajaykanani01818@gmail.com');

        final privacy = tapOf(
          'How we handle information is described in our',
          'privacy policy',
        );
        expect(privacy, isNotNull);
        privacy!();
        await tester.pumpAndSettle();
        expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
        expect(
          opened.where((u) => u.toString().contains('privacy-policy')),
          isEmpty,
          reason: 'opened in the app',
        );
      },
    );

    testWidgets('Help and support: email, FAQs, support page link', (
      tester,
    ) async {
      await pumpApp(tester, '/live/contact');
      expect(find.text('Help and support'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('contact_email_text')),
            )
            .data,
        Brand.supportEmail,
      );
      await tester.tap(find.byKey(const ValueKey('contact_email_send')));
      await tester.pump();
      expect(
        opened.last.toString(),
        'mailto:ajaykanani01818@gmail.com?subject=Cric%20Ticker%20Feedback',
      );
      final text = await readWholePage(tester);
      expect(
        text,
        contains('Coverage depends on the data available from our providers.'),
      );
      expect(
        text,
        contains('Open Settings in the app and choose Light, Dark or System.'),
      );
      await tester.tap(find.byKey(const ValueKey('contact_web')));
      await tester.pump();
      expect(opened.last.toString(), Brand.supportUrl);
    });

    testWidgets('a throwing launcher never crashes', (tester) async {
      LinkLauncher.opener = (_) => throw StateError('no handler');
      await pumpApp(tester, '/live/contact');
      await tester.tap(find.byKey(const ValueKey('contact_email_send')));
      await tester.pump();
      expect(
        find.text('No email app found. Copy the address instead.'),
        findsOneWidget,
      );
    });

    testWidgets('About: brand, version, coverage, website', (tester) async {
      await pumpApp(tester, '/live/about');
      await tester.pump();
      expect(find.text('About Cric Ticker'), findsOneWidget);
      expect(find.text(Brand.tagline), findsOneWidget);
      expect(find.text('Version 1.2.3 (7)'), findsOneWidget);
      final text = await readWholePage(tester);
      expect(
        text,
        contains('Coverage depends on the data available from our providers.'),
      );
      await tester.tap(find.byKey(const ValueKey('about_website')));
      await tester.pump();
      expect(opened.last.toString(), Brand.websiteUrl);
    });

    testWidgets('App info: name, version, platform; empty version hidden', (
      tester,
    ) async {
      await pumpApp(tester, '/live/app-info');
      await tester.pump();
      expect(find.text('Cric Ticker'), findsOneWidget);
      expect(find.text('1.2.3 (7)'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('© ${DateTime.now().year} Cric Ticker'), findsOneWidget);
    });

    testWidgets('App info: unknown version shows no placeholder', (
      tester,
    ) async {
      AppVersion.debugReset();
      PackageInfo.setMockInitialValues(
        appName: '',
        packageName: '',
        version: '',
        buildNumber: '',
        buildSignature: '',
      );
      await pumpApp(tester, '/live/app-info');
      await tester.pump();
      expect(find.byKey(const ValueKey('app_version')), findsNothing);
      expect(find.text('-'), findsNothing);
    });

    testWidgets('pages without a router: back uses Navigator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ContactUsScreen(),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Help and support'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('screen_title_back')));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('MoreScreen (legacy route)', () {
    testWidgets(
      'settings list, back, no rewarded row while ads are not ready',
      (tester) async {
        final r = await pumpApp(tester, '/live/more');
        expect(find.text('More'), findsOneWidget);
        expect(find.byKey(const ValueKey('more_list')), findsOneWidget);
        expect(find.byKey(const ValueKey('more_rewarded')), findsNothing);
        expect(r.canPop(), isTrue);
      },
    );

    testWidgets(
      'rewarded row: visible when ads ready; tap rewards and grants no-ads',
      (tester) async {
        final backend = FakeAdsBackend()..rewardedGate = Completer<void>();
        AdsManager.instance.debugReset(backend: backend, ready: true);
        await pumpApp(tester, '/live/more');
        await tester.pump();
        expect(find.byKey(const ValueKey('more_rewarded')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('more_rewarded')));
        await tester.pump();
        expect(find.text('Loading ad…'), findsOneWidget);
        backend.rewardedGate!.complete();
        await tester.pump();
        await tester.pump();
        expect(backend.rewardeds.single.shows, 1);
        expect(AdsManager.instance.noAdsActive, isTrue);
        await AdsManager.instance.noAds.clear();
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
