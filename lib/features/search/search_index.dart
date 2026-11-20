import 'dart:async';

import '../../core/api/json.dart';
import '../../core/services/cricket_services.dart';
import '../../core/utils/match_transform.dart';
import '../common/match_parsing.dart';
import '../common/match_time.dart';

/// There is no search endpoint (research §0.2, §8), so search is local:
/// an in-memory index of what the app has already loaded (Home and Live
/// feed it as they load) plus what [SearchIndex.warmUp] fetches once per
/// session: live / upcoming / recent matches, the series list and trending
/// players. Players are also looked up through the trending-players
/// endpoint's `search` parameter, which is the only server-side filter.

/// A series result.
class SeriesHit {
  const SeriesHit({
    required this.id,
    required this.name,
    this.dates,
    this.status,
  });
  final String id;
  final String name;

  /// "Nov 19 – Nov 29" when both dates parse.
  final String? dates;

  /// Sentence-case provider status ("Ongoing", "Upcoming").
  final String? status;

  static SeriesHit? fromJson(JsonMap s) {
    final name = J.text(s['name']);
    final id = J.text(s['sb_series_key']) ?? J.text(s['_id']);
    if (name == null || id == null) return null;
    final a = J.text(s['startDate']), b = J.text(s['endDate']);
    final st = J.text(s['seriesStatus']);
    return SeriesHit(
      id: id,
      name: name,
      dates: a != null && b != null
          ? '${formatShortDate(a)} – ${formatShortDate(b)}'
          : null,
      status: st == null ? null : sentenceCase(st),
    );
  }
}

/// A player result.
class PlayerHit {
  const PlayerHit({
    required this.key,
    required this.name,
    this.country,
    this.logo,
    this.raw = const {},
  });
  final String key;
  final String name;
  final String? country;
  final String? logo;
  final JsonMap raw;

  static PlayerHit? fromJson(JsonMap p) {
    final key = J.text(p['key']) ?? J.text(p['playerKey']);
    final name = J.text(p['name']) ?? J.text(p['playerName']);
    if (key == null || name == null) return null;
    return PlayerHit(
      key: key,
      name: name,
      country: J.text(p['country']),
      logo: J.text(p['logo']),
      raw: p,
    );
  }
}

class SearchResults {
  const SearchResults({
    this.matches = const [],
    this.series = const [],
    this.players = const [],
  });
  final List<MatchSummary> matches;
  final List<SeriesHit> series;
  final List<PlayerHit> players;
  bool get isEmpty => matches.isEmpty && series.isEmpty && players.isEmpty;
  int get length => matches.length + series.length + players.length;
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', //
};

