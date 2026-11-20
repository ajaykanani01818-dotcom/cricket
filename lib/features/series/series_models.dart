import 'package:intl/intl.dart';

import '../../core/api/json.dart';
import '../../core/utils/match_transform.dart';
import '../common/match_parsing.dart';
import '../matches/match_filters.dart';

/// View-models + parsers for the Series list and the series hub.
/// Everything here is pure (no Flutter) and parsed ONCE when data arrives.
///
/// Data rules: values the provider leaves out are shown as "–" or hidden,
/// never as 0; standings come from the provider only (no computed
/// qualification, PRD §10).

/// RN `getNativeConfig('series_list' | 'series_detail').interval` defaults.
const int kSeriesNativeAdInterval = 3;

/// Shown for a value the provider did not send.
const kNotAvailable = '–';

// ───────────────────────── Series list ─────────────────────────

enum SeriesStatusKey { ongoing, upcoming, completed }

SeriesStatusKey? toSeriesStatusKey(String? status) {
  switch ((status ?? '').trim().toUpperCase()) {
    case 'ONGOING':
    case 'LIVE':
    case 'RUNNING':
      return SeriesStatusKey.ongoing;
    case 'UPCOMING':
    case 'NOT_STARTED':
      return SeriesStatusKey.upcoming;
    case 'COMPLETED':
    case 'FINISHED':
      return SeriesStatusKey.completed;
  }
  return null;
}

String seriesStatusLabel(SeriesStatusKey s) => switch (s) {
  SeriesStatusKey.ongoing => 'Ongoing',
  SeriesStatusKey.upcoming => 'Upcoming',
  SeriesStatusKey.completed => 'Completed',
};

/// "2 Oct – 21 Nov 2026" (local time); the start keeps its year only when
/// it differs. '' if either date is missing/invalid.
String formatSeriesDateRange(String? startDate, String? endDate) {
  final s = DateTime.tryParse(startDate?.trim() ?? '')?.toLocal();
  final e = DateTime.tryParse(endDate?.trim() ?? '')?.toLocal();
  if (s == null || e == null) return '';
  return formatDateSpan(s, e);
}

String formatDateSpan(DateTime s, DateTime e) {
  final end = DateFormat('d MMM y', 'en_US').format(e);
  if (s.year == e.year && s.month == e.month && s.day == e.day) return end;
  final start = DateFormat(s.year == e.year ? 'd MMM' : 'd MMM y', 'en_US').format(s);
  return '$start – $end';
}

class SeriesItem {
  const SeriesItem({
    required this.id,
    required this.navId,
    required this.name,
    required this.status,
    required this.format,
    required this.dateRange,
    this.year,
    this.isPopular = false,
  });

  /// Stable list identity (`_id` → `sb_series_key` → `key`).
  final String id;

  /// `sb_series_key || _id || key`: what the series hub is opened with.
  final String navId;
  final String name;
  final SeriesStatusKey? status;
  final String format; // provider label ("T20", "Test"), '' when missing
  final String dateRange;

  /// `year`, else the start date's year; null when neither is known.
  final int? year;

  /// Provider flag (data, not a follow).
  final bool isPopular;

  bool get isLive => status == SeriesStatusKey.ongoing;

  static SeriesItem fromJson(JsonMap m, {int index = 0}) {
    final navId = J.text(m['sb_series_key']) ?? J.text(m['_id']) ?? J.text(m['key']) ?? '';
    final id = J.text(m['_id']) ?? (navId.isNotEmpty ? navId : 'series-$index');
    final start = DateTime.tryParse(J.str(m['startDate']).trim())?.toLocal();
    final y = J.integer(m['year']);
    return SeriesItem(
      id: id,
      navId: navId,
      name: (J.text(m['name']) ?? '').trim(),
      status: toSeriesStatusKey(J.text(m['seriesStatus'])),
      format: formatLabel((J.text(m['format']) ?? '').toUpperCase()) ?? '',
      dateRange: formatSeriesDateRange(J.text(m['startDate']), J.text(m['endDate'])),
      year: (y != null && y > 1800 && y < 3000) ? y : start?.year,
      isPopular: J.boolean(m['isPopular']),
    );
  }
}

