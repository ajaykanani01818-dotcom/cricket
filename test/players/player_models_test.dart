import 'package:crickbex/features/players/player_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18);

  group('helpers', () {
    test('role / hand labels are sentence case; unknown is null (hidden)', () {
      expect(roleLabelOf(0), 'Batter');
      expect(roleLabelOf(4), 'Bowling all-rounder');
      expect(roleLabelOf(null), isNull);
      expect(roleLabelOf(99), isNull);
      expect(roleWithHand(0, 1), 'Batter, left-hand bat');
      expect(roleWithHand(1, null), 'Bowler');
      expect(roleWithHand(null, 0), 'Right-hand bat');
      expect(roleWithHand(null, 7), isNull);
    });

    test('age and dates: missing / zero / future are null, never 0', () {
      const dob = 1009843200; // 2002-01-01 UTC
      expect(ageYears(dob, now: now), 24);
      expect(ageLong(dob, now: now), '24 years');
      expect(ageLong(null), isNull);
      expect(ageLong(0), isNull);
      final oneYear =
          now.subtract(const Duration(days: 400)).millisecondsSinceEpoch ~/
          1000;
      expect(ageLong(oneYear, now: now), '1 year');
      expect(
        ageYears(now.millisecondsSinceEpoch ~/ 1000 + 100000, now: now),
        isNull,
      );
      expect(formatDate(null), isNull);
      expect(formatDate(0), isNull);
      final ts = DateTime(1994, 10, 4, 12).millisecondsSinceEpoch ~/ 1000;
      expect(formatDate(ts), 'Oct 4, 1994');
    });

    test('stripHtml', () {
      expect(stripHtml(null), '');
      expect(
        stripHtml(
          '<p>Hello&nbsp;<b>world</b></p><p>It&#39;s &amp; &lt;ok&gt; &quot;x&quot;</p>',
        ),
        'Hello world\nIt\'s & <ok> "x"',
      );
      expect(stripHtml('a<br/>b<BR>c'), 'a\nb\nc');
    });

    test('fmtStat / fmtOpt', () {
      expect(fmtStat(56.0), '56');
      expect(fmtStat(35.65), '35.65');
      expect(fmtStat('2/27'), '2/27');
      expect(fmtStat(null), kDash);
      expect(fmtStat(''), kDash);
      expect(fmtStat(double.nan), kDash);
      expect(fmtOpt({'a': 1}), isNull);
      expect(fmtOpt(true), isNull);
    });

    test('formatLabel', () {
      expect(formatLabel('TEST'), 'Test');
      expect(formatLabel('T20I'), 'T20I');
      expect(formatLabel('HUNDRED'), 'The Hundred');
      expect(formatLabel(''), kDash);
    });

    test('nameMatches needs every word', () {
      expect(nameMatches('Virat Kohli', 'kohli'), isTrue);
      expect(nameMatches('Virat Kohli', 'vir koh'), isTrue);
      expect(nameMatches('Virat Kohli', 'virat sharma'), isFalse);
      expect(nameMatches('Virat Kohli', '  '), isFalse);
    });

    test('computeHasMore', () {
      expect(
        computeHasMore(
          received: 20,
          perPage: 20,
          infoPage: 1,
          infoPerPage: 20,
          infoTotal: 5370,
        ),
        isTrue,
      );
      expect(
        computeHasMore(
          received: 20,
          perPage: 20,
          infoPage: 1,
          infoPerPage: 20,
          infoTotal: 20,
        ),
        isFalse,
      );
      expect(computeHasMore(received: 7, perPage: 20), isFalse);
      expect(
        computeHasMore(
          received: 5,
          perPage: 20,
          infoPage: 1,
          infoPerPage: 0,
          infoTotal: 100,
        ),
        isFalse,
      );
    });

    test(
      'IccRanks: empty strings are unranked; best() prefers the role category',
      () {
        final r = IccRanks(
          fixtureJson('players_country')['data'][0]['iccRanking'],
        );
        expect(r.rank('batting', 'test'), '#5');
        expect(r.rank('batting', 'odi'), isNull);
        expect(r.hasCategory('bowling'), isFalse);
        expect(r.best(category: 'batting'), (5, 'Test', 'Batting'));
        expect(const IccRanks({}).hasAny, isFalse);
        expect(
          const IccRanks({
            'batting': {'test': '0'},
          }).rank('batting', 'test'),
          isNull,
        );
      },
    );
  });

  group('CountryPlayer', () {
    test('parses fixture with role line and ICC badge', () {
      final list = CountryPlayer.listFrom(
        fixtureJson('players_country')['data'],
        now: now,
      );
      expect(list.length, 20);
      final p = list.first;
      expect(p.playerKey, 'yashasvi_jaiswal');
      expect(p.name, 'Yashasvi Jaiswal');
      expect(p.subtitle, 'Batter, left-hand bat, 24 years');
      expect(p.rankBadge, '#5 Test');
      expect(p.rankLabel, 'ICC Test batting rank 5');
      expect(p.raw['playerKey'], 'yashasvi_jaiswal');
    });

    test('trending items use `key` and have no role: subtitle hidden', () {
      final list = CountryPlayer.listFrom(
        fixtureJson('players_trending')['data'],
      );
      expect(list.first.playerKey, 'ibrahim_zadran');
      expect(list.first.subtitle, isNull);
      expect(list.first.rankBadge, isNull);
    });

    test('malformed items degrade or are skipped', () {
      final list = CountryPlayer.listFrom([
        null,
        'x',
        <String, dynamic>{},
        {
          'playerKey': 'k1',
          'role': '1',
          'dob': 'abc',
          'battingStyle': 'z',
          'iccRanking': 'bad',
        },
        {'_id': 'id2', 'name': '  ', 'logo': ''},
      ]);
      expect(list.length, 2);
      expect(list[0].id, 'k1');
      expect(list[0].name, 'Unnamed player');
      expect(list[0].subtitle, 'Bowler');
      expect(list[1].playerKey, '');
      expect(list[1].logo, isNull);
      expect(CountryPlayer.listFrom('nope'), isEmpty);
    });
  });

  group('PlayerProfile', () {
    test('parses player_info fixture into facts and career tables', () {
      final p = PlayerProfile.fromJson(
        fixtureJson('player_info')['data'],
        now: now,
      );
      expect(p.name, 'Aiden Markram');
      expect(p.country, 'South Africa');
      expect(p.facts.map((f) => f.$1), ['Role', 'Batting', 'Bowling', 'Born']);
      expect(p.role, 'Batter');
      expect(p.batting, 'Right-hand bat');
      expect(p.bowling, 'Right-arm off-break');
      expect(p.ranks!.rank('batting', 'test'), '#17');
      expect(p.ranks!.hasCategory('bowling'), isFalse);

      final bat = p.battingTable;
      expect(bat.columns, [
        'M',
        'Inn',
        'Runs',
        'HS',
        'Avg',
        'SR',
        '100s',
        '50s',
      ]);
      expect(bat.rows.map((r) => r.format), [
        'Test',
        'ODI',
        'T20I',
        'IPL',
        'SA20',
        'The Hundred',
      ]);
      expect(bat.rows.first.cells, [
        '52',
        '95',
        '3315',
        '152',
        '35.65',
        '57.76',
        '8',
        '14',
      ]);

      final bowl = p.bowlingTable;
      expect(bowl.rows.first.cells, [
        '52',
        '30',
        '6',
        '336',
        '56',
        '2.91',
        '2/27',
        '0',
      ]);
      // The Hundred: 0 wickets → average and best figures are not defined.
      final hundred = bowl.rows.last;
      expect(hundred.format, 'The Hundred');
      expect(hundred.cells[4], kDash);
      expect(hundred.cells[6], kDash);

      expect(p.debuts.first.format, 'Test');
      expect(p.debuts.first.match, 'South Africa vs Bangladesh');
      expect(p.debuts.first.date, isNotNull);
      expect(p.teams, contains('Lucknow Super Giants'));
      expect(p.description, startsWith('A young prodigy'));
      expect(p.description, isNot(contains('<p>')));
    });

    test('list item (withDetails: false) has header facts only', () {
      final p = PlayerProfile.fromJson(
        fixtureJson('players_country')['data'][0],
        withDetails: false,
        now: now,
      );
      expect(p.name, 'Yashasvi Jaiswal');
      expect(p.hasDetails, isFalse);
      expect(p.ranks, isNull);
      expect(p.battingTable.isEmpty, isTrue);
      expect(p.facts.first, ('Role', 'Batter'));
    });

    test('malformed / empty JSON never throws and invents nothing', () {
      final p = PlayerProfile.fromJson(null);
      expect(p.name, 'Unnamed player');
      expect(p.facts, isEmpty);
      final q = PlayerProfile.fromJson({
        'name': 'x',
        'isWicketKeeper': 'true',
        'iccRanking': {'batting': 'bad'},
        'battingStats': [
          null,
          {'name': 'ODI', 'stats': 'oops'},
          {
            'name': 'T20I',
            'stats': {'runs': 10},
          },
        ],
        'bowlingStats': [
          {
            'name': 'TEST',
            'stats': {'ball': 0, 'innings': 0},
          },
          {
            'stats': {'wickets': '2', 'fiveWicketHauls': '1'},
          },
        ],
        'debuts': [
          {'format': null},
          'x',
          {'format': 'ODI', 'timestamp': 0},
        ],
        'teams': [
          {'name': null},
          'str',
          {'name': 'Team A'},
          {'name': 'Team A'},
        ],
        'description': 42,
      });
      expect(q.facts, [('Wicketkeeper', 'Yes')]);
      expect(q.ranks, isNull);
      expect(q.battingTable.rows.length, 1); // the 'oops' row is dropped
      expect(q.battingTable.rows.single.cells[2], '10');
      expect(q.battingTable.rows.single.cells[0], kDash);
      expect(q.bowlingTable.rows.length, 1); // never bowled in Tests → left out
      expect(q.bowlingTable.rows.single.format, kDash);
      expect(q.debuts.single.date, isNull);
      expect(q.teams, ['Team A']);
      expect(q.description, '');
    });
  });
}
