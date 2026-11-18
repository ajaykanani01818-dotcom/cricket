import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/utils/chase_summary.dart';
import 'package:crickbex/core/utils/fixture_status.dart';
import 'package:crickbex/core/utils/match_transform.dart';
import 'package:flutter_test/flutter_test.dart';

JsonMap fixture(String name) => J.map(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

void main() {
  group('J', () {
    test('tolerates wrong types and missing fields', () {
      expect(J.integer('12'), 12);
      expect(J.integer('12.7'), 12);
      expect(J.integer(null), isNull);
      expect(J.number('3.5'), 3.5);
      expect(J.text('  - '), isNull);
      expect(J.text(' x '), 'x');
      expect(J.at({'a': [{'b': 1}]}, 'a.0.b'), 1);
      expect(J.at({'a': 1}, 'a.b.c'), isNull);
      expect(J.maps([1, {'a': 2}, null]), [{'a': 2}]);
      expect(J.boolean('true'), isTrue);
      expect(J.integer('NaN'), isNull);
      expect(J.integer(double.infinity), isNull);
      expect(J.number('Infinity'), isNull);
    });
  });

  group('chase summary', () {
    test('score parsing helpers', () {
      expect(parseLeadingRunsFromScore('145/6 (18.2)'), 145);
      expect(parseLeadingRunsFromScore('-'), isNull);
      expect(parseOversFromScoreParen('145/6 (18.2)'), '18.2');
      expect(oversToLegalBallsCompleted('18.2'), 110);
      expect(oversToLegalBallsCompleted('18.9'), 113); // clamps bad fraction to .5
      expect(inferMaxOversFromFormat('T20'), 20);
      expect(inferMaxOversFromFormat('ODI'), 50);
      expect(inferMaxOversFromFormat('TEST'), isNull);
      expect(inferMaxOversFromFormat('T10'), 10);
    });

    test('computes runs and balls for a live T20 chase', () {
      final c = computeChaseSummaryForLiveList({
        'format': 'T20',
        'inningsOrder': ['t1_1', 't2_1'],
        'teams': {
          't1': {'name': 'India', 'score': '180/5 (20)'},
          't2': {'name': 'Australia', 'score': '100/3 (12.0)'},
        },
      })!;
      expect(c.chasingTeamName, 'Australia');
      expect(c.runsNeeded, 81);
      expect(c.ballsRemaining, 48);
    });

    test('no summary when result exists or innings unknown', () {
      expect(computeChaseSummaryForLiveList({'result': {'message': 'India won'}}), isNull);
      expect(computeChaseSummaryForLiveList({'teams': {'t1': {'score': '10/0'}, 't2': {'score': '-'}}}), isNull);
    });
  });

  group('fixture status', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    test('maps API statuses', () {
      expect(resolveSeriesFixtureDisplay('LIVE', '2026-01-01T10:00:00Z', null, now).kind, FixtureCardKind.live);
      expect(resolveSeriesFixtureDisplay('COMPLETED', '', 'India won', now).statusLine, 'India won');
      expect(resolveSeriesFixtureDisplay('ABANDONED', '', null, now).kind, FixtureCardKind.abandoned);
      expect(resolveSeriesFixtureDisplay('NO_RESULT', '', null, now).kind, FixtureCardKind.cancelled);
      expect(resolveSeriesFixtureDisplay('NOT_STARTED', '2026-01-02T10:00:00Z', null, now).statusLine, 'Not started');
    });
    test('infers cancelled when long past and undecided', () {
      expect(resolveSeriesFixtureDisplay('NOT_STARTED', '2025-12-31T00:00:00Z', null, now).kind, FixtureCardKind.cancelled);
    });
  });

  group('match transform', () {
    test('transforms every match in the real /match/recent fixture without throwing', () {
      final list = transformApiMatches(J.maps(fixture('match_recent')['data']));
      expect(list, isNotEmpty);
      for (final m in list) {
        expect(m.id, isNotEmpty);
        expect(m.team1, isNotEmpty);
      }
    });

    test('prefers sb_match_key for the id and result message for status', () {
      final m = transformApiMatch({
        '_id': 'mongo',
        'sb_match_key': 'abc1234',
        'status': 'COMPLETED',
        'result': {'message': 'India won by 5 runs'},
        'teams': {'t1': {'name': 'India', 'score': '200/5'}, 't2': {'name': 'Aus', 'score': '195/9'}},
      });
      expect(m.id, 'abc1234');
      expect(m.isLive, isFalse);
      expect(m.status, 'India won by 5 runs');
    });

    test('live first innings shows "yet to bat"', () {
      final m = transformApiMatch({
        'status': 'LIVE',
        'currentInning': 't1_1',
        'teams': {'t1': {'name': 'India', 'score': '50/1 (6)'}, 't2': {'name': 'Aus', 'score': ''}},
      });
      expect(m.isLive, isTrue);
      expect(m.status, 'Aus yet to bat');
    });

    test('empty / garbage match JSON does not crash', () {
      final m = transformApiMatch({'teams': 'oops'});
      expect(m.team1, '');
      expect(m.status, 'Match starting soon');
    });
  });
}
