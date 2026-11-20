import '../../../core/api/json.dart';

/// View-models for the Scorecard tab, built once per new scorecard payload.
/// Every display string is pre-formatted here so `build` does no parsing.
/// Equality is by [signature] (all displayed values), so a poll that returns
/// identical data keeps the previous view-model and skips the rebuild.

class ScorecardTeamMeta {
  const ScorecardTeamMeta({this.logo, required this.displayShort});
  final String? logo;
  final String displayShort;
}

/// Port of RN `getScorecardTeamMeta` (components/match/matchUtils.ts).
ScorecardTeamMeta scorecardTeamMeta(JsonMap scorecard, JsonMap inning, int inningIndex) {
  final rawInfo = inning['teamInfo'];
  if (rawInfo is! Map) return const ScorecardTeamMeta(displayShort: 'Team');
  final info = J.map(rawInfo);
  final infoName = J.str(info['teamName']);
  final infoShort = J.str(info['shortName']);
  String firstNonEmpty(List<String> v, String fb) => v.firstWhere((s) => s.isNotEmpty, orElse: () => fb);

  final teams = J.map(scorecard['teams']);
  final rawT1 = teams['team1'];
  final rawT2 = teams['team2'];
  if (rawT1 is! Map || rawT2 is! Map) {
    return ScorecardTeamMeta(displayShort: firstNonEmpty([infoShort, infoName], 'Inn ${inningIndex + 1}'));
  }
  final t1 = J.map(rawT1);
  final t2 = J.map(rawT2);
  String? logoOf(JsonMap t) => J.text(t['logo']);

  bool matches(JsonMap t) {
    final tn = J.str(t['name']).trim().toLowerCase();
    final ts = J.str(t['shortName']).trim().toLowerCase();
    final un = infoName.trim().toLowerCase();
    final us = infoShort.trim().toLowerCase();
    if (un.isNotEmpty && tn.isNotEmpty && (tn == un || tn.contains(un) || un.contains(tn))) return true;
    if (us.isNotEmpty && ts.isNotEmpty && (ts == us || (tn.isNotEmpty && tn.contains(us)) || (un.isNotEmpty && un.contains(ts)))) {
      return true;
    }
    return false;
  }

  if (matches(t1)) {
    return ScorecardTeamMeta(logo: logoOf(t1), displayShort: firstNonEmpty([J.str(t1['shortName']), infoShort, infoName], ''));
  }
  if (matches(t2)) {
    return ScorecardTeamMeta(logo: logoOf(t2), displayShort: firstNonEmpty([J.str(t2['shortName']), infoShort, infoName], ''));
  }
  final order = J.list(scorecard['inningsOrder']);
  final k = inningIndex < order.length && order[inningIndex] != null ? J.str(order[inningIndex]).toLowerCase() : '';
  if (k.contains('t1') || k == 'team1') {
    return ScorecardTeamMeta(logo: logoOf(t1), displayShort: firstNonEmpty([J.str(t1['shortName']), infoShort], ''));
  }
  if (k.contains('t2') || k == 'team2') {
    return ScorecardTeamMeta(logo: logoOf(t2), displayShort: firstNonEmpty([J.str(t2['shortName']), infoShort], ''));
  }
  return ScorecardTeamMeta(
    logo: inningIndex % 2 == 0 ? logoOf(t1) : logoOf(t2),
    displayShort: firstNonEmpty([infoShort, infoName], 'Inn ${inningIndex + 1}'),
  );
}

class ScBatter {
  const ScBatter({
    required this.id,
    required this.name,
    required this.isOut,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    required this.outLine,
  });
  final String id, name, runs, balls, fours, sixes, strikeRate, outLine;
  final bool isOut;
}

class ScBowler {
  const ScBowler({
    required this.id,
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
  });
  final String id, name, overs, maidens, runs, wickets, economy;
}

class ScFow {
  const ScFow({required this.id, required this.name, required this.score, required this.over});
  final String id, name, score, over;
}

class ScYetToBat {
  const ScYetToBat({required this.id, required this.name});
  final String id, name;
}

class ScInning {
  const ScInning({
    required this.id,
    required this.teamName,
    required this.shortName,
    required this.runs,
    required this.wickets,
    required this.overs,
    required this.extras,
    required this.extrasDetail,
    required this.logo,
    required this.batting,
    required this.bowling,
    required this.fallOfWickets,
    required this.yetToBat,
  });
  final String id, teamName, runs, wickets, overs, extras, extrasDetail;
  final String? shortName, logo;
  final List<ScBatter> batting;
  final List<ScBowler> bowling;
  final List<ScFow> fallOfWickets;
  final List<ScYetToBat> yetToBat;
}

class ScorecardView {
  const ScorecardView({
    required this.target,
    required this.innings,
    required this.signature,
    this.inningsOrder = const [],
    this.maxOvers,
  });
  final String? target;
  final List<ScInning> innings;
  final String signature;

  /// Raw `inningsOrder` keys ("t2_1", "t1_1") aligned with [innings].
  final List<String> inningsOrder;

  /// Raw `maxOvers` ('' → null).
  final String? maxOvers;

  /// Provider target as a number (null when absent).
  int? get targetRuns => target == null ? null : int.tryParse(target!.trim());

  static const empty = ScorecardView(target: null, innings: [], signature: '');

  bool get hasInnings => innings.isNotEmpty;

