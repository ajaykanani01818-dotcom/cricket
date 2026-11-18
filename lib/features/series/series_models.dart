import 'package:intl/intl.dart';

import '../../core/api/json.dart';
import '../../core/utils/fixture_status.dart';

/// View-models + parsers for the Series tab and Series Detail screen.
/// Ported from RN `SeriesScreen.tsx` / `SeriesDetailScreen.tsx` helpers.
/// Everything here is pure (no Flutter) and parsed ONCE when data arrives.

/// RN `getNativeConfig('series_list' | 'series_detail').interval` defaults (adsConfig.ts).
const int kSeriesNativeAdInterval = 3;

// ───────────────────────── Series list ─────────────────────────

enum SeriesStatusKey { ongoing, upcoming, completed }

/// RN `toStatusKey`.
SeriesStatusKey? toSeriesStatusKey(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'ONGOING':
      return SeriesStatusKey.ongoing;
    case 'UPCOMING':
      return SeriesStatusKey.upcoming;
    case 'COMPLETED':
      return SeriesStatusKey.completed;
  }
  return null;
}

/// RN `formatDateRange`: "Oct 2 – Nov 21" (local time), '' if either date is missing/invalid.
String formatSeriesDateRange(String? startDate, String? endDate) {
  if (startDate == null || endDate == null || startDate.isEmpty || endDate.isEmpty) return '';
  final s = DateTime.tryParse(startDate);
  final e = DateTime.tryParse(endDate);
  if (s == null || e == null) return '';
  final f = DateFormat('MMM d', 'en_US');
  return '${f.format(s.toLocal())} – ${f.format(e.toLocal())}';
}

class SeriesItem {
  const SeriesItem({
    required this.id,
    required this.navId,
    required this.name,
    required this.status,
    required this.format,
    required this.dateRange,
  });

  /// Stable list identity (`_id` → `sb_series_key` → `key`).
  final String id;

  /// RN: `sb_series_key || _id || key` — what SeriesDetail is opened with.
  final String navId;
  final String name;
  final SeriesStatusKey? status;
  final String format; // upper-cased, '' when missing
  final String dateRange;

  bool get isLive => status == SeriesStatusKey.ongoing;

  static SeriesItem? fromJson(JsonMap m, {int index = 0}) {
    final navId = J.text(m['sb_series_key']) ?? J.text(m['_id']) ?? J.text(m['key']) ?? '';
    final id = J.text(m['_id']) ?? (navId.isNotEmpty ? navId : 'series-$index');
    return SeriesItem(
      id: id,
      navId: navId,
      name: J.text(m['name']) ?? '',
      status: toSeriesStatusKey(J.text(m['seriesStatus'])),
      format: (J.text(m['format']) ?? '').toUpperCase(),
      dateRange: formatSeriesDateRange(J.text(m['startDate']), J.text(m['endDate'])),
    );
  }
}

/// RN loadTab: `data` is either a list or `{ series: [...] }`.
List<SeriesItem> parseSeriesList(dynamic data) {
  final raw = data is List ? data : J.map(data)['series'];
  final out = <SeriesItem>[];
  var i = 0;
  for (final m in J.maps(raw)) {
    final item = SeriesItem.fromJson(m, index: i++);
    if (item != null) out.add(item);
  }
  return out;
}

// ───────────────────────── Fixtures ─────────────────────────

/// RN `stripLeadingOrdinalFromTitle`.
String stripLeadingOrdinalFromTitle(String raw) => raw
    .replaceFirst(RegExp(r'^\s*\d{1,2}(st|nd|rd|th)\s+match\s*[:\-–,]?\s*', caseSensitive: false), '')
    .replaceFirst(RegExp(r'^\s*match\s*no\.?\s*\d+\s*[:\-–,]?\s*', caseSensitive: false), '')
    .replaceFirst(RegExp(r'^\s*\d{1,2}\s*[:\-–]\s*'), '')
    .trim();

