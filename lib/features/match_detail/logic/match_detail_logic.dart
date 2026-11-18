/// Pure helpers / transforms ported from RN `src/screens/MatchDetailScreen.tsx`
/// and `src/components/match/matchUtils.ts`. Everything here is synchronous,
/// side-effect free and unit-tested (test/match_detail/match_detail_logic_test.dart).
library;

import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../core/api/json.dart';
import 'commentary_html.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Date / score formatting
// ─────────────────────────────────────────────────────────────────────────────

/// Normalize API `timestamp` to Unix seconds (API uses seconds e.g. 1770471000).
/// Handles string JSON numbers and ms vs s heuristics.
int? parseMatchStartTimestampSeconds(dynamic raw) {
  if (raw == null || raw == '') return null;
  final double? n = raw is num ? raw.toDouble() : double.tryParse(raw.toString().trim().replaceAll(',', ''));
  if (n == null || !n.isFinite || n <= 0) return null;
  // Values this large are almost always epoch milliseconds
  if (n > 1e12) return (n / 1000).floor();
  return n.floor();
}

/// Match start: prefer `timestamp`, then ISO `startDate` — device local time.
/// e.g. "Sun, Nov 15, 2026 · 1:30 PM". Null when neither parses.
String? formatMatchDateTime(String? startDate, dynamic timestamp) {
  DateTime? d;
  final sec = parseMatchStartTimestampSeconds(timestamp);
  if (sec != null) d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  if (d == null && startDate != null && startDate.trim().isNotEmpty) {
    d = DateTime.tryParse(startDate.trim())?.toLocal();
  }
  if (d == null) return null;
  return '${DateFormat('EEE, MMM d, y', 'en_US').format(d)} · ${DateFormat('h:mm a', 'en_US').format(d)}';
}

/// U+2060 word joiner — discourages line break between adjacent glyphs.
const wj = '⁠';
const nbsp = ' ';

String guardScoreDecimalsAndSpaces(String fragment) =>
    fragment.replaceAll(RegExp(r'\s+'), nbsp).replaceAllMapped(RegExp(r'\.(\d)'), (m) => '.$wj${m.group(1)}');

/// One-line team score: avoid breaks after `/`, inside decimals (48.5), and before `)`.
String formatTeamScoreLine(String runs, String wickets, [String? overs]) {
  final core = '$runs$wj/$wj$wickets';
  if (overs == null || overs.isEmpty) return core;
  final o = guardScoreDecimalsAndSpaces(overs.trim());
  return '$core$nbsp($wj$o$wj)';
}

String formatTeamScoreFromApi(String? score) {
  final s = (score == null || score.isEmpty ? '-' : score).trim();
  if (s == '-' || s.isEmpty) return '-';
  var t = s.replaceAll(RegExp(r'\s+'), nbsp);
  t = t.replaceAllMapped(RegExp(r'(\d+)/(\d+)'), (m) => '${m.group(1)}$wj/$wj${m.group(2)}');
  t = guardScoreDecimalsAndSpaces(t);
  t = t.replaceAllMapped(RegExp(r'(\S)(?=\))'), (m) => '${m.group(1)}$wj');
  return t;
}

/// Removes the invisible joiners (handy for tests / semantics).
String stripJoiners(String s) => s.replaceAll(wj, '').replaceAll(nbsp, ' ');

class TeamScore {
  final String runs, wickets;
  final String? overs;
  const TeamScore(this.runs, this.wickets, [this.overs]);

  String get display => formatTeamScoreLine(runs, wickets, overs);

  @override
  bool operator ==(Object other) => other is TeamScore && other.runs == runs && other.wickets == wickets && other.overs == overs;
  @override
  int get hashCode => Object.hash(runs, wickets, overs);
}

/// "386/7 (90.0)" -> TeamScore. Null when the string doesn't have that shape.
TeamScore? parseScore(String? score) {
  if (score == null || score.isEmpty) return null;
  final m = RegExp(r'(\d+)/(\d+)\s*\(([\d.]+)\)').firstMatch(score);
  if (m == null) return null;
  return TeamScore(m.group(1)!, m.group(2)!, m.group(3)!);
}

TeamScore? teamScoreFromInningsStats(dynamic stats) {
  if (stats is! Map) return null;
  final m = J.map(stats);
  final runs = J.text(m['runs']);
  final wkts = J.text(m['wickets']);
  if (runs == null && wkts == null) return null;
  return TeamScore(runs ?? '0', wkts ?? '0', J.text(m['overs']));
}

