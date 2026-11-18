import 'package:crickbex/features/players/player_models.dart';
import 'package:crickbex/features/rankings/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../players/test_helpers.dart';

void main() {
  test('categoryToApiType', () {
    expect(categoryToApiType('batters'), 'BATSMAN');
    expect(categoryToApiType('bowlers'), 'BOWLER');
    expect(categoryToApiType('allRounders'), 'ALL_ROUNDER');
    expect(categoryToApiType('??'), 'BATSMAN');
  });

  test('parseTeamRankings uses order/points; teams are not tappable', () {
    final list = parseTeamRankings(fixtureJson('rank_team')['data']);
    expect(list.length, 20);
    expect(list.first.name, 'India');
    expect(list.first.rank, 1);
    expect(list.first.ratingText, '3841'); // RN shows points as rating
    expect(list.first.playerKey, isNull);
    expect(list.first.image, isNull);
    expect(list.first.initial, 'I');
  });

  test('parsePlayerRankings', () {
    final list = parsePlayerRankings(fixtureJson('rank_player')['data']);
    expect(list.length, 102);
    expect(list.first.name, 'Shubman Gill');
    expect(list.first.playerKey, 'shubman_gill');
    expect(list.first.id, 'shubman_gill');
    expect(list.first.ratingText, '801');
    expect(list.first.toInitialPlayer(), {'playerKey': 'shubman_gill', 'name': 'Shubman Gill'});
  });

  test('malformed rows degrade, duplicates are dropped', () {
    final list = parsePlayerRankings([
      null,
      {'name': 'A', 'order': '2', 'points': '700', 'playerKey': 'a', 'logo': 'https://x/a.png'},
      {'name': 'A again', 'order': 3, 'playerKey': 'a'},
      {'playerName': 'B'},
      {},
    ]);
    expect(list.map((e) => e.name), ['A', 'B', kDash]);
    expect(list[0].rank, 2);
    expect(list[0].ratingText, '700');
    expect(list[0].toInitialPlayer()['logo'], 'https://x/a.png');
    expect(list[1].rank, 3); // 1-based index fallback (non-map rows are skipped)
    expect(list[1].ratingText, kDash);
    expect(list[1].playerKey, isNull);
    expect(list[2].initial, '?');
    expect(parseTeamRankings('bad'), isEmpty);
    expect(parseTeamRankings(null), isEmpty);
  });

  test('filterRankings', () {
    final list = parsePlayerRankings(fixtureJson('rank_player')['data']);
    expect(filterRankings(list, ''), same(list));
    expect(filterRankings(list, '  GILL ').map((e) => e.name), contains('Shubman Gill'));
    expect(filterRankings(list, 'zzzz'), isEmpty);
  });

  test('splitForDisplay: podium + ranks 4–100; search shows every match', () {
    final list = parsePlayerRankings(fixtureJson('rank_player')['data']);
    final s = splitForDisplay(list, searching: false);
    expect(s.podium.length, 3);
    expect(s.rows.length, 97);
    expect(s.rows.first.rank, 4);

    final small = list.take(2).toList();
    final s2 = splitForDisplay(small, searching: false);
    expect(s2.podium.length, 2);
    expect(s2.rows, isEmpty);

    // Regression: RN dropped the first 3 search results.
    final found = filterRankings(list, 'gill');
    final s3 = splitForDisplay(found, searching: true);
    expect(s3.podium, isEmpty);
    expect(s3.rows.length, found.length);
    expect(s3.rows.first.name, 'Shubman Gill');
  });
}
