/// Match Centre state derivation (research §3.2 header states).
///
/// Everything here is pure and unit-tested (test/match_detail/match_state_test.dart).
/// Rules that come from the data quirks (research §0.3):
///  - status comes from `status`, never `isLive`;
///  - `inningsOrder` lists the PLANNED innings (a live ODI first innings
///    already carries `["t2_1", "t1_1"]`), so an innings only counts as
///    started when it has a score (scorecard innings, live inningsStats or a
///    parseable team score);
///  - missing values stay null: nothing here invents a 0.
library;

import '../../../core/api/json.dart';
import '../../../core/utils/chase_summary.dart' show inferMaxOversFromFormat, oversToLegalBallsCompleted;
import '../tabs/tab_scorecard_parse.dart';
import 'commentary_html.dart';
import 'match_detail_logic.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Status
// ─────────────────────────────────────────────────────────────────────────────

enum MatchPhase {
  /// Not started (includes "toss done").
  upcoming,

  /// Play in progress.
  live,

  /// Stumps, lunch, tea, innings break, rain delay…: score frozen, no pulse.
  interrupted,

  /// Finished with a result (incl. tie / draw).
  completed,

  /// Abandoned, no result, cancelled, postponed: label only.
  abandoned,

  /// Status missing or not recognised.
  unknown,
}

class MatchStatus {
  const MatchStatus(this.phase, this.label, this.raw);
  final MatchPhase phase;

  /// Readable sentence-case label ("Stumps", "Innings break", "Result").
  final String label;

  /// Raw provider value (diagnostics).
  final String raw;

  bool get isLive => phase == MatchPhase.live;

  /// Live or a break inside a live match: the screen keeps polling.
  bool get inPlay => phase == MatchPhase.live || phase == MatchPhase.interrupted;

  @override
  bool operator ==(Object other) => other is MatchStatus && other.phase == phase && other.label == label && other.raw == raw;
  @override
  int get hashCode => Object.hash(phase, label, raw);
}

