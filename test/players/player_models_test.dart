import 'package:crickbex/features/players/player_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18);

  group('helpers', () {
    test('role / hand labels', () {
      expect(roleLabelOf(0), 'Batsman');
      expect(roleLabelOf(4), 'Bowling All Rounder');
      expect(roleLabelOf(null), 'Player');
      expect(roleLabelOf(99), 'Player');
      expect(roleWithHand(0, 1), 'Batsman · Left Handed');
      expect(roleWithHand(1, null), 'Bowler');
      expect(roleWithHand(null, 7), 'Player');
    });

    test('age', () {
      // 2002-01-01 UTC
      const dob = 1009843200;
      expect(ageYears(dob, now: now), 24);
      expect(ageShort(dob, now: now), '24');
      expect(ageLong(dob, now: now), '24 years');
      expect(ageShort(null), kDash);
      expect(ageShort(0), kDash);
      expect(ageLong(null), kDash);
      // One year old.
      final oneYear = now.subtract(const Duration(days: 400)).millisecondsSinceEpoch ~/ 1000;
      expect(ageLong(oneYear, now: now), '1 year');
      // Future dob → unknown.
      expect(ageShort(now.millisecondsSinceEpoch ~/ 1000 + 100000, now: now), kDash);
    });

    test('formatDob', () {
      expect(formatDob(null), kDash);
      expect(formatDob(0), kDash);
      expect(formatDob(-5), kDash);
      final ts = DateTime(1994, 10, 4, 12).millisecondsSinceEpoch ~/ 1000;
      expect(formatDob(ts), 'Oct 4, 1994');
    });

    test('stripHtml', () {
      expect(stripHtml(null), '');
      expect(stripHtml(''), '');
      expect(stripHtml('<p>Hello&nbsp;<b>world</b></p><p>It&#39;s &amp; &lt;ok&gt; &quot;x&quot;</p>'),
          'Hello world\nIt\'s & <ok> "x"');
      expect(stripHtml('a<br/>b<BR>c'), 'a\nb\nc');
    });

    test('fmtStat mirrors JS number display', () {
      expect(fmtStat(56), '56');
      expect(fmtStat(56.0), '56');
      expect(fmtStat(35.65), '35.65');
      expect(fmtStat('2/27'), '2/27');
      expect(fmtStat(null), kDash);
      expect(fmtStat(''), kDash);
      expect(fmtStat(null, '0'), '0');
      expect(fmtStat(double.nan), kDash);
    });

    test('computeHasMore', () {
      expect(computeHasMore(received: 20, perPage: 20, infoPage: 1, infoPerPage: 20, infoTotal: 5370), isTrue);
      expect(computeHasMore(received: 20, perPage: 20, infoPage: 1, infoPerPage: 20, infoTotal: 20), isFalse);
      expect(computeHasMore(received: 20, perPage: 20), isTrue);
      expect(computeHasMore(received: 7, perPage: 20), isFalse);
      expect(computeHasMore(received: 0, perPage: 20, infoPage: 1, infoPerPage: 20, infoTotal: 100), isFalse);
      // perPage 0 in pageInfo must not loop forever.
      expect(computeHasMore(received: 5, perPage: 20, infoPage: 1, infoPerPage: 0, infoTotal: 100), isFalse);
    });
  });

  group('CountryPlayer', () {
    test('parses fixture', () {
      final list = CountryPlayer.listFrom(fixtureJson('players_country')['data'], now: now);
      expect(list.length, 20);
      final p = list.first;
      expect(p.playerKey, 'yashasvi_jaiswal');
      expect(p.id, '6afb224d31bbe1ca56430b4f');
      expect(p.name, 'Yashasvi Jaiswal');
      expect(p.roleText, 'Batsman · Left Handed');
      expect(p.ageText, '24');
      expect(p.logo, startsWith('https://'));
      expect(p.raw['playerKey'], 'yashasvi_jaiswal');
    });

    test('malformed items degrade or are skipped', () {
      final list = CountryPlayer.listFrom([
        null,
        'x',
        <String, dynamic>{},
        {'playerKey': 'k1', 'role': '1', 'dob': 'abc', 'battingStyle': 'z'},
        {'_id': 'id2', 'name': '  ', 'logo': ''},
      ]);
      expect(list.length, 2);
      expect(list[0].id, 'k1');
      expect(list[0].name, kDash);
      expect(list[0].roleText, 'Bowler');
      expect(list[0].ageText, kDash);
      expect(list[1].playerKey, '');
      expect(list[1].logo, isNull);
      expect(CountryPlayer.listFrom('nope'), isEmpty);
    });
  });

  group('PlayerProfile', () {
    test('parses player_info fixture', () {
      final p = PlayerProfile.fromJson(fixtureJson('player_info')['data'], now: now);
      expect(p.name, 'Aiden Markram');
      expect(p.country, 'South Africa');
      expect(p.roleText, 'Batsman');
      expect(p.battingText, 'Right Handed');
      expect(p.bowlingText, 'Right-arm off-break');
      expect(p.meta, 'South Africa  ·  Batsman');
      expect(p.ranks, isNotNull);
      expect(p.ranks!.rank('batting', 'test'), '#17');
      expect(p.ranks!.rank('batting', 'odi'), '#29');
      expect(p.ranks!.rank('bowling', 't20'), kDash);
      expect(p.batting.first.name, 'TEST');
      final bat = {for (final r in p.batting.first.rows) r.label: r.value};
      expect(bat['Runs'], '3315');
      expect(bat['Average'], '35.65');
      expect(bat['100s / 50s'], '8 / 14');
      final bowl = {for (final r in p.bowling.first.rows) r.label: r.value};
      expect(bowl['Matches'], '52');
      expect(bowl['BBI / BBM'], '2/27 / 2/10');
      expect(bowl.containsKey('5w / 10w'), isFalse);
      expect(p.teams, contains('Lucknow Super Giants'));
      expect(p.description, isNot(contains('<p>')));
      expect(p.description, startsWith('A young prodigy'));
    });

    test('list item (withDetails: false) ignores rankings/stats', () {
      final item = fixtureJson('players_country')['data'][0];
      final p = PlayerProfile.fromJson(item, withDetails: false);
      expect(p.name, 'Yashasvi Jaiswal');
      expect(p.ranks, isNull);
      expect(p.batting, isEmpty);
    });

    test('malformed / empty JSON never throws', () {
      final p = PlayerProfile.fromJson(null);
      expect(p.name, kDash);
      expect(p.initial, '?');
      expect(p.bornText, kDash);
      expect(p.roleText, 'Player');
      expect(p.meta, 'Player');
      final q = PlayerProfile.fromJson({
        'name': 'x',
        'isWicketKeeper': 'true',
        'iccRanking': {'batting': 'bad'},
        'battingStats': [null, {'name': 'ODI', 'stats': 'oops'}],
        'bowlingStats': [
          {'stats': {'fiveWicketHauls': '2', 'tenWicketHauls': null}}
        ],
        'teams': [{'name': null}, 'str', {'name': 'Team A'}],
        'description': 42,
      });
      expect(q.meta, 'Player  ·  WK');
      expect(q.ranks!.rank('batting', 'test'), kDash);
      expect(q.batting.length, 1);
      expect(q.batting.first.rows.first.value, kDash);
      expect(q.bowling.first.name, kDash);
      expect(q.bowling.first.rows.last.label, '5w / 10w');
      expect(q.bowling.first.rows.last.value, '2 / 0');
      expect(q.teams, ['Team A']);
      expect(q.description, '42');
    });
  });
}
