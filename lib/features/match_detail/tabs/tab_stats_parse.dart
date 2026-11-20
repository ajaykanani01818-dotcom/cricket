import '../../../core/api/json.dart';

/// View-model for the Stats tab, built from the `data` objects of
/// /match/:id/analytics, /match/:id/scoring-rate and /match/:id/boundaries
/// (each may be null when its request failed). Every innings the provider
/// sent is kept (Tests have up to four). A value the provider did not send
/// stays null and is shown as not available, never as 0.

class BowlerEconomy {
  const BowlerEconomy({required this.name, required this.economy, this.overs, this.wickets});
  final String name;
  final double economy;
  final String? overs;
  final int? wickets;
}

class InningsStatsVM {
  const InningsStatsVM({
    required this.key,
    required this.teamCode,
    required this.number,
    this.overRuns = const [],
    this.dotBalls,
    this.totalBalls,
    this.dotPercent,
    this.runRate,
    this.runs,
    this.overs,
    this.fours,
    this.sixes,
    this.boundaries,
    this.bowling = const [],
  });

  /// Innings key, e.g. "t1_1".
  final String key;
  final String teamCode;

  /// 1-based innings number for the team.
  final int number;

  /// Runs per over, index 0 = over 1.
  final List<int> overRuns;
  final int? dotBalls, totalBalls;
  final double? dotPercent;
  final double? runRate;
  final int? runs;
  final String? overs;
  final int? fours, sixes, boundaries;
  final List<BowlerEconomy> bowling;

  String get label => '$teamCode ${_ordinal(number)} innings';
  String get shortLabel => '$teamCode ${_ordinal(number)}';

  String get signature =>
      '$key|$teamCode|${overRuns.join(',')}|$dotBalls|$totalBalls|$dotPercent|$runRate|$runs|$overs|$fours|$sixes|$boundaries|'
      '${bowling.map((b) => '${b.name}:${b.economy}:${b.overs}:${b.wickets}').join(',')}';
}

String _ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };

class StatsView {
  const StatsView({required this.innings});
  final List<InningsStatsVM> innings;

  bool get isEmpty => innings.isEmpty;

  String get signature => innings.map((i) => i.signature).join('||');

  @override
  bool operator ==(Object other) => other is StatsView && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

double? _num(dynamic v) {
  final n = J.number(v);
  return n == null || !n.isFinite ? null : n.toDouble();
}

int? _int(dynamic v) => _num(v)?.round();

/// [order] = innings order keys (e.g. scorecard `inningsOrder`) used to
/// sort; keys not in it go last.
StatsView parseStats({dynamic analytics, dynamic scoringRate, dynamic boundaries, List<String> order = const []}) {
  final byKey = <String, Map<String, dynamic>>{};
  final codes = <String, String>{};

  void team(String teamKey, String fallbackCode) {
    final a = J.map(J.at(analytics, 'teams.$teamKey'));
    final s = J.map(J.at(scoringRate, 'teams.$teamKey'));
    final b = J.map(J.at(boundaries, 'teams.$teamKey'));
    final code = J.text(a['shortName']) ?? J.text(s['shortName']) ?? J.text(b['shortName']) ?? J.text(a['name']) ?? fallbackCode;
    for (final inn in J.maps(a['innings'])) {
      final k = J.text(inn['inningsIndex']);
      if (k == null) continue;
      (byKey[k] ??= {})['a'] = inn;
      codes[k] = code;
    }
    final sInn = J.map(s['innings']);
    for (final e in sInn.entries) {
      if (e.value is! Map) continue;
      (byKey[e.key] ??= {})['s'] = J.map(e.value);
      codes[e.key] = code;
    }
    final bInn = J.map(b['innings']);
    for (final e in bInn.entries) {
      if (e.value is! Map) continue;
      (byKey[e.key] ??= {})['b'] = J.map(e.value);
      codes[e.key] = code;
    }
  }

  team('team1', 'Team 1');
  team('team2', 'Team 2');

  final keys = byKey.keys.toList()
    ..sort((x, y) {
      final ix = order.indexOf(x), iy = order.indexOf(y);
      if (ix != -1 || iy != -1) {
        if (ix == -1) return 1;
        if (iy == -1) return -1;
        return ix.compareTo(iy);
      }
      // Fallback: innings number, then team.
      final nx = int.tryParse(x.split('_').last) ?? 0, ny = int.tryParse(y.split('_').last) ?? 0;
      return nx != ny ? nx.compareTo(ny) : x.compareTo(y);
    });

  final out = <InningsStatsVM>[];
  for (final k in keys) {
    final parts = byKey[k]!;
    final a = parts['a'] as Map<String, dynamic>?;
    final s = parts['s'] as Map<String, dynamic>?;
    final b = parts['b'] as Map<String, dynamic>?;

    final overs = J.maps(a?['overs']).where((o) => J.integer(o['overNumber']) != null).toList()
      ..sort((x, y) => J.integer(x['overNumber'])!.compareTo(J.integer(y['overNumber'])!));
    final runs = <int>[];
    if (overs.isNotEmpty) {
      final base = J.integer(overs.first['overNumber'])! == 0 ? 0 : 1;
      final last = J.integer(overs.last['overNumber'])! - base;
      final list = List<int>.filled(last + 1, 0);
      for (final o in overs) {
        final i = J.integer(o['overNumber'])! - base;
        if (i >= 0 && i < list.length) list[i] = _int(o['runs']) ?? 0;
      }
      runs.addAll(list);
    }

    final bowling = <BowlerEconomy>[];
    for (final r in J.maps(s?['bowling'])) {
      final e = _num(r['economyRate']) ?? _num(r['economy']);
      final name = J.text(r['playerName']) ?? J.text(r['name']);
      if (e == null || name == null) continue;
      bowling.add(BowlerEconomy(name: name, economy: e, overs: J.text(r['overs']), wickets: _int(r['wickets'])));
    }

    out.add(InningsStatsVM(
      key: k,
      teamCode: codes[k] ?? k,
      number: int.tryParse(k.split('_').last) ?? 1,
      overRuns: runs,
      dotBalls: _int(a?['dotBalls']),
      totalBalls: _int(a?['totalBalls']),
      dotPercent: _num(a?['dotBallPercentage']),
      runRate: _num(s?['scoringRate']),
      runs: _int(s?['runs']),
      overs: J.text(s?['overs']),
      fours: _int(b?['fours']),
      sixes: _int(b?['sixes']),
      boundaries: _int(b?['boundaries']),
      bowling: bowling,
    ));
  }
  return StatsView(innings: out);
}

/// Over (1-based) in which a wicket fell, from a fall-of-wickets over
/// string: "1.3" → 2, "43.0"/"43" → 43.
int? wicketOverFromFow(String over) {
  final t = over.trim();
  final m = RegExp(r'^(\d+)(?:\.(\d))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final ball = int.tryParse(m.group(2) ?? '0') ?? 0;
  return ball == 0 ? whole : whole + 1;
}