/// RN `normalizeFixtureFormat`: prefer real format labels (T20 / ODI / TEST).
String? normalizeFixtureFormat(JsonMap f) {
  final raw = f['format'] ?? f['matchFormat'] ?? f['type'] ?? f['gameType'] ?? f['seriesFormat'];
  if (raw == null) return null;
  final s = J.str(raw).trim();
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n != null && n.isFinite && n >= 1 && n <= 200 && !s.toUpperCase().contains('T')) {
    if (n == 20) return 'T20';
    if (n == 50) return 'ODI';
    return null;
  }
  final u = s.toUpperCase();
  if (u == '20' || RegExp(r'^T\s*20$', caseSensitive: false).hasMatch(s)) return 'T20';
  if (u == '50' || u == 'ODI' || u == 'OD') return 'ODI';
  if (u.contains('TEST')) return 'TEST';
  if (u.contains('T20')) return 'T20';
  return u.length <= 12 ? u : u.substring(0, 12);
}

String ordinalSuffix(int n) {
  final j = n % 10, k = n % 100;
  if (j == 1 && k != 11) return 'st';
  if (j == 2 && k != 12) return 'nd';
  if (j == 3 && k != 13) return 'rd';
  return 'th';
}

enum FixtureChipVariant { upcoming, live, finished, cancelled, abandoned }

/// RN `fixtureKindToSeriesStatusChip`.
(String, FixtureChipVariant) fixtureStatusChip(FixtureCardKind kind) => switch (kind) {
      FixtureCardKind.live => ('Live', FixtureChipVariant.live),
      FixtureCardKind.completed => ('Finished', FixtureChipVariant.finished),
      FixtureCardKind.cancelled => ('Cancelled', FixtureChipVariant.cancelled),
      FixtureCardKind.abandoned => ('Abandoned', FixtureChipVariant.abandoned),
      FixtureCardKind.scheduled => ('Upcoming', FixtureChipVariant.upcoming),
    };

/// One fixture row (RN `seriesFixtureToMatch` + `SeriesResultsMatchCard` derived values).
class SeriesFixture {
  const SeriesFixture({
    required this.listKey,
    required this.matchId,
    required this.matchNumber,
    required this.team1,
    required this.team2,
    this.team1Logo,
    this.team2Logo,
    required this.venue,
    required this.date,
    required this.kind,
    required this.statusLine,
    required this.chipLabel,
    required this.chipVariant,
    required this.finishedMessage,
    required this.seriesLine,
    this.format,
    this.name,
  });

  final String listKey;
  final String matchId; // sb_match_key || _id ('' = not tappable)
  final int matchNumber; // 1-based
  final String team1, team2;
  final String? team1Logo, team2Logo;
  final String venue;
  final DateTime date;
  final FixtureCardKind kind;
  final String statusLine;
  final String chipLabel;
  final FixtureChipVariant chipVariant;
  final String finishedMessage;
  final String seriesLine;
  final String? format;
  final String? name;

  bool get isCompleted => kind == FixtureCardKind.completed;
  bool get isVoid => kind == FixtureCardKind.cancelled || kind == FixtureCardKind.abandoned;

  /// RN UpcomingMatchCard variant: completed → 'completed', void → 'cancelled', else 'upcoming'.
  bool get isUpcomingVariant => !isCompleted && !isVoid;

  /// RN `showVoidDetailRow`.
  bool get showVoidDetail {
    const short = {'Cancelled', 'Abandoned', 'cancelled', 'abandoned'};
    final s = statusLine.trim();
    return isVoid && s.isNotEmpty && !short.contains(s);
  }

  static DateTime _resolveDate(JsonMap f, DateTime now) {
    final startDate = f['startDate'];
    if (startDate is String && startDate.length > 4) {
      final d = DateTime.tryParse(startDate);
      if (d != null) return d;
    }
    final alt = f['date'] ?? f['matchDate'] ?? f['startedAt'];
    if (alt != null && J.str(alt).trim().length > 4) {
      return DateTime.tryParse(J.str(alt).trim()) ?? now;
    }
    final ts = J.number(f['timestamp']);
    if (ts != null) {
      // Heuristic: ms vs s (completed fixtures sometimes omit startDate)
      final ms = ts > 1e12 ? ts : ts * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
    }
    return now;
  }

