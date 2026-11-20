import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/services/cricket_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/sbx1_server.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, dynamic> fixtureJson(String name) => jsonDecode(fixture(name)) as Map<String, dynamic>;

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Records requests and answers them with [handler] (which may return a
/// Future that the test completes later to simulate slow responses).
class FakeApi {
  FakeApi(this.handler);
  FutureOr<http.Response> Function(http.Request req) handler;
  final List<Uri> requests = [];

  MatchService get service => MatchService(
    testClient(
      MockClient((req) async {
        requests.add(req.url);
        return handler(req);
      }),
      baseUrl: 'http://test',
      retryDelays: const [],
    ),
  );

  int count(bool Function(Uri u) test) => requests.where(test).length;
}

/// A series list page with [n] items whose ids start at [start].
/// [total] defaults to start + n (i.e. this is the last page).
Map<String, dynamic> seriesPage(String status, int start, int n, {int? total, int perPage = 24, int page = 1}) => {
  'message': 'ok',
  'data': [
    for (var i = start; i < start + n; i++)
      {
        '_id': '$status-$i',
        'name': '$status Series $i',
        'sb_series_key': 'key_${status}_$i',
        'seriesStatus': status,
        'startDate': '2026-11-07T11:51:27.000Z',
        'endDate': '2026-11-20T11:51:34.000Z',
      },
  ],
  'pageInfo': {'total': total ?? start + n, 'perPage': perPage, 'page': page},
};

/// Router with the Series tab + stub detail/match/player routes.
GoRouter seriesTestRouter({required Widget home, String initial = '/series', Object? initialExtra}) => GoRouter(
  initialLocation: initial,
  initialExtra: initialExtra,
  routes: [
    GoRoute(
      path: '/series',
      builder: (_, _) => home,
      routes: [
        GoRoute(
          path: 'series-detail/:id',
          builder: (_, s) => Scaffold(body: Text('DETAIL ${s.pathParameters['id']} ${s.extra ?? ''}')),
        ),
        GoRoute(
          path: 'match/:id',
          builder: (_, s) => Scaffold(body: Text('MATCH ${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: 'player/:id',
          builder: (_, s) => Scaffold(body: Text('PLAYER ${s.pathParameters['id']}')),
        ),
      ],
    ),
  ],
);

Widget routerApp(GoRouter router) => MaterialApp.router(routerConfig: router);

/// Pumps a few frames so mock HTTP futures resolve (no pumpAndSettle: shimmers animate forever).
Future<void> settleNetwork(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
