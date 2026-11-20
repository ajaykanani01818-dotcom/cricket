import '../../core/api/json.dart';
import '../../core/utils/chase_summary.dart';
import '../../core/utils/fixture_status.dart';
import '../../core/utils/match_transform.dart';

/// Shared match parsing for every list screen (Home, Live, Matches, Search).
///
/// Data rules (research §0.3, PRD rule 7):
/// - Status comes from the provider's `status` word only. `isLive` is wrong
///   on NOT_STARTED and COMPLETED items, and score heuristics guess.
/// - Raw status words become sentence-case labels ([statusLabelFor]); a raw
///   "LIVE" never reaches the UI.
/// - No fake numbers: an upcoming match has no score, a chase line never says
///   "need 0 runs", and a missing value is hidden instead of shown as 0.

/// What the provider says the match is doing.
enum MatchPhase {
  /// In play ("LIVE").
  live,

  /// Started but not in play: stumps, breaks, delays, toss.
  paused,
  upcoming,
  result,
  noResult,
  abandoned,
  cancelled,

  /// Empty or unrecognised status word.
  unknown,
}

String _norm(String raw) => raw
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'[\s-]+'), '_')
    .replaceAll(RegExp(r'[^A-Z0-9_]'), '');

const _paused = {
  'STUMPS': 'Stumps',
  'INNINGS_BREAK': 'Innings break',
  'INNINGSBREAK': 'Innings break',
  'LUNCH': 'Lunch',
  'TEA': 'Tea',
  'DINNER': 'Dinner',
  'DRINKS': 'Drinks',
  'DRINKS_BREAK': 'Drinks',
  'STRATEGIC_TIMEOUT': 'Timeout',
  'RAIN': 'Rain delay',
  'RAIN_DELAY': 'Rain delay',
  'DELAY': 'Delayed',
  'DELAYED': 'Delayed',
  'BAD_LIGHT': 'Bad light',
  'WET_OUTFIELD': 'Wet outfield',
  'TOSS': 'Toss',
  'INTERRUPTED': 'Interrupted',
  'SUSPENDED': 'Suspended',
};

const _upcoming = {
  'NOT_STARTED',
  'NOTSTARTED',
  'SCHEDULED',
  'UPCOMING',
  'FIXTURE',
  'PRE_MATCH',
};

const _result = {
  'COMPLETED',
  'COMPLETE',
  'FINISHED',
  'RESULT',
  'ENDED',
  'TIED',
  'TIE',
  'DRAW',
  'DRAWN',
};

/// Phase for a raw provider status word ("LIVE", "NOT_STARTED", ...).
MatchPhase phaseForStatus(String raw) {
  final k = _norm(raw);
  if (k.isEmpty) return MatchPhase.unknown;
  if (k == 'LIVE' || k == 'IN_PROGRESS' || k == 'INPROGRESS') {
    return MatchPhase.live;
  }
  if (_paused.containsKey(k)) return MatchPhase.paused;
  if (k.contains('ABANDON')) return MatchPhase.abandoned;
  if (k == 'NO_RESULT' || k == 'NORESULT') return MatchPhase.noResult;
  if (k.contains('CANCEL') || k == 'WASH_OUT' || k == 'WASHOUT') {
    return MatchPhase.cancelled;
  }
  if (_upcoming.contains(k)) return MatchPhase.upcoming;
  if (_result.contains(k)) return MatchPhase.result;
  if (k.contains('LIVE')) return MatchPhase.live;
  if (k.contains('BREAK') || k.contains('DELAY')) return MatchPhase.paused;
  return MatchPhase.unknown;
}

/// "DRINKS_BREAK" -> "Drinks break".
String sentenceCase(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'[_\s]+'), ' ').toLowerCase();
  if (s.isEmpty) return '';
  return s[0].toUpperCase() + s.substring(1);
}

