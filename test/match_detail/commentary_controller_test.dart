import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/logic/commentary_controller.dart';
import 'package:crickbex/features/match_detail/logic/match_detail_logic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

/// Page 1 after [newOvers] more overs: the new deliveries (overs 201…)
/// followed by the same older balls (identical keys).
JsonMap livePage(int newOvers, {int count = 60, int totalCount = 70}) {
  final base = commentaryPage(count: count, totalCount: totalCount);
  final fresh = <dynamic>[
    for (var k = newOvers; k >= 1; k--) ...J.list(commentaryPage(count: 6, totalCount: 0, startOver: 200 + k)['balls']),
  ];
  final balls = [...fresh, ...J.list(base['balls'])].take(count).toList();
  return {...base, 'balls': balls};
}

void main() {
  CommentaryController make(FakeApi api, {ValueNotifier<bool>? vis}) => CommentaryController(
        matchId: '3QJ-e3k',
        service: api.matches,
        visibility: vis ?? ValueNotifier(true),
      );

  test('loads page 1 from the fixture (30 balls < page size → no more)', () async {
    final api = FakeApi();
    final c = make(api);
    c.ensureLoaded();
    c.ensureLoaded(); // idempotent
    expect(c.loading, isTrue);
    await pumpEventQueue();
    expect(api.count('commentary'), 1);
    expect(api.calls.single.queryParameters, {'page': '1', 'perPage': '60'});
    expect(c.balls.length, 30);
    expect(c.hasMore, isFalse);
    expect(c.visible.first.timestamp, greaterThanOrEqualTo(c.visible.last.timestamp));
    expect(c.teams, ['t1_1']);
    c.dispose();
  });

  test('load more appends page 2 once even when tapped repeatedly; dedupes overlap', () async {
    final api = FakeApi();
    final page2 = Completer<http.Response>();
    api.commentary = (req) {
      final p = req.url.queryParameters['page'];
      if (p == '1') return ok(commentaryPage(count: 60, totalCount: 100));
      return page2.future;
    };
    final c = make(api);
    c.ensureLoaded();
    await pumpEventQueue();
    expect(c.hasMore, isTrue);
    unawaited(c.loadMore());
    unawaited(c.loadMore());
    unawaited(c.loadMore());
    await pumpEventQueue();
    expect(api.callsOf('commentary').where((u) => u.queryParameters['page'] == '2').length, 1);
    expect(c.loadingMore, isTrue);
    // page 2 overlaps the last 6 balls of page 1 (server pagination shifted)
    final p1 = commentaryPage(count: 60, totalCount: 100);
    final p2 = commentaryPage(count: 40, totalCount: 100, startOver: 190);
    (p2['balls'] as List).insertAll(0, (p1['balls'] as List).sublist(54));
    page2.complete(ok(p2));
    await pumpEventQueue();
    expect(c.page, 2);
    expect(c.balls.length, 100);
    expect(c.hasMore, isFalse);
    expect(c.loadingMore, isFalse);
    c.dispose();
  });

  test('filters and team chips', () async {
    final api = FakeApi();
    api.commentary = (_) => ok(commentaryPage(count: 12, totalCount: 12, wicketAt: 'yes'));
    final c = make(api);
    c.ensureLoaded();
    await pumpEventQueue();
    c.setFilter(CommentaryFilter.wickets);
    expect(c.visible.single.value, 'WK');
    c.setFilter(CommentaryFilter.boundaries);
    expect(c.filtered, isEmpty);
    c.setFilter(CommentaryFilter.all);
    c.setTeam('t2_1');
    expect(c.filtered, isEmpty);
    c.setTeam('all');
    expect(c.visible.length, 12);
    c.dispose();
  });

  test('404 → quiet empty state; 500 → error + retry recovers', () async {
    final api = FakeApi();
    api.commentary = (_) => err(404, 'Commentary not found');
    final c = make(api);
    c.ensureLoaded();
    await pumpEventQueue();
    expect(c.error, isNull);
    expect(c.hasData, isFalse);
    expect(c.hasMore, isFalse);

    api.commentary = (_) => err(500);
    await c.retry();
    expect(c.error, isNotNull);
    api.commentary = (_) => ok(J.map(fixture('match_commentary')['data']));
    await c.retry();
    expect(c.error, isNull);
    expect(c.balls.length, 30);
    c.dispose();
  });

  test('result after dispose is ignored', () async {
    final api = FakeApi();
    final gate = Completer<http.Response>();
    api.commentary = (_) => gate.future;
    final c = make(api);
    c.ensureLoaded();
    await pumpEventQueue();
    c.dispose();
    gate.complete(ok(J.map(fixture('match_commentary')['data'])));
    await pumpEventQueue(); // must not throw (notifyListeners after dispose)
  });

  testWidgets('live poll every 10s while visible; refresh merges in front of loaded pages', (tester) async {
    final api = FakeApi();
    var newOvers = 0;
    api.commentary = (req) => req.url.queryParameters['page'] == '1'
        ? ok(livePage(newOvers))
        : ok(commentaryPage(count: 10, totalCount: 70, startOver: 150));
    final vis = ValueNotifier(true);
    final c = make(api, vis: vis);
    c.ensureLoaded();
    await tester.pump();
    c.setPolling(true);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(api.count('commentary'), 2);
    vis.value = false;
    await tester.pump(const Duration(minutes: 2));
    expect(api.count('commentary'), 2);
    vis.value = true;
    await tester.pump();
    expect(api.count('commentary'), 3);
    await c.loadMore();
    expect(c.page, 2);
    expect(c.balls.length, 70);
    // One new over arrives: page 1 now starts at over 201 (6 new balls).
    newOvers = 1;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(c.page, 2, reason: 'loaded pages are kept');
    expect(c.balls.length, 76, reason: 'deduped merge: only the 6 new balls are added');
    expect(c.balls.map((b) => b.key).toSet().length, c.balls.length);
    c.setPolling(false);
    c.dispose();
  });

  testWidgets('scroll-position rule: while held, new balls wait behind a count; showPending applies them', (tester) async {
    final api = FakeApi();
    var newOvers = 0;
    api.commentary = (_) => ok(livePage(newOvers, count: 30, totalCount: 30));
    final c = make(api);
    c.ensureLoaded();
    await tester.pump();
    final first = c.visible.first.key;
    var notified = 0;
    c.addListener(() => notified++);
    c.setPolling(true);
    c.setHold(true);

    // Unchanged refresh: nothing pending, list untouched.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(c.pendingCount, 0);
    expect(c.visible.first.key, first);

    newOvers = 1; // 6 new deliveries
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(c.pendingCount, 6);
    expect(c.visible.first.key, first, reason: 'held: the feed does not move');
    expect(notified, greaterThan(0));

    c.showPending();
    expect(c.pendingCount, 0);
    expect(c.visible.first.key, isNot(first));
    expect(c.visible.first.overLabel, '201.6');

    // Releasing the hold applies anything pending immediately.
    newOvers = 2;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(c.pendingCount, 6);
    c.setHold(false);
    expect(c.pendingCount, 0);
    expect(c.visible.first.overLabel, '202.6');
    c.setPolling(false);
    c.dispose();
  });

  test('visible feed keeps info notes under "All" only; over-end summaries parse', () async {
    final api = FakeApi()..live = (_) => ok(J.map(fixture('match_live')['data']));
    api.commentary = (_) => ok({...J.map(fixture('match_live')['data']), 'totalCount': 25});
    final c = make(api);
    c.ensureLoaded();
    await pumpEventQueue();
    expect(c.visible.where((b) => b.isInfo), isNotEmpty);
    final withSummary = c.visible.firstWhere((b) => b.overEnd != null);
    expect(withSummary.overEnd!.overNumber, 62);
    expect(withSummary.overEnd!.runs, 5);
    expect(withSummary.overEnd!.bowlerLine, 'Taskin Ahmed 15.0-4-45-0');
    expect(withSummary.overEnd!.batterLines, ['Temba Bavuma 19 (54)', 'Ryan Rickelton 7 (7)']);
    c.setFilter(CommentaryFilter.wickets);
    expect(c.visible.every((b) => b.type == 'ball'), isTrue);
    c.dispose();
  });
}
