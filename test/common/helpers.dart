import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/sbx1_server.dart';

String fixtureText(String name) => File('test/fixtures/$name.json').readAsStringSync();
JsonMap fixtureJson(String name) => J.map(jsonDecode(fixtureText(name)));

/// A LIVE match crafted from the first /match/recent item: chasing side t1,
/// partial scores, no result yet.
JsonMap liveMatchJson({String key = 'LIVE01', String series = 'Abu Dhabi T10 League 2026'}) {
  final m = J.map(jsonDecode(jsonEncode(J.maps(fixtureJson('match_recent')['data']).first)));
  m
    ..remove('result')
    ..['sb_match_key'] = key
    ..['status'] = 'LIVE'
    ..['seriesName'] = series
    ..['inningsOrder'] = ['t2_1', 't1_1']
    ..['currentInning'] = 't1_1';
  J.map(J.at(m, 'teams.t1'))['score'] = '45/2 (4.1)';
  J.map(J.at(m, 'teams.t2'))['score'] = '131/1 (10.0)';
  return m;
}

String body(Object data, {Map<String, Object?>? pageInfo, String message = 'ok'}) =>
    jsonEncode({'message': message, 'data': data, 'pageInfo': ?pageInfo});

typedef Responder = FutureOr<http.Response> Function(http.Request req);

/// Routes MockClient requests by path; counts calls per path.
class FakeApi {
  FakeApi([Map<String, Responder>? routes]) : routes = {...?routes};
  final Map<String, Responder> routes;
  final Map<String, int> calls = {};
  final List<Uri> log = [];

  int count(String path) => calls[path] ?? 0;

  late final MockClient client = MockClient((req) async {
    final path = req.url.path;
    calls[path] = count(path) + 1;
    log.add(req.url);
    final r = routes[path];
    if (r == null) return http.Response(jsonEncode({'message': 'not found'}), 404);
    return await r(req);
  });

  void install() {
    final api = testClient(client, baseUrl: 'http://test', retryDelays: const []);
    MatchService.instance = MatchService(api);
    RankingService.instance = RankingService(api);
    PlayerService.instance = PlayerService(api);
  }

  static Responder ok(String text) => (_) => http.Response.bytes(utf8.encode(text), 200, headers: {'content-type': 'application/json'});
  static Responder fixture(String name) => ok(fixtureText(name));
  static Responder status(int code, [String message = 'Server exploded']) =>
      (_) => http.Response(jsonEncode({'message': message}), code);

  /// Response held until [gate] completes.
  static Responder gated(Completer<void> gate, Responder inner) => (req) async {
        await gate.future;
        return inner(req);
      };
}

/// Default routes for the Home + Matches screens.
Map<String, Responder> defaultRoutes() => {
      '/match/recent': FakeApi.fixture('match_recent'),
      '/match/live': FakeApi.fixture('match_live_list'),
      '/match/upcoming': FakeApi.fixture('match_upcoming'),
      '/match/completed': FakeApi.fixture('match_completed'),
      '/series/upcoming': FakeApi.fixture('series_upcoming'),
      '/rank/player': FakeApi.fixture('rank_player'),
    };

/// Minimal app shell mirroring lib/core/router/app_router.dart (same paths,
/// same tab order) with stub detail pages, so navigation can be asserted
/// through the router location.
GoRouter testRouter({required Widget home, required Widget matches, String initialLocation = '/live'}) {
  List<RouteBase> details() => [
        GoRoute(path: 'match/:matchId', builder: (_, s) => Scaffold(body: Text('match:${s.pathParameters['matchId']}'))),
        GoRoute(path: 'player/:playerKey', builder: (_, s) => Scaffold(body: Text('player:${s.pathParameters['playerKey']}'))),
        GoRoute(
            path: 'series-detail/:seriesId',
            builder: (_, s) => Scaffold(body: Text('series:${s.pathParameters['seriesId']}:${s.extra}'))),
      ];
  Widget stub(String t) => Scaffold(body: Center(child: Text('tab:$t')));
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/live', builder: (_, _) => home, routes: [
              ...details(),
              GoRoute(path: 'more', builder: (_, _) => const Scaffold(body: Text('page:more'))),
            ]),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/matches', builder: (_, _) => matches, routes: details())]),
          StatefulShellBranch(routes: [GoRoute(path: '/series', builder: (_, _) => stub('series'), routes: details())]),
          StatefulShellBranch(routes: [GoRoute(path: '/ranking', builder: (_, _) => stub('ranking'), routes: details())]),
          StatefulShellBranch(routes: [GoRoute(path: '/players', builder: (_, _) => stub('players'), routes: details())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => stub('settings'))]),
        ],
      ),
    ],
  );
}

Widget routerApp(GoRouter router) => MaterialApp.router(theme: buildAppTheme(), routerConfig: router);

String location(GoRouter r) => r.state.uri.toString();

/// Pumps enough frames for chained mock HTTP calls + route transitions
/// (pumpAndSettle can't be used: shimmers/live dots animate forever).
Future<void> settle(WidgetTester tester, {int frames = 12, Duration step = const Duration(milliseconds: 50)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Slow drag down from the top of [scrollable] so RefreshIndicator arms.
Future<void> pullToRefresh(WidgetTester tester, Finder scrollable, double distance) async {
  final g = await tester.startGesture(tester.getTopLeft(scrollable) + const Offset(200, 20));
  const step = 40.0;
  for (var d = 0.0; d < distance; d += step) {
    await g.moveBy(const Offset(0, step));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump();
}