// ─────────────────────────────────────────────────────────────────────────────
// Poll fingerprints (skip setState when nothing changed)
// ─────────────────────────────────────────────────────────────────────────────

String _safeEncode(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '${DateTime.now().microsecondsSinceEpoch}';
  }
}

/// Stable snapshot for poll deduping — avoids full-screen rebuilds when nothing changed.
String matchDetailPollFingerprint(JsonMap m) => _safeEncode({
      't1s': J.at(m, 'teams.t1.score'),
      't2s': J.at(m, 'teams.t2.score'),
      'st': m['status'],
      'res': m['result'],
      'co': m['currentOver'],
      'il': m['isLive'],
      'io': m['inningsOrder'],
      'wx': m['weather'],
    });

/// Stable snapshot of the scorecard, so the 10s poll only rebuilds on real change.
String scorecardPollFingerprint(JsonMap? s) {
  if (s == null) return '';
  return _safeEncode(s['result'] ?? s);
}

/// So live polls refresh when only recentOvers changes (ball-by-ball).
String liveRecentOversFingerprint(dynamic recentOvers) {
  final overs = J.list(recentOvers);
  if (overs.isEmpty) return '';
  return overs.map((over) {
    final balls = J.maps(over).where((b) => b['type'] == 'ball').toList();
    var ts = 0;
    for (final b in balls) {
      final t = J.integer(b['commentaryTimestamp']) ?? 0;
      if (t > ts) ts = t;
    }
    final sig = balls.map((b) => '${J.str(b['overNumber'])}-${J.str(b['ballNumber'])}-${J.str(b['value'])}').join(',');
    return '$ts:$sig';
  }).join('||');
}

