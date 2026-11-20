import 'package:crickbex/features/rankings/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../players/test_helpers.dart';

void main() {
  test('kinds map to the API type; selection titles read naturally', () {
    expect(RankKind.teams.apiType, isNull);
    expect(RankKind.batting.apiType, 'BATSMAN');
    expect(RankKind.bowling.apiType, 'BOWLER');
    expect(RankKind.allRounders.apiType, 'ALL_ROUNDER');
    expect(selectionTitle(RankKind.teams, 'TEST', 'MALE'), "Men's Test team");
    expect(
      selectionTitle(RankKind.allRounders, 'T20', 'FEMALE'),
      "Women's T20 all-rounder",
    );
  });

  test(
    'parseTeamRankings keeps rating and points apart; teams have no key',
    () {
      final list = parseTeamRankings(fixtureJson('rank_team')['data']);
      expect(list.length, 20);
      expect(list.first.name, 'India');
      expect(list.first.rank, 1);
      expect(list.first.rating, '116');
      expect(list.first.points, '3841');
      expect(list.first.playerKey, isNull);
      expect(
        list.first.semanticsLabel,
        'Rank 1, India, rating 116, 3841 points',
      );
    },
  );

  test('parsePlayerRankings uses points as the rating', () {
    final list = parsePlayerRankings(fixtureJson('rank_player')['data']);
    expect(list.length, 102);
    expect(list.first.playerKey, 'shubman_gill');
    expect(list.first.rating, '801');
    expect(list.first.points, isNull);
    expect(list.first.toInitialPlayer(), {
      'playerKey': 'shubman_gill',
      'name': 'Shubman Gill',
    });
  });

  test(
    'malformed rows: skipped or degraded, duplicates dropped, sorted by rank, no fake zeros',
    () {
      final list = parsePlayerRankings([
        null,
        {
          'name': 'A',
          'order': '2',
          'points': '700',
          'playerKey': 'a',
          'logo': 'https://x/a.png',
        },
        {'name': 'A again', 'order': 3, 'playerKey': 'a'},
        {'playerName': 'B', 'order': 1},
        {'order': 9},
        {'name': 'C', 'points': ''},
      ]);
      expect(list.map((e) => e.name), ['B', 'A', 'C']);
      expect(list[1].toInitialPlayer()['logo'], 'https://x/a.png');
      expect(list[0].rating, isNull);
      expect(list[2].rating, isNull);
      expect(parseTeamRankings('bad'), isEmpty);
      expect(parseTeamRankings(null), isEmpty);
    },
  );

  test('filterRankings matches every word, case-insensitive', () {
    final list = parsePlayerRankings(fixtureJson('rank_player')['data']);
    expect(filterRankings(list, ''), same(list));
    expect(
      filterRankings(list, '  GILL ').map((e) => e.name),
      contains('Shubman Gill'),
    );
    expect(filterRankings(list, 'shubman gill').length, 1);
    expect(filterRankings(list, 'zzzz'), isEmpty);
  });

  test(
    'splitForDisplay: three leaders + rows to 100; search puts every match in rows',
    () {
      final list = parsePlayerRankings(fixtureJson('rank_player')['data']);
      final s = splitForDisplay(list, searching: false);
      expect(s.leaders.map((e) => e.rank), [1, 2, 3]);
      expect(s.rows.first.rank, 4);
      expect(s.rows.last.rank, 100);
      final q = splitForDisplay(list.take(2).toList(), searching: true);
      expect(q.leaders, isEmpty);
      expect(q.rows.length, 2);
      expect(
        splitForDisplay(list.take(2).toList(), searching: false).rows,
        isEmpty,
      );
    },
  );
}
