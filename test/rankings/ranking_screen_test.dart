import 'dart:async';

import 'package:crickbex/features/rankings/ranking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../players/test_helpers.dart';

Map<String, Object> _rows(List<String> names) => {
      'message': 'ok',
      'data': [
        for (var i = 0; i < names.length; i++) {'name': names[i], 'order': i + 1, 'points': 900 - i, 'playerKey': names[i].toLowerCase()}
      ],
    };

/// Waits past the 120ms fade-out debounce and lets responses land.
Future<void> settle(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 130));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(WidgetTester t) async {
    await t.pumpWidget(routerApp(testRouter('/ranking', const RankingScreen())));
  }

  http.Response defaultHandler(http.Request r) =>
      jsonRes(r.url.path.endsWith('/rank/player') ? fixture('rank_player') : fixture('rank_team'));

  testWidgets('shows shimmer, then team podium + rows from /rank', (t) async {
    final completer = Completer<http.Response>();
    final api = FakeApi((r) => completer.future);
    await pumpScreen(t);
    expect(find.byKey(const ValueKey('rankings_shimmer')), findsOneWidget);
    expect(api.requests.single.path, '/rank');
    expect(api.requests.single.queryParameters, {'gender': 'MALE', 'matchType': 'TEST'});

    completer.complete(jsonRes(fixture('rank_team')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('rankings_shimmer')), findsNothing);
    expect(find.text('India'), findsOneWidget); // podium #1
    expect(find.text('3841'), findsOneWidget);
    expect(find.text('RANKS 4–20'), findsOneWidget);
    expect(find.byKey(const ValueKey('ranking_podium_1')), findsOneWidget);
    // Search is players-only.
    expect(find.byKey(const ValueKey('rankings_search')), findsNothing);
  });

  testWidgets('team rows are not tappable', (t) async {
    FakeApi(defaultHandler);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ranking_podium_1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('stub_detail')), findsNothing);
  });

  testWidgets('players mode: fetches /rank/player, search filters, tap navigates with initial player', (t) async {
    final api = FakeApi(defaultHandler);
    await pumpScreen(t);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('segment_players')));
    await settle(t);
    final playerReq = api.where((u) => u.path == '/rank/player');
    expect(playerReq.length, 1);
    expect(playerReq.single.queryParameters, {'gender': 'MALE', 'matchType': 'TEST', 'type': 'BATSMAN'});
    expect(find.text('Shubman Gill'), findsOneWidget);
    expect(find.text('RANKS 4–100'), findsOneWidget);

    // Category → bowlers.
    await t.tap(find.byKey(const ValueKey('segment_bowlers')));
    await settle(t);
    expect(api.where((u) => u.queryParameters['type'] == 'BOWLER').length, 1);

    // Search (regression: the first match must be shown even though it is rank 1).
    await t.enterText(find.byKey(const ValueKey('rankings_search')), 'gill');
    await t.pumpAndSettle();
    expect(find.text('1 RESULT'), findsOneWidget);
    expect(find.text('Shubman Gill'), findsOneWidget);
    expect(find.byKey(const ValueKey('ranking_podium_1')), findsNothing);

    await t.enterText(find.byKey(const ValueKey('rankings_search')), 'zzzz');
    await t.pumpAndSettle();
    expect(find.text('No matches for "zzzz"'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('rankings_search_clear')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ranking_podium_1')), findsOneWidget);

    // Scroll to a row far down the lazy list and tap it → detail route
    // with the initial player.
    const row = ValueKey('ranking_row_max_odowd');
    await t.scrollUntilVisible(find.byKey(row), 300, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(row));
    await t.pumpAndSettle();
    expect(find.text("detail:max_odowd:Max O'Dowd"), findsOneWidget);
  });

  testWidgets('podium tap navigates once even on double tap', (t) async {
    FakeApi(defaultHandler);
    final router = testRouter('/ranking', const RankingScreen());
    await t.pumpWidget(routerApp(router));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('segment_players')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('ranking_podium_1')));
    await t.tap(find.byKey(const ValueKey('ranking_podium_1')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('detail:shubman_gill:Shubman Gill'), findsOneWidget);
    // Exactly one detail page on the stack.
    expect(router.routerDelegate.currentConfiguration.matches.length, 2);
  });

  testWidgets('~100 rows are rendered lazily', (t) async {
    FakeApi(defaultHandler);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('segment_players')));
    await settle(t);
    final built = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('ranking_row_'));
    expect(built.evaluate().length, lessThan(30));
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('rapid toggling sends one request for the final selection', (t) async {
    final api = FakeApi(defaultHandler);
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(api.requests.length, 1);

    await t.tap(find.byKey(const ValueKey('segment_ODI')));
    await t.pump(const Duration(milliseconds: 30));
    await t.tap(find.byKey(const ValueKey('segment_T20')));
    await t.pump(const Duration(milliseconds: 30));
    await t.tap(find.byKey(const ValueKey('segment_FEMALE')));
    await t.pump(const Duration(milliseconds: 30));
    await settle(t);

    expect(api.requests.length, 2);
    expect(api.requests.last.queryParameters, {'gender': 'FEMALE', 'matchType': 'T20'});

    // Going back to a cached combination does not refetch.
    await t.tap(find.byKey(const ValueKey('segment_MALE')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('segment_TEST')));
    await settle(t);
    expect(api.requests.where((u) => u.queryParameters['matchType'] == 'TEST' && u.queryParameters['gender'] == 'MALE').length, 1);
  });

  testWidgets('out-of-order responses never show stale results', (t) async {
    final pending = <String, Completer<http.Response>>{};
    final api = FakeApi((r) {
      final f = r.url.queryParameters['matchType']!;
      if (f == 'TEST') return jsonRes(_rows(['TestTeam']));
      return (pending[f] = Completer<http.Response>()).future;
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('TestTeam'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('segment_ODI')));
    await t.pump(const Duration(milliseconds: 130)); // ODI request in flight
    await t.tap(find.byKey(const ValueKey('segment_T20')));
    await t.pump(const Duration(milliseconds: 130)); // T20 request in flight
    expect(api.requests.length, 3);

    pending['T20']!.complete(jsonRes(_rows(['T20Team'])));
    await t.pumpAndSettle();
    expect(find.text('T20Team'), findsOneWidget);

    pending['ODI']!.complete(jsonRes(_rows(['OdiTeam'])));
    await t.pumpAndSettle();
    expect(find.text('OdiTeam'), findsNothing);
    expect(find.text('T20Team'), findsOneWidget);

    // The late ODI result was still cached: selecting ODI shows it without a request.
    await t.tap(find.byKey(const ValueKey('segment_ODI')));
    await settle(t);
    expect(find.text('OdiTeam'), findsOneWidget);
    expect(api.requests.length, 3);
  });

  testWidgets('server error shows Try Again, which recovers', (t) async {
    var fail = true;
    FakeApi((r) => fail ? jsonRes({'message': 'Internal error'}, 500) : jsonRes(fixture('rank_team')));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('Internal error'), findsOneWidget);
    // Controls still usable after a failed first load.
    expect(find.byKey(const ValueKey('rankings_mode')), findsOneWidget);

    fail = false;
    await t.tap(find.byKey(const ValueKey('rankings_retry')));
    await t.pumpAndSettle();
    expect(find.text('India'), findsOneWidget);
  });

  testWidgets('network timeout / socket error shows friendly message', (t) async {
    FakeApi((r) => throw http.ClientException('boom'));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.textContaining('Unable to reach the server'), findsOneWidget);
  });

  testWidgets('empty data shows "No rankings available"', (t) async {
    FakeApi((r) => jsonRes({'message': 'ok', 'data': []}));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('No rankings available'), findsOneWidget);
  });

  testWidgets('malformed payload does not crash', (t) async {
    FakeApi((r) => jsonRes({'message': 'ok', 'data': {'weird': true}}));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('No rankings available'), findsOneWidget);
  });

  testWidgets('pull-to-refresh bypasses the cache and keeps the list', (t) async {
    final api = FakeApi(defaultHandler);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.fling(find.byKey(const ValueKey('rankings_list')), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(api.requests.length, 2);
    expect(find.text('India'), findsOneWidget);
  });

  testWidgets('refresh failure keeps data and shows a snackbar', (t) async {
    var calls = 0;
    FakeApi((r) => ++calls == 1 ? jsonRes(fixture('rank_team')) : jsonRes({'message': 'Down'}, 503));
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.fling(find.byKey(const ValueKey('rankings_list')), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(find.text('India'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
  });
}
