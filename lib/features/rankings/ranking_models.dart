import '../../core/api/json.dart';
import '../players/player_models.dart';

enum RankMode { teams, players }

/// gender: MALE | FEMALE
const kGenderOptions = [('MALE', 'Men'), ('FEMALE', 'Women')];

/// matchType: TEST | ODI | T20
const kFormatOptions = [('TEST', 'Test'), ('ODI', 'ODI'), ('T20', 'T20')];

/// RN PlayerCategory → API `type`.
const kCategoryOptions = [('batters', 'Batters'), ('bowlers', 'Bowlers'), ('allRounders', 'All-Rounders')];

String categoryToApiType(String category) => switch (category) {
      'bowlers' => 'BOWLER',
      'allRounders' => 'ALL_ROUNDER',
      _ => 'BATSMAN',
    };

/// Ported from RN `RankingRowItem` (+ playerTransform.transformApiPlayersToPlayers).
class RankingRowItem {
  const RankingRowItem({required this.name, required this.rank, required this.ratingText, this.image, this.playerKey});

  final String name;
  final int rank;

  /// RN shows `points` as the "rating" for both teams and players.
  final String ratingText;
  final String? image;

  /// Only set for players (teams are not tappable).
  final String? playerKey;

  String get id => playerKey ?? '$rank-$name';

  String get initial {
    final n = name.trim();
    return n.isEmpty || n == kDash ? '?' : n[0].toUpperCase();
  }

  /// Minimal list item handed to PlayerDetail as `initialPlayer` so the
  /// header renders immediately while /players/:key/info loads.
  JsonMap toInitialPlayer() => {
        'playerKey': playerKey,
        'name': name,
        if (image != null) 'logo': image,
      };
}

List<RankingRowItem> _parse(dynamic data, {required bool players}) {
  final seen = <String>{};
  final out = <RankingRowItem>[];
  final rows = J.maps(data);
  for (var i = 0; i < rows.length; i++) {
    final m = rows[i];
    final item = RankingRowItem(
      name: J.text(m['name']) ?? J.text(m['playerName']) ?? kDash,
      rank: J.integer(m['order']) ?? i + 1,
      ratingText: fmtStat(m['points']),
      image: players ? J.text(m['logo']) : null,
      playerKey: players ? J.text(m['playerKey']) : null,
    );
    // Unique ids keep list keys stable even if the API repeats a row.
    if (seen.add(item.id)) out.add(item);
  }
  return out;
}

/// GET /rank → rows (team logos are not shown in RN; teams are not tappable).
List<RankingRowItem> parseTeamRankings(dynamic data) => _parse(data, players: false);

/// GET /rank/player → rows.
List<RankingRowItem> parsePlayerRankings(dynamic data) => _parse(data, players: true);

/// Case-insensitive name filter (RN searchQuery).
List<RankingRowItem> filterRankings(List<RankingRowItem> list, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return list;
  return list.where((e) => e.name.toLowerCase().contains(q)).toList();
}

/// Splits the visible list into podium (top 3) + rows (up to rank 100).
///
/// RN bug fixed: while searching RN hides the podium but still sliced the
/// results from index 3, so the first 3 matches were never shown. When a
/// search is active every match (max 100) goes into the rows.
({List<RankingRowItem> podium, List<RankingRowItem> rows}) splitForDisplay(List<RankingRowItem> list, {required bool searching}) {
  if (searching) return (podium: const [], rows: list.take(100).toList());
  return (
    podium: list.take(3).toList(),
    rows: list.length > 3 ? list.sublist(3, list.length > 100 ? 100 : list.length) : const [],
  );
}
