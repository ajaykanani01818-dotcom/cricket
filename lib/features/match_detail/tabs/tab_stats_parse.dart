import '../../../core/api/json.dart';

/// View-model for the Stats tab. Built from the `data` objects of
/// /match/:id/analytics, /match/:id/scoring-rate and /match/:id/boundaries
/// (each may be null when its request failed — RN `.catch(() => null)`).
/// Like RN, only the first innings of each team is shown (t1_1 / t2_1 /
/// innings[0]) and teams are labelled "Team 1" / "Team 2".

class BoundaryStat {
  const BoundaryStat({required this.fours, required this.sixes, required this.total});
  final int fours, sixes, total;
}

class StatsView {
  const StatsView({
    required this.scoringRate1,
    required this.scoringRate2,
    required this.boundaries1,
    required this.boundaries2,
    required this.dotBall1,
    required this.dotBall2,
  });

  /// Pre-formatted (`toFixed(2)`).
  final String scoringRate1, scoringRate2;
  final BoundaryStat boundaries1, boundaries2;

  /// Pre-formatted (`toFixed(1)` + '%').
  final String dotBall1, dotBall2;

  String get signature => '$scoringRate1|$scoringRate2|${boundaries1.fours},${boundaries1.sixes},${boundaries1.total}|'
      '${boundaries2.fours},${boundaries2.sixes},${boundaries2.total}|$dotBall1|$dotBall2';

  @override
  bool operator ==(Object other) => other is StatsView && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

double _num(dynamic v) {
  final n = J.number(v);
  return n == null || !n.isFinite ? 0 : n;
}

// Not J.integer: it throws on "NaN"/"Infinity" strings (double.toInt).
int _int(dynamic v) => _num(v).toInt();

StatsView parseStats({dynamic analytics, dynamic scoringRate, dynamic boundaries}) {
  BoundaryStat b(String team, String inn) {
    final m = J.at(boundaries, 'teams.$team.innings.$inn');
    final x = J.map(m);
    return BoundaryStat(fours: _int(x['fours']), sixes: _int(x['sixes']), total: _int(x['boundaries']));
  }

  return StatsView(
    scoringRate1: _num(J.at(scoringRate, 'teams.team1.innings.t1_1.scoringRate')).toStringAsFixed(2),
    scoringRate2: _num(J.at(scoringRate, 'teams.team2.innings.t2_1.scoringRate')).toStringAsFixed(2),
    boundaries1: b('team1', 't1_1'),
    boundaries2: b('team2', 't2_1'),
    dotBall1: '${_num(J.at(analytics, 'teams.team1.innings.0.dotBallPercentage')).toStringAsFixed(1)}%',
    dotBall2: '${_num(J.at(analytics, 'teams.team2.innings.0.dotBallPercentage')).toStringAsFixed(1)}%',
  );
}
