import 'package:crickbex/core/storage/prefs.dart';
import 'package:crickbex/features/review/review.dart';
import 'package:crickbex/features/startup/startup_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SplashScreen', () {
    testWidgets('branding + loader; onFinish fires exactly once after 1400ms', (tester) async {
      var finished = 0;
      await tester.pumpWidget(MaterialApp(home: SplashScreen(onFinish: () => finished++)));
      expect(find.text('Live Cricket Scores. Real Time.'), findsOneWidget);
      expect(find.byKey(const ValueKey('startup_splash_bar')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(finished, 0);
      final mid = tester.getSize(find.byKey(const ValueKey('startup_splash_bar'))).width;
      expect(mid, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 2));
      expect(finished, 1);
    });

    testWidgets('disposed early → onFinish never fires, no pending timers', (tester) async {
      var finished = 0;
      await tester.pumpWidget(MaterialApp(home: SplashScreen(onFinish: () => finished++)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 2));
      expect(finished, 0);
    });

    testWidgets('small screen renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SplashScreen(onFinish: () {})));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('OnboardingScreen', () {
    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('onboarding_next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('Next walks the 4 slides, then Get started completes once', (tester) async {
      var done = 0;
      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onComplete: () => done++)));
      expect(find.text('Live scores at your fingertips'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      await next(tester);
      expect(find.text('Matches & series'), findsOneWidget);
      await next(tester);
      expect(find.text('Rankings & players'), findsOneWidget);
      await next(tester);
      expect(find.text("You're all set"), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      // Double tap on Get started → onComplete only once.
      await tester.tap(find.byKey(const ValueKey('onboarding_next')));
      await tester.tap(find.byKey(const ValueKey('onboarding_next')));
      await tester.pump();
      expect(done, 1);
    });

    testWidgets('rapid Next taps advance only one slide (pagination lock)', (tester) async {
      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onComplete: () {})));
      await tester.tap(find.byKey(const ValueKey('onboarding_next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding_next')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final pv = tester.widget<PageView>(find.byKey(const ValueKey('onboarding_page_view')));
      expect(pv.controller!.page, 1);
    });

    testWidgets('swipe changes the active dot', (tester) async {
      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onComplete: () {})));
      // width includes the 4px side margins: active 24+8, inactive 8+8.
      expect(tester.getSize(find.byKey(const ValueKey('onboarding_dot_0'))).width, 32);
      await tester.fling(find.byKey(const ValueKey('onboarding_page_view')), const Offset(-500, 0), 1500);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(find.byKey(const ValueKey('onboarding_dot_1'))).width, 32);
      expect(tester.getSize(find.byKey(const ValueKey('onboarding_dot_0'))).width, 16);
    });

    for (final size in const [Size(320, 600), Size(430, 932)]) {
      testWidgets('layout fits at ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onComplete: () {})));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('onboarding config', () {
    tearDown(() => OnboardingConfig.alwaysShowOnboarding = false);

    test('first launch only (default)', () async {
      expect(await shouldShowOnboarding(), isTrue);
      await markOnboardingComplete();
      expect(await AppPrefs.hasSeenOnboarding(), isTrue);
      expect(await shouldShowOnboarding(), isFalse);
    });

    test('always show: shown every launch and not persisted', () async {
      OnboardingConfig.alwaysShowOnboarding = true;
      await markOnboardingComplete();
      expect(await AppPrefs.hasSeenOnboarding(), isFalse);
      expect(await shouldShowOnboarding(), isTrue);
    });

    test('null: never shown', () async {
      OnboardingConfig.alwaysShowOnboarding = null;
      expect(await shouldShowOnboarding(), isFalse);
    });

    test('setFromRemote only accepts bool or explicit null', () {
      OnboardingConfig.setFromRemote({'always_show_onboarding': 'yes'});
      expect(OnboardingConfig.alwaysShowOnboarding, isFalse);
      OnboardingConfig.setFromRemote({'other': true});
      expect(OnboardingConfig.alwaysShowOnboarding, isFalse);
      OnboardingConfig.setFromRemote({'always_show_onboarding': true});
      expect(OnboardingConfig.isAlwaysShow, isTrue);
      OnboardingConfig.setFromRemote({'always_show_onboarding': null});
      expect(OnboardingConfig.isDisabled, isTrue);
    });
  });

  group('version gate', () {
    test('compareSemver', () {
      expect(compareSemver('1.0.0', '1.0.0'), 0);
      expect(compareSemver('1.0', '1.0.0'), 0);
      expect(compareSemver('v1.2.3', '1.2.3'), 0);
      expect(compareSemver('1.2.3', '1.10.0'), -1);
      expect(compareSemver('2.0.0', '1.99.99'), 1);
      expect(compareSemver('1.0.0-beta', '1.0.1'), -1);
      expect(compareSemver('garbage', '0.0.0'), 0);
    });

    test('isUpdateRequired', () {
      expect(versionGateConfig, isNull, reason: 'inert, same as RN');
      expect(isUpdateRequired('1.0.0', null), isFalse);
      expect(isUpdateRequired('1.0.0', const VersionGateConfig(minimumAppVersion: '')), isFalse);
      expect(isUpdateRequired('1.0.0', const VersionGateConfig(minimumAppVersion: '1.0.1')), isTrue);
      expect(isUpdateRequired('1.2.0', const VersionGateConfig(minimumAppVersion: '1.0.1')), isFalse);
      expect(isUpdateRequired('', const VersionGateConfig(minimumAppVersion: '0.0.1')), isTrue);
    });

    testWidgets('inert config renders only the child and never reads the version', (tester) async {
      var reads = 0;
      await tester.pumpWidget(MaterialApp(
        home: VersionUpdateGate(installedVersion: () async {
          reads++;
          return '0.0.1';
        }, child: const Text('app')),
      ));
      await tester.pump();
      expect(find.text('app'), findsOneWidget);
      expect(find.byKey(const ValueKey('version_gate_card')), findsNothing);
      expect(reads, 0);
    });

    testWidgets('soft gate: Update opens store, Maybe later dismisses', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: VersionUpdateGate(
          config: const VersionGateConfig(minimumAppVersion: '2.0.0'),
          installedVersion: () async => '1.0.0',
          openStore: (u) async => opened.add(u),
          child: const Text('app'),
        ),
      ));
      await tester.pump();
      expect(find.text('New version ready'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version_gate_update')));
      await tester.pump();
      expect(opened.single, contains('com.crickbex.dark'));
      await tester.tap(find.byKey(const ValueKey('version_gate_later')));
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_card')), findsNothing);
    });

    testWidgets('force gate: no Maybe later, back is swallowed', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: VersionUpdateGate(
          config: const VersionGateConfig(minimumAppVersion: '2.0.0', forceUpdate: true),
          installedVersion: () async => '1.0.0',
          openStore: (_) async {},
          child: const Text('app'),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_later')), findsNothing);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_card')), findsOneWidget);
    });

    testWidgets('up-to-date install → no gate', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: VersionUpdateGate(
          config: const VersionGateConfig(minimumAppVersion: '1.0.0'),
          installedVersion: () async => '1.0.0',
          child: const Text('app'),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_card')), findsNothing);
    });
  });

  testWidgets('AppChrome provides ReviewScope to router pages', (tester) async {
    final c = ReviewController(openStoreListing: () async => true, exitApp: () {});
    ReviewController? seen;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppChrome(reviewController: c, child: child!),
      home: Builder(builder: (context) {
        seen = ReviewScope.maybeOf(context);
        return const Text('page');
      }),
    ));
    expect(find.text('page'), findsOneWidget);
    expect(seen, same(c));
    c.showRatingModal();
    await tester.pump();
    expect(find.byType(RatingModal), findsOneWidget);
  });
}
