import 'package:intl/intl.dart';

import '../../core/utils/match_transform.dart';

/// Client-side filters for the Matches tab. Everything here works on the
/// lists that are already loaded: changing a filter never sends a request.

// ───────────────────────── Format ─────────────────────────

enum FormatFilter {
  all('All'),
  test('Test'),
  odi('ODI'),
  t20('T20'),
  other('Other');

  const FormatFilter(this.label);
  final String label;
}

/// Maps the provider `format` string to a chip bucket.
/// TEST → Test; ODI / OD → ODI; T20 / T20I → T20; anything else (T10,
/// The Hundred, List A, first-class, missing) → Other.
FormatFilter formatBucket(String? format) {
  final f = (format ?? '').trim().toUpperCase().replaceAll(' ', '');
  if (f.isEmpty) return FormatFilter.other;
  if (f.contains('TEST')) return FormatFilter.test;
  if (f == 'ODI' || f == 'OD' || f == 'ODIW' || f == 'WODI') return FormatFilter.odi;
  if (f == 'T20' || f == 'T20I' || f == 'T20W' || f == 'WT20' || f == 'WT20I') return FormatFilter.t20;
  return FormatFilter.other;
}

/// Display label for a provider format code: "TEST" → "Test", the others
/// keep their case (they are data: ODI, T20, T10).
String? formatLabel(String? format) {
  final f = format?.trim() ?? '';
  if (f.isEmpty) return null;
  if (f.toUpperCase() == 'TEST') return 'Test';
  return f;
}

// ───────────────────────── Women ─────────────────────────

final _womenWord = RegExp(r"\bwom[ae]n'?s?\b", caseSensitive: false);
final _womenSuffix = RegExp(r'\sW$');

/// Women's cricket is not a provider field, so it is derived from names.
///
/// Rule: a match counts as women's when the series name or either team name
/// contains the word "Women" / "Womens" / "Women's" (any case), or a team
/// name ends with a separate capital " W" (for example "India W").
/// The Women chip is shown only when at least one loaded match matches.
bool isWomenMatch(MatchSummary m) {
  if (_womenWord.hasMatch(m.series) || _womenWord.hasMatch(m.team1) || _womenWord.hasMatch(m.team2)) return true;
  return _womenSuffix.hasMatch(m.team1.trim()) || _womenSuffix.hasMatch(m.team2.trim());
}

// ───────────────────────── Day ─────────────────────────

DateTime dayOf(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Local calendar day a match starts on (null when the date is missing).
DateTime? matchDay(MatchSummary m) {
  final t = DateTime.tryParse(m.date.trim());
  return t == null ? null : dayOf(t);
}

/// "Yesterday" / "Today" / "Tomorrow" / "Thu 20 Nov" (local time).
String dayLabel(DateTime day, DateTime now) {
  final today = dayOf(now);
  final d = DateTime(day.year, day.month, day.day);
  final diff = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  return DateFormat(d.year == today.year ? 'EEE d MMM' : 'd MMM y', 'en_US').format(d);
}

// ───────────────────────── Combined ─────────────────────────

class MatchFilters {
  const MatchFilters({this.format = FormatFilter.all, this.women = false, this.day});

  final FormatFilter format;
  final bool women;

  /// Local day; null = all dates.
  final DateTime? day;

  bool get isDefault => format == FormatFilter.all && !women && day == null;
  bool get hasContentFilter => format != FormatFilter.all || women;

  MatchFilters copyWith({FormatFilter? format, bool? women, DateTime? day, bool clearDay = false}) =>
      MatchFilters(format: format ?? this.format, women: women ?? this.women, day: clearDay ? null : (day ?? this.day));

  /// [applyDay] is false on the Live segment (live means now).
  bool matches(MatchSummary m, {bool applyDay = true}) {
    if (format != FormatFilter.all && formatBucket(m.format) != format) return false;
    if (women && !isWomenMatch(m)) return false;
    if (applyDay && day != null) {
      final d = matchDay(m);
      if (d == null || d != day) return false;
    }
    return true;
  }

  List<MatchSummary> apply(List<MatchSummary> list, {bool applyDay = true}) => isDefault || (!hasContentFilter && !applyDay)
      ? list
      : [
          for (final m in list)
            if (matches(m, applyDay: applyDay)) m,
        ];

  @override
  bool operator ==(Object other) => other is MatchFilters && other.format == format && other.women == women && other.day == day;

  @override
  int get hashCode => Object.hash(format, women, day);
}

// ───────────────────────── Grouping ─────────────────────────

class SeriesGroup {
  SeriesGroup(this.key, this.title, this.seriesKey);
  final String key;
  final String title;
  final String? seriesKey;
  final List<MatchSummary> matches = [];
}

/// Groups by series. Group order = first appearance in [list]; rows keep the
/// provider order inside a group (upcoming arrive soonest-first, results
/// newest-first). A blank series name goes to "Other matches".
List<SeriesGroup> groupBySeries(List<MatchSummary> list) {
  final byKey = <String, SeriesGroup>{};
  final out = <SeriesGroup>[];
  for (final m in list) {
    final title = m.series.trim().isEmpty ? 'Other matches' : m.series.trim();
    final key = title.toLowerCase();
    final g = byKey.putIfAbsent(key, () {
      final ng = SeriesGroup(key, title, m.seriesKey);
      out.add(ng);
      return ng;
    });
    g.matches.add(m);
  }
  return out;
}