/// Sentence-case label for a raw status word: LIVE -> Live, NOT_STARTED ->
/// Upcoming, COMPLETED -> Result, STUMPS -> Stumps, NO_RESULT -> No result,
/// ABANDONED -> Abandoned. Unknown words are sentence-cased, never shouted.
String statusLabelFor(String raw) {
  final k = _norm(raw);
  final paused = _paused[k];
  if (paused != null) return paused;
  return switch (phaseForStatus(raw)) {
    MatchPhase.live => 'Live',
    MatchPhase.upcoming => 'Upcoming',
    MatchPhase.result => 'Result',
    MatchPhase.noResult => 'No result',
    MatchPhase.abandoned => 'Abandoned',
    MatchPhase.cancelled => 'Cancelled',
    MatchPhase.paused || MatchPhase.unknown => sentenceCase(raw),
  };
}

bool _isTest(String? format) =>
    RegExp(r'\bTEST\b').hasMatch((format ?? '').toUpperCase());

/// One line under a live score: the chase equation for limited-overs
/// matches ("India need 87 runs in 35 balls"), the lead for a Test
/// ("Pakistan lead by 37"), or null when there is nothing honest to say
/// (never "need 0 runs", never "in 0 balls").
String? liveEquationLine(JsonMap m) {
  if (J.text(J.at(m, 'result.message')) != null) return null;
  if (_isTest(J.text(m['format']))) return _testLeadLine(m);
  final c = computeChaseSummaryForLiveList(m);
  if (c == null || c.runsNeeded <= 0) return null;
  final runs = '${c.runsNeeded} ${c.runsNeeded == 1 ? 'run' : 'runs'}';
  final balls = c.ballsRemaining;
  if (balls == null || balls <= 0) return '${c.chasingTeamName} need $runs';
  return '${c.chasingTeamName} need $runs in $balls ${balls == 1 ? 'ball' : 'balls'}';
}

/// Test lead/trail, only while both first innings are the whole story
/// (list items carry one score string per team, so later innings are
/// ambiguous: hide instead of guessing).
String? _testLeadLine(JsonMap m) {
  final io = J.list(m['inningsOrder']).map((e) => '$e'.toLowerCase()).toList();
  if (io.length != 2) return null;
  final second = io[1].startsWith('t2') ? 't2' : 't1';
  final first = second == 't1' ? 't2' : 't1';
  final r1 = parseLeadingRunsFromScore(J.text(J.at(m, 'teams.$first.score')));
  final r2 = parseLeadingRunsFromScore(J.text(J.at(m, 'teams.$second.score')));
  if (r1 == null || r2 == null) return null;
  final name =
      J.text(J.at(m, 'teams.$second.short_name')) ??
      J.text(J.at(m, 'teams.$second.name'));
  if (name == null) return null;
  final d = r2 - r1;
  if (d == 0) return 'Scores level';
  return d > 0 ? '$name lead by $d' : '$name trail by ${-d}';
}

FixtureCardKind _kindFor(MatchPhase p) => switch (p) {
  MatchPhase.live || MatchPhase.paused => FixtureCardKind.live,
  MatchPhase.result => FixtureCardKind.completed,
  MatchPhase.abandoned => FixtureCardKind.abandoned,
  MatchPhase.noResult || MatchPhase.cancelled => FixtureCardKind.cancelled,
  MatchPhase.upcoming || MatchPhase.unknown => FixtureCardKind.scheduled,
};

