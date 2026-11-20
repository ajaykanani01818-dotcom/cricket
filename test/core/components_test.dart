import 'package:crickbex/core/motion/motion.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/theme/theme_controller.dart';
import 'package:crickbex/core/utils/match_transform.dart';
import 'package:crickbex/core/widgets/app_bottom_bar.dart';
import 'package:crickbex/core/widgets/cards.dart';
import 'package:crickbex/core/widgets/empty_state.dart';
import 'package:crickbex/core/widgets/live_pill.dart';
import 'package:crickbex/core/widgets/net_image.dart';
import 'package:crickbex/core/widgets/pressable.dart';
import 'package:crickbex/core/widgets/score_text.dart';
import 'package:crickbex/core/widgets/seam_strip.dart';
import 'package:crickbex/core/widgets/skeletons.dart';
import 'package:crickbex/core/widgets/titles.dart';
import 'package:crickbex/features/common/live_match_card.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/discover/discover_screen.dart';
import 'package:crickbex/features/live/live_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

MatchSummary _live() => parseMatchList([liveMatchJson()]).single;

Widget _app(Widget child, Brightness b) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, c) => PaletteSync(child: c!),
  home: Scaffold(body: child),
);

Widget _catalogue() => ListView(
  children: [
    const AppTopBar(),
    AppTopBar(
      title: 'A very long screen title that has to ellipsize',
      onBack: () {},
      onSearch: () {},
      onMorePress: () {},
    ),
    ScreenTitle(
      title: 'Rankings and records for every format',
      onSearch: () {},
      rightIcon: Icons.tune,
      onRightPress: () {},
    ),
    SectionHeader(
      title: 'Live matches from every series in the world right now',
      showLiveDot: true,
      onActionPress: () {},
    ),
    SectionHeader(
      title: 'Starting soon',
      overline: 'Next 24 hours',
      onActionPress: () {},
      actionLabel: 'Full schedule',
    ),
    const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusChip(kind: StatusKind.live),
        StatusChip(kind: StatusKind.completed),
        StatusChip(kind: StatusKind.upcoming),
        StatusChip(kind: StatusKind.cancelled),
        FormatChip('T20'),
        LivePill(filled: true),
      ],
    ),
    const TeamLogo(url: null, name: 'Sri Lanka'),
    const ScoreText('245/6 (48.2)'),
    LiveMatchCard(match: _live(), onTap: () {}, fullWidth: true),
    LiveMatchCard(match: _live(), onTap: () {}),
    SeamStrip.labels(
      const ['0', '1', '4', '6', 'W', '1NB'],
      overLabel: 'Ov 61',
      summary: '12 runs',
    ),
    const SkeletonList(cards: 1, rows: 2),
    const EmptyState(
      title: 'No matches are live right now',
      subtitle: 'Live scores show up here the moment a match starts.',
      actionLabel: 'See upcoming matches',
      onAction: _noop,
    ),
    ErrorRetry(message: 'The server did not answer in time.', onRetry: () {}),
    AppBottomBar(
      items: const [
        AppBottomBarItem(icon: Icons.home, label: 'Home', keyName: 'home'),
        AppBottomBarItem(icon: Icons.sensors, label: 'Live', keyName: 'live'),
        AppBottomBarItem(
          icon: Icons.sports_cricket,
          label: 'Matches',
          keyName: 'matches',
        ),
        AppBottomBarItem(
          icon: Icons.explore,
          label: 'Discover',
          keyName: 'discover',
        ),
        AppBottomBarItem(
          icon: Icons.settings,
          label: 'Settings',
          keyName: 'settings',
        ),
      ],
      currentIndex: 3,
      onTap: (_) {},
    ),
  ],
);

void _noop() {}