String _normStatus(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_').replaceAll(RegExp(r'[^A-Z0-9_]'), '').trim();

/// "RAIN_DELAY" → "Rain delay".
String sentenceCaseStatus(String raw) {
  final s = raw.replaceAll(RegExp(r'[_\-]+'), ' ').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

const _statusTable = <String, (MatchPhase, String)>{
  'LIVE': (MatchPhase.live, 'Live'),
  'IN_PROGRESS': (MatchPhase.live, 'Live'),
  'INPROGRESS': (MatchPhase.live, 'Live'),
  'PLAYING': (MatchPhase.live, 'Live'),
  'STUMPS': (MatchPhase.interrupted, 'Stumps'),
  'LUNCH': (MatchPhase.interrupted, 'Lunch'),
  'TEA': (MatchPhase.interrupted, 'Tea'),
  'DINNER': (MatchPhase.interrupted, 'Dinner'),
  'DRINKS': (MatchPhase.interrupted, 'Drinks'),
  'INNINGS_BREAK': (MatchPhase.interrupted, 'Innings break'),
  'INNINGSBREAK': (MatchPhase.interrupted, 'Innings break'),
  'BREAK': (MatchPhase.interrupted, 'Break'),
  'STRATEGIC_TIMEOUT': (MatchPhase.interrupted, 'Strategic timeout'),
  'RAIN_DELAY': (MatchPhase.interrupted, 'Rain delay'),
  'RAIN': (MatchPhase.interrupted, 'Rain delay'),
  'DELAYED': (MatchPhase.interrupted, 'Delayed'),
  'DELAY': (MatchPhase.interrupted, 'Delayed'),
  'BAD_LIGHT': (MatchPhase.interrupted, 'Bad light'),
  'WET_OUTFIELD': (MatchPhase.interrupted, 'Wet outfield'),
  'INTERRUPTED': (MatchPhase.interrupted, 'Play interrupted'),
  'SUSPENDED': (MatchPhase.interrupted, 'Play suspended'),
  'NOT_STARTED': (MatchPhase.upcoming, 'Upcoming'),
  'NOTSTARTED': (MatchPhase.upcoming, 'Upcoming'),
  'SCHEDULED': (MatchPhase.upcoming, 'Upcoming'),
  'UPCOMING': (MatchPhase.upcoming, 'Upcoming'),
  'PREVIEW': (MatchPhase.upcoming, 'Upcoming'),
  'TOSS': (MatchPhase.upcoming, 'Toss done'),
  'COMPLETED': (MatchPhase.completed, 'Result'),
  'COMPLETE': (MatchPhase.completed, 'Result'),
  'FINISHED': (MatchPhase.completed, 'Result'),
  'RESULT': (MatchPhase.completed, 'Result'),
  'ENDED': (MatchPhase.completed, 'Result'),
  'TIED': (MatchPhase.completed, 'Match tied'),
  'TIE': (MatchPhase.completed, 'Match tied'),
  'DRAW': (MatchPhase.completed, 'Match drawn'),
  'DRAWN': (MatchPhase.completed, 'Match drawn'),
  'ABANDONED': (MatchPhase.abandoned, 'Abandoned'),
  'MATCH_ABANDONED': (MatchPhase.abandoned, 'Abandoned'),
  'NO_RESULT': (MatchPhase.abandoned, 'No result'),
  'NORESULT': (MatchPhase.abandoned, 'No result'),
  'CANCELLED': (MatchPhase.abandoned, 'Cancelled'),
  'CANCELED': (MatchPhase.abandoned, 'Cancelled'),
  'WASHOUT': (MatchPhase.abandoned, 'Washed out'),
  'WASH_OUT': (MatchPhase.abandoned, 'Washed out'),
  'POSTPONED': (MatchPhase.abandoned, 'Postponed'),
};

/// Maps the raw provider `status` to a phase + readable label. A non-empty
/// result message on a not-finished status means the match just ended.
MatchStatus resolveMatchStatus(String? rawStatus, {String? resultMessage}) {
  final raw = (rawStatus ?? '').trim();
  final key = _normStatus(raw);
  final hasResult = (resultMessage ?? '').trim().isNotEmpty;
  final hit = _statusTable[key];
  if (hit != null) {
    if (hasResult && (hit.$1 == MatchPhase.live || hit.$1 == MatchPhase.interrupted || hit.$1 == MatchPhase.upcoming)) {
      return MatchStatus(MatchPhase.completed, 'Result', raw);
    }
    return MatchStatus(hit.$1, hit.$2, raw);
  }
  if (key.contains('ABANDON')) return MatchStatus(MatchPhase.abandoned, 'Abandoned', raw);
  if (key.contains('CANCEL')) return MatchStatus(MatchPhase.abandoned, 'Cancelled', raw);
  if (key.contains('LIVE')) return MatchStatus(hasResult ? MatchPhase.completed : MatchPhase.live, hasResult ? 'Result' : 'Live', raw);
  if (hasResult) return MatchStatus(MatchPhase.completed, 'Result', raw);
  if (raw.isEmpty) return MatchStatus(MatchPhase.unknown, 'Status not available', raw);
  return MatchStatus(MatchPhase.unknown, sentenceCaseStatus(raw), raw);
}

bool isTestFormat(String? format) {
  final f = (format ?? '').toUpperCase();
  return RegExp(r'\bTEST\b').hasMatch(f) || f.contains('FIRST_CLASS') || f.contains('FIRST CLASS') || f == 'FC';
}

// ─────────────────────────────────────────────────────────────────────────────
// Scores
// ─────────────────────────────────────────────────────────────────────────────

/// One parsed score. Null fields are "not supplied".
class ParsedScore {
  const ParsedScore({required this.runs, this.wickets, this.overs});
  final int runs;
  final int? wickets;
  final String? overs;

  @override
  bool operator ==(Object other) => other is ParsedScore && other.runs == runs && other.wickets == wickets && other.overs == overs;
  @override
  int get hashCode => Object.hash(runs, wickets, overs);
}

final _scoreRe = RegExp(r'^\s*(\d+)\s*(?:/\s*(\d+))?\s*(?:\(\s*([\d.]+)\s*(?:ov[a-z]*)?\s*\))?\s*$');

/// "137/4 (9.5)", "0/0", "400", "135/4". Null for empty, "-", Test
/// multi-innings strings ("400 & 186/3") and anything else.
ParsedScore? parseScoreString(String? s) {
  final t = (s ?? '').trim();
  if (t.isEmpty || t == '-' || t.contains('&')) return null;
  final m = _scoreRe.firstMatch(t);
  if (m == null) return null;
  final runs = int.tryParse(m.group(1)!);
  if (runs == null) return null;
  return ParsedScore(runs: runs, wickets: m.group(2) == null ? null : int.tryParse(m.group(2)!), overs: m.group(3));
}

ParsedScore? _scoreFromStats(dynamic stats) {
  if (stats is! Map) return null;
  final m = J.map(stats);
  final runs = J.integer(m['runs']);
  if (runs == null) return null;
  final overs = J.text(m['overs']);
  return ParsedScore(runs: runs, wickets: J.integer(m['wickets']), overs: overs);
}

/// One innings of one team.
class InningsScore {
  const InningsScore({required this.side, required this.number, required this.runs, this.wickets, this.overs});
  final TeamSide side;

  /// 1-based innings number for this team.
  final int number;
  final int runs;
  final int? wickets;
  final String? overs;

  bool get allOut => wickets == 10;

  /// "287/4", "400" (all out), "135".
  String get scoreText {
    if (wickets == null || allOut) return '$runs';
    return '$runs/$wickets';
  }

  /// Legal balls bowled, when overs are supplied.
  int? get legalBalls {
    final o = overs;
    if (o == null || o.trim().isEmpty || !RegExp(r'^\d+(\.\d+)?$').hasMatch(o.trim())) return null;
    return oversToLegalBallsCompleted(o);
  }

  @override
  bool operator ==(Object other) =>
      other is InningsScore &&
      other.side == side &&
      other.number == number &&
      other.runs == runs &&
      other.wickets == wickets &&
      other.overs == overs;
  @override
  int get hashCode => Object.hash(side, number, runs, wickets, overs);

  @override
  String toString() => 'Inn(${side.name}#$number $scoreText ${overs ?? ''})';
}

TeamSide? sideOfInningsKey(String key) {
  final k = key.toLowerCase();
  if (k.startsWith('t1') || k == 'team1') return TeamSide.team1;
  if (k.startsWith('t2') || k == 'team2') return TeamSide.team2;
  return null;
}

/// Started innings in batting order.
///
/// Source priority: the scorecard's innings list (with the live innings
/// overlaid when live is ahead); else the innings order keys that have a
/// score in live `inningsStats` / the detail team score. A team that bats
/// twice without a scorecard can't be split, so its later innings are
/// dropped rather than guessed.
List<InningsScore> buildInnings({
  required MatchDetailVM match,
  LiveVM? live,
  ScorecardView? scorecard,
  List<String> scorecardOrder = const [],
}) {
  ParsedScore? liveOf(TeamSide s) => _scoreFromStats(J.at(live?.score, 'teams.${s == TeamSide.team1 ? 'team1' : 'team2'}.inningsStats'));
  ParsedScore? apiOf(TeamSide s) => parseScoreString(s == TeamSide.team1 ? match.t1.score : match.t2.score);

  final out = <InningsScore>[];
  int nextNumber(TeamSide s) => out.where((i) => i.side == s).length + 1;

  final sc = scorecard;
  if (sc != null && sc.hasInnings) {
    for (var i = 0; i < sc.innings.length; i++) {
      final inn = sc.innings[i];
      TeamSide? side = i < scorecardOrder.length ? sideOfInningsKey(scorecardOrder[i]) : null;
      side ??= _sideByName(inn.teamName, inn.shortName, match);
      final runs = int.tryParse(inn.runs);
      if (side == null || runs == null) continue;
      out.add(InningsScore(
        side: side,
        number: nextNumber(side),
        runs: runs,
        wickets: int.tryParse(inn.wickets),
        overs: inn.overs == '-' ? null : inn.overs,
      ));
    }
    if (out.isNotEmpty) {
      // Live is fresher than the scorecard for the innings in progress.
      final last = out.last;
      final l = liveOf(last.side);
      if (l != null && l.runs >= last.runs && (l.runs != last.runs || l.wickets != last.wickets || l.overs != last.overs)) {
        out[out.length - 1] = InningsScore(side: last.side, number: last.number, runs: l.runs, wickets: l.wickets, overs: l.overs);
      }
      // A new innings the scorecard has not caught up with yet (limited
      // overs: the other side has live stats but no innings).
      final other = last.side == TeamSide.team1 ? TeamSide.team2 : TeamSide.team1;
      final lo = liveOf(other);
      if (out.length == 1 && lo != null && (lo.runs > 0 || (lo.overs != null && lo.legalBallsOrZero > 0))) {
        out.add(InningsScore(side: other, number: 1, runs: lo.runs, wickets: lo.wickets, overs: lo.overs));
      }
      return out;
    }
  }

  final order = (live != null && live.inningsOrder.isNotEmpty) ? live.inningsOrder : match.inningsOrder;
  final seen = <TeamSide>{};
  for (final key in order) {
    final side = sideOfInningsKey(key);
    if (side == null || seen.contains(side)) continue; // second innings of a side can't be split
    final s = liveOf(side) ?? apiOf(side);
    if (s == null) continue;
    seen.add(side);
    out.add(InningsScore(side: side, number: 1, runs: s.runs, wickets: s.wickets, overs: s.overs));
  }
  if (out.isEmpty && order.isEmpty) {
    // No order at all: only safe when exactly one side has a score.
    final a = liveOf(TeamSide.team1) ?? apiOf(TeamSide.team1);
    final b = liveOf(TeamSide.team2) ?? apiOf(TeamSide.team2);
    if (a != null && b == null) out.add(InningsScore(side: TeamSide.team1, number: 1, runs: a.runs, wickets: a.wickets, overs: a.overs));
    if (b != null && a == null) out.add(InningsScore(side: TeamSide.team2, number: 1, runs: b.runs, wickets: b.wickets, overs: b.overs));
  }
  return out;
}

extension on ParsedScore {
  int get legalBallsOrZero {
    final o = overs;
    if (o == null || !RegExp(r'^\d+(\.\d+)?$').hasMatch(o.trim())) return 0;
    return oversToLegalBallsCompleted(o);
  }
}

TeamSide? _sideByName(String teamName, String? shortName, MatchDetailVM m) {
  final n = teamName.trim().toLowerCase();
  final s = (shortName ?? '').trim().toLowerCase();
  bool hit(TeamVM t) {
    final tn = t.name.toLowerCase();
    final ts = (t.shortName ?? '').toLowerCase();
    return (n.isNotEmpty && tn == n) || (s.isNotEmpty && ts == s);
  }

  if (hit(m.t1)) return TeamSide.team1;
  if (hit(m.t2)) return TeamSide.team2;
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Situation
// ─────────────────────────────────────────────────────────────────────────────

String _rate(double r) => r.toStringAsFixed(2);

/// Runs per over, null when no legal ball has been bowled.
String? runRate(int runs, int? legalBalls) {
  if (legalBalls == null || legalBalls <= 0) return null;
  return _rate(runs * 6 / legalBalls);
}

class ChaseInfo {
  const ChaseInfo({
    required this.side,
    required this.target,
    required this.targetDerived,
    required this.runsNeeded,
    this.ballsLeft,
    this.ballsEstimated = false,
    this.requiredRate,
  });
  final TeamSide side;
  final int target;

  /// True when the provider sent no `targetRuns` and the target is
  /// first-innings runs + 1 (noted in the Info tab).
  final bool targetDerived;
  final int runsNeeded;

  /// Null when the overs limit is unknown.
  final int? ballsLeft;

  /// Balls left come from the format default (T20 = 20 overs …), not from
  /// the provider's `maxOvers`.
  final bool ballsEstimated;
  final String? requiredRate;
}

/// What the header shows for the current situation.
class MatchSituation {
  const MatchSituation({
    required this.status,
    required this.isTest,
    required this.innings,
    this.batting,
    this.headline,
    this.subline,
    this.chase,
    this.currentRunRate,
    this.projection,
    this.winner,
  });

  final MatchStatus status;
  final bool isTest;
  final List<InningsScore> innings;

  /// Side of the innings in progress / last innings.
  final TeamSide? batting;

  /// Plain-language line: "BAN need 46 from 38 balls", "Pakistan lead by
  /// 37", "UAE Bulls won by 6 wickets". Null when nothing can be derived.
  final String? headline;

  /// Secondary line under the headline ("About 180 balls left (est.)").
  final String? subline;
  final ChaseInfo? chase;
  final String? currentRunRate;

  /// "At this rate: 312" (arithmetic, only when `maxOvers` is supplied).
  final String? projection;

  /// Winning side when `winnerTeamKey` resolves.
  final TeamSide? winner;

  InningsScore? get current => innings.isEmpty ? null : innings.last;
  List<InningsScore> inningsOf(TeamSide s) => innings.where((i) => i.side == s).toList(growable: false);

  /// "400 & 186/3" for Tests, "287/4" otherwise; null when the side has not batted.
  String? scoreLineOf(TeamSide s) {
    final list = inningsOf(s);
    if (list.isEmpty) return null;
    return list.map((i) => i.scoreText).join(' & ');
  }

  int totalOf(TeamSide s) => inningsOf(s).fold(0, (a, i) => a + i.runs);
}

int? _maxOversFromScorecard(String? raw) {
  final n = num.tryParse((raw ?? '').trim());
  if (n == null || n <= 0) return null;
  return n.round();
}

/// Builds the header situation. [teamLabel] names a side in sentences.
MatchSituation deriveSituation({
  required MatchDetailVM match,
  required MatchStatus status,
  required List<InningsScore> innings,
  int? providerTarget,
  String? scorecardMaxOvers,
  required String Function(TeamSide) teamLabel,
}) {
  final isTest = isTestFormat(match.format);
  final current = innings.isEmpty ? null : innings.last;
  final batting = current?.side;
  TeamSide? winner;
  final wk = (match.winnerKey ?? '').toLowerCase();
  if (wk.isNotEmpty) {
    if ((match.t1.key ?? '').toLowerCase() == wk) winner = TeamSide.team1;
    if ((match.t2.key ?? '').toLowerCase() == wk) winner = TeamSide.team2;
  }

  String? headline, subline, crr, projection;
  ChaseInfo? chase;

  switch (status.phase) {
    case MatchPhase.completed:
      headline = match.resultMessage ?? (status.label == 'Result' ? null : status.label);
    case MatchPhase.abandoned:
      headline = match.resultMessage;
    case MatchPhase.upcoming:
    case MatchPhase.unknown:
      break;
    case MatchPhase.live:
    case MatchPhase.interrupted:
      if (current == null) break;
      crr = runRate(current.runs, current.legalBalls);
      if (isTest) {
        headline = _testLine(innings, teamLabel);
      } else {
        final maxOvers = _maxOversFromScorecard(scorecardMaxOvers);
        if (innings.length == 1) {
          if (maxOvers != null && current.legalBalls != null && current.legalBalls! > 0 && current.legalBalls! < maxOvers * 6) {
            final proj = (current.runs * maxOvers * 6 / current.legalBalls!).round();
            projection = 'At this rate: $proj';
          }
        } else if (innings.length == 2 && innings[0].side != innings[1].side) {
          chase = _chase(innings[0], innings[1], providerTarget, maxOvers, match.format);
          if (chase != null) {
            final who = teamLabel(chase.side);
            final runs = chase.runsNeeded == 1 ? '1 run' : '${chase.runsNeeded} runs';
            if (chase.ballsLeft != null && !chase.ballsEstimated) {
              final balls = chase.ballsLeft == 1 ? '1 ball' : '${chase.ballsLeft} balls';
              headline = '$who need ${chase.runsNeeded} from $balls';
            } else {
              headline = '$who need $runs';
              if (chase.ballsLeft != null) subline = 'About ${chase.ballsLeft} balls left (est.)';
            }
          }
        }
      }
  }

  return MatchSituation(
    status: status,
    isTest: isTest,
    innings: innings,
    batting: batting,
    headline: headline,
    subline: subline,
    chase: chase,
    currentRunRate: crr,
    projection: projection,
    winner: winner,
  );
}

ChaseInfo? _chase(InningsScore first, InningsScore second, int? providerTarget, int? maxOvers, String? format) {
  final derived = providerTarget == null || providerTarget <= 0;
  final target = derived ? first.runs + 1 : providerTarget;
  final need = target - second.runs;
  if (need <= 0) return null; // never "need 0"
  if (second.allOut) return null;
  int? ballsLeft;
  var est = false;
  final legal = second.legalBalls;
  var limit = maxOvers;
  if (limit == null) {
    limit = inferMaxOversFromFormat(format);
    est = limit != null;
  }
  if (limit != null && legal != null) {
    final left = limit * 6 - legal;
    if (left > 0) ballsLeft = left;
  }
  if (limit != null && legal != null && ballsLeft == null) return null; // overs used up
  String? rrr;
  if (ballsLeft != null) rrr = _rate(need * 6 / ballsLeft);
  return ChaseInfo(
    side: second.side,
    target: target,
    targetDerived: derived,
    runsNeeded: need,
    ballsLeft: ballsLeft,
    ballsEstimated: est && ballsLeft != null,
    requiredRate: rrr,
  );
}

/// Test situation: lead / trail / need N to win. Null for the first innings.
String? _testLine(List<InningsScore> innings, String Function(TeamSide) label) {
  if (innings.length < 2) return null;
  final bat = innings.last.side;
  final other = bat == TeamSide.team1 ? TeamSide.team2 : TeamSide.team1;
  int total(TeamSide s) => innings.where((i) => i.side == s).fold(0, (a, i) => a + i.runs);
  final who = label(bat);
  if (innings.length >= 4) {
    final need = total(other) - total(bat) + 1;
    if (need <= 0) return null;
    return '$who need $need to win';
  }
  final diff = total(bat) - total(other);
  if (diff > 0) return '$who lead by $diff';
  if (diff < 0) return '$who trail by ${-diff}';
  return 'Scores level';
}

// ─────────────────────────────────────────────────────────────────────────────
// Upcoming / notes
// ─────────────────────────────────────────────────────────────────────────────

/// "Starts in 2d 4h", "Starts in 3h 15m", "Starts in 12m", or null when the
/// start has passed (the caller then says it is due to start).
String? countdownLabel(DateTime start, DateTime now) {
  final d = start.difference(now);
  if (d.inSeconds <= 0) return null;
  final mins = (d.inSeconds / 60).ceil();
  final days = mins ~/ (24 * 60);
  final hours = (mins % (24 * 60)) ~/ 60;
  final m = mins % 60;
  if (days > 0) return 'Starts in ${days}d ${hours}h';
  if (hours > 0) return 'Starts in ${hours}h ${m}m';
  return 'Starts in ${m}m';
}

/// Newest `type:"info"` commentary as plain text (the stumps summary …).
String? latestInfoNote(LiveVM? live) {
  if (live == null) return null;
  for (final b in J.maps(live.raw['balls'])) {
    if (b['type'] != 'info') continue;
    final text = parseCommentaryRuns(J.str(b['commentary'])).map((r) => r.text).join().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Overs for the Seam strip
// ─────────────────────────────────────────────────────────────────────────────

/// One over for the strip: ball labels in bowling order (extras included,
/// never dropped).
class OverView {
  const OverView({required this.key, this.overNumber, required this.labels, this.runs, this.bowler, this.inProgress = false});

  /// Stable identity (innings + over) so a new over starts a fresh strip.
  final String key;

  /// 1-based over number ("Over 62"), null when unknown.
  final int? overNumber;
  final List<String> labels;

  /// Runs in the over when the provider supplied it or it is exactly
  /// derivable (no extras); else null.
  final int? runs;
  final String? bowler;
  final bool inProgress;

  String get title => overNumber != null ? 'Over $overNumber' : 'This over';

  @override
  bool operator ==(Object other) =>
      other is OverView &&
      other.key == key &&
      other.runs == runs &&
      other.bowler == bowler &&
      other.labels.length == labels.length &&
      Iterable.generate(labels.length).every((i) => other.labels[i] == labels[i]);
  @override
  int get hashCode => Object.hash(key, runs, bowler, Object.hashAll(labels));
}

int? _exactRuns(List<String> labels) {
  var sum = 0;
  for (final l in labels) {
    final u = l.trim().toUpperCase();
    if (u == 'W' || u == 'WK' || u == 'WKT' || u == '0' || u.isEmpty) continue;
    final n = int.tryParse(u);
    if (n == null) return null; // extras: provider total unknown
    sum += n;
  }
  return sum;
}

/// Current over first, then up to [maxPrevious] earlier overs (newest first).
///
/// Current over: the newest over in the live `balls` feed (API order is
/// newest first, so it is reversed to keep a no-ball before its re-bowled
/// delivery); else the detail `currentOver`. Earlier overs: live
/// `recentOvers` (with `overSummary`).
List<OverView> buildOverViews({required MatchDetailVM match, LiveVM? live, int maxPrevious = 4}) {
  final out = <OverView>[];
  final feed = J.maps(live?.raw['balls']).where((b) => b['type'] == 'ball' && J.text(b['value']) != null).toList();
  if (feed.isNotEmpty) {
    final head = feed.first;
    final inn = J.str(head['inningsIndex']);
    final over = J.integer(head['overNumber']);
    final same = feed.takeWhile((b) => J.str(b['inningsIndex']) == inn && J.integer(b['overNumber']) == over).toList();
    final summary = OverEndSummary.fromJson(same.firstWhere((b) => b['overSummary'] is Map, orElse: () => const {})['overSummary']);
    final osb = J.list(J.at(same.firstWhere((b) => b['overSummary'] is Map, orElse: () => const {}), 'overSummary.overSummaryBalls'));
    final labels = osb.isNotEmpty ? osb.map((e) => J.str(e).trim()).where((e) => e.isNotEmpty).toList() : same.reversed.map((b) => J.str(b['value']).trim()).toList();
    out.add(OverView(
      key: '$inn:$over',
      overNumber: summary?.overNumber ?? (over != null ? over + 1 : null),
      labels: labels,
      runs: summary?.runs ?? _exactRuns(labels),
      bowler: summary?.bowlerLine?.replaceAll(RegExp(r' [\d.]+-\d+-\d+-\d+$'), ''),
      inProgress: summary == null,
    ));
  } else if (match.currentOver != null) {
    final co = match.currentOver!;
    final labels = co.balls.map((b) => b.value).where((v) => v.isNotEmpty).toList();
    final osb = match.raw['currentOver'] is Map
        ? J.list(J.at(J.maps(J.at(match.raw, 'currentOver.balls')).firstWhere((b) => b['overSummary'] is Map, orElse: () => const {}), 'overSummary.overSummaryBalls'))
        : const [];
    final ordered = osb.isNotEmpty ? osb.map((e) => J.str(e).trim()).where((e) => e.isNotEmpty).toList() : labels;
    final balls = J.maps(J.at(match.raw, 'currentOver.balls'));
    final summary = OverEndSummary.fromJson(balls.firstWhere((b) => b['overSummary'] is Map, orElse: () => const {})['overSummary']);
    final ballOver = balls.isEmpty ? null : J.integer(balls.first['overNumber']);
    out.add(OverView(
      key: 'detail:${co.titleOverNumber}',
      overNumber: summary?.overNumber ?? (ballOver != null ? ballOver + 1 : co.titleOverNumber),
      labels: ordered,
      runs: summary?.runs ?? _exactRuns(ordered),
      bowler: summary?.bowlerLine?.replaceAll(RegExp(r' [\d.]+-\d+-\d+-\d+$'), ''),
      inProgress: summary == null,
    ));
  }
  final curNo = out.isEmpty ? null : out.first.overNumber;
  for (final r in live?.recentOvers ?? const <RecentOverRow>[]) {
    if (out.length > maxPrevious) break;
    if (curNo != null && r.displayOverNumber >= curNo) continue;
    out.add(OverView(
      key: 'recent:${r.displayOverNumber}:${r.key}',
      overNumber: r.displayOverNumber,
      labels: r.chips,
      runs: r.runs,
      bowler: r.bowler,
    ));
  }
  return out;
}
