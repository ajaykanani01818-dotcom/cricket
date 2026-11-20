import 'package:crickbex/core/router/app_shell.dart';
import 'package:crickbex/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Router mirroring lib/core/router/app_router.dart (same five tab paths in
/// bar order, the Discover sections, and the per-tab search / match /
/// player / series-detail children) with stub pages except where a real
/// screen is passed. [realShell] wraps the tabs in the app's [AppShell]
/// (fixed orange bottom bar) instead of a bare Scaffold. Lets tab jumps and pushes be asserted through the
/// router location without compiling every feature.
GoRouter appTestRouter({
  Widget? home,
  Widget? live,
  String initialLocation = '/home',
  bool realShell = false,
}) {
  Widget stub(String t) => Scaffold(body: Center(child: Text('tab:$t')));
  List<RouteBase> children([List<RouteBase> extra = const []]) => [
    ...extra,
    GoRoute(path: 'search', builder: (_, _) => const SearchScreen()),
    GoRoute(
      path: 'match/:matchId',
      builder: (_, s) =>
          Scaffold(body: Text('match:${s.pathParameters['matchId']}')),
    ),
    GoRoute(
      path: 'player/:playerKey',
      builder: (_, s) =>
          Scaffold(body: Text('player:${s.pathParameters['playerKey']}')),
    ),
    GoRoute(
      path: 'series-detail/:seriesId',
      builder: (_, s) => Scaffold(
        body: Text('series:${s.pathParameters['seriesId']}:${s.extra}'),
      ),
    ),
  ];
  StatefulShellBranch branch(
    String path,
    Widget screen, [
    List<RouteBase> extra = const [],
  ]) => StatefulShellBranch(
    routes: [
      GoRoute(path: path, builder: (_, _) => screen, routes: children(extra)),
    ],
  );
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            realShell ? AppShell(shell: shell) : Scaffold(body: shell),
        branches: [
          branch('/home', home ?? stub('home')),
          branch('/live', live ?? stub('live')),
          branch('/matches', stub('matches')),
          branch('/discover', stub('discover'), [
            for (final s in ['series', 'rankings', 'players'])
              GoRoute(path: s, builder: (_, _) => stub('discover/$s')),
          ]),
          branch('/settings', stub('settings')),
        ],
      ),
    ],
  );
}
