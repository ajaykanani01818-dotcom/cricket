import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/logic/match_detail_logic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('timestamps & date label', () {
    test('parseMatchStartTimestampSeconds', () {
      expect(parseMatchStartTimestampSeconds(1794729600), 1794729600);
      expect(parseMatchStartTimestampSeconds('1,794,729,600'), 1794729600);
      expect(parseMatchStartTimestampSeconds(1794729600123), 1794729600);
      expect(parseMatchStartTimestampSeconds(null), isNull);
      expect(parseMatchStartTimestampSeconds(''), isNull);
      expect(parseMatchStartTimestampSeconds('abc'), isNull);
      expect(parseMatchStartTimestampSeconds(-5), isNull);
    });

    test('formatMatchDateTime prefers timestamp, falls back to startDate, null when neither', () {
      final s = formatMatchDateTime(null, 1794729600)!;
      expect(s, matches(RegExp(r'^\w{3}, \w{3} \d{1,2}, 2026 · \d{1,2}:\d{2} (AM|PM)$')));
      expect(formatMatchDateTime('2026-11-15T08:00:00.000Z', null), isNotNull);
      expect(formatMatchDateTime('garbage', 'x'), isNull);
      expect(formatMatchDateTime(null, null), isNull);
    });
  });

  group('score formatting', () {
    test('formatTeamScoreLine guards breaks', () {
      expect(stripJoiners(formatTeamScoreLine('386', '7', '90.0')), '386/7 (90.0)');
      expect(formatTeamScoreLine('386', '7', '90.0'), contains('⁠/⁠'));
      expect(stripJoiners(formatTeamScoreLine('10', '0')), '10/0');
      expect(stripJoiners(formatTeamScoreLine('10', '0', '')), '10/0');
    });

    test('formatTeamScoreFromApi', () {
      expect(formatTeamScoreFromApi(null), '-');
      expect(formatTeamScoreFromApi(''), '-');
      expect(formatTeamScoreFromApi(' - '), '-');
      expect(stripJoiners(formatTeamScoreFromApi('120/3 & 45/1 (12.4)')), '120/3 & 45/1 (12.4)');
      expect(stripJoiners(formatTeamScoreFromApi('Yet to bat')), 'Yet to bat');
    });

    test('parseScore', () {
      expect(parseScore('386/7 (90.0)'), const TeamScore('386', '7', '90.0'));
      expect(parseScore('386/7(90)'), const TeamScore('386', '7', '90'));
      expect(parseScore('386'), isNull);
      expect(parseScore(null), isNull);
    });

    test('headerScoreText: live inningsStats > parsed API > raw API', () {
      expect(stripJoiners(headerScoreText(live: const TeamScore('287', '4', '62.0'), apiScore: '386/7 (90.0)')), '287/4 (62.0)');
      expect(stripJoiners(headerScoreText(apiScore: '386/7 (90.0)')), '386/7 (90.0)');
      expect(stripJoiners(headerScoreText(apiScore: '150')), '150');
      expect(headerScoreText(apiScore: null), '-');
    });

    test('teamScoreFromInningsStats handles numbers, strings and junk', () {
      expect(teamScoreFromInningsStats({'runs': 287, 'wickets': 4, 'overs': '62.0'}), const TeamScore('287', '4', '62.0'));
      expect(teamScoreFromInningsStats({'runs': '12'}), const TeamScore('12', '0'));
      expect(teamScoreFromInningsStats({}), isNull);
      expect(teamScoreFromInningsStats('x'), isNull);
    });
  });

  group('chips / overs', () {
    test('inferRunsFromChip & isWicketChip & derive', () {
      expect(inferRunsFromChip('4'), 4);
      expect(inferRunsFromChip('L2'), 2);
      expect(inferRunsFromChip('WD'), 0);
      expect(isWicketChip(' wk '), isTrue);
      expect(isWicketChip('WD'), isFalse);
      expect(deriveRunsWicketsFromChips(['1', '4', 'W', 'L1', 'NB', '6']), const RunsWickets(12, 1));
    });

    test('positiveOverNumber', () {
      expect(positiveOverNumber([null, 0, -1, 61.7, 3]), 61);
      expect(positiveOverNumber(['5', null]), isNull);
    });

    test('buildRecentOverRows on fixture: summary chips, runsInOver, bowler', () {
      final rows = buildRecentOverRows(fixture('match_live')['data']['recentOvers']);
      expect(rows, isNotEmpty);
      final first = rows.first;
      expect(first.displayOverNumber, 61);
      expect(first.chips, ['1', '0', '0', '0', '1', '1']);
      expect(first.runs, 3);
      expect(first.wickets, 0); // derived from chips, not the stale wicketsInOver
      expect(first.bowler, 'Hasan Mahmud');
    });

    test('buildRecentOverRows without summary sorts by ball number; skips empty overs; malformed input', () {
      final rows = buildRecentOverRows([
        [
          {'type': 'ball', 'value': 'W', 'ballNumber': 2, 'overNumber': 7, 'commentaryTimestamp': 2},
          {'type': 'ball', 'value': '4', 'ballNumber': 1, 'overNumber': 7, 'commentaryTimestamp': 1},
          {'type': 'info'},
        ],
        [
          {'type': 'info'}
        ],
        'junk',
      ]);
      expect(rows.length, 1);
      expect(rows.single.chips, ['4', 'W']);
      expect(rows.single.runs, 4);
      expect(rows.single.wickets, 1);
      expect(rows.single.displayOverNumber, 7);
      expect(buildRecentOverRows(null), isEmpty);
      expect(buildRecentOverRows('x'), isEmpty);
    });

    test('ballTone', () {
      expect(ballTone('4'), BallTone.four);
      expect(ballTone('6'), BallTone.six);
      expect(ballTone('WK'), BallTone.wicket);
      expect(ballTone('NB'), BallTone.wicket);
      expect(ballTone('0'), BallTone.dot);
      expect(ballTone('L1'), BallTone.run);
      expect(ballTone(null), BallTone.run);
    });
  });

  group('fingerprints', () {
    test('detail fingerprint ignores irrelevant fields and changes on score', () {
      final a = liveDetailData();
      final b = deepCopy(a)..['updatedAt'] = 'later';
      expect(matchDetailPollFingerprint(a), matchDetailPollFingerprint(b));
      final c = deepCopy(a);
      (c['teams'] as Map)['t1']['score'] = '390/7 (91.0)';
      expect(matchDetailPollFingerprint(a), isNot(matchDetailPollFingerprint(c)));
    });

    test('live fingerprint changes when only recentOvers changes', () {
      final a = J.map(fixture('match_live')['data']);
      final b = deepCopy(a);
      ((b['recentOvers'] as List).first as List).first['commentaryTimestamp'] = 9999999999999;
      expect(livePollFingerprint(a), isNot(livePollFingerprint(b)));
      expect(livePollFingerprint(a), livePollFingerprint(deepCopy(a)));
      expect(livePollFingerprint(null), '');
      expect(livePollFingerprint({}), '');
    });

    test('scorecard fingerprint', () {
      final s = J.map(fixture('match_scorecard')['data']);
      final t = deepCopy(s)..['updatedAt'] = 'x';
      expect(scorecardPollFingerprint(s), scorecardPollFingerprint(t));
      expect(scorecardPollFingerprint(null), '');
    });
  });

  group('MatchDetailVM', () {
    test('fixture: live Test match', () {
      final vm = MatchDetailVM.fromJson(liveDetailData());
      expect(vm.isLive, isTrue); // status STUMPS = in play (a break), no result
      expect(vm.matchStatus.phase.name, 'interrupted');
      expect(vm.matchStatus.label, 'Stumps');
      expect(vm.format, 'TEST');
      expect(vm.t1.code, 'RSA');
      expect(vm.t1.key, 'rsa');
      expect(vm.isMatchWon, isFalse);
      expect(vm.metaLine, 'TEST · The Wanderers Stadium, Johannesburg, South Africa');
      expect(vm.toss, 'Bangladesh opt to bat');
      expect(vm.t1.name, 'South Africa');
      expect(vm.seriesKey, 'ser-1');
      expect(vm.weather!.humidity, '73');
      final co = vm.currentOver!;
      expect(co.title, 'Current Over (61)');
      expect(co.displayRuns, 5);
      expect(co.displayWickets, 0);
      expect(co.balls.length, 6);
      expect(vm.currentOverCommentaryBalls.length, 6);
      expect(vm.momEligible, isFalse);
    });

    test('completed match with MoM', () {
      final vm = MatchDetailVM.fromJson(completedDetailData());
      expect(vm.isLive, isFalse);
      expect(vm.isMatchWon, isTrue);
      expect(vm.momKey, 'aiden_markram');
      expect(vm.momEligible, isTrue);
      expect(vm.resultMessage, 'South Africa won by 5 wickets');
    });

    test('deriveDetailIsLive comes from status only (isLive is ignored)', () {
      expect(deriveDetailIsLive({'status': 'LIVE'}), isTrue);
      expect(deriveDetailIsLive({'status': 'In LIVE play'}), isTrue);
      expect(deriveDetailIsLive({'status': 'STUMPS'}), isTrue);
      expect(deriveDetailIsLive({'status': 'LIVE', 'isLive': false}), isTrue);
      expect(deriveDetailIsLive({'status': 'COMPLETED', 'isLive': true}), isFalse);
      expect(deriveDetailIsLive({'status': 'LIVE', 'result': {'message': 'X won'}}), isFalse);
      expect(deriveDetailIsLive({'status': 'NOT_STARTED', 'isLive': true}), isFalse);
      expect(deriveDetailIsLive({'status': 'abandoned', 'isLive': true}), isFalse);
      expect(deriveIsMatchWon({'status': 'COMPLETED'}), isTrue);
      expect(deriveIsMatchWon({'status': 'ABANDONED'}), isFalse);
    });

    test('malformed detail never throws', () {
      final vm = MatchDetailVM.fromJson({'teams': 'x', 'currentOver': {'balls': 'nope'}, 'weather': 5, 'result': []});
      expect(vm.t1.name, 'TBD');
      expect(vm.t1.score, isNull);
      expect(vm.currentOver, isNull);
      expect(vm.weather, isNull);
      expect(vm.metaLine, '');
      expect(vm.isLive, isFalse);
    });

    test('current over: only info rows → no card; runs fallback to chips', () {
      expect(CurrentOverVM.fromJson({'balls': [{'type': 'info'}]}), isNull);
      final co = CurrentOverVM.fromJson({
        'runs': 'n/a',
        'balls': [
          {'type': 'ball', 'value': '6', 'ballNumber': 2, 'overNumber': 3},
          {'type': 'ball', 'value': 'W', 'ballNumber': 1, 'overNumber': 3},
        ],
      })!;
      expect(co.displayRuns, 6);
      expect(co.displayWickets, 1);
      expect(co.titleOverNumber, 3);
      expect(co.statsLine, '6 runs • 1 wicket');
    });
  });

  group('LiveVM / batting team / rows', () {
    test('fixture', () {
      final live = LiveVM.fromJson(J.map(fixture('match_live')['data']));
      expect(live.team1, const TeamScore('287', '4', '62.0'));
      expect(live.team2, const TeamScore('400', '10', '101.2'));
      expect(live.firstBallInningsIndex, 't1_1');
      expect(live.battingPair.map((b) => b.displayName), ['Ryan Rickelton *', 'Temba Bavuma']);
      expect(live.battingPair.first.strikeRate, '100.00');
      expect(live.bowler!.name, 'Taskin Ahmed');
      expect(live.bowler!.economy, '3.00');
      expect(live.commentaryBalls.every((b) => b.type == 'ball'), isTrue);
      expect(live.recentOvers.length, greaterThan(0));
    });

    test('sole batter at crease gets the star', () {
      final pair = liveBattingPair({
        'nonStriker': {'name': 'A', 'runs': 3}
      });
      expect(pair.single.displayName, 'A *');
      expect(pair.single.balls, '-');
      expect(pair.single.strikeRate, '0.00');
    });

    test('battingTeamKey priority', () {
      final live = LiveVM.fromJson(J.map(fixture('match_live')['data']));
      expect(battingTeamKey(live: live, detailInningsOrder: const []), TeamSide.team1);
      final noBalls = LiveVM.fromJson({
        'score': {'inningsOrder': ['t1_1', 't2_1'], 'flag': 1}
      });
      expect(battingTeamKey(live: noBalls, detailInningsOrder: const []), TeamSide.team2);
      expect(battingTeamKey(live: null, detailInningsOrder: const ['t2_1', 't1_1']), TeamSide.team1);
      final flagOnly = LiveVM.fromJson({
        'score': {'flag': 1}
      });
      expect(battingTeamKey(live: flagOnly, detailInningsOrder: const []), TeamSide.team1);
      expect(battingTeamKey(live: null, detailInningsOrder: const []), TeamSide.team2);
    });

    test('scorecard fallback rows from fixture', () {
      final last = lastScorecardInning(J.map(fixture('match_scorecard')['data']))!;
      final bats = scorecardBatters(last);
      expect(bats.length, 2);
      expect(bats.first.name, 'Aiden Markram');
      expect(bats.first.outSummary, 'c Litton Das b Hasan Mahmud');
      expect(bats.first.star, isFalse);
      expect(bats.first.strikeRate, '50.00');
      final bowls = scorecardBowlers(last);
      expect(bowls.length, lessThanOrEqualTo(5));
      expect(bowls.first.overs, '15.0');
      expect(bowls.first.economy, '3.00');
      expect(lastScorecardInning({}), isNull);
      expect(scorecardBatters(null), isEmpty);
    });

    test('liveTabCommentary: live balls first (max 20) else current over', () {
      final detail = MatchDetailVM.fromJson(liveDetailData());
      final live = LiveVM.fromJson(J.map(fixture('match_live')['data']));
      final fromLive = liveTabCommentary(live, detail);
      expect(fromLive.length, lessThanOrEqualTo(20));
      expect(fromLive.first.key, live.commentaryBalls.first.key);
      expect(liveTabCommentary(null, detail).length, 6);
    });
  });

  group('commentary', () {
    test('CommentaryPage from fixture', () {
      final p = CommentaryPage.fromJson(J.map(fixture('match_commentary')['data']));
      expect(p.balls.length, 30);
      expect(p.totalCount, 990);
      expect(p.team1Name, 'South Africa');
      expect(p.balls.first.textRuns, isNotEmpty);
      expect(p.balls.first.overLabel, '61.6');
    });

    test('hasMore', () {
      expect(commentaryHasMore(received: 60, page: 1, totalCount: 990), isTrue);
      expect(commentaryHasMore(received: 30, page: 1, totalCount: 990), isFalse);
      expect(commentaryHasMore(received: 60, page: 2, totalCount: 120), isFalse);
    });

    test('runs per ball', () {
      expect(commentaryBallRuns('WD'), 1);
      expect(commentaryBallRuns('NB'), 1);
      expect(commentaryBallRuns('W'), 0);
      expect(commentaryBallRuns('WK'), 0);
      expect(commentaryBallRuns('4'), 4);
      expect(commentaryBallRuns('2lb'), 2);
      expect(commentaryBallRuns('L1'), 0);
    });

    test('commentaryTime', () {
      expect(commentaryTime(1794843123137), matches(RegExp(r'^\d{2}:\d{2} (AM|PM)$')));
      expect(commentaryTime(0), '');
    });

    test('merge dedupes, filter + sort newest first, unique teams, team names', () {
      final a = CommentaryPage.fromJson(commentaryPage(count: 10, totalCount: 20, wicketAt: 'x')).balls;
      final merged = mergeCommentary(a, [...a.take(3), ...CommentaryPage.fromJson(commentaryPage(count: 4, totalCount: 20, startOver: 100)).balls]);
      expect(merged.length, 14);
      final sorted = filterCommentary(merged.reversed.toList());
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i - 1].timestamp >= sorted[i].timestamp, isTrue);
      }
      expect(filterCommentary(merged, filter: CommentaryFilter.wickets).single.value, 'WK');
      expect(filterCommentary(merged, filter: CommentaryFilter.boundaries), isEmpty);
      expect(filterCommentary(merged, team: 't2_1'), isEmpty);
      expect(uniqueInningsKeys(merged), ['t1_1']);
      final page = CommentaryPage.fromJson(J.map(fixture('match_commentary')['data']));
      expect(commentaryTeamName('t1_1', page), 'South Africa');
      expect(commentaryTeamName('t2_2', page), 'Bangladesh');
      expect(commentaryTeamName('x', null), 'x');
      expect(commentaryTeamName('', null), 'Unknown Team');
    });

    test('malformed commentary data', () {
      final p = CommentaryPage.fromJson({'balls': 'x', 'totalCount': 'abc'});
      expect(p.balls, isEmpty);
      expect(p.totalCount, 0);
      final b = CommentaryBall.fromJson({'value': 5});
      expect(b.value, '5');
      expect(b.isBallWithCommentary, isFalse);
    });
  });

  group('getScorecardTeamMeta', () {
    final sc = J.map(J.map(fixture('match_scorecard')['data'])['result']);
    test('matches by name', () {
      final inns = J.maps(sc['innings']);
      final m0 = getScorecardTeamMeta(sc, inns[0], 0);
      expect(m0.displayShort, 'BAN');
      expect(m0.logo, contains('ban'));
    });
    test('fallbacks', () {
      expect(getScorecardTeamMeta(sc, {}, 0).displayShort, 'Team');
      expect(getScorecardTeamMeta({}, {'teamInfo': {'teamName': 'X'}}, 1).displayShort, 'X');
      final viaOrder = getScorecardTeamMeta({
        'teams': {
          'team1': {'name': 'A', 'shortName': 'AA', 'logo': 'a.png'},
          'team2': {'name': 'B', 'shortName': 'BB', 'logo': 'b.png'}
        },
        'inningsOrder': ['t2_1']
      }, {
        'teamInfo': {'teamName': 'Zed', 'shortName': 'ZZ'}
      }, 0);
      expect(viaOrder.displayShort, 'BB');
      expect(viaOrder.logo, 'b.png');
    });
  });
}
