import '../../core/api/json.dart';

/// Ported from RN `src/constants/player.ts` (role codes → labels, same as web).
const Map<int, String> kRoleMap = {
  0: 'Batsman',
  1: 'Bowler',
  2: 'All Rounder',
  3: 'Batting All Rounder',
  4: 'Bowling All Rounder',
  5: 'Other',
};

const Map<int, String> kBattingStyleMap = {
  0: 'Right Handed',
  1: 'Left Handed',
};

const Map<int, String> kBowlingStyleMap = {
  0: 'Right-arm medium',
  1: 'Right-arm off-break',
  2: 'Right-arm leg-break',
  3: 'Right-arm fast-medium',
  4: 'Right-arm orthodox',
  5: 'Right-arm fast',
  6: 'Left-arm chinaman',
  7: 'Left-arm fast-medium',
  8: 'Left-arm orthodox',
  9: 'Left-arm fast',
  10: 'Left-arm medium',
  11: 'Left-arm off-break',
};

const String kDefaultCountry = 'India';

/// Placeholder used by RN for missing values.
const String kDash = '–';

String roleLabelOf(int? role) => kRoleMap[role] ?? 'Player';

/// RN PlayersTableByCountry.getRoleLabel: "Batsman · Left Handed".
String roleWithHand(int? role, int? battingStyle) {
  final r = roleLabelOf(role);
  final hand = kBattingStyleMap[battingStyle];
  return hand == null ? r : '$r · $hand';
}

/// Whole years since [dobSeconds] (unix seconds). null/0 → null.
/// (RN treats only null as unknown; a 0 timestamp is a missing value in this
/// API, so it is treated as unknown too instead of showing "56".)
int? ageYears(int? dobSeconds, {DateTime? now}) {
  if (dobSeconds == null || dobSeconds == 0) return null;
  final n = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  final age = ((n - dobSeconds) / (365.25 * 24 * 3600)).floor();
  return age < 0 ? null : age;
}

/// Players list: "27" or '–'.
String ageShort(int? dobSeconds, {DateTime? now}) => ageYears(dobSeconds, now: now)?.toString() ?? kDash;

