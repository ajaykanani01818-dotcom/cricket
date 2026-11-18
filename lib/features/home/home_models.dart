import '../../core/api/json.dart';
import '../common/match_time.dart';

/// RN `Player` → `TopPlayerItem` (playerTransform + playerToTopPlayerItem).
class TopPlayer {
  const TopPlayer({required this.playerKey, required this.name, this.points, this.order, this.logo, this.raw = const {}});

  /// Empty when the API omitted `playerKey` (RN used a synthetic `player-N` id).
  final String playerKey;
  final String name;
  final num? points;
  final int? order;
  final String? logo;
  final JsonMap raw;

  String get pointsLabel => points == null ? '0' : _thousands(points!);
  String get orderLabel => order == null ? '-' : '$order';

  static String _thousands(num n) {
    final whole = n.round();
    final s = whole.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${whole < 0 ? '-' : ''}$b';
  }
}

List<TopPlayer> parseTopPlayers(dynamic data, {int limit = 5}) => [
      for (final p in J.maps(data).take(limit))
        TopPlayer(
          playerKey: J.text(p['playerKey']) ?? '',
          name: J.text(p['playerName']) ?? J.text(p['name']) ?? 'Unknown',
          points: J.number(p['points']),
          order: J.integer(p['order']),
          logo: J.text(p['logo']),
          raw: p,
        ),
    ];

enum PlayerCategory { batters, bowlers, allRounders }

class TopPlayers {
  const TopPlayers({this.batters = const [], this.bowlers = const [], this.allRounders = const []});
  final List<TopPlayer> batters, bowlers, allRounders;

  List<TopPlayer> of(PlayerCategory c) => switch (c) {
        PlayerCategory.batters => batters,
        PlayerCategory.bowlers => bowlers,
        PlayerCategory.allRounders => allRounders,
      };
}

class SeriesTeam {
  const SeriesTeam({required this.label, this.logo});
  final String label;
  final String? logo;
}

/// RN `ApiUpcomingSeries` (/series/upcoming item), pre-formatted for display.
class UpcomingSeriesItem {
  const UpcomingSeriesItem({
    required this.id,
    required this.name,
    required this.dateRange,
    this.sbSeriesKey,
    this.firstMatchSeriesId,
    this.firstMatchSeriesName,
    this.team1,
    this.team2,
  });

  final String id; // _id
  final String name;
  final String dateRange; // "Nov 19 – Nov 29"
  final String? sbSeriesKey;
  final String? firstMatchSeriesId, firstMatchSeriesName;
  final SeriesTeam? team1, team2;

  bool get hasFirstMatch => team1 != null || team2 != null;

  /// Ids worth trying on /series/:id, best first.
  List<String?> get idCandidates => [sbSeriesKey, id, firstMatchSeriesId];
}

UpcomingSeriesItem? parseUpcomingSeries(JsonMap s, int index) {
  final name = J.text(s['name']);
  final id = J.text(s['_id']) ?? J.text(s['sb_series_key']) ?? J.text(s['key']);
  if (name == null && id == null) return null;
  final fm = J.map(s['firstMatch']);
  SeriesTeam? team(String k) {
    final t = J.map(J.at(fm, 'teams.$k'));
    return SeriesTeam(label: J.text(t['short_name']) ?? J.text(t['name']) ?? 'TBD', logo: J.text(t['logo']));
  }

  return UpcomingSeriesItem(
    id: id ?? 'series-$index',
    name: name ?? '-',
    dateRange: '${formatShortDate(J.str(s['startDate']))} – ${formatShortDate(J.str(s['endDate']))}',
    sbSeriesKey: J.text(s['sb_series_key']),
    firstMatchSeriesId: J.text(fm['seriesId']),
    firstMatchSeriesName: J.text(fm['seriesName']),
    team1: fm.isEmpty ? null : team('t1'),
    team2: fm.isEmpty ? null : team('t2'),
  );
}

List<UpcomingSeriesItem> parseUpcomingSeriesList(dynamic data) {
  final out = <UpcomingSeriesItem>[];
  final list = J.maps(data);
  for (var i = 0; i < list.length; i++) {
    final s = parseUpcomingSeries(list[i], i);
    if (s != null) out.add(s);
  }
  return out;
}
