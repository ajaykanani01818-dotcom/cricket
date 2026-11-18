import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

JsonMap fixture(String name) => J.map(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

JsonMap deepCopy(JsonMap m) => J.map(jsonDecode(jsonEncode(m)));

/// match_detail.json `data` (a Test match, isLive:true, status STUMPS).
JsonMap liveDetailData() {
  final d = deepCopy(J.map(fixture('match_detail')['data']));
  d['sb_series_key'] = 'ser-1';
  return d;
}

/// Same match, finished: result + Player of the Match.
JsonMap completedDetailData() {
  final d = liveDetailData();
  d['status'] = 'COMPLETED';
  d['isLive'] = false;
  d['result'] = {'message': 'South Africa won by 5 wickets', 'winnerTeamKey': 'rsa', 'menOfTheMatchKey': 'aiden_markram'};
  return d;
}

JsonMap envelope(Object? data, {String message = 'ok'}) => {'message': message, 'data': data};

/// A commentary page of [count] balls derived from the fixture (unique timestamps / over numbers).
JsonMap commentaryPage({required int count, required int totalCount, int startOver = 200, String? wicketAt}) {
  final base = J.map(fixture('match_commentary')['data']);
  final template = J.maps(base['balls']).first;
  final balls = <JsonMap>[];
  for (var i = 0; i < count; i++) {
    final over = startOver - (i ~/ 6);
    final ball = 6 - (i % 6);
    final b = deepCopy(template)
      ..remove('overSummary')
      ..['overNumber'] = over
      ..['ballNumber'] = ball
      ..['value'] = i == 0 && wicketAt != null ? 'WK' : '${i % 3}'
      ..['commentary'] = '<p>Ball $over.$ball <strong>commentary</strong></p>'
      // later overs (higher startOver) are newer
      ..['commentaryTimestamp'] = 1700000000000 + startOver * 1000000 - i * 1000;
    balls.add(b);
  }
  return {...deepCopy(base), 'balls': balls, 'totalCount': totalCount};
}

typedef Responder = FutureOr<http.Response> Function(http.Request req);

http.Response ok(Object? data) => http.Response(jsonEncode(envelope(data)), 200, headers: {'content-type': 'application/json'});
http.Response err(int status, [String msg = 'boom']) => http.Response(jsonEncode({'message': msg}), status);

/// Routes /match/:id[/live|/scorecard|/commentary] and /players/:key/info to
/// replaceable responders and records every request.
class FakeApi {
  FakeApi({String matchId = '3QJ-e3k'}) : _id = matchId {
    detail = (_) => ok(liveDetailData());
    live = (_) => ok(J.map(fixture('match_live')['data']));
    scorecard = (_) => ok(J.map(fixture('match_scorecard')['data']));
    commentary = (_) => ok(J.map(fixture('match_commentary')['data']));
    player = (_) => ok(J.map(fixture('player_info')['data']));
  }

  final String _id;
  late Responder detail, live, scorecard, commentary, player;
  final List<Uri> calls = [];

  int count(String suffix) => calls.where((u) => _kind(u) == suffix).length;
  List<Uri> callsOf(String suffix) => calls.where((u) => _kind(u) == suffix).toList();

  String _kind(Uri u) {
    final p = u.path.replaceFirst('/api', '');
    if (p.startsWith('/players/')) return 'player';
    if (p == '/match/$_id') return 'detail';
    if (p.endsWith('/live')) return 'live';
    if (p.endsWith('/scorecard')) return 'scorecard';
    if (p.endsWith('/commentary')) return 'commentary';
    return 'other';
  }

  late final MockClient client = MockClient((req) async {
    calls.add(req.url);
    switch (_kind(req.url)) {
      case 'detail':
        return detail(req);
      case 'live':
        return live(req);
      case 'scorecard':
        return scorecard(req);
      case 'commentary':
        return commentary(req);
      case 'player':
        return player(req);
    }
    return err(404, 'not found');
  });

  /// Long timeout so tests can hold a request "in flight" with a Completer.
  late final ApiClient api =
      ApiClient(client: client, baseUrl: 'http://test/api', apiKey: 'k', retryDelays: const [], timeout: const Duration(hours: 1));
  late final MatchService matches = MatchService(api);
  late final PlayerService players = PlayerService(api);
}