/// Player detail: "1 year" / "27 years" or '–'.
String ageLong(int? dobSeconds, {DateTime? now}) {
  final a = ageYears(dobSeconds, now: now);
  if (a == null) return kDash;
  return a == 1 ? '1 year' : '$a years';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// RN formatDate: "Oct 6, 1994" (local time) or '–' for missing/≤0.
String formatDob(int? seconds) {
  if (seconds == null || seconds <= 0) return kDash;
  final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// RN stripHtml.
String stripHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .trim();
}

/// Display a loosely-typed numeric/string stat like JS would (56.0 → "56").
String fmtStat(dynamic v, [String fallback = kDash]) {
  if (v == null) return fallback;
  if (v is num) {
    if (v.isNaN || v.isInfinite) return fallback;
    return v == v.truncate() ? v.toInt().toString() : v.toString();
  }
  final s = J.str(v).trim();
  return s.isEmpty ? fallback : s;
}

/// Item from GET /players/country/:country (RN ApiPlayerCountryPlayer),
/// parsed once when the page arrives.
class CountryPlayer {
  const CountryPlayer({
    required this.id,
    required this.playerKey,
    required this.name,
    required this.country,
    required this.roleText,
    required this.ageText,
    required this.raw,
    this.logo,
  });

  /// Stable list identity (`_id` || playerKey).
  final String id;
  final String playerKey;
  final String name;
  final String country;
  final String? logo;
  final String roleText;
  final String ageText;

  /// Original JSON, handed to the detail screen as `initialPlayer`.
  final JsonMap raw;

  static CountryPlayer? fromJson(dynamic json, {DateTime? now}) {
    final m = J.map(json);
    final key = J.text(m['playerKey']) ?? J.text(m['key']);
    final id = J.text(m['_id']) ?? key;
    if (id == null) return null;
    return CountryPlayer(
      id: id,
      playerKey: key ?? '',
      name: J.text(m['name']) ?? kDash,
      country: J.str(m['country']),
      logo: J.text(m['logo']),
      roleText: roleWithHand(J.integer(m['role']), J.integer(m['battingStyle'])),
      ageText: ageShort(J.integer(m['dob']), now: now),
      raw: m,
    );
  }

  static List<CountryPlayer> listFrom(dynamic data, {DateTime? now}) =>
      J.list(data).map((e) => fromJson(e, now: now)).whereType<CountryPlayer>().toList();
}

/// "has more pages" — RN: pageInfo ? page*perPage < total : list.length >= perPage.
bool computeHasMore({required int received, required int perPage, int? infoPage, int? infoPerPage, int? infoTotal}) {
  if (received == 0) return false;
  if (infoPage != null && infoPerPage != null && infoTotal != null && infoPerPage > 0) {
    return infoPage * infoPerPage < infoTotal;
  }
  return received >= perPage;
}

class StatLine {
  const StatLine(this.label, this.value);
  final String label;
  final String value;
}

class FormatStats {
  const FormatStats(this.name, this.rows);
  final String name;
  final List<StatLine> rows;
}

class IccRanks {
  const IccRanks(this._m);
  final JsonMap _m;

  /// [category]: batting | bowling | all; [format]: test | odi | t20.
  /// "#5" or '–'.
  String rank(String category, String format) {
    final r = J.text(J.at(_m, '$category.$format'));
    return r == null ? kDash : '#$r';
  }
}

/// Full player profile (RN ApiPlayerInfo). Also built from a list item
/// (initialPlayer) — then the stats/teams/about lists are just empty.
class PlayerProfile {
  const PlayerProfile({
    required this.playerKey,
    required this.name,
    required this.country,
    required this.roleText,
    required this.bornText,
    required this.ageText,
    required this.battingText,
    required this.bowlingText,
    this.logo,
    this.isWicketKeeper = false,
    this.ranks,
    this.batting = const [],
    this.bowling = const [],
    this.teams = const [],
    this.description = '',
  });

  final String playerKey;
  final String name;
  final String country;
  final String? logo;
  final String roleText;
  final bool isWicketKeeper;
  final String bornText;
  final String ageText;
  final String battingText;
  final String bowlingText;
  final IccRanks? ranks;
  final List<FormatStats> batting;
  final List<FormatStats> bowling;
  final List<String> teams;
  final String description;

  String get initial {
    final n = name.trim();
    return n.isEmpty || n == kDash ? '?' : n[0].toUpperCase();
  }

  /// "South Africa  ·  Batsman  ·  WK"
  String get meta {
    final parts = <String>[if (country.trim().isNotEmpty) country.trim(), roleText, if (isWicketKeeper) 'WK'];
    return parts.join('  ·  ');
  }

  /// [withDetails] false for list items: RN only reads rankings/stats/teams/
  /// description from the info response.
  factory PlayerProfile.fromJson(dynamic json, {bool withDetails = true, DateTime? now}) {
    final m = J.map(json);
    final dob = J.integer(m['dob']);
    final batStyle = J.integer(m['battingStyle']);
    final bowlStyle = J.integer(m['bowlingStyle']);
    final rankMap = J.map(m['iccRanking']);
    return PlayerProfile(
      playerKey: J.text(m['playerKey']) ?? J.text(m['key']) ?? '',
      name: J.text(m['name']) ?? J.text(m['playerName']) ?? kDash,
      country: J.str(m['country']),
      logo: J.text(m['logo']),
      roleText: roleLabelOf(J.integer(m['role'])),
      isWicketKeeper: J.boolean(m['isWicketKeeper']),
      bornText: formatDob(dob),
      ageText: ageLong(dob, now: now),
      battingText: kBattingStyleMap[batStyle] ?? kDash,
      bowlingText: kBowlingStyleMap[bowlStyle] ?? kDash,
      ranks: withDetails && m['iccRanking'] is Map ? IccRanks(rankMap) : null,
      batting: withDetails ? J.maps(m['battingStats']).map(_battingOf).toList() : const [],
      bowling: withDetails ? J.maps(m['bowlingStats']).map(_bowlingOf).toList() : const [],
      teams: withDetails ? J.maps(m['teams']).map((t) => J.text(t['name'])).whereType<String>().toList() : const [],
      description: withDetails ? stripHtml(J.str(m['description'])) : '',
    );
  }

  static FormatStats _battingOf(JsonMap b) {
    final s = J.map(b['stats']);
    return FormatStats(J.text(b['name']) ?? kDash, [
      StatLine('Matches', fmtStat(s['matches'])),
      StatLine('Innings', fmtStat(s['innings'])),
      StatLine('Runs', fmtStat(s['runs'])),
      StatLine('Highest', fmtStat(s['highestScore'])),
      StatLine('Average', fmtStat(s['average'])),
      StatLine('Strike rate', fmtStat(s['strikeRate'])),
      StatLine('100s / 50s', '${fmtStat(s['hundreds'], '0')} / ${fmtStat(s['fifties'], '0')}'),
    ]);
  }

  static FormatStats _bowlingOf(JsonMap b) {
    final s = J.map(b['stats']);
    final five = J.number(s['fiveWicketHauls']) ?? 0;
    final ten = J.number(s['tenWicketHauls']) ?? 0;
    return FormatStats(J.text(b['name']) ?? kDash, [
      StatLine('Matches', fmtStat(s['match'])),
      StatLine('Innings', fmtStat(s['innings'])),
      StatLine('Wickets', fmtStat(s['wickets'])),
      StatLine('Runs conceded', fmtStat(s['runsConceded'])),
      StatLine('Average', fmtStat(s['average'])),
      StatLine('Economy', fmtStat(s['economy'])),
      StatLine('BBI / BBM', '${fmtStat(s['bbi'])} / ${fmtStat(s['bbm'])}'),
      if (five > 0 || ten > 0) StatLine('5w / 10w', '${fmtStat(s['fiveWicketHauls'], '0')} / ${fmtStat(s['tenWicketHauls'], '0')}'),
    ]);
  }
}
