import '../api/json.dart';

/// Ported from RN `src/utils/chaseSummary.ts`.
int? parseLeadingRunsFromScore(String? score) {
  final s = score?.trim() ?? '';
  if (s.isEmpty || s == '-') return null;
  final m = RegExp(r'^(\d+)').firstMatch(s);
  return m == null ? null : int.tryParse(m.group(1)!);
}

String? parseOversFromScoreParen(String? score) {
  if (score == null) return null;
  final m = RegExp(r'\(([\d.]+)\)').firstMatch(score);
  return m?.group(1)?.trim();
}

int oversToLegalBallsCompleted(String oversStr) {
  final s = oversStr.trim();
  final dot = s.indexOf('.');
  if (dot == -1) return (int.tryParse(s) ?? 0) * 6;
  final whole = int.tryParse(s.substring(0, dot)) ?? 0;
  var frac = int.tryParse(s.substring(dot + 1)) ?? 0;
  if (frac > 5) frac = 5;
  return whole * 6 + frac;
}

int? inferMaxOversFromFormat(String? format) {
  final f = (format ?? '').toUpperCase();
  if (RegExp(r'\bTEST\b').hasMatch(f)) return null;
  if (RegExp(r'\bT10\b').hasMatch(f)) return 10;
  if (RegExp(r'\b(ODI|OD\b|50\s*OVER|ONE[\s-]*DAY)').hasMatch(f)) return 50;
  if (RegExp(r'\b(T20|TWENTY|20\s*OVER)').hasMatch(f)) return 20;
  return null;
}

class ChaseSummary {
  final int runsNeeded;
  final int? ballsRemaining;
  final String chasingTeamName;
  const ChaseSummary(this.runsNeeded, this.ballsRemaining, this.chasingTeamName);
}

ChaseSummary? computeChaseSummaryForLiveList(JsonMap m) {
  if (J.text(J.at(m, 'result.message')) != null) return null;
  final t1s = J.text(J.at(m, 'teams.t1.score'));
  final t2s = J.text(J.at(m, 'teams.t2.score'));
  if (t1s == null || t2s == null) return null;

  String chasing;
  final io = J.list(m['inningsOrder']).map((e) => e.toString().toLowerCase()).toList();
  final cur = J.str(m['currentInning']).toLowerCase();
  if (io.length >= 2) {
    chasing = io[1].startsWith('t2') ? 't2' : 't1';
  } else if (io.length == 1) {
    if (cur.isEmpty || cur == io[0]) return null;
    final fromCur = cur.startsWith('t2') ? 't2' : 't1';
    final fromIo = io[0].startsWith('t2') ? 't2' : 't1';
    if (fromCur == fromIo) return null;
    chasing = fromCur;
  } else {
    if (cur.isEmpty) return null;
    if (cur.startsWith('t2') || cur.contains('t2_')) {
      chasing = 't2';
    } else if (cur.startsWith('t1') || cur.contains('t1_')) {
      chasing = 't1';
    } else {
      return null;
    }
  }
  final firstBatting = chasing == 't1' ? 't2' : 't1';
  final firstScore = firstBatting == 't1' ? t1s : t2s;
  final chaseScore = chasing == 't1' ? t1s : t2s;
  final firstRuns = parseLeadingRunsFromScore(firstScore);
  final chaseRuns = parseLeadingRunsFromScore(chaseScore);
  if (firstRuns == null || chaseRuns == null) return null;

  final target = J.integer(m['targetRuns']) ?? firstRuns + 1;
  final runsNeeded = (target - chaseRuns).clamp(0, 1 << 30);

  num? maxOvers = J.number(m['maxOvers']);
  if (maxOvers != null && maxOvers <= 0) maxOvers = null;
  maxOvers ??= inferMaxOversFromFormat(J.str(m['format']));

  int? ballsRemaining;
  final chaseOvers = parseOversFromScoreParen(chaseScore);
  if (maxOvers != null && maxOvers > 0 && chaseOvers != null) {
    final maxBalls = (maxOvers * 6).round();
    ballsRemaining = (maxBalls - oversToLegalBallsCompleted(chaseOvers)).clamp(0, 1 << 30);
  }
  final name = J.text(J.at(m, 'teams.$chasing.name')) ?? 'Team';
  return ChaseSummary(runsNeeded, ballsRemaining, name);
}
