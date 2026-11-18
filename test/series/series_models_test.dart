import 'package:crickbex/core/utils/fixture_status.dart';
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
    });

    test('parses /series/upcoming (no seriesStatus)', () {
      final items = parseSeriesList(fixtureJson('series_upcoming.json')['data']);
      expect(items, hasLength(8));
      expect(items.first.status, isNull);
      expect(items.first.navId, 'sddbjDn');
    });

    test('accepts { series: [...] } shape and malformed input', () {
      expect(parseSeriesList({'series': [{'_id': 'a', 'name': 'X'}]}).single.navId, 'a');
      expect(parseSeriesList(null), isEmpty);
      expect(parseSeriesList('oops'), isEmpty);
      expect(parseSeriesList([1, 'x', null, {}]), hasLength(1));
      final weird = parseSeriesList([{'name': 42, 'seriesStatus': 'ongoing', 'format': 't20'}]).single;
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
      expect(formatSeriesDateRange('2026-01-05T12:00:00', '2026-02-10T12:00:00'), 'Jan 5 – Feb 10');
    });
  });

  group('fixtures parsing', () {
    test('parses real /series/:id fixture', () {
      final list = parseSeriesFixtures(fixtureJson('series_fixtures.json')['data'], seriesTitle: 'Abu Dhabi T10');
      expect(list, hasLength(4));
      final f = list.first;
      expect(f.matchId, '03OiKOD');
      expect(f.matchNumber, 1);
      expect(f.team1, 'Arabian Aces');
      expect(f.team2, 'United Tigers');
      expect(f.kind, FixtureCardKind.completed);
      expect(f.chipLabel, 'Finished');
      expect(f.finishedMessage, 'Arabian Aces won by 7 wickets');
      expect(f.format, 'T10');
      expect(f.seriesLine, 'Abu Dhabi T10');
      expect(f.venue, startsWith('Sheikh Zayed'));
    });

    test('missing teams/status/date degrade safely', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final f = parseSeriesFixtures([{}], now: now).single;
      expect(f.team1, 'TBD');
      expect(f.team2, 'TBD');
      expect(f.matchId, '');
      expect(f.kind, FixtureCardKind.scheduled);
      expect(f.chipLabel, 'Upcoming');
      expect(f.date, now);
      expect(parseSeriesFixtures(null), isEmpty);
      expect(parseSeriesFixtures({'data': [{'_id': 'z'}]}).single.listKey, 'z');
    });

    test('timestamp seconds vs ms and past undecided → cancelled', () {
      final now = DateTime.utc(2026, 1, 2);
      final secs = parseSeriesFixtures([{'timestamp': 1767225600, 'status': 'NOT_STARTED'}], now: now).single;
      expect(secs.date.toUtc(), DateTime.utc(2026, 1, 1));
      expect(secs.kind, FixtureCardKind.cancelled);
      expect(secs.showVoidDetail, isFalse); // statusLine is the short 'Cancelled'
      final ms = parseSeriesFixtures([{'timestamp': '1767225600000'}], now: now).single;
      expect(ms.date.toUtc(), DateTime.utc(2026, 1, 1));
    });

    test('abandoned with reason shows void detail; live chip', () {
      final now = DateTime.utc(2026, 1, 1);
      final a = parseSeriesFixtures([
        {'status': 'ABANDONED', 'result': {'message': 'Rain stopped play'}, 'startDate': '2026-01-01T00:00:00Z'},
        {'status': 'LIVE', 'startDate': '2026-01-01T00:00:00Z'},
      ], now: now);
      expect(a[0].kind, FixtureCardKind.abandoned);
      expect(a[0].showVoidDetail, isTrue);
      expect(a[0].isCompleted, isFalse);
      expect(a[1].chipLabel, 'Live');
      expect(a[1].isUpcomingVariant, isTrue);
    });

    test('stripLeadingOrdinalFromTitle / normalizeFixtureFormat / ordinalSuffix', () {
      expect(stripLeadingOrdinalFromTitle('1st Match: India vs Aus'), 'India vs Aus');
      expect(stripLeadingOrdinalFromTitle('Match No. 12 - Final'), 'Final');
      expect(stripLeadingOrdinalFromTitle('Final'), 'Final');
      expect(normalizeFixtureFormat({'format': 20}), 'T20');
      expect(normalizeFixtureFormat({'format': '50'}), 'ODI');
      expect(normalizeFixtureFormat({'format': 7}), isNull);
      expect(normalizeFixtureFormat({'matchFormat': 'Test match'}), 'TEST');
      expect(normalizeFixtureFormat({'format': 't 20'}), 'T20');
      expect(normalizeFixtureFormat({}), isNull);
      expect(normalizeFixtureFormat({'format': 'abcdefghijklmnop'}), 'ABCDEFGHIJKL');
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map((n) => '$n${ordinalSuffix(n)}').toList(),
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '101st']);
    });

    test('startsInLabel', () {
      final now = DateTime(2026, 1, 1);
      expect(startsInLabel(now.subtract(const Duration(minutes: 1)), now), isNull);
      expect(startsInLabel(now.add(const Duration(days: 2, hours: 3)), now), '2d 3h');
      expect(startsInLabel(now.add(const Duration(hours: 4, minutes: 5)), now), '4h 5m');
      expect(startsInLabel(now.add(const Duration(minutes: 12)), now), '12m');
    });
  });

  group('points table parsing', () {
    test('parses real fixture', () {
      final groups = parsePointsTable(fixtureJson('series_point_table.json')['data']);
      expect(groups, hasLength(1));
      expect(groups.single.name, 'Group');
      expect(groups.single.rows, hasLength(6));
      final ara = groups.single.rows.first;
      expect(ara.shortName, 'ARA');
      expect(ara.matches, '9');
      expect(ara.points, '12');
      expect(ara.nrr, '0.42');
    });

    test('malformed rows degrade to zeros', () {
      final g = parsePointsTable({
        'series': {
          'pointsTable': [
            {'name': null, 'teams': [{'won': '3', 'netRunRate': 'abc'}, 'junk']},
            'junk',
          ],
        },
      });
      expect(g, hasLength(1));
      expect(g.single.name, '');
      final r = g.single.rows.single;
      expect(r.won, '3');
      expect(r.lost, '0');
      expect(r.nrr, '0.00');
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
      // most_fifties is not in RN STAT_ORDER → skipped
      expect(keys, ['most_runs', 'highest_score', 'best_batting_average', 'best_batting_strike', 'most_wickets', 'most_fours', 'most_sixes', 'best_bowling_average']);
      final bowl = s.formats.single.categories.last;
      expect(bowl.title, 'Best Bowling Avg');
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
      expect(cat.entries[0].name, 'Unknown Player');
      expect(cat.entries[0].value, '0');
      expect(cat.entries[0].playerKey, isNull);
      expect(cat.entries[1].value, '12');
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
      expect(t.players[0].tag, 'XI, C, WK');
      expect(t.players[0].role, 'Wicket Keeper');
      expect(t.players[1].tag, '-');
      expect(t.players[1].role, 'Batsman');
      expect(t.players[2].role, 'Player');
      expect(t.players[3].role, 'All Rounder');
      expect(parseSquads(null), isEmpty);
      expect(parseSquads({'squads': 'x'}), isEmpty);
      expect(roleName(4), 'Batsman/WK');
    });
  });
}
