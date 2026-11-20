import 'package:crickbex/features/series/series_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'series_test_helpers.dart';

void main() {
  group('series list parsing', () {
    test('parses real /series fixture', () {
      final items = parseSeriesList(fixtureJson('series_list.json')['data']);
      expect(items, hasLength(12));
      final first = items.first;
      expect(first.name, 'Mens Cricket World Cup 2027');
      expect(first.navId, 'j5C4a58'); // sb_series_key preferred for navigation
      expect(first.id, '6afc9d2d31bbe1ca564b0f80');
      expect(first.status, SeriesStatusKey.upcoming);
      expect(first.dateRange, contains('–'));
      expect(first.isPopular, isTrue);
      expect(first.year, 2027);
    });

    test('parses /series/upcoming (no seriesStatus)', () {
      final items = parseSeriesList(fixtureJson('series_upcoming.json')['data']);
      expect(items, hasLength(8));
      expect(items.first.status, isNull);
      expect(items.first.navId, 'sddbjDn');
    });

    test('accepts { series: [...] } shape and malformed input', () {
      expect(
        parseSeriesList({
          'series': [
            {'_id': 'a', 'name': 'X'},
          ],
        }).single.navId,
        'a',
      );
      expect(parseSeriesList(null), isEmpty);
      expect(parseSeriesList('oops'), isEmpty);
      expect(parseSeriesList([1, 'x', null, {}]), hasLength(1));
      final weird = parseSeriesList([
        {'name': 42, 'seriesStatus': 'ongoing', 'format': 't20'},
      ]).single;
      expect(weird.name, '42');
      expect(weird.isLive, isTrue);
      expect(weird.format, 'T20');
      expect(weird.navId, '');
    });

    test('status key + date range helpers', () {
      expect(toSeriesStatusKey('Completed'), SeriesStatusKey.completed);
      expect(toSeriesStatusKey('foo'), isNull);
      expect(toSeriesStatusKey(null), isNull);
      expect(formatSeriesDateRange(null, '2026-01-01'), '');
      expect(formatSeriesDateRange('bad', '2026-01-01'), '');
      expect(formatSeriesDateRange('2026-01-05T12:00:00', '2026-02-10T12:00:00'), '5 Jan – 10 Feb 2026');
      expect(formatSeriesDateRange('2026-12-30T12:00:00', '2027-01-10T12:00:00'), '30 Dec 2026 – 10 Jan 2027');
    });
  });

  group('fixtures parsing', () {
    test('parses real /series/:id fixture with the shared match parser', () {
      final f = parseSeriesFixtures(fixtureJson('series_fixtures.json')['data']);
      expect(f.matches, hasLength(4));
      final m = f.matches.first;
      expect(m.id, '03OiKOD');
      expect(m.team1, 'Arabian Aces');
      expect(m.resultMessage, 'Arabian Aces won by 7 wickets');
      expect(f.results, hasLength(4));
      expect(f.results.first.id, 'LCoO4aA', reason: 'most recent first');
      expect(f.upcoming, isEmpty);
      expect(f.live, isEmpty);
      expect(f.formats, ['T10']);
      expect(f.dateSpan, isNotEmpty);
    });

    test('splits live / upcoming (soonest first) / results; malformed input is safe', () {
      final f = parseSeriesFixtures([
        {'sb_match_key': 'u2', 'status': 'NOT_STARTED', 'startDate': '2026-12-02T00:00:00Z'},
        {'sb_match_key': 'u1', 'status': 'NOT_STARTED', 'startDate': '2026-12-01T00:00:00Z'},
        {'sb_match_key': 'l', 'status': 'LIVE'},
        {
          'sb_match_key': 'a',
          'status': 'ABANDONED',
          'result': {'message': 'Abandoned due to rain'},
        },
        'junk',
        {'format': 'TEST'},
      ]);
      expect(f.matches, hasLength(5));
      expect(f.live.single.id, 'l');
      expect(f.upcoming.map((m) => m.id).take(2), ['u1', 'u2']);
      expect(f.results.single.id, 'a');
      expect(f.formats, ['Test']);
      expect(parseSeriesFixtures(null).matches, isEmpty);
      expect(
        parseSeriesFixtures({
          'data': [
            {'_id': 'z'},
          ],
        }).matches,
        hasLength(1),
      );
    });
  });

  group('points table parsing', () {
    test('parses real fixture: provider order, signed NRR, form, no computed markers', () {
      final groups = parsePointsTable(fixtureJson('series_point_table.json')['data']);
      expect(groups, hasLength(1));
      expect(groups.single.name, 'Group');
      expect(groups.single.rows, hasLength(6));
      final ara = groups.single.rows.first;
      expect(ara.position, 1);
      expect(ara.shortName, 'ARA');
      expect(ara.matches, '9');
      expect(ara.points, '12');
      expect(ara.nrr, '+0.422');
      expect(groups.single.rows[3].nrr, '-0.605');
      expect(ara.form, ['W', 'W', 'W', 'W', 'L'], reason: 'last five decided results, oldest first');
      expect(ara.results.last.outcome, isNull, reason: 'unplayed match has no outcome');
      expect(groups.single.rows.every((r) => r.marker == null), isTrue, reason: 'qualify/eliminate are null: no markers');
    });

    test('missing values are "–", never 0; provider qualify/eliminate become Q/E', () {
      final g = parsePointsTable({
        'series': {
          'pointsTable': [
            {
              'name': null,
              'teams': [
                {'won': '3', 'netRunRate': 'abc', 'qualify': 'Q'},
                {'shortName': 'B', 'matches': 0, 'eliminate': true},
                'junk',
              ],
            },
            {'name': 'Empty', 'teams': []},
            'junk',
          ],
        },
      });
      expect(g, hasLength(1));
      expect(g.single.name, '');
      final r = g.single.rows.first;
      expect(r.won, '3');
      expect(r.lost, kNotAvailable);
      expect(r.nrr, kNotAvailable);
      expect(r.marker, 'Q');
      expect(g.single.rows[1].matches, '0', reason: 'a real provider 0 stays');
      expect(g.single.rows[1].marker, 'E');
      expect(formatNrr(0), '0.000');
      expect(parsePointsTable(null), isEmpty);
      expect(parsePointsTable({'series': {}}), isEmpty);
    });
  });

  group('stats parsing', () {
    test('parses real fixture in STAT_ORDER, top 10, decimals', () {
      final s = parseSeriesStats(fixtureJson('series_stats.json')['data']);
      expect(s.hasData, isTrue);
      expect(s.comingSoon, isFalse);
      expect(s.formats.single.format, 'T10');
      final keys = s.formats.single.categories.map((c) => c.key).toList();
      expect(keys.first, 'most_runs');
      expect(keys, contains('most_fifties'));
      final bowl = s.formats.single.categories.firstWhere((c) => c.key == 'best_bowling_average');
      expect(bowl.title, 'Best bowling average');
      expect(bowl.entries.length, lessThanOrEqualTo(10));
      expect(bowl.entries.first.value, '4.50');
      expect(bowl.entries.first.rank, 1);
      expect(bowl.entries.first.playerKey, 'amshi_de_silva');
      final runs = s.formats.single.categories.first;
      expect(runs.entries.first.value, isNot(contains('.')));
    });

    test('empty / malformed', () {
      expect(parseSeriesStats(null).hasData, isFalse);
      expect(parseSeriesStats([]).hasData, isFalse);
      expect(parseSeriesStats({'seriesId': 'x', 'sbSeriesKey': 'y'}).formats, isEmpty);
      final s = parseSeriesStats({
        'ODI': {
          'most_runs': [
            {'playerName': null, 'value': null},
            {'playerName': 'B', 'value': '12'},
          ],
          'most_wickets': 'junk',
        },
      });
      final cat = s.formats.single.categories.single;
      expect(cat.entries, hasLength(1), reason: 'rows without a name or value are skipped, never shown as 0');
      expect(cat.entries.single.value, '12');
      expect(cat.entries.single.rank, 1);
      expect(cat.entries.single.playerKey, isNull);
    });
  });

  group('squads parsing', () {
    test('parses real fixture', () {
      final teams = parseSquads(fixtureJson('series_squad.json')['data']);
      expect(teams, hasLength(2));
      expect(teams.first.players, isNotEmpty);
      final p = teams.first.players.first;
      expect(p.name, 'Dunith Wellalage');
      expect(p.role, 'Bowler');
      expect(p.key, 'dunith_wellalage');
      expect(teams.first.key, isNot(equals(teams.last.key)));
    });

    test('roles and tags', () {
      final t = parseSquads({
        'squads': [
          {
            'players': [
              {'name': 'A', 'role': 3, 'isCaptain': true, 'isWicketKeeper': true, 'isPlaying': true},
              {'name': 'B'},
              {'name': 'C', 'role': 'x'},
              {'name': 'D', 'role': '2'},
            ],
          },
        ],
      }).single;
      expect(t.name, 'Team 1');
      expect(t.players[0].tags, ['C', 'WK', 'XI']);
      expect(t.players[0].role, 'Wicketkeeper');
      expect(t.players[1].tags, isEmpty);
      expect(t.players[1].role, '', reason: 'unknown role is hidden, not guessed');
      expect(t.players[2].role, '');
      expect(t.players[3].role, 'All-rounder');
      expect(parseSquads(null), isEmpty);
      expect(parseSquads({'squads': 'x'}), isEmpty);
      expect(roleName(4), 'Wicketkeeper batter');
    });
  });
}
