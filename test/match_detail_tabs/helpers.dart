import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/sbx1_server.dart';

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
  MatchService.instance = MatchService(testClient(mock, baseUrl: 'http://test', retryDelays: const []));
  return calls;
}

http.Response okJson(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});

http.Response serverError() => http.Response(jsonEncode({'message': 'Boom'}), 500);

/// Tab content inside the page scroll view (how the Match Centre hosts it).
Widget host(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
  theme: buildAppTheme(brightness: brightness),
  home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: child)),
);

Widget scrollHost(Widget child) => host(child);
