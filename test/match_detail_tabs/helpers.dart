import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

JsonMap fixture(String name) => J.map(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

/// Response handler per path suffix (e.g. 'playing11'); returning null → 404.
typedef Route = http.Response? Function(http.Request req);

/// Installs a MatchService backed by a MockClient; returns a call log.
List<String> installService(Route route) {
  final calls = <String>[];
  final mock = MockClient((req) async {
    calls.add(req.url.path);
    return route(req) ?? http.Response(jsonEncode({'message': 'not found'}), 404);
  });
  MatchService.instance = MatchService(
    ApiClient(client: mock, baseUrl: 'http://test', apiKey: 'k', retryDelays: const []),
  );
  return calls;
}

http.Response okJson(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json'});

http.Response serverError() => http.Response(jsonEncode({'message': 'Boom'}), 500);

/// Bounded-height host (like a TabBarView / Expanded).
Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Unbounded-height host (tab content inside the page scroll view, as in RN).
Widget scrollHost(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
