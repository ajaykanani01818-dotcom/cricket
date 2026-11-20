import 'dart:async';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/common/match_time.dart';
import 'package:crickbex/features/common/series_resolver.dart';
import 'package:crickbex/features/common/tap_guard.dart';
import 'package:crickbex/features/common/upcoming_match_card.dart';
import 'package:crickbex/features/common/visible_poller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('match_time', () {
    final now = DateTime(2026, 11, 18, 10, 0);

    test('startsInLabel formats days/hours/minutes and hides past starts', () {
      expect(startsInLabel(now.add(const Duration(days: 2, hours: 3, minutes: 5)), now), '2d 3h');
      expect(startsInLabel(now.add(const Duration(hours: 5, minutes: 7)), now), '5h 7m');
      expect(startsInLabel(now.add(const Duration(minutes: 42)), now), '42m');
      expect(startsInLabel(now.add(const Duration(seconds: 20)), now), '0m');
      expect(startsInLabel(now, now), isNull);
      expect(startsInLabel(now.subtract(const Duration(minutes: 1)), now), isNull);
    });

    test('countdownWithin24h only within the next 24h', () {
      expect(countdownWithin24h(now.add(const Duration(hours: 3, minutes: 1)), now), '3h 1m');
      expect(countdownWithin24h(now.add(const Duration(minutes: 9)), now), '9m');
      expect(countdownWithin24h(now.add(const Duration(hours: 25)), now), isNull);
      expect(countdownWithin24h(now.subtract(const Duration(hours: 1)), now), isNull);
    });

    test('formatMatchTime: Today / Tomorrow / date', () {
      expect(formatMatchTime(DateTime(2026, 11, 18, 15, 30), now), (dayLabel: 'Today', time: '03:30 PM'));
      expect(formatMatchTime(DateTime(2026, 11, 19, 9, 5), now).dayLabel, 'Tomorrow');
      expect(formatMatchTime(DateTime(2026, 12, 2, 9, 5), now).dayLabel, 'Dec 2');
    });

    test('formatShortDate degrades to "-" on garbage', () {
      expect(formatShortDate(DateTime(2026, 11, 19, 12).toIso8601String()), 'Nov 19');
      expect(formatShortDate(''), '-');
      expect(formatShortDate('not a date'), '-');
    });

    test('MinuteClock ticks only while listened to', () {
      void l() {}
      expect(MinuteClock.instance.isTicking, isFalse);
      MinuteClock.instance.addListener(l);
      expect(MinuteClock.instance.isTicking, isTrue);
      MinuteClock.instance.removeListener(l);
      expect(MinuteClock.instance.isTicking, isFalse);
    });
  });

  group('parseMatchList', () {
    test('parses the real fixtures', () {
      final recent = parseMatchList(fixtureJson('match_recent')['data']);
      expect(recent, hasLength(10));
      expect(recent.first.id, 'LCoO4aA');
      expect(recent.every((m) => !m.isLive), isTrue);
      expect(parseMatchList(fixtureJson('match_upcoming')['data']), hasLength(6));
      expect(parseMatchList(fixtureJson('match_live_list')['data']), isEmpty);
    });

    test('crafted LIVE match gets a chase line', () {
      final m = parseMatchList([liveMatchJson()]).single;
      expect(m.isLive, isTrue);
      expect(m.chaseSummaryLine, 'UAE Bulls need 87 runs in 35 balls');
    });

    test('malformed input never throws', () {
      expect(parseMatchList(null), isEmpty);
      expect(parseMatchList('nope'), isEmpty);
      expect(parseMatchList({'a': 1}), isEmpty);
      final l = parseMatchList([1, 'x', <String, dynamic>{}, {'teams': 5, 'status': 9}]);
      expect(l, hasLength(2));
      expect(l.first.team1, '');
    });
  });

  group('UpcomingMatchCard helpers', () {
    test('ordinalSuffix', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map((n) => '$n${ordinalSuffix(n)}').toList(),
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '101st', '111th']);
    });

    test('isMatchLiveForCard / hasDisplayableResult', () {
      final live = parseMatchList([liveMatchJson()]).single;
      final done = parseMatchList(fixtureJson('match_recent')['data']).first;
      expect(isMatchLiveForCard(live), isTrue);
      expect(isMatchLiveForCard(live, completed: true), isFalse);
      expect(isMatchLiveForCard(done), isFalse);
      expect(hasDisplayableResult(done), isTrue);
    });
  });

  group('resolveSeriesId', () {
    test('null without candidates', () async {
      FakeApi().install();
      expect(await resolveSeriesId(MatchService.instance, candidates: [null, ' ']), isNull);
    });

    test('prefers catalog ids that resolve, probing in order', () async {
      final api = FakeApi({
        '/series': FakeApi.ok(body([
          {'name': 'Other', '_id': 'zzz'},
          {'name': 'Big Bash League 2026-27', '_id': 'cat_id', 'sb_series_key': 'SB1'},
        ])),
        '/series/SB1': FakeApi.fixture('series_fixtures'),
      })
        ..install();
      final id = await resolveSeriesId(MatchService.instance, candidates: ['raw_id'], name: 'Big Bash League 2026-27');
      expect(id, 'SB1');
      // _id is tried before sb_series_key (RN unshift order), and fails.
      expect(api.count('/series/cat_id'), 1);
      expect(api.count('/series/raw_id'), 0);
    });

    test('falls back to the first candidate when nothing resolves', () async {
      FakeApi({'/series': FakeApi.status(500)}).install();
      expect(await resolveSeriesId(MatchService.instance, candidates: ['a', 'b']), 'a');
    });
  });

  test('TapGuard ignores re-entry and recovers after errors', () async {
    final g = TapGuard(cooldown: Duration.zero);
    final gate = Completer<void>();
    var runs = 0;
    final f = g.run(() async {
      runs++;
      await gate.future;
    });
    await g.run(() => runs++);
    expect(runs, 1);
    gate.complete();
    await f;
    await g.run(() => throw StateError('x'));
    await g.run(() => runs++);
    expect(runs, 2);
    expect(TapGuard().busy, isFalse);
  });

  group('VisiblePoller', () {
    testWidgets('pauses when hidden or backgrounded, ticks immediately on return', (tester) async {
      var ticks = 0;
      final p = VisiblePoller(interval: const Duration(seconds: 30), onTick: () => ticks++)..start();
      await tester.pump(const Duration(seconds: 61));
      expect(ticks, 2);

      p.setScreenVisible(false);
      expect(p.isRunning, isFalse);
      await tester.pump(const Duration(minutes: 5));
      expect(ticks, 2);

      p.setScreenVisible(true);
      expect(ticks, 3, reason: 'immediate refresh when shown again');
      expect(p.isRunning, isTrue);

      p.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      expect(ticks, 3);
      p.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(p.isRunning, isFalse);
      p.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(ticks, 4);

      // Resumed while the tab is hidden: stays paused.
      p.setScreenVisible(false);
      p.didChangeAppLifecycleState(AppLifecycleState.paused);
      p.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(ticks, 4);
      expect(p.isRunning, isFalse);

      p.dispose();
      p.setScreenVisible(true);
      expect(p.isRunning, isFalse);
    });
  });

  test('friendly errors are passed through', () {
    expect(friendlyError(const ApiException(500, 'boom')), 'boom');
  });
}
