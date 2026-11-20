import 'package:crickbex/core/brand/brand.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/features/startup/startup_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// StartupIntroHost / StartupIntro on their own (a stub "Home" underneath),
/// so these run even while other features don't compile. The full-app path
/// is in startup_app_test.dart.

const _intro = ValueKey('startup_intro');
const _home = ValueKey('stub_home');

/// Stands in for Home: records when it was mounted (= when its data
/// requests would start).
class _StubHome extends StatefulWidget {
  const _StubHome(this.onMount);
  final VoidCallback onMount;
  @override
  State<_StubHome> createState() => _StubHomeState();
}

class _StubHomeState extends State<_StubHome> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: _home, color: Colors.white);
}

Future<void> _pumpHost(
  WidgetTester tester, {
  VoidCallback? onHomeMount,
  Duration? freezeAt,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => StartupIntroHost(
        freezeAt: freezeAt,
        child: child ?? const SizedBox(),
      ),
      home: _StubHome(onHomeMount ?? () {}),
    ),
  );
}

/// Steps fake time in 16 ms frames (like a real 60 Hz run).
Future<void> _run(WidgetTester tester, Duration d) async {
  final end = tester.binding.clock.now().add(d);
  while (tester.binding.clock.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

bool _homePainted(WidgetTester tester) =>
    find.byKey(_home).hitTestable().evaluate().isNotEmpty;

Finder get _mark =>
    find.descendant(of: find.byKey(_intro), matching: find.byType(Image));

void main() {
  testWidgets('home mounts on frame 0, intro done within 1.5 s', (
    tester,
  ) async {
    var mounted = 0;
    await _pumpHost(tester, onHomeMount: () => mounted++);
    expect(mounted, 1, reason: 'Home (and its requests) start under the intro');
    expect(find.byKey(_intro), findsOneWidget);
    expect(_homePainted(tester), isFalse);
    await _run(tester, const Duration(milliseconds: 1500));
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
    expect(mounted, 1, reason: 'Home is never rebuilt from scratch');
    expect(tester.takeException(), isNull);
  });

  testWidgets('fail-safe: a stalled ticker still reveals Home at 1.55 s', (
    tester,
  ) async {
    await _pumpHost(tester);
    // One big jump (no intermediate frames): only the timer can finish it.
    await tester.pump(const Duration(milliseconds: 1560));
    await tester.pump();
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
  });

  testWidgets('tap anywhere skips', (tester) async {
    await _pumpHost(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
  });

  testWidgets('reduced motion: static logo, gone within 400 ms', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpHost(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text(Brand.tagline), findsOneWidget);
    final r0 = tester.getRect(_mark);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(_mark), r0, reason: 'no motion');
    await tester.pump(const Duration(milliseconds: 184));
    expect(find.byKey(_intro), findsNothing);
    expect(_homePainted(tester), isTrue);
  });

  testWidgets('accessibleNavigation takes the static path too', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpHost(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_intro), findsNothing);
  });

  testWidgets('missing assets: no exceptions, still finishes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = 0;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _FailingBundle(),
          child: MaterialApp(home: StartupIntro(onDone: () => done++)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _run(tester, const Duration(milliseconds: 1500));
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real assets decode and paint without errors', (tester) async {
    await tester.runAsync(() async {
      await _pumpHost(tester);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await _run(tester, const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    await _run(tester, const Duration(milliseconds: 700));
    expect(find.byKey(_intro), findsNothing);
  });

  testWidgets('frame sequence: frame 0 = native splash, then storyboard', (
    tester,
  ) async {
    // flutter_test runs as Android: the Android 12 splash geometry.
    const size = Size(390, 844);
    await _pumpHost(tester, size: size);
    final tagline = find.text(Brand.tagline);
    final log = <String>[];
    var elapsed = 0;
    Future<Rect> at(int ms) async {
      if (ms > elapsed) {
        await _run(tester, Duration(milliseconds: ms - elapsed));
      }
      elapsed = ms;
      final r = tester.getRect(_mark);
      log.add(
        '${ms.toString().padLeft(4)} ms: mark '
        '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)} '
        'centre (${r.center.dx.toStringAsFixed(1)}, '
        '${r.center.dy.toStringAsFixed(1)}) '
        'lettering=${tagline.evaluate().isNotEmpty} '
        'homePainted=${_homePainted(tester)}',
      );
      return r;
    }

    // 0 ms: mark fitted in 176 dp, centred (+2 dp x) = splash_icon.png.
    final r0 = await at(0);
    expect(r0.width, closeTo(176, 0.01));
    expect(r0.height, closeTo(176 / Brand.iconMarkAspect, 0.01));
    expect(r0.center.dx, closeTo(size.width / 2 + 2, 0.01));
    expect(r0.center.dy, closeTo(size.height / 2, 0.01));
    expect(find.text('Cric Ticker'), findsNothing);

    expect(await at(300), r0, reason: 'mark holds while the comet sweeps');
    final r850 = await at(850);
    expect(r850.width, greaterThan(176), reason: 'landing pulse');
    final r1100 = await at(1100);
    expect(r1100.width, closeTo(176, 0.01), reason: 'pulse settled');
    expect(r1100.center.dy, lessThan(r0.center.dy - 30), reason: 'rose');
    expect(find.text('Cric Ticker'), findsOneWidget);
    expect(tagline, findsOneWidget);
    await at(1450);
    expect(find.byKey(_intro), findsOneWidget, reason: 'exit fade running');
    await _run(tester, const Duration(milliseconds: 120));
    expect(find.byKey(_intro), findsNothing);
    // ignore: avoid_print
    print('Intro frame sequence (390x844, Android):\n  ${log.join('\n  ')}');
  });

  testWidgets('iOS geometry matches the 150 pt LaunchImage', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
        home: StartupIntro(onDone: () {}),
      ),
    );
    final r = tester.getRect(_markOf(find.byType(StartupIntro)));
    expect(r.width, closeTo(150, 0.01));
    expect(r.center, const Offset(195, 422));
    await _run(tester, const Duration(milliseconds: 1500));
  });

  testWidgets('freezeAt holds a frame (screenshot aid) and tap dismisses', (
    tester,
  ) async {
    await _pumpHost(tester, freezeAt: const Duration(milliseconds: 1000));
    await _run(tester, const Duration(milliseconds: 2000));
    expect(find.byKey(_intro), findsOneWidget);
    expect(find.text('Cric Ticker'), findsOneWidget);
    await tester.tapAt(const Offset(195, 400));
    await tester.pump();
    expect(find.byKey(_intro), findsNothing);
  });

  testWidgets('freezeAt in the exit fade reveals Home underneath', (
    tester,
  ) async {
    await _pumpHost(tester, freezeAt: const Duration(milliseconds: 1450));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(_intro), findsOneWidget);
    final vis = tester.widget<Visibility>(
      find
          .descendant(
            of: find.byType(StartupIntroHost),
            matching: find.byType(Visibility),
          )
          .first,
    );
    expect(vis.visible, isTrue);
  });

  testWidgets('wide screen (1440x900) lays out without overflow', (
    tester,
  ) async {
    await _pumpHost(tester, size: const Size(1440, 900));
    await _run(tester, const Duration(milliseconds: 1100));
    expect(tester.takeException(), isNull);
    final word = tester.getRect(find.text('Cric Ticker'));
    expect(word.center.dx, closeTo(720, 1));
    await _run(tester, const Duration(milliseconds: 400));
  });
}

Finder _markOf(Finder intro) =>
    find.descendant(of: intro, matching: find.byType(Image));

class _FailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => key.startsWith('assets/brand/')
      ? throw FlutterError('asset missing: $key')
      : rootBundle.load(key);
}
