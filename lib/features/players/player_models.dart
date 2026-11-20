import '../../core/api/json.dart';

/// Role codes → labels (the mapping the web app and RN app use).
const Map<int, String> kRoleMap = {
  0: 'Batter',
  1: 'Bowler',
  2: 'All-rounder',
  3: 'Batting all-rounder',
  4: 'Bowling all-rounder',
  5: 'Other',
};

const Map<int, String> kBattingStyleMap = {
  0: 'Right-hand bat',
  1: 'Left-hand bat',
};

const Map<int, String> kBowlingStyleMap = {
  0: 'Right-arm medium',
  1: 'Right-arm off-break',
  2: 'Right-arm leg-break',
  3: 'Right-arm fast-medium',
  4: 'Right-arm orthodox',
  5: 'Right-arm fast',
  6: 'Left-arm wrist spin',
  7: 'Left-arm fast-medium',
  8: 'Left-arm orthodox',
  9: 'Left-arm fast',
  10: 'Left-arm medium',
  11: 'Left-arm off-break',
};

const String kDefaultCountry = 'India';

/// Shown in a table cell when the provider sent nothing (never a fake 0).
const String kDash = '–';

/// null when the role is missing or unknown (the slot is hidden).
String? roleLabelOf(int? role) => kRoleMap[role];

/// "Batter, left-hand bat"; null when neither is known.
String? roleWithHand(int? role, int? battingStyle) {
  final parts = [
    ?roleLabelOf(role),
    ?_lowerFirst(kBattingStyleMap[battingStyle]),
  ];
  if (parts.isEmpty) return null;
  final s = parts.join(', ');
  return s[0].toUpperCase() + s.substring(1);
}

String? _lowerFirst(String? s) =>
    s == null || s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Whole years since [dobSeconds] (unix seconds). null/0/future → null
/// (a 0 timestamp means "missing" in this API).
int? ageYears(int? dobSeconds, {DateTime? now}) {
  if (dobSeconds == null || dobSeconds <= 0) return null;
  final n = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  final age = ((n - dobSeconds) / (365.25 * 24 * 3600)).floor();
  return age < 0 ? null : age;
}

