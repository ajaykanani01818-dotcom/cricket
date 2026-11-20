import '../../core/api/json.dart';
import '../../core/services/cricket_services.dart';

/// Ported from the RN "open series detail" logic shared by HomeScreen
/// (`openSeriesDetailFromHome`) and PopularSeriesQuickAction: list items carry
/// several possible ids (`_id`, `firstMatch.seriesId`, ...) and not all of
/// them resolve on `/series/:id`, so:
///  1. look the series up by name/id in the catalog (`/series?perPage=100`)
///     and try its `sb_series_key` / `key` / `_id` first,
///  2. probe `/series/:id` for each candidate and use the first that works,
///  3. fall back to the first candidate.
/// Returns null when there is no candidate at all (RN then opens the Series tab).
Future<String?> resolveSeriesId(
  MatchService service, {
  required List<String?> candidates,
  String? name,
  String? altName,
}) async {
  final ids = <String>[
    for (final c in candidates)
      if (c != null && c.trim().isNotEmpty) c.trim(),
  ];
  if (ids.isEmpty) return null;

  try {
    final catalog = (await service.getSeries(page: 1, perPage: 100)).dataList;
    JsonMap? hit;
    for (final s in catalog) {
      final n = J.text(s['name']);
      final keys = [
        J.text(s['sb_series_key']),
        J.text(s['key']),
        J.text(s['_id']),
      ];
      if ((n != null && (n == name || n == altName)) ||
          keys.any((k) => k != null && ids.contains(k))) {
        hit = s;
        break;
      }
    }
    if (hit != null) {
      for (final id in [
        J.text(hit['sb_series_key']),
        J.text(hit['key']),
        J.text(hit['_id']),
      ]) {
        // Same order as RN (each catalog id is unshifted in turn).
        if (id != null && !ids.contains(id)) ids.insert(0, id);
      }
    }
  } catch (_) {
    // ignore — fall through to probing
  }

  for (final id in ids) {
    try {
      await service.getSeriesFixtures(id);
      return id;
    } catch (_) {
      // try next
    }
  }
  return ids.first;
}