/// Re-derives status, live flag, scores and status line of a transformed
/// match from the provider `status` field (see the rules at the top).
MatchSummary normalizeMatch(MatchSummary m) {
  final raw = m.raw;
  final rawStatus = J.str(raw['status']);
  final phase = phaseForStatus(rawStatus);
  final inProgress = phase == MatchPhase.live || phase == MatchPhase.paused;
  final label = statusLabelFor(rawStatus);
  final result = m.resultMessage?.trim();
  final equation = inProgress ? liveEquationLine(raw) : null;

  final String status;
  if (result != null && result.isNotEmpty) {
    status = result;
  } else if (equation != null) {
    status = equation;
  } else {
    status = label;
  }

  // An upcoming match has no score: "0/0" or "-" there would be a fake zero.
  final upcoming = phase == MatchPhase.upcoming;
  String? score(String? s) {
    final t = s?.trim();
    if (upcoming || t == null || t.isEmpty || t == '-') return null;
    return t;
  }

  return MatchSummary(
    id: m.id,
    team1: m.team1,
    team2: m.team2,
    team1Logo: m.team1Logo,
    team2Logo: m.team2Logo,
    team1Score: score(m.team1Score),
    team2Score: score(m.team2Score),
    status: status,
    rawStatus: rawStatus,
    venue: m.venue,
    date: m.date,
    isLive: inProgress,
    series: m.series,
    seriesKey: m.seriesKey,
    format: m.format,
    toss: m.toss,
    name: m.name,
    resultMessage: result == null || result.isEmpty ? null : result,
    winnerTeamKey: m.winnerTeamKey,
    manOfTheMatchKey: m.manOfTheMatchKey,
    chaseSummaryLine: equation,
    fixtureCardKind: _kindFor(phase),
    raw: raw,
  );
}

/// Transforms an API match list once when it arrives (never in build).
/// Malformed entries (non-maps) are skipped; missing fields degrade to ''.
List<MatchSummary> parseMatchList(dynamic data) => [
  for (final m in transformApiMatches(J.maps(data))) normalizeMatch(m),
];

/// Status helpers for the cards and screens.
extension MatchStatusX on MatchSummary {
  MatchPhase get phase => phaseForStatus(rawStatus);

  /// Sentence-case chip text ("Live", "Stumps", "Result", "Upcoming").
  String get statusLabel => statusLabelFor(rawStatus);

  /// Live or paused (stumps, breaks): the match has started and not ended.
  bool get isInProgress =>
      phase == MatchPhase.live || phase == MatchPhase.paused;
  bool get isInPlay => phase == MatchPhase.live;
  bool get isUpcoming => phase == MatchPhase.upcoming;

  /// Finished one way or another (result, no result, abandoned, cancelled).
  bool get isFinished =>
      phase == MatchPhase.result ||
      phase == MatchPhase.noResult ||
      phase == MatchPhase.abandoned ||
      phase == MatchPhase.cancelled;

  /// The line under the teams, or null when it would only repeat the chip.
  String? get statusLine {
    final s = status.trim();
    if (s.isEmpty || s == statusLabel) return null;
    if (_norm(s) == _norm(rawStatus)) return null; // raw "LIVE" etc.
    return s;
  }

  /// 1 or 2 when `result.winnerTeamKey` names one of the teams.
  int? get winnerSide {
    final w = winnerTeamKey?.trim().toLowerCase();
    if (w == null || w.isEmpty) return null;
    String k(String t) =>
        (J.text(J.at(raw, 'teams.$t.key')) ?? '').trim().toLowerCase();
    if (k('t1') == w) return 1;
    if (k('t2') == w) return 2;
    return null;
  }

  String? shortName(int side) => J.text(J.at(raw, 'teams.t$side.short_name'));

  /// Score text for a team row: the score, "—" while the side is yet to
  /// bat in a match in progress, otherwise null (hide).
  String? displayScore(int side) {
    final s = side == 1 ? team1Score : team2Score;
    if (s != null) return s;
    return isInProgress ? '—' : null;
  }

  /// Provider `updatedAt` (ISO), local time.
  DateTime? get updatedAt =>
      DateTime.tryParse(J.str(raw['updatedAt']))?.toLocal();

  /// Labels of the current over's balls when the item carries them
  /// (`currentOver.balls[].value`, match-by-id payloads); empty otherwise.
  List<String> get currentOverBalls => [
    for (final b in J.maps(J.at(raw, 'currentOver.balls')))
      if (J.text(b['value']) != null) J.text(b['value'])!,
  ];

  int? get currentOverNumber => J.integer(J.at(raw, 'currentOver.overNumber'));
}
