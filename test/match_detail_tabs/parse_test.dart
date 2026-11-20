import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/tabs/tab_playing_xi_parse.dart';
import 'package:crickbex/features/match_detail/tabs/tab_scorecard_parse.dart';
import 'package:crickbex/features/match_detail/tabs/tab_stats_parse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('parseScorecard', () {
    final data = J.map(fixture('match_scorecard')['data']);

    test('unwraps data.result and parses the real Test fixture', () {
      final v = parseScorecard(data);
      expect(v.innings, hasLength(2));
      final ban = v.innings[0];
      expect(ban.teamName, 'Bangladesh');
      expect(ban.shortName, 'BAN');
      expect('${ban.runs}/${ban.wickets}', '400/10');
      expect(ban.overs, '101.2');
      expect(ban.extras, '20');
      expect(ban.extrasDetail, '8 b, 10 lb, 1 wd, 1 nb, 0 p');
      expect(ban.logo, contains('ban.png'));
      expect(ban.batting, hasLength(11));
      expect(ban.bowling, hasLength(6));
      expect(ban.fallOfWickets, hasLength(10));
      expect(ban.batting.first.name, 'Mahfijul Islam');
      expect(ban.batting.first.strikeRate, '0.00');
      expect(ban.batting.first.outLine, 'c Marco Jansen b Kagiso Rabada');
      expect(ban.batting.last.isOut, isFalse);
      expect(ban.batting.last.outLine, '');
      expect(ban.bowling.first.economy, '3.18');
      expect(v.innings[1].yetToBat, hasLength(5));
      expect(v.target, isNull); // targetRuns: null
    });

    test('accepts the already-unwrapped result object', () {
      final a = parseScorecard(data);
      final b = parseScorecard(J.map(data['result']));
      expect(b, a);
    });

    test('null / empty / malformed payloads degrade to empty', () {
      expect(parseScorecard(null).hasInnings, isFalse);
      expect(parseScorecard({}).hasInnings, isFalse);
      expect(parseScorecard({'innings': 'x'}).hasInnings, isFalse);
      expect(parseScorecard({'result': 5}).hasInnings, isFalse);
    });

    test('missing fields never throw and show safe placeholders', () {
      final v = parseScorecard({
        'targetRuns': 0,
        'innings': [
          {
            'teamInfo': 'oops',
            'batting': [
              {'playerName': 'A', 'strikeRate': 'abc', 'isOut': 'true', 'outSummary': '  b X  '},
              {'playerName': 'B', 'strikeRate': '133.333', 'fours': '2', 'runs': '40'},
              'garbage',
            ],
            'bowling': [
              {'playerName': 'C', 'economyRate': 'NaN'},
            ],
            'fallOfWickets': null,
          }
        ],
      });
      expect(v.target, '0');
      final inn = v.innings.single;
      expect(inn.teamName, '-');
      expect(inn.runs, '-');
      expect(inn.extras, '0');
      expect(inn.batting, hasLength(2));
      expect(inn.batting[0].strikeRate, '0.00');
      expect(inn.batting[0].isOut, isTrue);
      expect(inn.batting[0].outLine, 'b X');
      expect(inn.batting[0].runs, '-');
      expect(inn.batting[0].fours, '0');
      expect(inn.batting[1].strikeRate, '133.33');
      expect(inn.batting[1].fours, '2');
      expect(inn.batting[1].runs, '40');
      expect(inn.bowling.single.economy, '0.00');
      expect(inn.bowling.single.wickets, '0');
      expect(inn.fallOfWickets, isEmpty);
    });

    test('empty-string target is hidden (RN targetRuns !== "")', () {
      expect(parseScorecard({'targetRuns': '', 'innings': []}).target, isNull);
      expect(parseScorecard({'targetRuns': 251, 'innings': []}).target, '251');
    });

    test('equal content → equal views; a changed run → different', () {
      final a = parseScorecard(data);
      final copy = J.map(fixture('match_scorecard')['data']);
      expect(parseScorecard(copy), a);
      final inn = J.maps(J.at(copy, 'result.innings'))[0];
      J.maps(inn['batting'])[0]['runs'] = 99;
      expect(parseScorecard(copy) == a, isFalse);
    });
  });

  group('scorecardTeamMeta', () {
    final teams = {
      'team1': {'name': 'South Africa', 'shortName': 'RSA', 'logo': 'l1'},
      'team2': {'name': 'Bangladesh', 'shortName': 'BAN', 'logo': 'l2'},
    };

    test('matches by name', () {
      final m = scorecardTeamMeta({'teams': teams}, {'teamInfo': {'teamName': 'Bangladesh'}}, 0);
      expect(m.logo, 'l2');
      expect(m.displayShort, 'BAN');
    });

    test('matches by short name', () {
      final m = scorecardTeamMeta({'teams': teams}, {'teamInfo': {'teamName': 'Proteas', 'shortName': 'rsa'}}, 1);
      expect(m.logo, 'l1');
    });

    test('falls back to inningsOrder then index parity', () {
      final sc = {'teams': teams, 'inningsOrder': ['t2_1', 't1_1']};
      expect(scorecardTeamMeta(sc, {'teamInfo': {'teamName': 'X'}}, 0).logo, 'l2');
      expect(scorecardTeamMeta(sc, {'teamInfo': {'teamName': 'X'}}, 1).logo, 'l1');
      final noOrder = {'teams': teams};
      expect(scorecardTeamMeta(noOrder, {'teamInfo': {'teamName': 'X'}}, 0).logo, 'l1');
      expect(scorecardTeamMeta(noOrder, {'teamInfo': {'teamName': 'X'}}, 1).logo, 'l2');
      expect(scorecardTeamMeta(noOrder, {'teamInfo': {}}, 2).displayShort, 'Inn 3');
    });

    test('no teamInfo / no teams', () {
      expect(scorecardTeamMeta({}, {}, 0).displayShort, 'Team');
      final m = scorecardTeamMeta({}, {'teamInfo': {'shortName': 'IND'}}, 0);
      expect(m.logo, isNull);
      expect(m.displayShort, 'IND');
    });
  });

  group('parsePlayingXI', () {
    test('parses the real fixture', () {
      final v = parsePlayingXI(fixture('match_playing11')['data']);
      expect(v.hasMatch, isTrue);
      expect(v.team1.name, 'South Africa');
      expect(v.team2.name, 'Bangladesh');
      expect(v.team1.logo, contains('rsa.png'));
      expect(v.team1.players, hasLength(11));
      expect(v.team2.players, hasLength(11));
      final shanto = v.team2.players.firstWhere((p) => p.name == 'Najmul Hossain Shanto');
      expect(shanto.isCaptain, isTrue);
      final mushfiq = v.team2.players.firstWhere((p) => p.name == 'Mushfiqur Rahim');
      expect(mushfiq.isWicketKeeper, isTrue);
      expect(v.team1.players.first.roleLabel, 'Batter');
      expect(v.team1.players.first.country, 'South Africa');
      expect(v.team1.players.first.avatar, contains('aiden_markram'));
    });

    test('role labels', () {
      expect(playingXIRoleLabel(0), 'Batter');
      expect(playingXIRoleLabel(1), 'Bowler');
      expect(playingXIRoleLabel(2), 'Wicketkeeper');
      expect(playingXIRoleLabel(3), 'Batting all-rounder');
      expect(playingXIRoleLabel(4), 'Bowling all-rounder');
      expect(playingXIRoleLabel(9), 'Player');
      expect(playingXIRoleLabel(null), 'Player');
      expect(playingXIRoleLabel('NaN'), 'Player');
    });

    test('missing match → empty; missing teams/players degrade', () {
      expect(parsePlayingXI(null).hasMatch, isFalse);
      expect(parsePlayingXI({'match': null}).hasMatch, isFalse);
      expect(parsePlayingXI([]).hasMatch, isFalse);
      final v = parsePlayingXI({
        'match': {
          'playingXI_Team1': [
            {'name': 'P', 'playerInfo': {'country': '  ', 'logo': ''}},
            7,
          ],
        }
      });
      expect(v.hasMatch, isTrue);
      expect(v.team1.name, 'Team 1');
      expect(v.team2.name, 'Team 2');
      expect(v.team1.players.single.country, isNull);
      expect(v.team1.players.single.avatar, isNull);
      expect(v.team2.players, isEmpty);
    });

    test('equality by content', () {
      final a = parsePlayingXI(fixture('match_playing11')['data']);
      final b = parsePlayingXI(fixture('match_playing11')['data']);
      expect(a, b);
      expect(a == PlayingXIView.empty, isFalse);
    });
  });

  group('parseSquad', () {
    test('bench and wicketkeepers from the real fixture', () {
      final v = parseSquad(fixture('match_squad')['data']);
      expect(v.bench1, hasLength(4));
      expect(v.bench2, hasLength(4));
      expect(v.keepers, isNotEmpty);
      expect(parseSquad(null).bench1, isEmpty);
      expect(parseSquad({'match': 'x'}).keepers, isEmpty);
    });
  });

  group('parseStats', () {
    test('every innings from the real fixtures, in batting order', () {
      final v = parseStats(
        analytics: fixture('match_analytics')['data'],
        scoringRate: fixture('match_scoring_rate')['data'],
        boundaries: fixture('match_boundaries')['data'],
        order: ['t2_1', 't1_1'],
      );
      expect(v.innings.map((i) => i.key), ['t2_1', 't1_1']);
      final ban = v.innings.first, rsa = v.innings.last;
      expect(ban.label, 'BAN 1st innings');
      expect(ban.runRate, 3.95);
      expect(ban.boundaries, 52);
      expect(ban.dotPercent, 66.45);
      expect(ban.overRuns, hasLength(102));
      expect(rsa.shortLabel, 'RSA 1st');
      expect(rsa.fours, 36);
      expect(rsa.sixes, 1);
      expect(rsa.dotBalls, 232);
      expect(rsa.totalBalls, 379);
      expect(rsa.overRuns, hasLength(62));
      expect(rsa.overRuns.take(3), [0, 5, 4], reason: 'overNumber 0 is the first over');
      expect(rsa.bowling.first.name, 'Taskin Ahmed');
      expect(rsa.bowling.first.economy, 3);
    });

    test('missing / malformed values stay null (never 0)', () {
      expect(parseStats().isEmpty, isTrue);
      final w = parseStats(
        scoringRate: {'teams': {'team1': {'innings': {'t1_1': {'scoringRate': 'Infinity'}}}}},
        boundaries: {'teams': {'team1': {'innings': {'t1_1': {'fours': 'NaN', 'sixes': '3'}}}}},
        analytics: {'teams': {'team1': {'innings': 'x'}}},
      );
      final i = w.innings.single;
      expect(i.runRate, isNull);
      expect(i.fours, isNull);
      expect(i.sixes, 3);
      expect(i.dotPercent, isNull);
      expect(i.overRuns, isEmpty);
      expect(i.teamCode, 'Team 1');
    });

    test('wicket over from a fall-of-wickets over string', () {
      expect(wicketOverFromFow('1.3'), 2);
      expect(wicketOverFromFow('58.6'), 59);
      expect(wicketOverFromFow('43'), 43);
      expect(wicketOverFromFow('-'), isNull);
    });
  });
}
