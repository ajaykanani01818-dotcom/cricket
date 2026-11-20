import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/logic/match_detail_logic.dart';
import 'package:crickbex/features/match_detail/logic/match_state.dart';
import 'package:crickbex/features/match_detail/tabs/tab_scorecard_parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

String label(MatchDetailVM m, TeamSide s) {
  final t = s == TeamSide.team1 ? m.t1 : m.t2;
  return t.name.length <= 16 ? t.name : t.code;
}

MatchSituation situate(JsonMap detail, {JsonMap? live, JsonMap? scorecard}) {
  final m = MatchDetailVM.fromJson(detail);
  final l = live == null ? null : LiveVM.fromJson(live);
  final sc = scorecard == null ? null : parseScorecard(scorecard);
  final inn = buildInnings(match: m, live: l, scorecard: sc, scorecardOrder: sc?.inningsOrder ?? const []);
  return deriveSituation(
    match: m,
    status: m.matchStatus,
    innings: inn,
    providerTarget: sc?.targetRuns,
    scorecardMaxOvers: sc?.maxOvers,
    teamLabel: (s) => label(m, s),
  );
}

void main() {
  group('resolveMatchStatus', () {
    test('maps raw words to readable labels and phases', () {
      expect(resolveMatchStatus('LIVE').phase, MatchPhase.live);
      expect(resolveMatchStatus('STUMPS').label, 'Stumps');
      expect(resolveMatchStatus('STUMPS').phase, MatchPhase.interrupted);
      expect(resolveMatchStatus('INNINGS_BREAK').label, 'Innings break');
      expect(resolveMatchStatus('rain delay').label, 'Rain delay');
      expect(resolveMatchStatus('NOT_STARTED').label, 'Upcoming');
      expect(resolveMatchStatus('COMPLETED').label, 'Result');
      expect(resolveMatchStatus('DRAWN').label, 'Match drawn');
      expect(resolveMatchStatus('ABANDONED').phase, MatchPhase.abandoned);
      expect(resolveMatchStatus('NO_RESULT').label, 'No result');
      expect(resolveMatchStatus('MATCH_CALLED_OFF').label, 'Match called off');
      expect(resolveMatchStatus('MATCH_CALLED_OFF').phase, MatchPhase.unknown);
      expect(resolveMatchStatus('').label, 'Status not available');
      expect(resolveMatchStatus(null).phase, MatchPhase.unknown);
    });

    test('a result message means finished, whatever the status says', () {
      expect(resolveMatchStatus('LIVE', resultMessage: 'X won by 3 runs').phase, MatchPhase.completed);
      expect(resolveMatchStatus('', resultMessage: 'X won').phase, MatchPhase.completed);
      expect(resolveMatchStatus('ABANDONED', resultMessage: 'No result').phase, MatchPhase.abandoned);
    });
  });

  group('parseScoreString', () {
    test('accepts real shapes, rejects multi-innings and junk', () {
      expect(parseScoreString('137/4 (9.5)'), const ParsedScore(runs: 137, wickets: 4, overs: '9.5'));
      expect(parseScoreString('0/0'), const ParsedScore(runs: 0, wickets: 0));
      expect(parseScoreString('400'), const ParsedScore(runs: 400));
      expect(parseScoreString(''), isNull);
      expect(parseScoreString('-'), isNull);
      expect(parseScoreString('400 & 186/3'), isNull);
      expect(parseScoreString('Yet to bat'), isNull);
    });
  });

  group('header states', () {
    test('limited overs, 1st innings (real ODI shape: inningsOrder lists the planned 2nd innings)', () {
      final s = situate(odiFirstInningsDetail(), live: odiFirstInningsLive());
      expect(s.status.phase, MatchPhase.live);
      expect(s.innings, hasLength(1), reason: 'AUS has no score yet: their innings has not started');
      expect(s.current!.side, TeamSide.team2);
      expect(s.current!.scoreText, '126/2');
      expect(s.currentRunRate, '6.63');
      expect(s.chase, isNull);
      expect(s.headline, isNull, reason: 'no chase equation in a first innings');
      expect(s.projection, isNull, reason: 'maxOvers not supplied → no projection');
      // With a provider overs limit the arithmetic projection appears.
      final withMax = situate(odiFirstInningsDetail(), live: odiFirstInningsLive(), scorecard: scorecardWith(maxOvers: '50', innings: [
        inningsJson('England', 'ENG', 126, 2, '19.0'),
      ], order: ['t2_1', 't1_1']));
      expect(withMax.projection, 'At this rate: 332');
    });

    test('T20 chase: plain-language equation only when derivable; target derived = 1st inns + 1', () {
      final s = situate(t20ChaseDetail(), live: t20ChaseLive());
      expect(s.chase, isNotNull);
      expect(s.chase!.target, 132);
      expect(s.chase!.targetDerived, isTrue);
      expect(s.chase!.runsNeeded, 87);
      expect(s.chase!.ballsLeft, 95);
      expect(s.chase!.ballsEstimated, isTrue, reason: 'format default, not provider maxOvers');
      expect(s.headline, 'UAE Bulls need 87 runs');
      expect(s.subline, 'About 95 balls left (est.)');

      final exact = situate(t20ChaseDetail(), live: t20ChaseLive(), scorecard: scorecardWith(maxOvers: '20', target: 140, innings: [
        inningsJson('Royal Desert Champions', 'RDC', 131, 1, '20.0'),
        inningsJson('UAE Bulls', 'UAEB', 45, 2, '4.1'),
      ], order: ['t2_1', 't1_1']));
      expect(exact.chase!.targetDerived, isFalse);
      expect(exact.headline, 'UAE Bulls need 95 from 95 balls');
      expect(exact.chase!.requiredRate, '6.00');
    });

    test('never "need 0": a chase already reached shows no equation', () {
      final live = t20ChaseLive();
      J.map(J.at(live, 'score.teams.team1'))['inningsStats'] = {'runs': 132, 'wickets': 2, 'overs': '15.0'};
      final s = situate(t20ChaseDetail(), live: live);
      expect(s.chase, isNull);
      expect(s.headline, isNull);
    });

    test('Test: trail, lead and need-to-win lines; no balls-left fields', () {
      // Real fixture: BAN 400, RSA 287/4 (live), status STUMPS.
      final trail = situate(liveDetailData(), live: J.map(fixture('match_live')['data']), scorecard: J.map(fixture('match_scorecard')['data']));
      expect(trail.isTest, isTrue);
      expect(trail.status.label, 'Stumps');
      expect(trail.headline, 'South Africa trail by 113');
      expect(trail.chase, isNull);
      expect(trail.scoreLineOf(TeamSide.team2), '400');

      final lead = situate(testDetail(order: ['t2_1', 't1_1']), scorecard: scorecardWith(innings: [
        inningsJson('Sri Lanka', 'SL', 98, 10, '35.3'),
        inningsJson('Pakistan', 'PAK', 135, 4, '42.0'),
      ], order: ['t2_1', 't1_1']));
      expect(lead.headline, 'Pakistan lead by 37');

      final fourth = situate(testDetail(order: ['t2_1', 't1_1', 't2_2', 't1_2']), scorecard: scorecardWith(innings: [
        inningsJson('Sri Lanka', 'SL', 300, 10, '90.0'),
        inningsJson('Pakistan', 'PAK', 250, 10, '80.0'),
        inningsJson('Sri Lanka', 'SL', 200, 10, '60.0'),
        inningsJson('Pakistan', 'PAK', 120, 3, '40.0'),
      ], order: ['t2_1', 't1_1', 't2_2', 't1_2']));
      expect(fourth.headline, 'Pakistan need 131 to win');
      expect(fourth.scoreLineOf(TeamSide.team1), '250 & 120/3');
      expect(fourth.scoreLineOf(TeamSide.team2), '300 & 200');
    });

    test('Test without a scorecard never splits a team\'s two innings', () {
      final d = testDetail(order: ['t2_1', 't1_1', 't2_2']);
      J.map(J.at(d, 'teams.t2'))['score'] = '300 & 120/2';
      J.map(J.at(d, 'teams.t1'))['score'] = '250/10 (80.0)';
      final s = situate(d);
      expect(s.innings.map((i) => i.side), [TeamSide.team1], reason: 'the multi-innings string is not parsed');
      expect(s.headline, isNull);
    });

    test('stumps: score frozen and the latest info note is the status note', () {
      final live = LiveVM.fromJson(J.map(fixture('match_live')['data']));
      expect(latestInfoNote(live), startsWith('9:00pm Ist / 5:30pm LT: Stumps on Day 2.'));
      expect(latestInfoNote(null), isNull);
    });

    test('upcoming: countdown ticks in minutes and says when it is due', () {
      final start = DateTime(2026, 11, 20, 9, 30);
      expect(countdownLabel(start, DateTime(2026, 11, 18, 5, 0)), 'Starts in 2d 4h');
      expect(countdownLabel(start, DateTime(2026, 11, 20, 6, 15)), 'Starts in 3h 15m');
      expect(countdownLabel(start, DateTime(2026, 11, 20, 9, 18, 30)), 'Starts in 12m');
      expect(countdownLabel(start, DateTime(2026, 11, 20, 9, 31)), isNull);
      final s = situate(upcomingDetail());
      expect(s.status.phase, MatchPhase.upcoming);
      expect(s.innings, isEmpty);
      expect(s.headline, isNull);
    });

    test('completed: result headline, winner resolved from winnerTeamKey', () {
      // The list item has no innings order: who batted first is unknown, so
      // no innings are built (the header shows the raw team scores).
      expect(situate(completedT10Detail()).innings, isEmpty);
      final s = situate(completedT10Detail()..['inningsOrder'] = ['t2_1', 't1_1']);
      expect(s.status.phase, MatchPhase.completed);
      expect(s.headline, 'UAE Bulls won by 6 wickets');
      expect(s.winner, TeamSide.team1);
      expect(s.scoreLineOf(TeamSide.team1), '137/4');
      expect(s.scoreLineOf(TeamSide.team2), '131/1');
    });

    test('abandoned / no result: label only, never zeros', () {
      final d = upcomingDetail()..['status'] = 'ABANDONED';
      final s = situate(d);
      expect(s.status.label, 'Abandoned');
      expect(s.innings, isEmpty);
      expect(s.headline, isNull);
      expect(s.scoreLineOf(TeamSide.team1), isNull);
      expect(s.currentRunRate, isNull);
    });

    test('malformed payload degrades without throwing', () {
      final s = situate({'_id': 'x', 'status': 'LIVE', 'teams': {'t1': {}, 't2': 'bad'}, 'inningsOrder': 'x'}, live: {'score': 'nope'});
      expect(s.innings, isEmpty);
      expect(s.headline, isNull);
      expect(s.status.phase, MatchPhase.live);
    });
  });

  group('overs for the Seam strip', () {
    test('current over from the live feed (+ previous overs), labels in bowling order', () {
      final m = MatchDetailVM.fromJson(liveDetailData());
      final live = LiveVM.fromJson(J.map(fixture('match_live')['data']));
      final overs = buildOverViews(match: m, live: live);
      expect(overs.first.overNumber, 62);
      expect(overs.first.labels, ['0', '4', '0', '0', '1', '0']);
      expect(overs.first.runs, 5);
      expect(overs.first.bowler, 'Taskin Ahmed');
      expect(overs.first.inProgress, isFalse);
      expect(overs.skip(1).map((o) => o.overNumber), [61, 60, 59, 58]);
      final nb = buildOverViews(match: m, live: live, maxPrevious: 10).firstWhere((o) => o.overNumber == 57);
      expect(nb.labels, ['0', '0', 'NB', '0', '1', '0', '0'], reason: 'extras are never dropped');
    });

    test('falls back to the detail current over; in-progress runs only when exact', () {
      final m = MatchDetailVM.fromJson(liveDetailData());
      final overs = buildOverViews(match: m);
      expect(overs.single.overNumber, 62);
      expect(overs.single.labels.length, 6);

      final feed = {
        'balls': [
          {'type': 'ball', 'value': '1WD', 'overNumber': 3, 'ballNumber': 2, 'inningsIndex': 't1_1'},
          {'type': 'ball', 'value': '4', 'overNumber': 3, 'ballNumber': 1, 'inningsIndex': 't1_1'},
        ],
      };
      final inProgress = buildOverViews(match: m, live: LiveVM.fromJson(feed));
      expect(inProgress.first.labels, ['4', '1WD']);
      expect(inProgress.first.overNumber, 4);
      expect(inProgress.first.inProgress, isTrue);
      expect(inProgress.first.runs, isNull, reason: 'extras: provider total unknown');
    });
  });
}
