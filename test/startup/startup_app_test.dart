// Full app (CrickbexApp + real router/Home) with the cold-start intro.
import 'package:crickbex/app.dart';
import 'package:crickbex/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

const _intro = ValueKey('startup_intro');

Future<FakeApi> _pumpApp(WidgetTester tester, {bool intro = true}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakeApi(defaultRoutes())..install();
  await tester.pumpWidget(CrickbexApp(requireEnv: false, showIntro: intro));
  return api;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

/// Steps fake time in 16 ms frames (like a real 60 Hz run).
Future<void> _run(WidgetTester tester, Duration d) async {
  final end = tester.binding.clock.now().add(d);
  while (tester.binding.clock.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

bool _homePainted(WidgetTester tester) =>
    find.byType(HomeScreen).hitTestable().evaluate().isNotEmpty;

void main() {
  testWidgets('cold start: intro over a loading Home, lands on Home ≤1.5 s', (
    tester,
  ) async {
    final api = await _pumpApp(tester);

    // Frame 0: intro on top, Home already mounted underneath (not painted).
    expect(find.byKey(_intro), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_homePainted(tester), isFalse);
    expect(find.byKey(const ValueKey('startup_onboarding')), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    // Home's data requests are already running while the intro plays.
    expect(api.count('/match/recent'), 1);
    expect(find.byKey(_intro), findsOneWidget);

    await _run(tester, const Duration(milliseconds: 1400));
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
    // Scores are there right away: no second fetch, no shimmer.
    expect(find.byKey(const ValueKey('home_shimmer')), findsNothing);
    expect(
      find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> &&
            RegExp(
              r'^home_(live_card|live_row|upcoming_card)_',
            ).hasMatch(k.value);
      }),
      findsWidgets,
      reason: 'match cards with data are on screen',
    );
    expect(api.count('/match/recent'), 1);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('tap anywhere skips straight to Home', (tester) async {
    await _pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_intro), findsOneWidget);
    await tester.tapAt(const Offset(195, 600));
    await tester.pump();
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
    await _unmount(tester);
  });

  testWidgets('showIntro false (default): Home straight away', (tester) async {
    await _pumpApp(tester, intro: false);
    await tester.pump();
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
    await _unmount(tester);
  });
}