/// "1 year" / "27 years" or null.
String? ageLong(int? dobSeconds, {DateTime? now}) {
  final a = ageYears(dobSeconds, now: now);
  if (a == null) return null;
  return a == 1 ? '1 year' : '$a years';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Oct 6, 1994" (local time) or null for missing/≤0.
String? formatDate(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

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
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// A loosely-typed number/string as display text (56.0 → "56"), or
/// [fallback] when missing.
String fmtStat(dynamic v, [String fallback = kDash]) => fmtOpt(v) ?? fallback;

/// Like [fmtStat] but null when missing (so the slot can be hidden).
String? fmtOpt(dynamic v) {
  if (v == null || v is bool) return null;
  if (v is num) {
    if (v.isNaN || v.isInfinite) return null;
    return v == v.truncate() ? v.toInt().toString() : v.toString();
  }
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// Format names from the API ("TEST", "T20I", "HUNDRED", "IPL") as labels.
/// Competition codes stay uppercase (they are data).
String formatLabel(String raw) => switch (raw.trim().toUpperCase()) {
  'TEST' => 'Test',
  'HUNDRED' => 'The Hundred',
  '' => kDash,
  final s => s,
};

/// ICC ranks by category (batting | bowling | all) and format
/// (test | odi | t20). Empty strings mean "not ranked".
class IccRanks {
  const IccRanks(this._m);
  final JsonMap _m;

  static const categories = [
    ('batting', 'Batting'),
    ('bowling', 'Bowling'),
    ('all', 'All-rounder'),
  ];
  static const formats = [('test', 'Test'), ('odi', 'ODI'), ('t20', 'T20')];

  /// "#5" or null.
  String? rank(String category, String format) {
    final r = J.text(J.at(_m, '$category.$format'));
    final n = r == null ? null : int.tryParse(r);
    return n == null || n <= 0 ? null : '#$n';
  }

  bool hasCategory(String category) =>
      formats.any((f) => rank(category, f.$1) != null);

  bool get hasAny => categories.any((c) => hasCategory(c.$1));

  /// Best (lowest) rank, preferring [category]: (rank, format label, category
  /// label), or null when unranked everywhere.
  (int, String, String)? best({String? category}) {
    (int, String, String)? pick(Iterable<(String, String)> cats) {
      (int, String, String)? out;
      for (final c in cats) {
        for (final f in formats) {
          final r = int.tryParse(J.str(J.at(_m, '${c.$1}.${f.$1}')));
          if (r == null || r <= 0) continue;
          if (out == null || r < out.$1) out = (r, f.$2, c.$2);
        }
      }
      return out;
    }

    final preferred = category == null
        ? null
        : pick(categories.where((c) => c.$1 == category));
    return preferred ?? pick(categories);
  }
}

/// The ICC category that matches a role code (for the list badge).
String? _rankCategoryFor(int? role) => switch (role) {
  0 => 'batting',
  1 => 'bowling',
  2 || 3 || 4 => 'all',
  _ => null,
};

/// A player list item (players by country, trending, search).
class CountryPlayer {
  const CountryPlayer({
    required this.id,
    required this.playerKey,
    required this.name,
    required this.country,
    required this.raw,
    this.logo,
    this.subtitle,
    this.rankBadge,
    this.rankLabel,
  });

  /// Stable list identity (`_id` || playerKey).
  final String id;
  final String playerKey;
  final String name;
  final String country;
  final String? logo;

  /// "Batter, left-hand bat, 24 years" (only the parts that exist).
  final String? subtitle;

  /// "#5 Test" and its spoken form ("ICC Test batting rank 5").
  final String? rankBadge;
  final String? rankLabel;

  /// Original JSON, handed to the detail screen as `initialPlayer`.
  final JsonMap raw;

  static CountryPlayer? fromJson(dynamic json, {DateTime? now}) {
    if (json is! Map) return null;
    final m = J.map(json);
    final key = J.text(m['playerKey']) ?? J.text(m['key']);
    final id = J.text(m['_id']) ?? key;
    if (id == null) return null;
    final role = J.integer(m['role']);
    final parts = [
      ?roleWithHand(role, J.integer(m['battingStyle'])),
      ?ageLong(J.integer(m['dob']), now: now),
    ];
    final best = m['iccRanking'] is Map
        ? IccRanks(
            J.map(m['iccRanking']),
          ).best(category: _rankCategoryFor(role))
        : null;
    return CountryPlayer(
      id: id,
      playerKey: key ?? '',
      name: J.text(m['name']) ?? 'Unnamed player',
      country: J.str(m['country']).trim(),
      logo: J.text(m['logo']),
      subtitle: parts.isEmpty ? null : parts.join(', '),
      rankBadge: best == null ? null : '#${best.$1} ${best.$2}',
      rankLabel: best == null
          ? null
          : 'ICC ${best.$2} ${best.$3.toLowerCase()} rank ${best.$1}',
      raw: m,
    );
  }

  static List<CountryPlayer> listFrom(dynamic data, {DateTime? now}) => J
      .list(data)
      .map((e) => fromJson(e, now: now))
      .whereType<CountryPlayer>()
      .toList();
}

/// Case-insensitive match on every word of [query] (local search filter).
bool nameMatches(String name, String query) {
  final n = name.toLowerCase();
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  return words.isNotEmpty && words.every(n.contains);
}

/// "has more pages": pageInfo ? page*perPage < total : list.length >= perPage.
bool computeHasMore({
  required int received,
  required int perPage,
  int? infoPage,
  int? infoPerPage,
  int? infoTotal,
}) {
  if (received == 0) return false;
  if (infoPage != null &&
      infoPerPage != null &&
      infoTotal != null &&
      infoPerPage > 0) {
    return infoPage * infoPerPage < infoTotal;
  }
  return received >= perPage;
}

/// One format row of a career table.
class CareerRow {
  const CareerRow(this.format, this.cells);
  final String format;
  final List<String> cells;
}

/// Format-wise career stats (batting or bowling) as a table.
class CareerTable {
  const CareerTable({
    required this.columns,
    required this.legend,
    required this.rows,
  });
  final List<String> columns;

  /// "M matches, Inn innings, …" — the abbreviations spelt out.
  final String legend;
  final List<CareerRow> rows;

  bool get isEmpty => rows.isEmpty;

  static const battingColumns = [
    'M',
    'Inn',
    'Runs',
    'HS',
    'Avg',
    'SR',
    '100s',
    '50s',
  ];
  static const battingLegend =
      'M matches, Inn innings, HS highest score, Avg average, SR strike rate';
  static const bowlingColumns = [
    'M',
    'Inn',
    'Wkts',
    'Runs',
    'Avg',
    'Econ',
    'BBI',
    '5w',
  ];
  static const bowlingLegend =
      'Wkts wickets, Runs runs conceded, Econ economy, BBI best bowling in an innings, 5w five-wicket hauls';

  static CareerTable batting(dynamic list) => CareerTable(
    columns: battingColumns,
    legend: battingLegend,
    rows: [
      for (final b in J.maps(list))
        if (J.map(b['stats']).isNotEmpty) _battingRow(b),
    ],
  );

  static CareerTable bowling(dynamic list) => CareerTable(
    columns: bowlingColumns,
    legend: bowlingLegend,
    rows: [
      for (final b in J.maps(list))
        if (J.map(b['stats']).isNotEmpty && _bowled(J.map(b['stats'])))
          _bowlingRow(b),
    ],
  );

  static CareerRow _battingRow(JsonMap b) {
    final s = J.map(b['stats']);
    final inns = J.number(s['innings']);
    final notOuts = J.number(s['notOuts']) ?? 0;
    // Average is undefined when the batter was never dismissed.
    final dismissed = inns != null && inns - notOuts > 0;
    return CareerRow(formatLabel(J.str(b['name'])), [
      fmtStat(s['matches']),
      fmtStat(s['innings']),
      fmtStat(s['runs']),
      fmtStat(s['highestScore']),
      dismissed ? fmtStat(s['average']) : kDash,
      (J.number(s['ballsFaced']) ?? 1) > 0 ? fmtStat(s['strikeRate']) : kDash,
      fmtStat(s['hundreds']),
      fmtStat(s['fifties']),
    ]);
  }

  /// A format where the player never bowled a ball is left out.
  static bool _bowled(JsonMap s) {
    final balls = J.number(s['ball']);
    final inns = J.number(s['innings']);
    return !(balls == 0 || (balls == null && inns == 0));
  }

  static CareerRow _bowlingRow(JsonMap b) {
    final s = J.map(b['stats']);
    final wkts = J.number(s['wickets']);
    final took = wkts != null && wkts > 0;
    return CareerRow(formatLabel(J.str(b['name'])), [
      fmtStat(s['match'] ?? s['matches']),
      fmtStat(s['innings']),
      fmtStat(s['wickets']),
      fmtStat(s['runsConceded']),
      took ? fmtStat(s['average']) : kDash,
      fmtStat(s['economy']),
      took ? fmtStat(s['bbi']) : kDash,
      fmtStat(s['fiveWicketHauls']),
    ]);
  }
}

class Debut {
  const Debut(this.format, this.match, this.date);
  final String format;
  final String? match;
  final String? date;
}

/// Full player profile. Also built from a list item (initialPlayer); then
/// the stats/teams/about parts are empty and [hasDetails] is false.
class PlayerProfile {
  const PlayerProfile({
    required this.playerKey,
    required this.name,
    required this.country,
    this.logo,
    this.role,
    this.batting,
    this.bowling,
    this.born,
    this.age,
    this.isWicketKeeper = false,
    this.ranks,
    this.battingTable = const CareerTable(columns: [], legend: '', rows: []),
    this.bowlingTable = const CareerTable(columns: [], legend: '', rows: []),
    this.debuts = const [],
    this.teams = const [],
    this.description = '',
    this.hasDetails = false,
  });

  final String playerKey;
  final String name;
  final String country;
  final String? logo;
  final String? role;
  final String? batting;
  final String? bowling;
  final String? born;
  final String? age;
  final bool isWicketKeeper;
  final IccRanks? ranks;
  final CareerTable battingTable;
  final CareerTable bowlingTable;
  final List<Debut> debuts;
  final List<String> teams;
  final String description;
  final bool hasDetails;

  /// Label/value facts that exist (missing ones are left out).
  List<(String, String)> get facts => [
    if (role != null) ('Role', role!),
    if (batting != null) ('Batting', batting!),
    if (bowling != null) ('Bowling', bowling!),
    if (born != null) ('Born', age == null ? born! : '$born ($age)'),
    if (isWicketKeeper) ('Wicketkeeper', 'Yes'),
  ];

  factory PlayerProfile.fromJson(
    dynamic json, {
    bool withDetails = true,
    DateTime? now,
  }) {
    final m = J.map(json);
    final dob = J.integer(m['dob']);
    final ranks = m['iccRanking'] is Map
        ? IccRanks(J.map(m['iccRanking']))
        : null;
    return PlayerProfile(
      playerKey: J.text(m['playerKey']) ?? J.text(m['key']) ?? '',
      name: J.text(m['name']) ?? J.text(m['playerName']) ?? 'Unnamed player',
      country: J.str(m['country']).trim(),
      logo: J.text(m['logo']),
      role: roleLabelOf(J.integer(m['role'])),
      isWicketKeeper: J.boolean(m['isWicketKeeper']),
      born: formatDate(dob),
      age: ageLong(dob, now: now),
      batting: kBattingStyleMap[J.integer(m['battingStyle'])],
      bowling: kBowlingStyleMap[J.integer(m['bowlingStyle'])],
      ranks: withDetails && ranks != null && ranks.hasAny ? ranks : null,
      battingTable: withDetails
          ? CareerTable.batting(m['battingStats'])
          : const CareerTable(columns: [], legend: '', rows: []),
      bowlingTable: withDetails
          ? CareerTable.bowling(m['bowlingStats'])
          : const CareerTable(columns: [], legend: '', rows: []),
      debuts: withDetails
          ? [
              for (final d in J.maps(m['debuts']))
                if (J.text(d['format']) != null)
                  Debut(
                    formatLabel(J.str(d['format'])),
                    J.text(d['opponent']),
                    formatDate(J.integer(d['timestamp'])),
                  ),
            ]
          : const [],
      teams: withDetails
          ? J
                .maps(m['teams'])
                .map((t) => J.text(t['name']))
                .whereType<String>()
                .toSet()
                .toList()
          : const [],
      description: withDetails && m['description'] is String
          ? stripHtml(m['description'] as String)
          : '',
      hasDetails: withDetails,
    );
  }
}