  static SeriesFixture fromJson(JsonMap f, {required int index, String? seriesTitle, DateTime? now}) {
    final current = now ?? DateTime.now();
    final id = J.text(f['sb_match_key']) ?? J.text(f['_id']) ?? '';
    final date = _resolveDate(f, current);
    final statusRaw = J.str(f['status']);
    final resultMsg = J.str(J.at(f, 'result.message')).trim();
    final disp = resolveSeriesFixtureDisplay(statusRaw, date.toUtc().toIso8601String(), resultMsg, current);
    final rawName = J.str(f['name']).trim();
    final titleFromRoute = seriesTitle?.trim() ?? '';
    final seriesLine = titleFromRoute.isNotEmpty ? titleFromRoute : (rawName.isNotEmpty ? stripLeadingOrdinalFromTitle(rawName) : '');
    final (chipLabel, chipVariant) = fixtureStatusChip(disp.kind);
    final finished = resultMsg.isNotEmpty
        ? resultMsg
        : (disp.statusLine.trim().isNotEmpty ? disp.statusLine.trim() : 'Match completed');
    return SeriesFixture(
      listKey: J.text(f['_id']) ?? (id.isNotEmpty ? id : 'fixture-$index'),
      matchId: id,
      matchNumber: index + 1,
      team1: J.text(J.at(f, 'teams.t1.name')) ?? 'TBD',
      team2: J.text(J.at(f, 'teams.t2.name')) ?? 'TBD',
      team1Logo: J.text(J.at(f, 'teams.t1.logo')),
      team2Logo: J.text(J.at(f, 'teams.t2.logo')),
      venue: J.str(f['ground']).trim(),
      date: date,
      kind: disp.kind,
      statusLine: disp.statusLine,
      chipLabel: chipLabel,
      chipVariant: chipVariant,
      finishedMessage: finished,
      seriesLine: seriesLine,
      format: normalizeFixtureFormat(f),
      name: rawName.isEmpty ? null : rawName,
    );
  }
}

/// RN FixturesView: `Array.isArray(data) ? data : data?.data ?? []`.
List<SeriesFixture> parseSeriesFixtures(dynamic data, {String? seriesTitle, DateTime? now}) {
  final raw = data is List ? data : J.map(data)['data'];
  final maps = J.maps(raw);
  return [
    for (var i = 0; i < maps.length; i++) SeriesFixture.fromJson(maps[i], index: i, seriesTitle: seriesTitle, now: now),
  ];
}

