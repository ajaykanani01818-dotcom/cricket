import '../api/json.dart';
import 'chase_summary.dart';
import 'fixture_status.dart';

/// Frontend match model — ported from RN `Match` (src/types/cricket.ts) and
/// `transformApiMatchesToMatches` (src/utils/matchTransform.ts).
class MatchSummary {
  final String id; // sb_match_key preferred; used for /match/:id
  final String team1, team2;
  final String? team1Logo, team2Logo, team1Score, team2Score;
  final String status;
  final String rawStatus;
  final String venue;
  final String date; // ISO start
  final bool isLive;
  final String series;
  final String? seriesKey; // sb_series_key
  final String? format, toss, name;
  final String? resultMessage, winnerTeamKey, manOfTheMatchKey;
  final String? chaseSummaryLine;
  final FixtureCardKind? fixtureCardKind;
  final JsonMap raw;

  const MatchSummary({
    required this.id,
    required this.team1,
    required this.team2,
    this.team1Logo,
    this.team2Logo,
    this.team1Score,
    this.team2Score,
    required this.status,
    this.rawStatus = '',
    required this.venue,
    required this.date,
    required this.isLive,
    required this.series,
    this.seriesKey,
    this.format,
    this.toss,
    this.name,
    this.resultMessage,
    this.winnerTeamKey,
    this.manOfTheMatchKey,
    this.chaseSummaryLine,
    this.fixtureCardKind,
    this.raw = const {},
  });

  DateTime? get startTime => DateTime.tryParse(date)?.toLocal();
}

bool _hasScore(String? s) {
  final t = s?.trim();
  return t != null && t.isNotEmpty && t != '-';
}

String matchIdOf(JsonMap m) =>
    J.text(m['sb_match_key']) ?? J.text(m['_id']) ?? J.str(m['key']);

bool deriveIsLive(JsonMap m) {
  final status = J.str(m['status']).toUpperCase();
  final has1 = _hasScore(J.str(J.at(m, 'teams.t1.score')));
  final has2 = _hasScore(J.str(J.at(m, 'teams.t2.score')));
  final single = (has1 && !has2) || (has2 && !has1);
  return status == 'LIVE' ||
      status == 'IN_PROGRESS' ||
      status.contains('LIVE') ||
      (single && J.str(m['status']) != 'COMPLETED');
}

MatchSummary transformApiMatch(JsonMap m) {
  final isLive = deriveIsLive(m);
  final t1 = J.map(J.at(m, 'teams.t1'));
  final t2 = J.map(J.at(m, 'teams.t2'));
  final t1Score = J.str(t1['score']);
  final t2Score = J.str(t2['score']);
  final resultMsg = J.text(J.at(m, 'result.message'));
  final currentInning = J.str(m['currentInning']).toLowerCase();
  String status = J.str(m['status']);

  if (resultMsg != null) {
    status = resultMsg;
  } else if (isLive && _hasScore(t1Score) && !_hasScore(t2Score)) {
    final chase =
        currentInning.contains('t2') || RegExp(r'/10\b').hasMatch(t1Score);
    final runs = t1Score.split('/').first.trim();
    status = chase
        ? '${J.text(t2['name']) ?? 'They'} need $runs runs'
        : '${J.text(t2['name']) ?? 'They'} yet to bat';
  } else if (isLive && _hasScore(t2Score) && !_hasScore(t1Score)) {
    final chase =
        currentInning.contains('t1') || RegExp(r'/10\b').hasMatch(t2Score);
    final runs = t2Score.split('/').first.trim();
    status = chase
        ? '${J.text(t1['name']) ?? 'They'} need $runs runs'
        : '${J.text(t1['name']) ?? 'They'} yet to bat';
  } else if (!_hasScore(t1Score) && !_hasScore(t2Score)) {
    status = 'Match starting soon';
  }

  String? chaseLine;
  if (isLive) {
    final c = computeChaseSummaryForLiveList(m);
    if (c != null) {
      final runNoun = c.runsNeeded == 1 ? 'run' : 'runs';
      chaseLine = c.ballsRemaining != null
          ? '${c.chasingTeamName} need ${c.runsNeeded} $runNoun in ${c.ballsRemaining} ${c.ballsRemaining == 1 ? 'ball' : 'balls'}'
          : '${c.chasingTeamName} need ${c.runsNeeded} $runNoun';
    }
  }

  return MatchSummary(
    id: matchIdOf(m),
    team1: J.str(t1['name']),
    team2: J.str(t2['name']),
    team1Logo: J.text(t1['logo']),
    team2Logo: J.text(t2['logo']),
    team1Score: J.text(t1Score),
    team2Score: J.text(t2Score),
    status: status.isNotEmpty ? status : J.str(m['status']),
    rawStatus: J.str(m['status']),
    venue: J.str(m['ground']),
    date: J.str(m['startDate']),
    isLive: isLive,
    series: J.str(m['seriesName']),
    seriesKey: J.text(m['sb_series_key']),
    format: J.text(m['format']),
    toss: J.text(m['toss']),
    name: J.text(m['name']),
    resultMessage: resultMsg,
    winnerTeamKey: J.text(J.at(m, 'result.winnerTeamKey')),
    manOfTheMatchKey: J.text(J.at(m, 'result.menOfTheMatchKey')),
    chaseSummaryLine: chaseLine,
    raw: m,
  );
}

List<MatchSummary> transformApiMatches(Iterable<JsonMap> list) =>
    list.map(transformApiMatch).toList();