String livePollFingerprint(JsonMap? d) {
  if (d == null || d['score'] is! Map) return '';
  final s = J.map(d['score']);
  final balls = J.list(d['balls']);
  return _safeEncode({
    't1': J.at(s, 'teams.team1.inningsStats'),
    't2': J.at(s, 'teams.team2.inningsStats'),
    'io': s['inningsOrder'],
    'fl': s['flag'],
    'st': s['striker'],
    'ns': s['nonStriker'],
    'bw': s['bowler'],
    'bl': balls.length,
    'lb': balls.isEmpty ? null : balls.last,
    'ro': liveRecentOversFingerprint(d['recentOvers']),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Over / ball helpers
// ─────────────────────────────────────────────────────────────────────────────

int inferRunsFromChip(String v) {
  final s = v.trim();
  if (RegExp(r'^\d+$').hasMatch(s)) return int.parse(s);
  final leg = RegExp(r'^L(\d+)$', caseSensitive: false).firstMatch(s);
  if (leg != null) return int.tryParse(leg.group(1)!) ?? 0;
  return 0;
}

/// Dismissal only — not WD (wide) / NB (no ball) / runs-with-wicket extras.
bool isWicketChip(String v) {
  final u = v.trim().toUpperCase();
  return u == 'W' || u == 'WK' || u == 'WKT';
}

class RunsWickets {
  final int runs, wickets;
  const RunsWickets(this.runs, this.wickets);
  @override
  bool operator ==(Object other) => other is RunsWickets && other.runs == runs && other.wickets == wickets;
  @override
  int get hashCode => Object.hash(runs, wickets);
  @override
  String toString() => 'RunsWickets($runs, $wickets)';
}

RunsWickets deriveRunsWicketsFromChips(List<String> chips) {
  var runs = 0, wickets = 0;
  for (final v in chips) {
    if (isWicketChip(v)) {
      wickets += 1;
    } else {
      runs += inferRunsFromChip(v);
    }
  }
  return RunsWickets(runs, wickets);
}

/// First candidate that is a finite number > 0 (floored).
int? positiveOverNumber(List<dynamic> candidates) {
  for (final c in candidates) {
    if (c is num && c.isFinite && c > 0) return c.floor();
  }
  return null;
}

bool _isRealBall(JsonMap b) => b['type'] == 'ball' && b['value'] != null && J.str(b['value']).trim().isNotEmpty;

class RecentOverRow {
  final String key;
  final int displayOverNumber;
  final int runs, wickets;
  final String? bowler;
  final List<String> chips;
  const RecentOverRow({
    required this.key,
    required this.displayOverNumber,
    required this.runs,
    required this.wickets,
    this.bowler,
    required this.chips,
  });
}

List<RecentOverRow> buildRecentOverRows(dynamic recentOvers) {
  final overs = J.list(recentOvers);
  if (overs.isEmpty) return const [];
  final rows = <RecentOverRow>[];
  for (var idx = 0; idx < overs.length; idx++) {
    final ballItems = J.maps(overs[idx]).where(_isRealBall).toList();
    if (ballItems.isEmpty) continue;
    final summaryBall = ballItems.firstWhere((b) => b['overSummary'] is Map, orElse: () => ballItems.first);
    final os = summaryBall['overSummary'] is Map ? J.map(summaryBall['overSummary']) : null;
    List<String> chips;
    final osb = J.list(os?['overSummaryBalls']);
    if (osb.isNotEmpty) {
      chips = osb.map((x) => J.str(x)).toList();
    } else {
      final sorted = [...ballItems]
        ..sort((a, b) => (J.number(a['ballNumber']) ?? 0).compareTo(J.number(b['ballNumber']) ?? 0));
      chips = sorted.map((b) => J.str(b['value'])).toList();
    }
    chips = chips.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    if (chips.isEmpty) continue;
    final derived = deriveRunsWicketsFromChips(chips);
    final rio = os?['runsInOver'];
    final runs = rio is num && rio.isFinite && rio >= 0 ? rio.toInt() : derived.runs;
    final displayOverNumber =
        positiveOverNumber([os?['overNumber'], summaryBall['overNumber'], ballItems.first['overNumber']]) ?? idx + 1;
    final bowler = J.text(J.at(os, 'bowlerStats.name'));
    final key = '$displayOverNumber-${J.str(os?['totalScore'])}-${J.str(summaryBall['commentaryTimestamp'], '$idx')}';
    rows.add(RecentOverRow(
      key: key,
      displayOverNumber: displayOverNumber,
      runs: runs,
      wickets: derived.wickets,
      bowler: bowler,
      chips: chips,
    ));
  }
  return rows;
}

enum BallTone { four, six, wicket, dot, run }

/// RN getBallColor: 4 → gold, 6 → goldLight, W/WK/WD/NB → error, 0 → dot, else run.
BallTone ballTone(String? value) {
  final v = (value ?? '').trim();
  if (v == '4') return BallTone.four;
  if (v == '6') return BallTone.six;
  if (v == 'W' || v == 'WK' || v == 'WD' || v == 'NB') return BallTone.wicket;
  if (v == '0') return BallTone.dot;
  return BallTone.run;
}

// ─────────────────────────────────────────────────────────────────────────────
// Match detail view-model (parsed once per response)
// ─────────────────────────────────────────────────────────────────────────────

class TeamVM {
  final String name;
  final String? logo;
  final String? score;
  const TeamVM({required this.name, this.logo, this.score});

  factory TeamVM.fromJson(dynamic v) {
    final m = J.map(v);
    return TeamVM(name: J.text(m['name']) ?? 'TBD', logo: J.text(m['logo']), score: J.text(m['score']));
  }
}

class WeatherVM {
  final String condition, temperature, wind, humidity, rainForecast;
  const WeatherVM(this.condition, this.temperature, this.wind, this.humidity, this.rainForecast);

  static WeatherVM? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = J.map(v);
    return WeatherVM(J.str(m['condition'], '-'), J.str(m['temperature'], '-'), J.str(m['wind'], '-'),
        J.str(m['humidity'], '-'), J.str(m['rainForecast'], '-'));
  }
}

/// One ball shown as a chip in the Current Over card.
class BallChip {
  final String key;
  final String value;
  const BallChip(this.key, this.value);
}

class CurrentOverVM {
  final int? titleOverNumber;
  final int displayRuns, displayWickets;
  final List<BallChip> balls;
  const CurrentOverVM({this.titleOverNumber, required this.displayRuns, required this.displayWickets, required this.balls});

  String get title => titleOverNumber != null ? 'Current Over ($titleOverNumber)' : 'Current Over';
  String get statsLine =>
      '$displayRuns run${displayRuns != 1 ? 's' : ''} • $displayWickets wicket${displayWickets != 1 ? 's' : ''}';

  /// Null when there are no real ball rows (card hidden — same as RN).
  static CurrentOverVM? fromJson(dynamic v) {
    if (v is! Map) return null;
    final co = J.map(v);
    final items = J.maps(co['balls']).where(_isRealBall).toList();
    if (items.isEmpty) return null;
    final sorted = [...items]
      ..sort((a, b) => (J.number(a['ballNumber']) ?? 0).compareTo(J.number(b['ballNumber']) ?? 0));
    final withSummary = sorted.firstWhere((b) => J.list(J.at(b, 'overSummary.overSummaryBalls')).isNotEmpty,
        orElse: () => const <String, dynamic>{});
    final osb = J.list(J.at(withSummary, 'overSummary.overSummaryBalls'));
    final chips = (osb.isNotEmpty ? osb.map((x) => J.str(x).trim()) : sorted.map((b) => J.str(b['value']).trim()))
        .where((s) => s.isNotEmpty)
        .toList();
    if (chips.isEmpty) return null;
    final derived = deriveRunsWicketsFromChips(chips);
    final r = co['runs'];
    final runs = r is num && r.isFinite && r >= 0 ? r.toInt() : derived.runs;
    final title = positiveOverNumber([co['overNumber'], items.last['overNumber']]);
    return CurrentOverVM(
      titleOverNumber: title,
      displayRuns: runs,
      displayWickets: derived.wickets,
      balls: [
        for (var i = 0; i < items.length; i++)
          BallChip('${J.str(items[i]['overNumber'])}-${J.str(items[i]['ballNumber'])}-$i', J.str(items[i]['value']).trim()),
      ],
    );
  }
}

/// RN `isLive` memo for the detail screen.
bool deriveDetailIsLive(JsonMap m) {
  if (J.text(J.at(m, 'result.message')) != null) return false;
  final raw = J.str(m['status']);
  final status = raw.toUpperCase();
  const finished = ['COMPLETED', 'FINISHED', 'ENDED', 'ABANDONED', 'CANCELLED'];
  if (finished.any(status.contains)) return false;
  if (m['isLive'] != null) return J.boolean(m['isLive']);
  return raw == 'LIVE' || status.contains('LIVE');
}

bool deriveIsMatchWon(JsonMap m) => J.text(J.at(m, 'result.message')) != null;

bool isCompletedForMom(String status) {
  final s = status.toUpperCase();
  return s == 'COMPLETED' || s == 'FINISHED' || s == 'COMPLETE';
}

class MatchDetailVM {
  final JsonMap raw;
  final String id; // _id
  final String seriesName;
  final String? seriesKey;
  final String metaLine; // format · ground
  final String? toss;
  final TeamVM t1, t2;
  final String status;
  final String? resultMessage;
  final bool isLive, isMatchWon;
  final String momKey; // '' when absent
  final bool momEligible; // completed + key
  final WeatherVM? weather;
  final CurrentOverVM? currentOver;
  final List<String> inningsOrder;
  final List<CommentaryBall> currentOverCommentaryBalls;
  final String? dateTimeLabel;
  final String fingerprint;

  const MatchDetailVM({
    required this.raw,
    required this.id,
    required this.seriesName,
    this.seriesKey,
    required this.metaLine,
    this.toss,
    required this.t1,
    required this.t2,
    required this.status,
    this.resultMessage,
    required this.isLive,
    required this.isMatchWon,
    required this.momKey,
    required this.momEligible,
    this.weather,
    this.currentOver,
    required this.inningsOrder,
    required this.currentOverCommentaryBalls,
    this.dateTimeLabel,
    required this.fingerprint,
  });

  factory MatchDetailVM.fromJson(JsonMap m) {
    final status = J.str(m['status']);
    final momKey = J.text(J.at(m, 'result.menOfTheMatchKey')) ?? '';
    return MatchDetailVM(
      raw: m,
      id: J.str(m['_id']),
      seriesName: J.str(m['seriesName']),
      seriesKey: J.text(m['sb_series_key']),
      metaLine: [J.text(m['format']), J.text(m['ground'])].whereType<String>().join(' · '),
      toss: J.text(m['toss']),
      t1: TeamVM.fromJson(J.at(m, 'teams.t1')),
      t2: TeamVM.fromJson(J.at(m, 'teams.t2')),
      status: status,
      resultMessage: J.text(J.at(m, 'result.message')),
      isLive: deriveDetailIsLive(m),
      isMatchWon: deriveIsMatchWon(m),
      momKey: momKey,
      momEligible: isCompletedForMom(status) && momKey.isNotEmpty,
      weather: WeatherVM.fromJson(m['weather']),
      currentOver: CurrentOverVM.fromJson(m['currentOver']),
      inningsOrder: J.list(m['inningsOrder']).map((e) => J.str(e)).toList(),
      currentOverCommentaryBalls: () {
        final list = J.maps(J.at(m, 'currentOver.balls')).where((b) => J.text(b['commentary']) != null).toList();
        return [for (var i = 0; i < list.length; i++) CommentaryBall.fromJson(list[i], i)];
      }(),
      dateTimeLabel: formatMatchDateTime(J.text(m['startDate']), m['timestamp']),
      fingerprint: matchDetailPollFingerprint(m),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batting / bowling rows
// ─────────────────────────────────────────────────────────────────────────────

String _cell(dynamic v, [String fallback = '-']) => J.text(v) ?? fallback;

String _fixed2(dynamic v) {
  final n = J.number(v);
  return n == null ? '0.00' : n.toStringAsFixed(2);
}

/// `a || b` in JS for numeric-ish values (0 / '' / null fall through).
dynamic _or(dynamic a, dynamic b) {
  if (a == null || a == '' || a == 0 || a == false) return b;
  return a;
}

class BatterRow {
  final String key;
  final String name;
  final String runs, balls, fours, sixes, strikeRate;
  final bool notOut; // green + ' *' style
  final bool star;
  final String? outSummary;
  const BatterRow({
    required this.key,
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    required this.notOut,
    required this.star,
    this.outSummary,
  });

  String get displayName => star ? '$name *' : name;
}

class BowlerRow {
  final String key;
  final String name, overs, maidens, runs, wickets, economy;
  const BowlerRow({
    required this.key,
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
  });
}

/// Live API striker / nonStriker. Live API often drops one of them briefly
/// after a wicket — never require both.
List<BatterRow> liveBattingPair(JsonMap? score) {
  if (score == null) return const [];
  final entries = <(String, JsonMap)>[
    if (score['striker'] is Map) ('striker', J.map(score['striker'])),
    if (score['nonStriker'] is Map) ('nonStriker', J.map(score['nonStriker'])),
  ];
  final sole = entries.length == 1;
  return [
    for (var i = 0; i < entries.length; i++)
      BatterRow(
        key: '${entries[i].$1}-${J.str(entries[i].$2['name'], '$i')}',
        name: J.str(entries[i].$2['name'], '-'),
        runs: _cell(entries[i].$2['runs']),
        balls: _cell(entries[i].$2['ballsFaced']),
        fours: J.str(_or(entries[i].$2['fours'], 0)),
        sixes: J.str(_or(entries[i].$2['sixes'], 0)),
        strikeRate: _fixed2(entries[i].$2['strikeRate']),
        notOut: true,
        star: entries[i].$1 == 'striker' || sole,
      ),
  ];
}

BowlerRow? liveBowlerRow(JsonMap? score) {
  if (score == null || score['bowler'] is! Map) return null;
  final b = J.map(score['bowler']);
  return BowlerRow(
    key: 'live-${J.str(b['name'])}',
    name: J.str(b['name'], '-'),
    overs: _cell(b['oversBowled']),
    maidens: _cell(b['maidens']),
    runs: _cell(b['runsConceded']),
    wickets: _cell(b['wickets']),
    economy: _fixed2(b['economy']),
  );
}

JsonMap? lastScorecardInning(JsonMap? scorecardData) {
  final innings = J.maps(J.at(scorecardData, 'result.innings'));
  return innings.isEmpty ? null : innings.last;
}

/// Scorecard (last innings) first two batters — Live tab fallback.
List<BatterRow> scorecardBatters(JsonMap? lastInning) {
  final list = J.maps(lastInning?['batting']).take(2).toList();
  return [
    for (var i = 0; i < list.length; i++)
      () {
        final b = list[i];
        final isOut = J.boolean(b['isOut']);
        final out = isOut ? J.text(b['outSummary']) : null;
        return BatterRow(
          key: J.text(b['_id']) ?? 'bat-$i',
          name: J.text(b['playerName']) ?? J.str(b['name'], '-'),
          runs: _cell(b['runs']),
          balls: _cell(b['ballsFaced']),
          fours: J.str(_or(b['fours'], 0)),
          sixes: J.str(_or(b['sixes'], 0)),
          strikeRate: _fixed2(b['strikeRate']),
          notOut: !isOut,
          star: !isOut,
          outSummary: out,
        );
      }(),
  ];
}

/// Scorecard (last innings) first five bowlers — Live tab fallback.
List<BowlerRow> scorecardBowlers(JsonMap? lastInning) {
  final list = J.maps(lastInning?['bowling']).take(5).toList();
  return [
    for (var i = 0; i < list.length; i++)
      BowlerRow(
        key: J.text(list[i]['_id']) ?? 'bowl-$i',
        name: J.text(list[i]['playerName']) ?? J.str(list[i]['name'], '-'),
        overs: J.str(_or(list[i]['overs'], list[i]['oversBowled']), '-'),
        maidens: J.str(_or(list[i]['maidens'], 0)),
        runs: J.str(_or(list[i]['runsConceded'], 0)),
        wickets: J.str(_or(list[i]['wickets'], 0)),
        economy: list[i]['economyRate'] != null ? _fixed2(list[i]['economyRate']) : _fixed2(list[i]['economy']),
      ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Live data view-model
// ─────────────────────────────────────────────────────────────────────────────

class CommentaryBall {
  final String key;
  final String value;
  final String? overNumber; // display
  final String ballNumber; // display ('' when absent)
  final int timestamp; // ms
  final String inningsIndex;
  final String type;
  final bool hasCommentary;
  final List<CommentaryTextRun> textRuns; // parsed once

  const CommentaryBall({
    required this.key,
    required this.value,
    this.overNumber,
    required this.ballNumber,
    required this.timestamp,
    required this.inningsIndex,
    required this.type,
    required this.hasCommentary,
    required this.textRuns,
  });

  factory CommentaryBall.fromJson(JsonMap b, [int index = 0]) {
    final html = J.str(b['commentary']);
    final ts = J.integer(b['commentaryTimestamp']) ?? 0;
    final over = J.text(b['overNumber']);
    final ball = J.str(b['ballNumber']);
    final inn = J.str(b['inningsIndex']);
    final type = J.str(b['type']);
    return CommentaryBall(
      key: '$inn|$over|$ball|$ts|$type|${ts == 0 ? index : ''}',
      value: J.str(b['value']).trim(),
      overNumber: over,
      ballNumber: ball,
      timestamp: ts,
      inningsIndex: inn,
      type: type,
      hasCommentary: html.trim().isNotEmpty,
      textRuns: parseCommentaryRuns(html),
    );
  }

  bool get isBallWithCommentary => type == 'ball' && hasCommentary;

  /// RN: WD/NB → 1; W/WK → 0; else parseInt(value) || 0.
  int get runs => commentaryBallRuns(value);

  String get overLabel => '${overNumber ?? ''}.$ballNumber';
}

int commentaryBallRuns(String value) {
  if (value == 'WD' || value == 'NB') return 1;
  if (value == 'W' || value == 'WK') return 0;
  final m = RegExp(r'^\s*[+-]?\d+').firstMatch(value);
  return m == null ? 0 : int.tryParse(m.group(0)!.trim()) ?? 0;
}

/// en-US "hh:mm AM" (RN toLocaleTimeString('en-US', {hour:'2-digit', minute:'2-digit', hour12:true})).
String commentaryTime(int timestampMs) {
  if (timestampMs <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return DateFormat('hh:mm a', 'en_US').format(d);
}

class LiveVM {
  final JsonMap raw;
  final JsonMap? score;
  final TeamScore? team1, team2;
  final List<String> inningsOrder;
  final int? flag;
  final String? firstBallInningsIndex;
  final List<BatterRow> battingPair;
  final BowlerRow? bowler;
  final List<RecentOverRow> recentOvers;
  final List<CommentaryBall> commentaryBalls; // type ball + commentary
  final String fingerprint;

  const LiveVM({
    required this.raw,
    this.score,
    this.team1,
    this.team2,
    required this.inningsOrder,
    this.flag,
    this.firstBallInningsIndex,
    required this.battingPair,
    this.bowler,
    required this.recentOvers,
    required this.commentaryBalls,
    required this.fingerprint,
  });

  factory LiveVM.fromJson(JsonMap d) {
    final score = d['score'] is Map ? J.map(d['score']) : null;
    final balls = J.maps(d['balls']);
    final withInnings = balls.firstWhere((b) => J.text(b['inningsIndex']) != null, orElse: () => const {});
    return LiveVM(
      raw: d,
      score: score,
      team1: teamScoreFromInningsStats(J.at(score, 'teams.team1.inningsStats')),
      team2: teamScoreFromInningsStats(J.at(score, 'teams.team2.inningsStats')),
      inningsOrder: J.list(score?['inningsOrder']).map((e) => J.str(e)).toList(),
      flag: J.integer(score?['flag']),
      firstBallInningsIndex: J.text(withInnings['inningsIndex']),
      battingPair: liveBattingPair(score),
      bowler: liveBowlerRow(score),
      recentOvers: buildRecentOverRows(d['recentOvers']),
      commentaryBalls: [
        for (var i = 0; i < balls.length; i++)
          if (balls[i]['type'] == 'ball' && J.text(balls[i]['commentary']) != null) CommentaryBall.fromJson(balls[i], i),
      ],
      fingerprint: livePollFingerprint(d),
    );
  }
}

enum TeamSide { team1, team2 }

/// RN getBattingTeamKey.
TeamSide battingTeamKey({LiveVM? live, required List<String> detailInningsOrder}) {
  final idx = live?.firstBallInningsIndex;
  if (idx != null) return idx.contains('t1') ? TeamSide.team1 : TeamSide.team2;
  final order = (live != null && live.inningsOrder.isNotEmpty) ? live.inningsOrder : detailInningsOrder;
  if (order.isNotEmpty) return order.last.contains('t1') ? TeamSide.team1 : TeamSide.team2;
  if (live?.flag != null) return live!.flag == 1 ? TeamSide.team1 : TeamSide.team2;
  return TeamSide.team2;
}

/// Header score line for a team: live inningsStats first, then parsed API
/// score, else the raw API score formatted.
String headerScoreText({TeamScore? live, String? apiScore}) {
  if (live != null) return live.display;
  final parsed = parseScore(apiScore);
  if (parsed != null) return parsed.display;
  return formatTeamScoreFromApi(apiScore ?? '-');
}

/// Live tab commentary list: live balls if any, else current over balls with commentary. Max 20.
List<CommentaryBall> liveTabCommentary(LiveVM? live, MatchDetailVM match) {
  final rawBalls = J.list(live?.raw['balls']);
  final source = rawBalls.isNotEmpty ? live!.commentaryBalls : match.currentOverCommentaryBalls;
  return source.take(20).toList(growable: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Commentary tab
// ─────────────────────────────────────────────────────────────────────────────

const commentaryPageSize = 60;

enum CommentaryFilter { all, six, four, wicket }

String commentaryFilterLabel(CommentaryFilter f) => switch (f) {
      CommentaryFilter.all => 'All',
      CommentaryFilter.six => '6s',
      CommentaryFilter.four => '4s',
      CommentaryFilter.wicket => 'Wickets',
    };

class CommentaryPage {
  final List<CommentaryBall> balls;
  final int totalCount;
  final String? team1Name, team2Name;
  final bool hasTeams;
  const CommentaryPage({required this.balls, required this.totalCount, this.team1Name, this.team2Name, this.hasTeams = false});

  factory CommentaryPage.fromJson(JsonMap data, {int indexOffset = 0}) {
    final balls = J.maps(data['balls']);
    final teams = J.at(data, 'score.teams');
    return CommentaryPage(
      balls: [for (var i = 0; i < balls.length; i++) CommentaryBall.fromJson(balls[i], indexOffset + i)],
      totalCount: J.integer(data['totalCount']) ?? 0,
      hasTeams: teams is Map,
      team1Name: J.text(J.at(teams, 'team1.name')),
      team2Name: J.text(J.at(teams, 'team2.name')),
    );
  }
}

/// RN: newBalls.length === PAGE_SIZE && page * PAGE_SIZE < totalCount
bool commentaryHasMore({required int received, required int page, required int totalCount, int pageSize = commentaryPageSize}) =>
    received == pageSize && page * pageSize < totalCount;

/// Appends [incoming] skipping balls already present (guards against
/// overlapping pages when new balls shift the server-side pagination).
List<CommentaryBall> mergeCommentary(List<CommentaryBall> existing, List<CommentaryBall> incoming) {
  final seen = {for (final b in existing) b.key};
  return [
    ...existing,
    for (final b in incoming)
      if (seen.add(b.key)) b,
  ];
}

/// innings keys in first-seen order (e.g. t1_1, t2_1).
List<String> uniqueInningsKeys(List<CommentaryBall> balls) {
  final out = <String>{};
  for (final b in balls) {
    if (b.inningsIndex.isNotEmpty) out.add(b.inningsIndex);
  }
  return out.toList(growable: false);
}

String commentaryTeamName(String inningsIndex, CommentaryPage? page) {
  if (page != null && page.hasTeams) {
    if (inningsIndex.contains('t1')) return page.team1Name ?? 'Team 1';
    if (inningsIndex.contains('t2')) return page.team2Name ?? 'Team 2';
  }
  return inningsIndex.isNotEmpty ? inningsIndex : 'Unknown Team';
}

/// Team + event filter, newest first (RN filteredBalls). Does NOT drop
/// non-ball rows — the renderer does that (RN shows the "no match" message
/// only when this list is empty).
List<CommentaryBall> filterCommentary(List<CommentaryBall> balls, {String team = 'all', CommentaryFilter filter = CommentaryFilter.all}) {
  Iterable<CommentaryBall> it = balls;
  if (team != 'all') it = it.where((b) => b.inningsIndex == team);
  switch (filter) {
    case CommentaryFilter.six:
      it = it.where((b) => b.value == '6');
    case CommentaryFilter.four:
      it = it.where((b) => b.value == '4');
    case CommentaryFilter.wicket:
      it = it.where((b) => b.value == 'W' || b.value == 'WK');
    case CommentaryFilter.all:
      break;
  }
  final list = it.toList();
  // stable sort newest first
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = b.$2.timestamp.compareTo(a.$2.timestamp);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

// ─────────────────────────────────────────────────────────────────────────────
// Scorecard team meta (RN matchUtils.getScorecardTeamMeta)
// ─────────────────────────────────────────────────────────────────────────────

class ScorecardTeamMeta {
  final String? logo;
  final String displayShort;
  const ScorecardTeamMeta(this.displayShort, [this.logo]);
}

ScorecardTeamMeta getScorecardTeamMeta(JsonMap? scorecard, JsonMap? inning, int inningIndex) {
  final info = inning?['teamInfo'];
  if (info is! Map) return const ScorecardTeamMeta('Team');
  final i = J.map(info);
  final teams = J.map(scorecard?['teams']);
  String? s(dynamic v) => J.text(v);
  if (teams['team1'] is! Map || teams['team2'] is! Map) {
    return ScorecardTeamMeta(s(i['shortName']) ?? s(i['teamName']) ?? 'Inn ${inningIndex + 1}');
  }
  final t1 = J.map(teams['team1']);
  final t2 = J.map(teams['team2']);
  bool matches(JsonMap t) {
    final tn = J.str(t['name']).trim().toLowerCase();
    final ts = J.str(t['shortName']).trim().toLowerCase();
    final un = J.str(i['teamName']).trim().toLowerCase();
    final us = J.str(i['shortName']).trim().toLowerCase();
    if (un.isNotEmpty && tn.isNotEmpty && (tn == un || tn.contains(un) || un.contains(tn))) return true;
    if (us.isNotEmpty && ts.isNotEmpty && (ts == us || (tn.isNotEmpty && tn.contains(us)) || (un.isNotEmpty && un.contains(ts)))) {
      return true;
    }
    return false;
  }

  if (matches(t1)) return ScorecardTeamMeta(s(t1['shortName']) ?? s(i['shortName']) ?? J.str(i['teamName']), s(t1['logo']));
  if (matches(t2)) return ScorecardTeamMeta(s(t2['shortName']) ?? s(i['shortName']) ?? J.str(i['teamName']), s(t2['logo']));
  final order = J.list(scorecard?['inningsOrder']);
  final k = inningIndex < order.length && order[inningIndex] != null ? J.str(order[inningIndex]).toLowerCase() : '';
  if (k.contains('t1') || k == 'team1') return ScorecardTeamMeta(s(t1['shortName']) ?? J.str(i['shortName']), s(t1['logo']));
  if (k.contains('t2') || k == 'team2') return ScorecardTeamMeta(s(t2['shortName']) ?? J.str(i['shortName']), s(t2['logo']));
  return ScorecardTeamMeta(
    s(i['shortName']) ?? s(i['teamName']) ?? 'Inn ${inningIndex + 1}',
    inningIndex.isEven ? s(t1['logo']) : s(t2['logo']),
  );
}
