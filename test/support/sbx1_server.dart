import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/route_map.g.dart';
import 'package:crickbex/core/api/sbx1.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The secret from docs/sbx1_vectors.json.
final Uint8List kTestSecret = Uint8List.fromList(List<int>.generate(32, (i) => i));

/// token -> legacy REST path template (for serving legacy fixtures).
const Map<String, String> kLegacyPaths = {
  RouteMap.matchRecent: '/match/recent',
  RouteMap.matchLive: '/match/live',
  RouteMap.matchUpcoming: '/match/upcoming',
  RouteMap.matchCompleted: '/match/completed',
  RouteMap.matchById: '/match/:matchId',
  RouteMap.matchLiveById: '/match/:matchId/live',
  RouteMap.matchScorecard: '/match/:matchId/scorecard',
  RouteMap.matchSquad: '/match/:matchId/squad',
  RouteMap.matchCommentary: '/match/:matchId/commentary',
  RouteMap.matchPlaying11: '/match/:matchId/playing11',
  RouteMap.matchBoundaries: '/match/:matchId/boundaries',
  RouteMap.matchScoringRate: '/match/:matchId/scoring-rate',
  RouteMap.matchAnalytics: '/match/:matchId/analytics',
  RouteMap.seriesList: '/series',
  RouteMap.seriesUpcoming: '/series/upcoming',
  RouteMap.seriesById: '/series/:seriesId',
  RouteMap.seriesPointTable: '/series/:seriesId/point-table',
  RouteMap.seriesSquad: '/series/:seriesId/squad',
  RouteMap.seriesStats: '/series/:seriesId/stats',
  RouteMap.playersTrending: '/players/trending',
  RouteMap.playersCountries: '/players/countries',
  RouteMap.playersByCountry: '/players/country/:country',
  RouteMap.playerInfo: '/players/:playerId/info',
  RouteMap.rankTeam: '/rank',
  RouteMap.rankPlayer: '/rank/player',
  RouteMap.newsList: '/news',
  RouteMap.newsByKey: '/news/:newsKey',
};

/// Rebuilds the legacy REST request (path + query) for a decrypted call.
Uri legacyUri(String base, String token, Map<String, dynamic> params) {
  final rest = Map<String, dynamic>.of(params);
  final path = kLegacyPaths[token]!.replaceAllMapped(RegExp(r':(\w+)'), (m) {
    final v = rest.remove(m[1]);
    return m[1] == 'country' || m[1] == 'playerId' ? Uri.encodeComponent('$v') : '$v';
  });
  final q = <String, String>{for (final e in rest.entries) if (e.value != null) e.key: e.value.toString()};
  final uri = Uri.parse('$base$path');
  return q.isEmpty ? uri : uri.replace(queryParameters: q);
}

typedef Sbx1Handler = FutureOr<({int status, Object? body})> Function(String token, Map<String, dynamic> params);

/// In-process SBX1 "server": verifies + decrypts each request, calls [handler],
/// returns the encrypted `{s, b}` payload.
MockClient sbx1Server(Sbx1Handler handler, {List<int>? secret, void Function(http.Request raw)? onRaw}) {
  final sec = secret ?? kTestSecret;
  return MockClient((req) async {
    onRaw?.call(req);
    final token = req.url.pathSegments.last;
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(req.body) as Map<String, dynamic>;
    } catch (_) {
      return http.Response('{"message":"Not Found"}', 404);
    }
    final ({Map<String, dynamic> params, String nonceB64, Sbx1Keys keys}) r;
    try {
      r = await Sbx1.parseRequest(secret: sec, token: token, body: parsed);
    } catch (_) {
      return http.Response('{"message":"Not Found"}', 404);
    }
    final out = await handler(token, r.params);
    final env = await Sbx1.buildResponse(keys: r.keys, nonceB64: r.nonceB64, payload: {'s': out.status, 'b': out.body});
    return http.Response(jsonEncode(env), 200, headers: {'content-type': 'application/json'});
  });
}

/// Compatibility factory for feature tests: serves LEGACY REST fixtures through
/// the SBX1 client. [legacy] receives a reconstructed GET (same URL shape as
/// the old plain-REST client sent, relative to [baseUrl]) and its response is
/// wrapped as the encrypted inner `{s, b}`.
ApiClient testClient(
  http.Client legacy, {
  String baseUrl = 'http://test',
  Duration timeout = const Duration(seconds: 15),
  List<Duration> retryDelays = const [],
}) {
  final server = sbx1Server((token, params) async {
    final res = await legacy.get(legacyUri(baseUrl, token, params));
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      if (res.statusCode >= 200 && res.statusCode < 300) throw const FormatException('legacy body not json');
      body = <String, dynamic>{};
    }
    return (status: res.statusCode, body: body);
  });
  final guarded = MockClient((req) async {
    try {
      return await replay(server, req);
    } on FormatException {
      return http.Response('<html>', 200);
    }
  });
  return ApiClient(client: guarded, baseUrl: baseUrl, secret: kTestSecret, timeout: timeout, retryDelays: retryDelays);
}

/// Re-sends [req] through [c] (a MockClient cannot send an already-finalized request).
Future<http.Response> replay(http.Client c, http.Request req) =>
    c.post(req.url, headers: req.headers, body: req.body);