/// `data` is either a list or `{ series: [...] }`.
List<SeriesItem> parseSeriesList(dynamic data) {
  final raw = data is List ? data : J.map(data)['series'];
  final maps = J.maps(raw);
  return [for (var i = 0; i < maps.length; i++) SeriesItem.fromJson(maps[i], index: i)];
}

// ───────────────────────── Fixtures ─────────────────────────

/// Series fixtures, parsed with the shared match parser (same status rules
/// as every other list), plus header facts derived from them.
class SeriesFixturesData {
  const SeriesFixturesData(this.matches);
  final List<MatchSummary> matches;

  List<MatchSummary> get live => [
    for (final m in matches)
      if (m.isInProgress) m,
  ];

  /// Soonest first.
  List<MatchSummary> get upcoming {
    final l = [
      for (final m in matches)
        if (!m.isInProgress && !m.isFinished && m.resultMessage == null) m,
    ];
    l.sort(_byStart);
    return l;
  }

  /// Most recent first.
  List<MatchSummary> get results {
    final l = [
      for (final m in matches)
        if (!m.isInProgress && (m.isFinished || m.resultMessage != null)) m,
    ];
    l.sort((a, b) => _byStart(b, a));
    return l;
  }

  /// Distinct provider formats, in order of appearance ("T20", "Test").
  List<String> get formats {
    final out = <String>[];
    for (final m in matches) {
      final f = formatLabel(m.format?.toUpperCase());
      if (f != null && !out.contains(f)) out.add(f);
    }
    return out;
  }

  /// "7 Nov – 20 Nov 2026" across the fixtures' start dates, '' if unknown.
  String get dateSpan {
    final dates = [for (final m in matches) ?m.startTime]..sort();
    if (dates.isEmpty) return '';
    return formatDateSpan(dates.first, dates.last);
  }

  static int _byStart(MatchSummary a, MatchSummary b) {
    final x = a.startTime, y = b.startTime;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }
}

/// `Array.isArray(data) ? data : data?.data ?? []`.
SeriesFixturesData parseSeriesFixtures(dynamic data) {
  final raw = data is List ? data : J.map(data)['data'];
  return SeriesFixturesData(parseMatchList(raw));
}

// ───────────────────────── Points table ─────────────────────────