/// Lower case, accents folded, "&" -> "and", punctuation -> spaces.
String normalizeForSearch(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll('&', ' and ')
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

bool _oneEditAway(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/// [t] is one edit away from [w] or from a prefix of it ("austrlia" ~
/// "australia", "cummns" ~ "cummins").
bool _typoMatch(String t, String w) {
  if (_oneEditAway(t, w)) return true;
  for (final n in [t.length, t.length + 1]) {
    if (w.length > n && _oneEditAway(t, w.substring(0, n))) return true;
  }
  return false;
}

/// Relevance of [haystack] for the query tokens: 0 = no match. Every token
/// must hit a word (prefix), the whole text (substring, 3+ letters) or,
/// for 5+ letters, a word one typo away.
int scoreText(List<String> tokens, String haystack) {
  if (tokens.isEmpty) return 0;
  final words = haystack.split(' ');
  var score = 0;
  for (final t in tokens) {
    if (words.contains(t)) {
      score += 4;
    } else if (words.any((w) => w.startsWith(t))) {
      score += 3;
    } else if (t.length >= 3 && haystack.contains(t)) {
      score += 2;
    } else if (t.length >= 5 && words.any((w) => _typoMatch(t, w))) {
      score += 1;
    } else {
      return 0;
    }
  }
  return score;
}

List<String> queryTokens(String q) =>
    normalizeForSearch(q).split(' ').where((t) => t.isNotEmpty).toList();

int _phaseRank(MatchSummary m) => m.isInProgress
    ? 0
    : m.isUpcoming
    ? 1
    : 2;

class SearchIndex {
  SearchIndex({MatchService? matchService, PlayerService? playerService})
    : _matchSvc = matchService,
      _playerSvc = playerService;

  /// Replaceable in tests.
  static SearchIndex instance = SearchIndex();

  final MatchService? _matchSvc;
  final PlayerService? _playerSvc;
  MatchService get _m => _matchSvc ?? MatchService.instance;
  PlayerService get _p => _playerSvc ?? PlayerService.instance;

  final _matches = <String, (MatchSummary, String)>{};

  /// Team names / codes only, per match id: a hit on a team outranks a hit on
  /// the venue or series name.
  final _matchTeams = <String, String>{};
  final _series = <String, (SeriesHit, String)>{};
  final _players = <String, (PlayerHit, String)>{};

  int get size => _matches.length + _series.length + _players.length;

  void addMatches(Iterable<MatchSummary> list) {
    for (final m in list) {
      if (m.id.isEmpty) continue;
      final hay = normalizeForSearch(
        [
          m.team1,
          m.team2,
          m.shortName(1) ?? '',
          m.shortName(2) ?? '',
          m.series,
          m.venue,
          m.name ?? '',
          m.format ?? '',
        ].join(' '),
      );
      _matches[m.id] = (m, hay);
      _matchTeams[m.id] = normalizeForSearch(
        [m.team1, m.team2, m.shortName(1) ?? '', m.shortName(2) ?? ''].join(' '),
      );
    }
  }

  void addSeries(Iterable<SeriesHit> list) {
    for (final s in list) {
      _series[s.id] = (s, normalizeForSearch(s.name));
    }
  }

  void addPlayers(Iterable<PlayerHit> list) {
    for (final p in list) {
      _players[p.key] = (p, normalizeForSearch('${p.name} ${p.country ?? ''}'));
    }
  }

  /// Local search over everything indexed. Matches: in progress first,
  /// then upcoming, then results; ties by relevance.
  SearchResults search(String query, {int perGroup = 8}) {
    final tokens = queryTokens(query);
    if (tokens.isEmpty) return const SearchResults();
    List<(T, int)> hits<T>(Map<String, (T, String)> m) => [
      for (final e in m.values)
        if (scoreText(tokens, e.$2) case final s when s > 0) (e.$1, s),
    ];

    // Matches: live first, then by relevance (a team-name hit counts double,
    // so "emirats" finds Emirates Eagles before a match merely played in the
    // Emirates), then upcoming before results.
    final ms = [
      for (final h in hits(_matches))
        (
          h.$1,
          h.$2 + 2 * scoreText(tokens, _matchTeams[h.$1.id] ?? ''),
        ),
    ]..sort((a, b) {
        final live = (a.$1.isInProgress ? 0 : 1).compareTo(b.$1.isInProgress ? 0 : 1);
        if (live != 0) return live;
        final rel = b.$2.compareTo(a.$2);
        return rel != 0 ? rel : _phaseRank(a.$1).compareTo(_phaseRank(b.$1));
      });
    final ss = hits(_series)..sort((a, b) => b.$2.compareTo(a.$2));
    final ps = hits(_players)..sort((a, b) => b.$2.compareTo(a.$2));
    return SearchResults(
      matches: [for (final h in ms.take(perGroup)) h.$1],
      series: [for (final h in ss.take(perGroup)) h.$1],
      players: [for (final h in ps.take(perGroup)) h.$1],
    );
  }

  Future<void>? _warm;
  DateTime? _warmedAt;

  /// Failure of the last warm-up when every source failed (null = fine).
  Object? warmError;

  /// Fetches the searchable lists (each failure is tolerated; [warmError]
  /// is set only when everything failed). Re-runs after 5 minutes.
  Future<void> warmUp({bool force = false}) {
    final fresh =
        _warmedAt != null &&
        DateTime.now().difference(_warmedAt!) < const Duration(minutes: 5);
    if (!force && fresh && warmError == null) return Future.value();
    return _warm ??= _doWarm().whenComplete(() => _warm = null);
  }

  Future<void> _doWarm() async {
    var ok = 0;
    Object? lastError;
    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
        ok++;
      } catch (e) {
        lastError = e;
      }
    }

    await Future.wait([
      run(
        () async =>
            addMatches(parseMatchList((await _m.getLiveMatches()).data)),
      ),
      run(
        () async =>
            addMatches(parseMatchList((await _m.getUpcomingMatches()).data)),
      ),
      run(
        () async =>
            addMatches(parseMatchList((await _m.getRecentMatches()).data)),
      ),
      run(
        () async =>
            addSeries(_parseSeries((await _m.getSeries(perPage: 50)).data)),
      ),
      run(
        () async => addPlayers(
          _parsePlayers((await _p.getTrendingPlayers(perPage: 50)).data),
        ),
      ),
    ]);
    _warmedAt = DateTime.now();
    warmError = ok == 0 ? lastError : null;
  }

  /// Server-side player lookup (trending players `search` param). Adds the
  /// hits to the index; throws on failure.
  Future<List<PlayerHit>> searchPlayers(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final res = await _p.getTrendingPlayers(search: q, perPage: 20);
    final list = _parsePlayers(res.data);
    addPlayers(list);
    return list;
  }

  static List<SeriesHit> _parseSeries(dynamic data) => [
    for (final s in J.maps(data is Map ? data['series'] ?? data['data'] : data))
      ?SeriesHit.fromJson(s),
  ];

  static List<PlayerHit> _parsePlayers(dynamic data) => [
    for (final p in J.maps(
      data is Map ? data['players'] ?? data['data'] : data,
    ))
      ?PlayerHit.fromJson(p),
  ];

  void clear() {
    _matches.clear();
    _matchTeams.clear();
    _series.clear();
    _players.clear();
    _warmedAt = null;
    warmError = null;
  }
}
