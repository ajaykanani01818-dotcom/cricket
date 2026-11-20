import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/features/discover/discover_cache.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/sbx1_server.dart';

String fixture(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

JsonMap fixtureJson(String name) => J.map(jsonDecode(fixture(name)));

http.Response jsonRes(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

typedef Handler = FutureOr<http.Response> Function(http.Request req);

/// Installs a MockClient-backed ApiClient into all three services and logs
/// every requested URL.
class FakeApi {
  FakeApi(this.handler) {
    final client = testClient(
      MockClient((r) async {
        requests.add(r.url);
        return await handler(r);
      }),
      baseUrl: 'http://test',
      retryDelays: const [],
    );
    RankingService.instance = RankingService(client);
    PlayerService.instance = PlayerService(client);
    MatchService.instance = MatchService(client);
    DiscoverCache.clear();
  }

  Handler handler;
  final List<Uri> requests = [];

  List<Uri> where(bool Function(Uri u) test) => requests.where(test).toList();
}

/// Router with [root] → [screen] and a stub player detail route that prints
/// the key and the passed initial player name.
GoRouter testRouter(
  String root,
  Widget screen, {
  Widget Function(String key, JsonMap? extra)? detail,
}) => GoRouter(
  initialLocation: root,
  routes: [
    GoRoute(
      path: root,
      builder: (_, _) => Scaffold(body: screen),
      routes: [
        GoRoute(
          path: 'player/:playerKey',
          builder: (_, s) {
            final key = s.pathParameters['playerKey']!;
            final extra = s.extra is Map ? J.map(s.extra) : null;
            return detail?.call(key, extra) ??
                Scaffold(
                  body: Text(
                    'detail:$key:${extra?['name'] ?? ''}',
                    key: const ValueKey('stub_detail'),
                  ),
                );
          },
        ),
      ],
    ),
  ],
);

Widget routerApp(GoRouter router, {Brightness brightness = Brightness.light}) =>
    MaterialApp.router(
      theme: buildAppTheme(brightness: brightness),
      routerConfig: router,
    );

/// Default fixture routes for the Discover pages.
http.Response discoverFixtures(http.Request r) {
  final path = r.url.path;
  if (path == '/rank') return jsonRes(fixture('rank_team'));
  if (path == '/rank/player') return jsonRes(fixture('rank_player'));
  if (path == '/players/trending') return jsonRes(fixture('players_trending'));
  if (path == '/players/countries') {
    return jsonRes(fixture('players_countries'));
  }
  if (path.startsWith('/players/country/')) {
    return jsonRes(fixture('players_country'));
  }
  if (path.endsWith('/info')) return jsonRes(fixture('player_info'));
  if (path == '/series') return jsonRes(fixture('series_list'));
  return jsonRes({'message': 'not found'}, 404);
}
