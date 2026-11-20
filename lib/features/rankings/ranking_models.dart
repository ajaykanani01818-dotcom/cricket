import '../../core/api/json.dart';
import '../players/player_models.dart';

/// What is ranked. [apiType] is the `/rank/player` `type` param (null for
/// the team endpoint).
enum RankKind {
  teams('Teams', null),
  batting('Batting', 'BATSMAN'),
  bowling('Bowling', 'BOWLER'),
  allRounders('All-rounders', 'ALL_ROUNDER');

  const RankKind(this.label, this.apiType);
  final String label;
  final String? apiType;
  bool get isTeam => this == RankKind.teams;

  /// Lower-case noun for copy ("batting", "team").
  String get noun => switch (this) {
    RankKind.teams => 'team',
    RankKind.batting => 'batting',
    RankKind.bowling => 'bowling',
    RankKind.allRounders => 'all-rounder',
  };
}

/// `gender` param → label. Always sent (the API rejects calls without it).
const kGenderOptions = [('MALE', 'Men'), ('FEMALE', 'Women')];

/// `matchType` param → label. Always sent.
const kFormatOptions = [('TEST', 'Test'), ('ODI', 'ODI'), ('T20', 'T20')];

String genderLabel(String g) => g == 'FEMALE' ? 'Women' : 'Men';
String formatOptionLabel(String f) =>
    kFormatOptions.firstWhere((o) => o.$1 == f, orElse: () => (f, f)).$2;

/// "Men's ODI batting", "Women's Test team".
String selectionTitle(RankKind kind, String format, String gender) =>
    "${genderLabel(gender)}'s ${formatOptionLabel(format)} ${kind.noun}";

/// One ranked team or player.
class RankingRowItem {
  const RankingRowItem({
    required this.name,
    required this.rank,
    this.rating,
    this.points,
    this.image,
    this.playerKey,
  });

  final String name;
  final int rank;

  /// Teams: `rating`; players: `points` (the player rating). null = missing.
  final String? rating;

  /// Teams only: aggregate `points`.
  final String? points;
  final String? image;

  /// Only set for players (team rows are not tappable).
  final String? playerKey;

  String get id => playerKey ?? '$rank-$name';

  /// Spoken row ("Rank 1, India, rating 116, 3841 points").
  String get semanticsLabel => [
    'Rank $rank',
    name,
    if (rating != null) 'rating $rating',
    if (points != null) '$points points',
  ].join(', ');

  /// Minimal list item handed to PlayerDetail as `initialPlayer` so the
  /// header renders while the profile loads.
  JsonMap toInitialPlayer() => {
    'playerKey': playerKey,
    'name': name,
    if (image != null) 'logo': image,
  };
}

List<RankingRowItem> _parse(dynamic data, {required bool players}) {
  final seen = <String>{};
  final out = <RankingRowItem>[];
  final rows = J.list(data);
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] is! Map) continue;
    final m = J.map(rows[i]);
    final name = J.text(m['name']) ?? J.text(m['playerName']);
    if (name == null) continue;
    final item = RankingRowItem(
      name: name,
      rank: J.integer(m['order']) ?? out.length + 1,
      rating: fmtOpt(
        J.number(players ? (m['points'] ?? m['rating']) : m['rating']),
      ),
      points: players ? null : fmtOpt(J.number(m['points'])),
      image: players ? J.text(m['logo']) : null,
      playerKey: players ? J.text(m['playerKey']) : null,
    );
    // Unique ids keep list keys stable even if the API repeats a row.
    if (seen.add(item.id)) out.add(item);
  }
  out.sort((a, b) => a.rank.compareTo(b.rank));
  return out;
}

/// `/rank` (teams).
List<RankingRowItem> parseTeamRankings(dynamic data) =>
    _parse(data, players: false);

/// `/rank/player`.
List<RankingRowItem> parsePlayerRankings(dynamic data) =>
    _parse(data, players: true);

/// Case-insensitive name filter.
List<RankingRowItem> filterRankings(List<RankingRowItem> list, String query) {
  final q = query.trim();
  if (q.isEmpty) return list;
  return list.where((e) => nameMatches(e.name, q)).toList();
}

/// Splits the visible list into the leaders (top 3, larger rows) and the
/// rest (up to 100 rows). While searching every match goes into [rows].
({List<RankingRowItem> leaders, List<RankingRowItem> rows}) splitForDisplay(
  List<RankingRowItem> list, {
  required bool searching,
}) {
  final capped = list.length > 100 ? list.sublist(0, 100) : list;
  if (searching) return (leaders: const [], rows: capped);
  return (
    leaders: capped.take(3).toList(),
    rows: capped.length > 3 ? capped.sublist(3) : const [],
  );
}
