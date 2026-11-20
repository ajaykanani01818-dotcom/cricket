import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/utils/fixture_status.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/common/upcoming_match_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

JsonMap _m({
  String status = 'LIVE',
  String? s1,
  String? s2,
  String format = 'T20',
  List<String>? order,
  String? current,
  Object? isLive,
  String? result,
  Object? target,
}) => {
  'sb_match_key': 'M1',
  'status': status,
  'format': format,
  'isLive': ?isLive,
  'inningsOrder': ?order,
  'currentInning': ?current,
  'targetRuns': ?target,
  'result': {'message': result ?? '', 'winnerTeamKey': ''},
  'teams': {
    't1': {
      'key': 'ind',
      'name': 'India',
      'short_name': 'IND',
      'score': s1 ?? '',
    },
    't2': {
      'key': 'aus',
      'name': 'Australia',
      'short_name': 'AUS',
      'score': s2 ?? '',
    },
  },
};

void main() {
  group('status words -> sentence-case labels', () {
    test('the documented mapping', () {
      expect(statusLabelFor('LIVE'), 'Live');
      expect(statusLabelFor('NOT_STARTED'), 'Upcoming');
      expect(statusLabelFor('COMPLETED'), 'Result');
      expect(statusLabelFor('STUMPS'), 'Stumps');
      expect(statusLabelFor('NO_RESULT'), 'No result');
      expect(statusLabelFor('ABANDONED'), 'Abandoned');
    });

    test('variants, breaks and unknown words never shout', () {
      expect(statusLabelFor('in progress'), 'Live');
      expect(statusLabelFor('Innings Break'), 'Innings break');
      expect(statusLabelFor('RAIN_DELAY'), 'Rain delay');
      expect(statusLabelFor('MATCH_ABANDONED'), 'Abandoned');
      expect(statusLabelFor('CANCELLED'), 'Cancelled');
      expect(statusLabelFor('SOMETHING_NEW'), 'Something new');
      expect(statusLabelFor(''), '');
    });

    test('phases', () {
      expect(phaseForStatus('LIVE'), MatchPhase.live);
      expect(phaseForStatus('STUMPS'), MatchPhase.paused);
      expect(phaseForStatus('TEA'), MatchPhase.paused);
      expect(phaseForStatus('NOT_STARTED'), MatchPhase.upcoming);
      expect(phaseForStatus('COMPLETED'), MatchPhase.result);
      expect(phaseForStatus('NO_RESULT'), MatchPhase.noResult);
      expect(phaseForStatus('ABANDONED'), MatchPhase.abandoned);
      expect(phaseForStatus(''), MatchPhase.unknown);
    });
  });

  group('parseMatchList derives everything from `status`', () {
    test(
      'isLive quirk: the isLive flag is ignored on upcoming and completed items',
      () {
        final up = parseMatchList(fixtureJson('match_upcoming')['data']);
        final done = parseMatchList(fixtureJson('match_completed')['data']);
        // The fixtures carry isLive: true on these items.
        expect(
          J.maps(fixtureJson('match_completed')['data']).first['isLive'],
          isTrue,
        );
        expect(up.every((m) => !m.isLive && m.isUpcoming), isTrue);
        expect(done.every((m) => !m.isLive && m.isFinished), isTrue);
        expect(done.first.fixtureCardKind, FixtureCardKind.completed);
      },
    );

    test('one-sided score is not "live" unless the status says so', () {
      final m = parseMatchList([
        _m(status: 'NOT_STARTED', s1: '0/0 (0.0)'),
      ]).single;
      expect(m.isLive, isFalse);
      expect(
        m.team1Score,
        isNull,
        reason: 'an upcoming match has no score (no fake zero)',
      );
      expect(m.displayScore(1), isNull);
      expect(m.statusLine, isNull);
    });

    test('STUMPS is in progress but not "in play"; no raw words leak', () {
      final m = parseMatchList([
        _m(status: 'STUMPS', s1: '135/4 (42.0)', format: 'TEST'),
      ]).single;
      expect(m.isLive, isTrue);
      expect(m.isInPlay, isFalse);
      expect(m.statusLabel, 'Stumps');
      expect(m.status, 'Stumps');
      expect(m.statusLine, isNull, reason: 'would only repeat the chip');
      expect(m.displayScore(2), '—', reason: 'yet to bat');
    });

    test('raw LIVE never becomes footer text', () {
      final m = parseMatchList([_m(s1: '45/2 (4.1)')]).single;
      expect(m.status, 'Live');
      expect(m.statusLine, isNull);
    });

    test('chase line; never "need 0 runs"; never "in 0 balls"', () {
      final chase = parseMatchList([liveMatchJson()]).single;
      expect(chase.chaseSummaryLine, 'UAE Bulls need 87 runs in 35 balls');
      expect(chase.statusLine, 'UAE Bulls need 87 runs in 35 balls');

      final won = parseMatchList([
        _m(
          s1: '150/4 (20.0)',
          s2: '151/3 (18.2)',
          order: ['t1_1', 't2_1'],
          current: 't2_1',
        ),
      ]).single;
      expect(won.chaseSummaryLine, isNull);
      expect(won.status, isNot(contains('need 0')));
      expect(won.status, 'Live');

      final lastBall = parseMatchList([
        _m(
          s1: '150/4 (20.0)',
          s2: '140/9 (20.0)',
          order: ['t1_1', 't2_1'],
          current: 't2_1',
        ),
      ]).single;
      expect(lastBall.chaseSummaryLine, 'Australia need 11 runs');

      expect(
        liveEquationLine(
          _m(s1: '150/4 (20.0)', s2: '149/3 (19.5)', order: ['t1_1', 't2_1']),
        ),
        'Australia need 2 runs in 1 ball',
      );
    });

    test('Test match: lead/trail instead of a chase', () {
      final lead = parseMatchList([
        _m(
          format: 'TEST',
          s1: '98/10 (40.0)',
          s2: '135/4 (42.0)',
          order: ['t1_1', 't2_1'],
          current: 't2_1',
        ),
      ]).single;
      expect(lead.chaseSummaryLine, 'AUS lead by 37');
      final trail = liveEquationLine(
        _m(
          format: 'TEST',
          s1: '300/10 (90.0)',
          s2: '120/2 (30.0)',
          order: ['t1_1', 't2_1'],
        ),
      );
      expect(trail, 'AUS trail by 180');
      expect(
        liveEquationLine(
          _m(format: 'TEST', s1: '1', s2: '2', order: ['t1_1', 't2_1', 't1_2']),
        ),
        isNull,
      );
    });

    test('result message wins; winner side from winnerTeamKey', () {
      final m = parseMatchList(fixtureJson('match_recent')['data']).first;
      expect(m.status, 'UAE Bulls won by 6 wickets');
      expect(m.statusLine, 'UAE Bulls won by 6 wickets');
      expect(m.winnerSide, 1);
      expect(hasDisplayableResult(m), isTrue);
    });

    test('abandoned without a message shows the label, not a result row', () {
      final m = parseMatchList([_m(status: 'ABANDONED')]).single;
      expect(m.status, 'Abandoned');
      expect(m.fixtureCardKind, FixtureCardKind.abandoned);
      expect(m.isFinished, isTrue);
      expect(hasDisplayableResult(m), isFalse);
      expect(isMatchLiveForCard(m), isFalse);
    });

    test('current over balls come from the item when present', () {
      final j = _m(s1: '10/0 (1.2)')
        ..['currentOver'] = {
          'overNumber': 2,
          'balls': [
            {'value': '4'},
            {'value': 'WK'},
            {'value': null},
          ],
        };
      final m = parseMatchList([j]).single;
      expect(m.currentOverBalls, ['4', 'WK']);
      expect(m.currentOverNumber, 2);
    });
  });
}