  @override
  bool operator ==(Object other) => other is ScorecardView && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// `-` for missing values (RN would render an empty cell).
String _val(dynamic v) => J.text(v) ?? '-';

/// RN `x || 0`.
String _orZero(dynamic v) {
  if (v == null || v == false || v == '' || v == 0) return '0';
  return J.text(v) ?? '0';
}

/// RN `x?.toFixed(2) || '0.00'`.
String _fixed2(dynamic v) {
  final n = J.number(v);
  return n == null || !n.isFinite ? '0.00' : n.toStringAsFixed(2);
}

/// Accepts either the `data` object of GET /match/:id/scorecard (which wraps
/// the scorecard in `result`) or the `result` object itself (what RN passes).
ScorecardView parseScorecard(JsonMap? input) {
  if (input == null) return ScorecardView.empty;
  var sc = input;
  if (sc['innings'] is! List && sc['result'] is Map) sc = J.map(sc['result']);
  final rawInnings = J.maps(sc['innings']);
  final sig = StringBuffer();

  final t = sc['targetRuns'];
  final target = t == null || (t is String && t.isEmpty) ? null : J.str(t);
  sig.write('T:$target|');

  final innings = <ScInning>[];
  for (var i = 0; i < rawInnings.length; i++) {
    final inn = rawInnings[i];
    final ti = J.map(inn['teamInfo']);
    final meta = scorecardTeamMeta(sc, inn, i);

    final batting = <ScBatter>[];
    final rawBat = J.maps(inn['batting']);
    for (var b = 0; b < rawBat.length; b++) {
      final r = rawBat[b];
      final isOut = J.boolean(r['isOut']);
      batting.add(ScBatter(
        id: J.text(r['_id']) ?? 'bat$b',
        name: J.str(r['playerName']),
        isOut: isOut,
        runs: _val(r['runs']),
        balls: _val(r['ballsFaced']),
        fours: _orZero(r['fours']),
        sixes: _orZero(r['sixes']),
        strikeRate: _fixed2(r['strikeRate']),
        outLine: isOut ? J.str(r['outSummary']).trim() : '',
      ));
    }

    final bowling = <ScBowler>[];
    final rawBowl = J.maps(inn['bowling']);
    for (var b = 0; b < rawBowl.length; b++) {
      final r = rawBowl[b];
      bowling.add(ScBowler(
        id: J.text(r['_id']) ?? 'bowl$b',
        name: J.str(r['playerName']),
        overs: _val(r['overs']),
        maidens: _orZero(r['maidens']),
        runs: _orZero(r['runsConceded']),
        wickets: _orZero(r['wickets']),
        economy: _fixed2(r['economyRate']),
      ));
    }

    final fow = <ScFow>[];
    final rawFow = J.maps(inn['fallOfWickets']);
    for (var f = 0; f < rawFow.length; f++) {
      final r = rawFow[f];
      fow.add(ScFow(id: J.text(r['_id']) ?? 'fow$f', name: J.str(r['playerName']), score: _val(r['score']), over: _val(r['over'])));
    }

    final ytb = <ScYetToBat>[];
    final rawYtb = J.maps(inn['yetToBat']);
    for (var y = 0; y < rawYtb.length; y++) {
      ytb.add(ScYetToBat(id: J.text(rawYtb[y]['_id']) ?? 'ytb$y', name: J.str(rawYtb[y]['playerName'])));
    }

    final extrasRaw = ti['extras'];
    final inning = ScInning(
      id: J.text(inn['_id']) ?? 'inn$i',
      teamName: J.text(ti['teamName']) ?? '-',
      shortName: J.text(ti['shortName']),
      runs: _val(ti['runs']),
      wickets: _val(ti['wickets']),
      overs: _val(ti['overs']),
      extras: extrasRaw == null ? '0' : J.str(extrasRaw),
      extrasDetail: J.str(ti['extrasDetail']).trim(),
      logo: meta.logo,
      batting: batting,
      bowling: bowling,
      fallOfWickets: fow,
      yetToBat: ytb,
    );
    innings.add(inning);

    sig
      ..write('I:${inning.id}:${inning.teamName}:${inning.shortName}:${inning.runs}/${inning.wickets}:${inning.overs}:')
      ..write('${inning.extras}:${inning.extrasDetail}:${inning.logo}|');
    for (final x in batting) {
      sig.write('b:${x.id}:${x.name}:${x.isOut}:${x.runs}:${x.balls}:${x.fours}:${x.sixes}:${x.strikeRate}:${x.outLine}|');
    }
    for (final x in bowling) {
      sig.write('w:${x.id}:${x.name}:${x.overs}:${x.maidens}:${x.runs}:${x.wickets}:${x.economy}|');
    }
    for (final x in fow) {
      sig.write('f:${x.id}:${x.name}:${x.score}:${x.over}|');
    }
    for (final x in ytb) {
      sig.write('y:${x.id}:${x.name}|');
    }
  }
  final order = J.list(sc['inningsOrder']).map((e) => J.str(e)).toList(growable: false);
  final maxOvers = J.text(sc['maxOvers']);
  sig.write('O:${order.join(',')}|M:$maxOvers');
  return ScorecardView(
    target: target,
    innings: innings,
    signature: sig.toString(),
    inningsOrder: order,
    maxOvers: maxOvers,
  );
}