String _count(dynamic v) {
  final n = J.number(v);
  if (n == null) return kNotAvailable;
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// Signed, three decimals: "+0.422", "-0.605", "0.000"; "–" when missing.
String formatNrr(dynamic v) {
  final n = J.number(v);
  if (n == null || !n.isFinite) return kNotAvailable;
  final s = n.abs().toStringAsFixed(3);
  if (s == '0.000') return s;
  return n > 0 ? '+$s' : '-$s';
}

/// One provider result for a team (form guide / expanded row).
class TeamResult {
  const TeamResult({required this.opponent, required this.outcome, this.margin, this.title, this.date});
  final String opponent;

  /// 'W', 'L', or null when the match has no result yet.
  final String? outcome;
  final String? margin;
  final String? title;
  final DateTime? date;
}

class PointsRow {
  const PointsRow({
    required this.position,
    required this.key,
    required this.shortName,
    this.logo,
    required this.matches,
    required this.won,
    required this.lost,
    required this.tied,
    required this.noResult,
    required this.points,
    required this.nrr,
    this.marker,
    this.form = const [],
    this.results = const [],
  });

  /// Row order as the provider sends it (not computed).
  final int position;
  final String key;
  final String shortName;
  final String? logo;
  final String matches, won, lost, tied, noResult, points, nrr;

  /// 'Q' / 'E' only when the provider sets `qualify` / `eliminate`.
  final String? marker;

  /// Last five results, oldest first ('W' / 'L').
  final List<String> form;
  final List<TeamResult> results;

  static PointsRow fromJson(JsonMap t, int position) {
    final key = J.str(t['key']).trim();
    final results = <TeamResult>[];
    for (final tm in J.maps(t['teamMatches'])) {
      final wT = J.text(J.at(tm, 'result.wT'))?.trim();
      final String? outcome = wT == null || wT.isEmpty
          ? null
          : key.isNotEmpty && wT.toLowerCase() == key.toLowerCase()
          ? 'W'
          : 'L';
      final ts = J.number(tm['timestamp']);
      results.add(
        TeamResult(
          opponent: J.text(J.at(tm, 'opponent.shortName')) ?? J.text(J.at(tm, 'opponent.name')) ?? kNotAvailable,
          outcome: outcome,
          margin: J.text(J.at(tm, 'result.sM')),
          title: J.text(tm['name']),
          date: ts == null ? null : DateTime.fromMillisecondsSinceEpoch((ts > 1e12 ? ts : ts * 1000).round(), isUtc: true).toLocal(),
        ),
      );
    }
    final decided = [
      for (final r in results)
        if (r.outcome != null) r.outcome!,
    ];
    bool flag(dynamic v) {
      if (v == null || v == false || v == 0) return false;
      if (v is String && v.trim().isEmpty) return false;
      return true;
    }

    return PointsRow(
      position: position,
      key: key,
      shortName: J.text(t['shortName']) ?? J.text(t['name']) ?? kNotAvailable,
      logo: J.text(t['logo']),
      matches: _count(t['matches']),
      won: _count(t['won']),
      lost: _count(t['lost']),
      tied: _count(t['tied']),
      noResult: _count(t['noResult']),
      points: _count(t['points']),
      nrr: formatNrr(t['netRunRate']),
      marker: flag(t['qualify']) ? 'Q' : (flag(t['eliminate']) ? 'E' : null),
      form: decided.length > 5 ? decided.sublist(decided.length - 5) : decided,
      results: results,
    );
  }
}

class PointsGroup {
  const PointsGroup(this.name, this.rows);
  final String name;
  final List<PointsRow> rows;
}

/// `data.series.pointsTable`; malformed rows are skipped.
List<PointsGroup> parsePointsTable(dynamic data) {
  final out = <PointsGroup>[];
  for (final g in J.maps(J.at(data, 'series.pointsTable'))) {
    final teams = J.maps(g['teams']);
    if (teams.isEmpty) continue;
    out.add(PointsGroup(J.str(g['name']).trim(), [for (var i = 0; i < teams.length; i++) PointsRow.fromJson(teams[i], i + 1)]));
  }
  return out;
}

// ───────────────────────── Stats ─────────────────────────

const Map<String, String> kStatLabels = {
  'most_runs': 'Most runs',
  'most_wickets': 'Most wickets',
  'highest_score': 'Highest score',
  'best_batting_average': 'Best batting average',
  'best_batting_strike': 'Best strike rate',
  'best_bowling_average': 'Best bowling average',
  'most_sixes': 'Most sixes',
  'most_fours': 'Most fours',
  'most_fifties': 'Most fifties',
};

/// Unit word shown after a leader's value.
const Map<String, String> kStatUnits = {
  'most_runs': 'runs',
  'most_wickets': 'wkts',
  'highest_score': 'runs',
  'best_batting_average': 'avg',
  'best_batting_strike': 'SR',
  'best_bowling_average': 'avg',
  'most_sixes': 'sixes',
  'most_fours': 'fours',
  'most_fifties': '50s',
};

const List<String> kStatOrder = [
  'most_runs',
  'most_wickets',
  'highest_score',
  'best_batting_average',
  'best_batting_strike',
  'best_bowling_average',
  'most_sixes',
  'most_fours',
  'most_fifties',
];

bool isDecimalStat(String key) => key == 'best_batting_average' || key == 'best_batting_strike' || key == 'best_bowling_average';

class StatEntry {
  const StatEntry({
    required this.rank,
    required this.playerKey,
    required this.name,
    required this.team,
    this.logo,
    required this.value,
    this.innings,
  });
  final int rank;
  final String? playerKey;
  final String name, team;
  final String? logo;
  final String value;
  final int? innings;

  JsonMap toPlayerJson() => {'key': playerKey, 'name': name, 'logo': logo, 'team': team};
}

class StatCategory {
  const StatCategory(this.key, this.title, this.entries);
  final String key, title;
  final List<StatEntry> entries; // top 10, provider order
  String get unit => kStatUnits[key] ?? '';
}

class StatsFormat {
  const StatsFormat(this.format, this.categories);
  final String format;
  final List<StatCategory> categories;
}

class SeriesStatsData {
  const SeriesStatsData({this.comingSoon = false, this.formats = const [], this.hasData = true});
  final bool comingSoon;

  /// false when the API returned no `data` at all.
  final bool hasData;
  final List<StatsFormat> formats;
}

String? _statValue(dynamic v, int decimals) {
  final n = J.number(v);
  if (n == null || !n.isFinite) return null;
  if (decimals > 0) return n.toStringAsFixed(decimals);
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

SeriesStatsData parseSeriesStats(dynamic data) {
  if (data is! Map) return const SeriesStatsData(hasData: false);
  final m = J.map(data);
  final formats = <StatsFormat>[];
  for (final entry in m.entries) {
    if (entry.key == 'seriesId' || entry.key == 'sbSeriesKey' || entry.value is! Map) continue;
    final fm = J.map(entry.value);
    final cats = <StatCategory>[];
    for (final statKey in kStatOrder) {
      final decimals = isDecimalStat(statKey) ? 2 : 0;
      final entries = <StatEntry>[];
      for (final row in J.maps(fm[statKey])) {
        if (entries.length == 10) break;
        final value = _statValue(row['value'], decimals);
        final name = J.text(row['playerName']);
        if (value == null || name == null) continue; // never a fake 0 or nameless row
        entries.add(
          StatEntry(
            rank: entries.length + 1,
            playerKey: J.text(row['playerKey']),
            name: name,
            team: J.str(row['team']).trim(),
            logo: J.text(row['logo']),
            value: value,
            innings: J.integer(row['innings']),
          ),
        );
      }
      if (entries.isNotEmpty) cats.add(StatCategory(statKey, kStatLabels[statKey] ?? statKey, entries));
    }
    if (cats.isNotEmpty) formats.add(StatsFormat(formatLabel(entry.key) ?? entry.key, cats));
  }
  return SeriesStatsData(formats: formats);
}

// ───────────────────────── Squads ─────────────────────────

/// Provider role code → label (codes confirmed by the fixture: 1 = bowler).
String roleName(int? role) => switch (role) {
  0 => 'Batter',
  1 => 'Bowler',
  2 => 'All-rounder',
  3 => 'Wicketkeeper',
  4 => 'Wicketkeeper batter',
  _ => '',
};

class SquadPlayer {
  const SquadPlayer({required this.key, required this.name, this.logo, required this.role, required this.tags, required this.isPlaying});
  final String? key;
  final String name;
  final String? logo;

  /// '' when the provider role is unknown (the slot is hidden).
  final String role;

  /// 'C' (captain), 'WK' (wicketkeeper), 'XI' (in the playing XI).
  final List<String> tags;
  final bool isPlaying;

  JsonMap toPlayerJson() => {'key': key, 'name': name, 'logo': logo};

  static SquadPlayer fromJson(JsonMap p) {
    final isPlaying = J.boolean(p['isPlaying']);
    return SquadPlayer(
      key: J.text(p['key']),
      name: J.str(p['name']).trim(),
      logo: J.text(p['logo']),
      role: roleName(J.integer(p['role'])),
      tags: [if (J.boolean(p['isCaptain'])) 'C', if (J.boolean(p['isWicketKeeper'])) 'WK', if (isPlaying) 'XI'],
      isPlaying: isPlaying,
    );
  }
}

class SquadTeam {
  const SquadTeam({required this.key, required this.name, this.logo, required this.players});
  final String key, name;
  final String? logo;
  final List<SquadPlayer> players;
}

/// `data.squads`; players without a name are skipped.
List<SquadTeam> parseSquads(dynamic data) {
  final squads = J.maps(J.map(data)['squads']);
  return [
    for (var i = 0; i < squads.length; i++)
      () {
        final s = squads[i];
        final name = J.text(s['teamName']) ?? 'Team ${i + 1}';
        return SquadTeam(
          key: '${J.text(s['teamId']) ?? J.text(s['teamKey']) ?? J.text(s['_id']) ?? name}-$i',
          name: name,
          logo: J.text(s['teamLogo']),
          players: [
            for (final p in J.maps(s['players']))
              if (J.str(p['name']).trim().isNotEmpty) SquadPlayer.fromJson(p),
          ],
        );
      }(),
  ];
}
