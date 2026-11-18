import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/match_detail/logic/commentary_controller.dart';
import 'package:crickbex/features/match_detail/logic/match_detail_logic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

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
    c.setFilter(CommentaryFilter.wicket);
    expect(c.visible.single.value, 'WK');
    c.setFilter(CommentaryFilter.six);
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

  testWidgets('live poll refreshes page 1 every 20s only while on page 1 and visible', (tester) async {
    final api = FakeApi();
    api.commentary = (req) =>
        ok(commentaryPage(count: req.url.queryParameters['page'] == '1' ? 60 : 10, totalCount: 70, startOver: req.url.queryParameters['page'] == '1' ? 200 : 150));
    final vis = ValueNotifier(true);
    final c = make(api, vis: vis);
    c.ensureLoaded();
    await tester.pump();
    c.setPolling(true);
    await tester.pump(const Duration(seconds: 20));
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
    final before = api.count('commentary');
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(api.count('commentary'), before, reason: 'no page-1 replace after loading more pages');
    expect(c.balls.length, 70);
    c.setPolling(false);
    c.dispose();
  });
}
