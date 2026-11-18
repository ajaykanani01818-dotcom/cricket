import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/players/player_detail_screen.dart';
import 'package:crickbex/features/players/players_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  JsonMap listItem() => J.maps(fixtureJson('players_country')['data']).first; // Yashasvi Jaiswal

  Future<void> pumpDetail(WidgetTester t, String key, {JsonMap? initial}) =>
      t.pumpWidget(MaterialApp(home: Scaffold(body: PlayerDetailScreen(playerKey: key, initialPlayer: initial))));

  testWidgets('no initial player: full shimmer → profile sections', (t) async {
    final pending = Completer<http.Response>();
    final api = FakeApi((r) => pending.future);
    await pumpDetail(t, 'aiden_markram');
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsOneWidget);
    expect(api.requests.single.path, '/players/aiden_markram/info');

    pending.complete(jsonRes(fixture('player_info')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsNothing);
    expect(find.text('Aiden Markram'), findsOneWidget);
    expect(find.text('South Africa  ·  Batsman'), findsOneWidget);
    expect(find.text('PERSONAL'), findsOneWidget);
    expect(find.text('Right-arm off-break'), findsOneWidget);
    final scroll = find.byType(Scrollable).last;
    await t.scrollUntilVisible(find.byKey(const ValueKey('segment_odi')), 100, scrollable: scroll);
    await t.pumpAndSettle();
    expect(find.text('#17'), findsOneWidget);

    // Format toggle on the ranking card.
    await t.tap(find.byKey(const ValueKey('segment_odi')));
    await t.pumpAndSettle();
    expect(find.text('#29'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('segment_t20')));
    await t.pumpAndSettle();
    expect(find.text('#20'), findsOneWidget);

    // Lower sections exist further down the scroll view.
    await t.scrollUntilVisible(find.text('BATTING STATS'), 400, scrollable: scroll);
    expect(find.text('3315'), findsOneWidget);
    await t.scrollUntilVisible(find.text('BOWLING STATS'), 400, scrollable: scroll);
    for (var i = 0; i < 10; i++) {
      await t.drag(find.byKey(const ValueKey('player_detail_scroll')), const Offset(0, -2000));
      await t.pumpAndSettle();
    }
    expect(find.text('Lucknow Super Giants'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.textContaining('A young prodigy'), findsOneWidget);
    expect(find.textContaining('<p>'), findsNothing);
  });

  testWidgets('initial player renders the header immediately while info loads', (t) async {
    final pending = Completer<http.Response>();
    FakeApi((r) => pending.future);
    await pumpDetail(t, 'yashasvi_jaiswal', initial: listItem());
    await t.pump();
    expect(find.byKey(const ValueKey('player_detail_name')), findsOneWidget);
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    expect(find.text('India  ·  Batsman'), findsOneWidget);
    // Personal details come from the list item; the rest is shimmering.
    expect(find.text('Left Handed'), findsOneWidget);
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsOneWidget);

    final info = fixtureJson('player_info');
    (info['data'] as Map)['name'] = 'Yashasvi Jaiswal';
    pending.complete(jsonRes(info));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsNothing);
    expect(find.text('ICC RANKINGS'), findsOneWidget);
  });

  testWidgets('404 with initial player: header + "not available yet", no spinner', (t) async {
    FakeApi((r) => jsonRes({'message': 'Player not found!!'}, 404));
    await pumpDetail(t, 'yashasvi_jaiswal', initial: listItem());
    await t.pumpAndSettle();
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    expect(find.text('PERSONAL'), findsOneWidget);
    expect(find.text('Detailed profile not available yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('player_detail_retry')), findsNothing);
  });

  testWidgets('404 with a ranking-row initial player (name only) hides empty Personal card', (t) async {
    FakeApi((r) => jsonRes({'message': 'Player not found!!'}, 404));
    await pumpDetail(t, 'max_odowd', initial: {'playerKey': 'max_odowd', 'name': "Max O'Dowd"});
    await t.pumpAndSettle();
    expect(find.text("Max O'Dowd"), findsOneWidget);
    expect(find.text('PERSONAL'), findsNothing);
    expect(find.text('Detailed profile not available yet'), findsOneWidget);
  });

  testWidgets('404 without initial player shows "Player not found"', (t) async {
    FakeApi((r) => jsonRes({'message': 'Player not found!!'}, 404));
    await pumpDetail(t, 'ghost');
    await t.pumpAndSettle();
    expect(find.text('Player not found'), findsOneWidget);
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsNothing);
  });

  testWidgets('empty data body is treated as not found', (t) async {
    FakeApi((r) => jsonRes({'message': 'ok', 'data': null}));
    await pumpDetail(t, 'ghost');
    await t.pumpAndSettle();
    expect(find.text('Player not found'), findsOneWidget);
  });

  testWidgets('server error without initial player: Retry recovers', (t) async {
    var fail = true;
    FakeApi((r) => fail ? jsonRes({'message': 'Boom'}, 500) : jsonRes(fixture('player_info')));
    await pumpDetail(t, 'aiden_markram');
    await t.pumpAndSettle();
    expect(find.text('Boom'), findsOneWidget);
    fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Aiden Markram'), findsOneWidget);
  });

  testWidgets('server error with initial player: header + Try Again recovers', (t) async {
    var fail = true;
    FakeApi((r) => fail ? throw http.ClientException('offline') : jsonRes(fixture('player_info')));
    await pumpDetail(t, 'aiden_markram', initial: {'playerKey': 'aiden_markram', 'name': 'Aiden Markram'});
    await t.pumpAndSettle();
    expect(find.text('Aiden Markram'), findsOneWidget);
    expect(find.textContaining('Unable to reach the server'), findsOneWidget);
    fail = false;
    await t.tap(find.byKey(const ValueKey('player_detail_retry')));
    await t.pumpAndSettle();
    expect(find.text('ICC RANKINGS'), findsOneWidget);
  });

  testWidgets('malformed info payload degrades without crashing', (t) async {
    FakeApi((r) => jsonRes({
          'data': {
            'name': 'Odd Player',
            'role': 'nope',
            'dob': 'x',
            'iccRanking': {'batting': null},
            'battingStats': [
              {'name': 'TEST', 'stats': null}
            ],
            'bowlingStats': 'bad',
            'teams': [null],
            'description': '<p></p>',
          }
        }));
    await pumpDetail(t, 'odd');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Odd Player'), findsOneWidget);
    expect(find.text('Player'), findsWidgets);
    expect(find.text('–'), findsWidgets);
    expect(find.text('ABOUT'), findsNothing);
  });

  testWidgets('scrolling fades the parallax hero', (t) async {
    FakeApi((r) => jsonRes(fixture('player_info')));
    await pumpDetail(t, 'aiden_markram');
    await t.pumpAndSettle();
    Opacity heroOpacity() => t.widget<Opacity>(
        find.ancestor(of: find.byKey(const ValueKey('player_detail_name')), matching: find.byType(Opacity)).first);
    expect(heroOpacity().opacity, 1.0);
    await t.drag(find.byKey(const ValueKey('player_detail_scroll')), const Offset(0, -140));
    await t.pump();
    expect(heroOpacity().opacity, lessThan(1.0));
  });

  testWidgets('end to end: Players list → detail with initial player → back', (t) async {
    FakeApi((r) {
      if (r.url.path == '/players/countries') return jsonRes({'data': ['India']});
      if (r.url.path.endsWith('/info')) return jsonRes({'message': 'Player not found!!'}, 404);
      return jsonRes(fixture('players_country'));
    });
    final router = testRouter(
      '/players',
      const PlayersScreen(),
      detail: (key, extra) => PlayerDetailScreen(playerKey: key, initialPlayer: extra),
    );
    await t.pumpWidget(routerApp(router));
    await t.pumpAndSettle();
    await t.tap(find.text('Yashasvi Jaiswal'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_name')), findsOneWidget);
    expect(find.text('Detailed profile not available yet'), findsOneWidget);

    // Popping disposes the detail screen (recordDetailExit) without errors.
    router.pop();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_name')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
