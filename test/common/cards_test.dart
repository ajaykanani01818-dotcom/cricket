import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/utils/fixture_status.dart';
import 'package:crickbex/core/utils/match_transform.dart';
import 'package:crickbex/features/common/countdown_timer.dart';
import 'package:crickbex/features/common/favorites.dart';
import 'package:crickbex/features/common/hero_banner.dart';
import 'package:crickbex/features/common/live_match_card.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/common/popular_series.dart';
import 'package:crickbex/features/common/upcoming_match_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers.dart';

Widget _wrap(Widget child, {double textScale = 1}) => MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 900), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: Center(child: child))),
      ),
    );

MatchSummary _match(JsonMap m) => parseMatchList([m]).single;

void main() {
  final fixedNow = DateTime.utc(2026, 11, 18, 1, 0);
  setUp(() => MinuteClock.nowFn = () => fixedNow);
  tearDown(() => MinuteClock.nowFn = DateTime.now);

  group('LiveMatchCard', () {
    testWidgets('live match: blue card, LIVE badge, chase line, scores', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(LiveMatchCard(match: _match(liveMatchJson()), onTap: () => taps++)));
      expect(find.byKey(const ValueKey('common_live_badge')), findsOneWidget);
      expect(find.text('UAE Bulls need 87 runs in 35 balls'), findsOneWidget);
      expect(find.text('45/2 (4.1)'), findsOneWidget);
      expect(find.text('131/1 (10.0)'), findsOneWidget);
      expect(find.text('T10'), findsOneWidget);
      await tester.tap(find.byType(LiveMatchCard));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
    });

    testWidgets('completed match: no LIVE badge, result line', (tester) async {
      final m = parseMatchList(fixtureJson('match_recent')['data']).first;
      await tester.pumpWidget(_wrap(LiveMatchCard(match: m, onTap: () {})));
      expect(find.byKey(const ValueKey('common_live_badge')), findsNothing);
      expect(find.text('UAE Bulls won by 6 wickets'), findsOneWidget);
    });

    testWidgets('missing fields degrade (no logos, names, scores) without overflow, also at 2x text', (tester) async {
      final m = _match({'status': 'LIVE', 'teams': {}});
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(_wrap(LiveMatchCard(match: m, onTap: () {}), textScale: scale));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('—'), findsNWidgets(2));
        expect(find.text('?'), findsNWidgets(2));
      }
      await tester.pumpWidget(_wrap(LiveMatchCard(match: m, onTap: () {}, fullWidth: true, compact: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('very long names ellipsize instead of overflowing', (tester) async {
      final j = liveMatchJson();
      J.map(J.at(j, 'teams.t1'))['name'] = 'A' * 120;
      j['seriesName'] = 'Series ' * 40;
      await tester.pumpWidget(_wrap(LiveMatchCard(match: _match(j), onTap: () {})));
      expect(tester.takeException(), isNull);
    });
  });

  group('UpcomingMatchCard', () {
    testWidgets('upcoming: meta pills, venue, teams and countdown', (tester) async {
      final m = parseMatchList(fixtureJson('match_upcoming')['data']).first; // starts 03:30Z
      await tester.pumpWidget(_wrap(UpcomingMatchCard(match: m, onTap: () {})));
      expect(find.text('STARTS IN'), findsOneWidget);
      expect(find.text('2h 30m'), findsOneWidget);
      expect(find.text('VS'), findsOneWidget);
      expect(find.text(m.series.toUpperCase()), findsOneWidget);

      // The shared minute clock drives the countdown.
      MinuteClock.nowFn = () => fixedNow.add(const Duration(minutes: 31));
      MinuteClock.instance.debugTick();
      await tester.pump();
      expect(find.text('1h 59m'), findsOneWidget);

      // After start time the countdown disappears.
      MinuteClock.nowFn = () => fixedNow.add(const Duration(hours: 3));
      MinuteClock.instance.debugTick();
      await tester.pump();
      expect(find.text('STARTS IN'), findsNothing);
    });

    testWidgets('completed: result pill + result row; live match shows LIVE pill', (tester) async {
      final done = parseMatchList(fixtureJson('match_completed')['data']).first;
      await tester.pumpWidget(_wrap(UpcomingMatchCard(match: done, variant: UpcomingCardVariant.completed)));
      expect(find.byKey(const ValueKey('common_result_pill')), findsOneWidget);
      expect(find.byKey(const ValueKey('common_result_row')), findsOneWidget);
      expect(find.text('STARTS IN'), findsNothing);

      await tester.pumpWidget(_wrap(UpcomingMatchCard(match: _match(liveMatchJson()))));
      expect(find.byKey(const ValueKey('common_upcoming_live_pill')), findsOneWidget);
    });

    testWidgets('cancelled + series-detail layout options', (tester) async {
      const m = MatchSummary(
        id: 'x',
        team1: 'India',
        team2: 'Australia',
        status: 'Match abandoned due to rain',
        venue: '',
        date: '',
        isLive: false,
        series: 'S',
        fixtureCardKind: FixtureCardKind.abandoned,
      );
      await tester.pumpWidget(_wrap(const UpcomingMatchCard(match: m, variant: UpcomingCardVariant.cancelled)));
      expect(find.text('Abandoned'), findsOneWidget);
      expect(find.text('Match abandoned due to rain'), findsOneWidget);

      await tester.pumpWidget(_wrap(const UpcomingMatchCard(
        match: m,
        variant: UpcomingCardVariant.cancelled,
        seriesDetailLayout: true,
        listMatchNumber: 22,
        seriesDetailStatusChip: SeriesStatusChip('Cancelled', SeriesStatusChipVariant.cancelled),
      )));
      expect(find.text('22nd match'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('S'), findsNothing, reason: 'series line hidden in series-detail layout');
    });

    testWidgets('missing data does not crash', (tester) async {
      await tester.pumpWidget(_wrap(UpcomingMatchCard(match: _match({}), onTap: () {})));
      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsNWidgets(2));
    });
  });

  testWidgets('CountdownTimer shows only within 24h', (tester) async {
    await tester.pumpWidget(_wrap(CountdownTimer(targetDate: fixedNow.add(const Duration(hours: 2, minutes: 5)).toIso8601String())));
    expect(find.text('Starts in 2h 5m'), findsOneWidget);
    await tester.pumpWidget(_wrap(CountdownTimer(targetDate: fixedNow.add(const Duration(days: 2)).toIso8601String())));
    expect(find.textContaining('Starts in'), findsNothing);
    await tester.pumpWidget(_wrap(const CountdownTimer(targetDate: 'garbage')));
    expect(find.textContaining('Starts in'), findsNothing);
  });

  testWidgets('FavoriteButton toggles', (tester) async {
    var fav = false;
    await tester.pumpWidget(_wrap(StatefulBuilder(
      builder: (context, setState) => FavoriteButton(isFavorite: fav, onToggle: () => setState(() => fav = !fav)),
    )));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byType(FavoriteButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  group('PopularSeriesQuickAction', () {
    testWidgets('lists ongoing series, navigates to series detail, auto-collapses', (tester) async {
      FakeApi({
        '/series': (req) => req.url.queryParameters['status'] == 'ONGOING'
            ? FakeApi.ok(body([
                {'name': 'Big Bash League 2026-27', 'sb_series_key': 'BBL'},
              ]))(req)
            : FakeApi.ok(body([]))(req),
        '/series/BBL': FakeApi.fixture('series_fixtures'),
      }).install();
      final router = GoRouter(initialLocation: '/live', routes: [
        GoRoute(
          path: '/live',
          builder: (_, _) => const Scaffold(body: Stack(children: [PopularSeriesQuickAction(bottomOffset: 20)])),
          routes: [GoRoute(path: 'series-detail/:id', builder: (_, s) => Text('series:${s.pathParameters['id']}:${s.extra}'))],
        ),
      ]);
      await tester.pumpWidget(routerApp(router));
      await tester.pump();
      await tester.pump();
      expect(find.text('BBL2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('common_quick_action_BBL')));
      await settle(tester);
      expect(location(router), '/live/series-detail/BBL');
      expect(find.text('series:BBL:Big Bash League 2026-27'), findsOneWidget);
      router.pop();
      await tester.pump(const Duration(seconds: 1));
      // 5s of inactivity → collapsed.
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('common_quick_action_open')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('common_quick_action_open')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('common_quick_action_collapse')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('HeroBanner', () {
    testWidgets('renders slides, arrows and auto-advance; empty shows brand slide', (tester) async {
      final recent = parseMatchList(fixtureJson('match_recent')['data']).take(1).toList();
      final up = parseMatchList(fixtureJson('match_upcoming')['data']);
      HeroSlide? tapped;
      await tester.pumpWidget(_wrap(HeroBanner(
        slides: buildHeroSlides([_match(liveMatchJson()), ...recent], up, const [HeroPlayer(format: 'ODI', playerKey: 'p', name: 'Shubman Gill', rating: 801, rank: 1)]),
        onSlideTap: (s) => tapped = s,
      )));
      await tester.pump();
      expect(find.text('Live Now'), findsOneWidget);
      await tester.tap(find.text('Live Now'));
      expect(tapped?.type, HeroSlideType.live);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Result'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('common_hero_prev')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Live Now'), findsOneWidget);

      await tester.pumpWidget(_wrap(const HeroBanner(slides: [])));
      expect(find.text('Your premium cricket destination'), findsOneWidget);
    });
  });
}