void main() {
  setUp(() => ThemeController.instance.debugReset());

  for (final b in Brightness.values) {
    for (final w in [320.0, 390.0]) {
      testWidgets(
        'component catalogue: no overflow at ${w.toInt()} px × text 2.0 (${b.name})',
        (tester) async {
          tester.view.physicalSize = Size(w, 2400);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(_app(_catalogue(), b));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'LivePill: every dot shares ONE ticker; static with reduced motion; stops when unmounted',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(children: [LivePill(), LivePill(), LiveDot()]),
          Brightness.light,
        ),
      );
      expect(SharedPulse.instance.isTicking, isTrue);
      expect(find.text('Live'), findsNWidgets(2), reason: 'never colour-only');
      await tester.pumpWidget(const SizedBox());
      expect(SharedPulse.instance.isTicking, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const LivePill(),
          ),
        ),
      );
      expect(SharedPulse.instance.isTicking, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ScoreText: no roll on first build, rolls only changed digits, instant with reduced motion',
    (tester) async {
      await tester.pumpWidget(_app(const ScoreText('135/4'), Brightness.light));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('135/4'), findsOneWidget);
      await tester.pumpWidget(_app(const ScoreText('139/4'), Brightness.light));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isTrue);
      expect(
        find.text('9'),
        findsOneWidget,
        reason: 'the changed digit rolls in',
      );
      expect(
        find.text('/'),
        findsOneWidget,
        reason: 'unchanged characters stay put',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('139/4'), findsOneWidget, reason: 'one Text at rest');

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const ScoreText('139/4'),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const ScoreText('140/4'),
          ),
        ),
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('140/4'), findsOneWidget);
    },
  );

  testWidgets('Pressable: scales to 0.98 with a brandTint wash while pressed', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: Pressable(
            onTap: () => taps++,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
        Brightness.light,
      ),
    );
    final g = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.98,
    );
    final wash = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(Pressable),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (wash.decoration as BoxDecoration).color,
      AppPalette.light.brandTint,
    );
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('ErrorRetry says what happened and how to fix it', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      _app(
        ErrorRetry(message: 'Boom', onRetry: () => retried++),
        Brightness.light,
      ),
    );
    expect(find.text("Scores didn't load"), findsOneWidget);
    expect(find.text('Boom'), findsOneWidget);
    expect(find.text('Check your connection, then try again.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    expect(retried, 1);
  });

  test('initialsOf', () {
    expect(initialsOf('Sri Lanka'), 'SL');
    expect(initialsOf('PAK'), 'PA');
    expect(initialsOf('  '), '?');
    expect(initialsOf(null), '?');
  });

  group('Live screen', () {
    GoRouter router(Widget home) => GoRouter(
      initialLocation: '/live',
      routes: [
        GoRoute(
          path: '/live',
          builder: (_, _) => Scaffold(body: home),
          routes: [
            GoRoute(
              path: 'match/:id',
              builder: (_, s) => Text('match:${s.pathParameters['id']}'),
            ),
          ],
        ),
        GoRoute(path: '/matches', builder: (_, _) => const Text('matches tab')),
      ],
    );

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets(
      'groups live matches by series; tap opens the match on the Live stack',
      (tester) async {
        FakeApi({
          '/match/live': FakeApi.ok(
            body([
              liveMatchJson(key: 'L1', series: 'Series A'),
              liveMatchJson(key: 'L2', series: 'Series B'),
              liveMatchJson(key: 'L3', series: 'Series A'),
            ]),
          ),
        }).install();
        final r = router(const LiveScreen());
        await tester.pumpWidget(
          MaterialApp.router(theme: buildAppTheme(), routerConfig: r),
        );
        expect(find.byKey(const ValueKey('skeleton_list')), findsOneWidget);
        await settle(tester);
        expect(find.text('Series A'), findsOneWidget);
        expect(find.text('Series B'), findsOneWidget);
        expect(find.text('3 live'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('live_match_L1')));
        await settle(tester);
        expect(r.state.uri.path, '/live/match/L1');
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'empty → explains and links to Matches; error → Try again recovers',
      (tester) async {
        var fail = true;
        FakeApi({
          '/match/live': (req) =>
              fail ? FakeApi.status(500)(req) : FakeApi.ok(body(const []))(req),
        }).install();
        final r = router(const LiveScreen());
        await tester.pumpWidget(
          MaterialApp.router(theme: buildAppTheme(), routerConfig: r),
        );
        await settle(tester);
        expect(find.byKey(const ValueKey('live_error')), findsOneWidget);
        fail = false;
        await tester.tap(find.byKey(const ValueKey('empty_state_action')));
        await settle(tester);
        expect(find.byKey(const ValueKey('live_empty')), findsOneWidget);
        expect(find.text('No matches are live right now'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    test('groupBySeries keeps first-seen order', () {
      final ms = parseMatchList([
        liveMatchJson(key: 'a', series: 'X'),
        liveMatchJson(key: 'b', series: 'Y'),
        liveMatchJson(key: 'c', series: 'X'),
      ]);
      final g = groupBySeries(ms);
      expect(g.map((e) => e.$1), ['X', 'Y']);
      expect(g.first.$2.map((m) => m.id), ['a', 'c']);
    });
  });

  testWidgets('Discover hub lists Series, Rankings, Players', (tester) async {
    final r = GoRouter(
      initialLocation: '/discover',
      routes: [
        GoRoute(
          path: '/discover',
          builder: (_, _) => const Scaffold(body: DiscoverScreen()),
          routes: [
            GoRoute(
              path: 'series',
              builder: (_, _) => const Text('series list'),
            ),
            GoRoute(
              path: 'rankings',
              builder: (_, _) => const Text('rankings'),
            ),
            GoRoute(path: 'players', builder: (_, _) => const Text('players')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: buildAppTheme(), routerConfig: r),
    );
    for (final s in ['series', 'rankings', 'players']) {
      expect(find.byKey(ValueKey('discover_$s')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('discover_players')));
    await tester.pumpAndSettle();
    expect(r.state.uri.path, '/discover/players');
  });
}
