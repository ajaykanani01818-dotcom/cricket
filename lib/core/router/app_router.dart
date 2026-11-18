import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/match_detail/match_detail_screen.dart';
import '../../features/matches/matches_screen.dart';
import '../../features/players/player_detail_screen.dart';
import '../../features/players/players_screen.dart';
import '../../features/rankings/ranking_screen.dart';
import '../../features/series/series_detail_screen.dart';
import '../../features/series/series_screen.dart';
import '../../features/settings/settings_pages.dart';
import '../api/json.dart';
import 'app_shell.dart';

/// Tabs (same order as RN): Live, Matches, Series, Ranking, Players, Settings.
const tabRoots = ['/live', '/matches', '/series', '/ranking', '/players', '/settings'];

/// Tabs are built on first visit. Preloading every tab (RN `lazy: false`) was
/// measured on a realme 9i: startup worst frame 78ms -> 124ms and no gain on
/// tab switching, so it is OFF. (Old note:) Build every tab up-front so the first visit to a tab
/// doesn't pay for building the whole screen. Toggle for perf experiments with
/// --dart-define=PRELOAD_TABS=false.
const bool kPreloadTabs = bool.fromEnvironment('PRELOAD_TABS', defaultValue: false);

List<RouteBase> _detailRoutes() => [
      GoRoute(
        path: 'match/:matchId',
        builder: (_, s) => MatchDetailScreen(matchId: Uri.decodeComponent(s.pathParameters['matchId']!)),
      ),
      GoRoute(
        path: 'player/:playerKey',
        builder: (_, s) => PlayerDetailScreen(
          playerKey: Uri.decodeComponent(s.pathParameters['playerKey']!),
          initialPlayer: s.extra is Map ? J.map(s.extra) : null,
        ),
      ),
      GoRoute(
        path: 'series-detail/:seriesId',
        builder: (_, s) => SeriesDetailScreen(
          seriesId: Uri.decodeComponent(s.pathParameters['seriesId']!),
          seriesName: s.extra is String ? s.extra as String : null,
        ),
      ),
    ];

List<RouteBase> _infoRoutes() => [
      GoRoute(path: 'more', builder: (_, _) => const MoreScreen()),
      GoRoute(path: 'privacy', builder: (_, _) => const PrivacyPolicyScreen()),
      GoRoute(path: 'terms', builder: (_, _) => const TermsScreen()),
      GoRoute(path: 'about', builder: (_, _) => const AboutUsScreen()),
      GoRoute(path: 'contact', builder: (_, _) => const ContactUsScreen()),
      GoRoute(path: 'app-info', builder: (_, _) => const AppInfoScreen()),
    ];

GoRouter buildRouter({String initialLocation = '/live'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', redirect: (_, _) => '/live'),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(preload: kPreloadTabs, routes: [
              GoRoute(path: '/live', builder: (_, _) => const HomeScreen(), routes: [..._detailRoutes(), ..._infoRoutes()]),
            ]),
            StatefulShellBranch(preload: kPreloadTabs, routes: [
              GoRoute(path: '/matches', builder: (_, _) => const MatchesScreen(), routes: _detailRoutes()),
            ]),
            StatefulShellBranch(preload: kPreloadTabs, routes: [
              GoRoute(path: '/series', builder: (_, _) => const SeriesScreen(), routes: _detailRoutes()),
            ]),
            StatefulShellBranch(preload: kPreloadTabs, routes: [
              GoRoute(path: '/ranking', builder: (_, _) => const RankingScreen(), routes: _detailRoutes()),
            ]),
            StatefulShellBranch(preload: kPreloadTabs, routes: [
              GoRoute(path: '/players', builder: (_, _) => const PlayersScreen(), routes: _detailRoutes()),
            ]),
            StatefulShellBranch(preload: kPreloadTabs, routes: [
              GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen(), routes: _infoRoutes()),
            ]),
          ],
        ),
      ],
      errorBuilder: (context, state) => Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
    );
