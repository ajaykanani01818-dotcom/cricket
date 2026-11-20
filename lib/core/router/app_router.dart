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
import '../../features/discover/discover_screen.dart';
import '../../features/live/live_screen.dart';
// [B1 search] Search screen import (screen agent B1).
import '../../features/search/search_screen.dart';
import '../widgets/empty_state.dart';
import 'app_nav.dart';
import 'app_shell.dart';

/// Bottom-bar tabs, in bar order: Home, Live, Matches, Discover, Settings.
final tabRoots = [for (final t in AppTab.values) t.path];

/// Tabs are built on first visit (preloading every tab was measured slower
/// on a realme 9i). Toggle for perf experiments with
/// --dart-define=PRELOAD_TABS=true.
const bool kPreloadTabs = bool.fromEnvironment(
  'PRELOAD_TABS',
  defaultValue: false,
);

List<RouteBase> _detailRoutes() => [
  GoRoute(
    path: 'match/:matchId',
    builder: (_, s) => MatchDetailScreen(
      matchId: Uri.decodeComponent(s.pathParameters['matchId']!),
    ),
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

/// Every tab root gets the detail + info routes, so AppNav can push on the
/// current tab's stack.
List<RouteBase> _tabChildren([List<RouteBase> extra = const []]) => [
  ...extra,
  // [B1 search] Full-screen local search, pushed on the current tab
  // (AppNav.search). Begin/end of the screen agent B1 edit.
  GoRoute(path: 'search', builder: (_, _) => const SearchScreen()),
  ..._detailRoutes(),
  ..._infoRoutes(),
];

StatefulShellBranch _branch(
  String path,
  Widget Function() screen, [
  List<RouteBase> extra = const [],
]) => StatefulShellBranch(
  preload: kPreloadTabs,
  routes: [
    GoRoute(
      path: path,
      builder: (_, _) => screen(),
      routes: _tabChildren(extra),
    ),
  ],
);

GoRouter buildRouter({String initialLocation = '/home'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', redirect: (_, _) => AppTab.home.path),
    // Old tab paths (pre-rebuild deep links / web hashes).
    GoRoute(path: '/series', redirect: (_, _) => DiscoverSection.series.path),
    GoRoute(
      path: '/ranking',
      redirect: (_, _) => DiscoverSection.rankings.path,
    ),
    GoRoute(path: '/players', redirect: (_, _) => DiscoverSection.players.path),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        _branch(AppTab.home.path, () => const HomeScreen()),
        _branch(AppTab.live.path, () => const LiveScreen()),
        _branch(AppTab.matches.path, () => const MatchesScreen()),
        _branch(AppTab.discover.path, () => const DiscoverScreen(), [
          GoRoute(
            path: DiscoverSection.series.segment,
            builder: (_, _) => const SeriesScreen(),
          ),
          GoRoute(
            path: DiscoverSection.rankings.segment,
            builder: (_, _) => const RankingScreen(),
          ),
          GoRoute(
            path: DiscoverSection.players.segment,
            builder: (_, _) => const PlayersScreen(),
          ),
        ]),
        _branch(AppTab.settings.path, () => const SettingsScreen()),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: EmptyState(
      icon: Icons.link_off,
      title: 'This page does not exist',
      subtitle: 'The link may be out of date.',
      actionLabel: 'Go to Home',
      onAction: () => context.go(AppTab.home.path),
    ),
  ),
);
