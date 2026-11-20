import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../support/sbx1_server.dart';

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
    analytics = (_) => ok(J.map(fixture('match_analytics')['data']));
    scoringRate = (_) => ok(J.map(fixture('match_scoring_rate')['data']));
    boundaries = (_) => ok(J.map(fixture('match_boundaries')['data']));
    playing11 = (_) => ok(J.map(fixture('match_playing11')['data']));
    squad = (_) => ok(J.map(fixture('match_squad')['data']));
  }

  final String _id;
  late Responder detail, live, scorecard, commentary, player;
  late Responder analytics, scoringRate, boundaries, playing11, squad;
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
    if (p.endsWith('/analytics')) return 'analytics';
    if (p.endsWith('/scoring-rate')) return 'scoringRate';
    if (p.endsWith('/boundaries')) return 'boundaries';
    if (p.endsWith('/playing11')) return 'playing11';
    if (p.endsWith('/squad')) return 'squad';
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
      case 'analytics':
        return analytics(req);
      case 'scoringRate':
        return scoringRate(req);
      case 'boundaries':
        return boundaries(req);
      case 'playing11':
        return playing11(req);
      case 'squad':
        return squad(req);
    }
    return err(404, 'not found');
  });

  /// Long timeout so tests can hold a request "in flight" with a Completer.
  late final ApiClient api = testClient(client, baseUrl: 'http://test/api', retryDelays: const [], timeout: const Duration(hours: 1));
  late final MatchService matches = MatchService(api);
  late final PlayerService players = PlayerService(api);
}

// ── Crafted header states (shapes copied from real API payloads) ───────────

JsonMap _firstOf(String name) => deepCopy(J.maps(fixture(name)['data']).first);

/// Live ODI first innings (real w2bXPRS shape): ENG batting, AUS yet to
/// bat, `inningsOrder` already lists the planned second innings.
JsonMap odiFirstInningsDetail() {
  final d = _firstOf('match_upcoming')
    ..['status'] = 'LIVE'
    ..['inningsOrder'] = ['t2_1', 't1_1']
    ..['toss'] = 'England opt to bat'
    ..['sb_series_key'] = 'ser-odi';
  J.map(J.at(d, 'teams.t1'))['score'] = '';
  J.map(J.at(d, 'teams.t2'))['score'] = '126/2 (19.0)';
  return d;
}

JsonMap odiFirstInningsLive() {
  final l = deepCopy(J.map(fixture('match_live')['data']));
  final score = J.map(l['score']);
  score['teams'] = {
    'team1': {'key': 'aus', 'name': 'Australia', 'shortName': 'AUS', 'inningsStats': null},
    'team2': {
      'key': 'eng',
      'name': 'England',
      'shortName': 'ENG',
      'inningsStats': {'runs': 126, 'wickets': 2, 'overs': '19.0'},
    },
  };
  score['status'] = 'LIVE';
  score['inningsOrder'] = ['t2_1', 't1_1'];
  return l;
}

/// Live T20 chase: RDC 131/1 (20.0), UAEB 45/2 (4.1) chasing.
JsonMap t20ChaseDetail() {
  final d = _firstOf('match_recent')
    ..remove('result')
    ..['status'] = 'LIVE'
    ..['format'] = 'T20'
    ..['inningsOrder'] = ['t2_1', 't1_1']
    ..['currentInning'] = 't1_1';
  J.map(J.at(d, 'teams.t1'))['score'] = '45/2 (4.1)';
  J.map(J.at(d, 'teams.t2'))['score'] = '131/1 (20.0)';
  return d;
}

JsonMap t20ChaseLive({int runs = 45, int wickets = 2, String overs = '4.1'}) {
  final l = deepCopy(J.map(fixture('match_live')['data']));
  final score = J.map(l['score']);
  score['teams'] = {
    'team1': {
      'key': 'dbl',
      'name': 'UAE Bulls',
      'shortName': 'UAEB',
      'inningsStats': {'runs': runs, 'wickets': wickets, 'overs': overs},
    },
    'team2': {
      'key': 'rdc',
      'name': 'Royal Desert Champions',
      'shortName': 'RDC',
      'inningsStats': {'runs': 131, 'wickets': 1, 'overs': '20.0'},
    },
  };
  score['status'] = 'LIVE';
  score['inningsOrder'] = ['t2_1', 't1_1'];
  return l;
}

JsonMap inningsJson(String team, String short, int runs, int wickets, String overs) => {
      'teamInfo': {'teamName': team, 'shortName': short, 'runs': runs, 'wickets': wickets, 'overs': overs, 'extras': 0},
      'batting': [],
      'bowling': [],
    };

JsonMap scorecardWith({required List<JsonMap> innings, List<String> order = const [], String? maxOvers, int? target}) => {
      'result': {
        'innings': innings,
        'inningsOrder': order,
        'maxOvers': maxOvers ?? '',
        'targetRuns': target,
      },
    };

/// A live Test between PAK (t1) and SL (t2).
JsonMap testDetail({List<String> order = const ['t2_1', 't1_1']}) {
  final d = liveDetailData()
    ..remove('currentOver')
    ..['status'] = 'LIVE'
    ..['inningsOrder'] = order
    ..['teams'] = {
      't1': {'key': 'pak', 'name': 'Pakistan', 'short_name': 'PAK', 'logo': '', 'score': ''},
      't2': {'key': 'sl', 'name': 'Sri Lanka', 'short_name': 'SL', 'logo': '', 'score': ''},
    };
  return d;
}

/// Upcoming ODI (real match_upcoming item: NOT_STARTED, isLive true).
JsonMap upcomingDetail() => _firstOf('match_upcoming');

/// Completed T10 (real match_completed item).
JsonMap completedT10Detail() => _firstOf('match_completed');
