import 'dart:async';

import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/series/series_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'series_test_helpers.dart';

void main() {
  late MatchService original;
  setUp(() => original = MatchService.instance);
  tearDown(() => MatchService.instance = original);

  Future<FakeApi> pumpScreen(WidgetTester tester, FutureOr<http.Response> Function(http.Request) handler) async {
    final api = FakeApi(handler);
    MatchService.instance = api.service;
    await tester.pumpWidget(routerApp(seriesTestRouter(home: const SeriesScreen())));
    return api;
  }

  testWidgets('shows shimmer then the Current (ONGOING) list', (tester) async {
    final gate = Completer<http.Response>();
    final api = await pumpScreen(tester, (req) => gate.future);
    await tester.pump();
    expect(find.byKey(const ValueKey('series_shimmer')), findsOneWidget);
    expect(find.text('SERIES'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    gate.complete(jsonResponse(seriesPage('ONGOING', 0, 5)));
    await settleNetwork(tester);
    expect(find.byKey(const ValueKey('series_shimmer')), findsNothing);
    expect(find.text('ONGOING Series 0'), findsOneWidget);
    expect(find.text('LIVE'), findsWidgets);
    expect(api.requests.single.queryParameters['status'], 'ONGOING');
    // other tabs are not fetched until shown
    expect(api.count((u) => u.queryParameters['status'] != 'ONGOING'), 0);
  });

  testWidgets('renders real /series fixture', (tester) async {
    await pumpScreen(tester, (req) => jsonResponse(fixtureJson('series_list.json')));
    await settleNetwork(tester);
    expect(find.text('Mens Cricket World Cup 2027'), findsOneWidget);
    expect(find.text('UPCOMING'), findsWidgets);
  });

  testWidgets('empty state', (tester) async {
    await pumpScreen(tester, (req) => jsonResponse({'message': 'ok', 'data': []}));
    await settleNetwork(tester);
    expect(find.text('No series in this section'), findsOneWidget);
  });

  testWidgets('error state + Try Again recovers', (tester) async {
    var fail = true;
    final api = await pumpScreen(
        tester, (req) => fail ? jsonResponse({'message': 'Server exploded'}, 500) : jsonResponse(seriesPage('ONGOING', 0, 3)));
    await settleNetwork(tester);
    expect(find.text('Server exploded'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('series_retry')));
    await settleNetwork(tester);
    expect(find.text('ONGOING Series 0'), findsOneWidget);
    expect(api.requests, hasLength(2));
  });

  testWidgets('network timeout/offline shows friendly error', (tester) async {
    await pumpScreen(tester, (req) => throw http.ClientException('offline'));
    await settleNetwork(tester);
    expect(find.textContaining('Unable to reach the server'), findsOneWidget);
    expect(find.byKey(const ValueKey('series_retry')), findsOneWidget);
  });

  testWidgets('tapping a series opens detail with sb_series_key + name (no double push)', (tester) async {
    await pumpScreen(tester, (req) => jsonResponse(seriesPage('ONGOING', 0, 3)));
    await settleNetwork(tester);
    final card = find.byKey(const ValueKey('series_card_ONGOING-1'));
    await tester.tap(card);
    await tester.tap(card, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('DETAIL key_ONGOING_1 ONGOING Series 1'), findsOneWidget);
  });

  testWidgets('pull-to-refresh refetches page 1', (tester) async {
    var round = 0;
    final api = await pumpScreen(tester, (req) => jsonResponse(seriesPage('ONGOING', round++ * 100, 3)));
    await settleNetwork(tester);
    expect(find.text('ONGOING Series 0'), findsOneWidget);
    await tester.fling(find.byKey(const ValueKey('series_list_ONGOING')), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settleNetwork(tester);
    expect(api.requests, hasLength(2));
    expect(find.text('ONGOING Series 100'), findsOneWidget);
    expect(find.text('ONGOING Series 0'), findsNothing);
  });

  testWidgets('infinite scroll loads next page once and stops at last page', (tester) async {
    final api = await pumpScreen(tester, (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      return jsonResponse(seriesPage('ONGOING', (page - 1) * 24, 24, total: 48, page: page));
    });
    await settleNetwork(tester);
    expect(api.count((u) => u.queryParameters['page'] == '2'), 0);
    final list = find.byKey(const ValueKey('series_list_ONGOING'));
    for (var i = 0; i < 30; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settleNetwork(tester);
    expect(api.count((u) => u.queryParameters['page'] == '2'), 1);
    for (var i = 0; i < 40; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settleNetwork(tester);
    expect(find.text('ONGOING Series 47'), findsOneWidget);
    expect(api.count((u) => u.queryParameters['page'] == '2'), 1);
    expect(api.count((u) => u.queryParameters['page'] == '3'), 0);
  });

  testWidgets('first page shorter than the viewport still pages in', (tester) async {
    final api = await pumpScreen(tester, (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      // pageInfo says 2 pages but page 1 has only 2 rows (fits on screen)
      return jsonResponse(seriesPage('ONGOING', (page - 1) * 2, 2, total: 4, perPage: 2, page: page));
    });
    await settleNetwork(tester, 10);
    expect(api.count((u) => u.queryParameters['page'] == '2'), 1);
    expect(find.text('ONGOING Series 3'), findsOneWidget);
  });

  testWidgets('switching tabs: slow ONGOING response never overwrites Archive', (tester) async {
    final ongoing = Completer<http.Response>();
    final api = await pumpScreen(tester, (req) {
      final status = req.url.queryParameters['status'];
      if (status == 'ONGOING') return ongoing.future;
      return jsonResponse(seriesPage(status!, 0, 3));
    });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab_COMPLETED')));
    await settleNetwork(tester, 10);
    expect(find.text('COMPLETED Series 0'), findsOneWidget);
    // UPCOMING was only passed through by the animation — not fetched.
    expect(api.count((u) => u.queryParameters['status'] == 'UPCOMING'), 0);
    ongoing.complete(jsonResponse(seriesPage('ONGOING', 0, 3)));
    await settleNetwork(tester);
    expect(find.text('COMPLETED Series 0'), findsOneWidget);
    expect(find.text('ONGOING Series 0'), findsNothing);
    // Going back shows the ONGOING data without refetching.
    await tester.tap(find.byKey(const ValueKey('tab_ONGOING')));
    await settleNetwork(tester, 10);
    expect(find.text('ONGOING Series 0'), findsOneWidget);
    expect(api.count((u) => u.queryParameters['status'] == 'ONGOING'), 1);
  });

  testWidgets('swiping the pager loads the next tab', (tester) async {
    final api = await pumpScreen(tester, (req) => jsonResponse(seriesPage(req.url.queryParameters['status']!, 0, 2)));
    await settleNetwork(tester);
    await tester.fling(find.byKey(const ValueKey('series_pager')), const Offset(-500, 0), 1500);
    await settleNetwork(tester, 12);
    expect(api.count((u) => u.queryParameters['status'] == 'UPCOMING'), 1);
    expect(find.text('UPCOMING Series 0'), findsOneWidget);
  });

  testWidgets('load-more failure shows footer Try Again that recovers', (tester) async {
    var failPage2 = true;
    final api = await pumpScreen(tester, (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      if (page == 2 && failPage2) return jsonResponse({'message': 'Page 2 failed'}, 500);
      return jsonResponse(seriesPage('ONGOING', (page - 1) * 2, 2, total: 4, perPage: 2, page: page));
    });
    await settleNetwork(tester, 10);
    expect(find.text('Page 2 failed'), findsOneWidget);
    expect(find.text('ONGOING Series 0'), findsOneWidget); // first page kept
    // the failed page is not retried automatically
    expect(api.count((u) => u.queryParameters['page'] == '2'), 1);
    failPage2 = false;
    await tester.tap(find.byKey(const ValueKey('series_load_more_retry')));
    await settleNetwork(tester);
    expect(find.text('ONGOING Series 3'), findsOneWidget);
    expect(find.text('Page 2 failed'), findsNothing);
  });

  testWidgets('very long names and missing dates do not overflow', (tester) async {
    await pumpScreen(
      tester,
      (req) => jsonResponse({
        'data': [
          {'_id': 'a', 'name': 'Super ' * 80, 'seriesStatus': 'ONGOING', 'format': 'T20'},
          {'_id': 'b'},
        ],
      }),
    );
    await settleNetwork(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('T20'), findsOneWidget);
  });
}