/// RN `StartsInBig` label: "2d 3h" / "4h 5m" / "12m"; null when the match is in the past.
String? startsInLabel(DateTime target, DateTime now) {
  final diff = target.difference(now);
  if (diff.inMilliseconds <= 0) return null;
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

// ───────────────────────── Points table ─────────────────────────

String _fmtNum(dynamic v) {
  final n = J.number(v) ?? 0;
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

class PointsRow {
  const PointsRow({
    required this.shortName,
    this.logo,
    required this.matches,
    required this.won,
    required this.lost,
    required this.tied,
    required this.noResult,
    required this.points,
    required this.nrr,
  });
  final String shortName;
  final String? logo;
  final String matches, won, lost, tied, noResult, points, nrr;

  static PointsRow fromJson(JsonMap t) {
    final nrr = J.number(t['netRunRate']);
    return PointsRow(
      shortName: J.str(t['shortName']),
      logo: J.text(t['logo']),
      matches: _fmtNum(t['matches']),
      won: _fmtNum(t['won']),
      lost: _fmtNum(t['lost']),
      tied: _fmtNum(t['tied']),
      noResult: _fmtNum(t['noResult']),
      points: _fmtNum(t['points']),
      nrr: nrr == null ? '0.00' : nrr.toStringAsFixed(2),
    );
  }
}

class PointsGroup {
  const PointsGroup(this.name, this.rows);
  final String name;
  final List<PointsRow> rows;
}

/// RN PointsTableView: `data.series.pointsTable`.
List<PointsGroup> parsePointsTable(dynamic data) => [
      for (final g in J.maps(J.at(data, 'series.pointsTable')))
        PointsGroup(J.str(g['name']), [for (final t in J.maps(g['teams'])) PointsRow.fromJson(t)]),
    ];

// ───────────────────────── Stats ─────────────────────────

const Map<String, String> kStatLabels = {
  'most_runs': 'Most Runs',
  'highest_score': 'Highest Score',
  'best_batting_average': 'Best Batting Avg',
  'best_batting_strike': 'Best Strike Rate',
  'most_wickets': 'Most Wickets',
  'most_fours': 'Most Fours',
  'most_sixes': 'Most Sixes',
  'best_bowling_average': 'Best Bowling Avg',
};

const List<String> kStatOrder = [
  'most_runs',
  'highest_score',
  'best_batting_average',
  'best_batting_strike',
  'most_wickets',
  'most_fours',
  'most_sixes',
  'best_bowling_average',
];

bool isDecimalStat(String key) =>
    key == 'best_batting_average' || key == 'best_batting_strike' || key == 'best_bowling_average';

class StatEntry {
  const StatEntry({required this.rank, required this.playerKey, required this.name, required this.team, this.logo, required this.value});
  final int rank;
  final String? playerKey;
  final String name, team;
  final String? logo;
  final String value;

  JsonMap toPlayerJson() => {'key': playerKey, 'name': name, 'logo': logo, 'team': team};
}

class StatCategory {
  const StatCategory(this.key, this.title, this.entries);
  final String key, title;
  final List<StatEntry> entries; // top 10
}

class StatsFormat {
  const StatsFormat(this.format, this.categories);
  final String format;
  final List<StatCategory> categories;
}

class SeriesStatsData {
  const SeriesStatsData({this.comingSoon = false, this.formats = const [], this.hasData = true});
  final bool comingSoon;

  /// false when the API returned no `data` at all (RN "No stats available").
  final bool hasData;
  final List<StatsFormat> formats;
}

String _statValue(dynamic v, int decimals) {
  final n = J.number(v);
  if (decimals > 0) return (n ?? 0).toStringAsFixed(decimals);
  if (n == null) return J.text(v) ?? '0';
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
      final list = J.maps(fm[statKey]);
      if (list.isEmpty) continue;
      final decimals = isDecimalStat(statKey) ? 2 : 0;
      final top = list.take(10).toList();
      cats.add(StatCategory(statKey, kStatLabels[statKey] ?? statKey, [
        for (var i = 0; i < top.length; i++)
          StatEntry(
            rank: i + 1,
            playerKey: J.text(top[i]['playerKey']),
            name: J.text(top[i]['playerName']) ?? 'Unknown Player',
            team: J.str(top[i]['team']),
            logo: J.text(top[i]['logo']),
            value: _statValue(top[i]['value'], decimals),
          ),
      ]));
    }
    formats.add(StatsFormat(entry.key, cats));
  }
  return SeriesStatsData(formats: formats);
}

// ───────────────────────── Squads ─────────────────────────

/// RN `getRoleName`.
String roleName(int role) => switch (role) {
      0 => 'Batsman',
      1 => 'Bowler',
      2 => 'All Rounder',
      3 => 'Wicket Keeper',
      4 => 'Batsman/WK',
      _ => 'Player',
    };

class SquadPlayer {
  const SquadPlayer({required this.key, required this.name, this.logo, required this.role, required this.tag, required this.isPlaying});
  final String? key;
  final String name;
  final String? logo;
  final String role;
  final String tag;
  final bool isPlaying;

  JsonMap toPlayerJson() => {'key': key, 'name': name, 'logo': logo};

  static SquadPlayer fromJson(JsonMap p) {
    final isPlaying = J.boolean(p['isPlaying']);
    final tags = <String>[
      if (isPlaying) 'XI',
      if (J.boolean(p['isCaptain'])) 'C',
      if (J.boolean(p['isWicketKeeper'])) 'WK',
    ];
    final rawRole = p['role'];
    return SquadPlayer(
      key: J.text(p['key']),
      name: J.str(p['name']),
      logo: J.text(p['logo']),
      role: roleName(rawRole == null ? 0 : (J.integer(rawRole) ?? -1)),
      tag: tags.isEmpty ? '-' : tags.join(', '),
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

/// RN SquadsView: `data.squads`.
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
          players: [for (final p in J.maps(s['players'])) SquadPlayer.fromJson(p)],
        );
      }(),
  ];
}
