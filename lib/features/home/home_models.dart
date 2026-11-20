import '../../core/api/json.dart';
import '../common/match_time.dart';

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
    return SeriesTeam(
      label: J.text(t['short_name']) ?? J.text(t['name']) ?? 'TBD',
      logo: J.text(t['logo']),
    );
  }

  return UpcomingSeriesItem(
    id: id ?? 'series-$index',
    name: name ?? '-',
    dateRange:
        '${formatShortDate(J.str(s['startDate']))} – ${formatShortDate(J.str(s['endDate']))}',
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
