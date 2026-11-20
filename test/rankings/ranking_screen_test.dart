import 'dart:async';

import 'package:crickbex/features/rankings/ranking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../players/test_helpers.dart';

/// Waits past the switch delay and lets responses land.
Future<void> settle(WidgetTester t) async {
  await t.pump(RankingScreen.switchDelay + const Duration(milliseconds: 10));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(WidgetTester t, {Size? size}) async {
    if (size != null) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }
    await t.pumpWidget(
      routerApp(testRouter('/ranking', const RankingScreen())),
    );
  }

  testWidgets(
    'skeleton, then team leaders + table from /rank with gender and matchType',
    (t) async {
      final completer = Completer<http.Response>();
      final api = FakeApi((r) => completer.future);
      await pumpScreen(t);
      expect(find.byKey(const ValueKey('rankings_shimmer')), findsOneWidget);
      expect(api.requests.single.path, '/rank');
      expect(api.requests.single.queryParameters, {
        'gender': 'MALE',
        'matchType': 'TEST',
      });

      completer.complete(jsonRes(fixture('rank_team')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('rankings_shimmer')), findsNothing);
      expect(find.text("Men's Test team rankings"), findsOneWidget);
      expect(find.text('20 teams ranked by the ICC'), findsOneWidget);
      // Leader row: rating and points from the payload (rating 116, 3841 points).
      expect(find.byKey(const ValueKey('ranking_top_1')), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
      expect(find.text('Rating 116, 3841 points'), findsOneWidget);
      expect(find.text('Ranks 4 to 20'), findsOneWidget);
      expect(find.text('Points'), findsOneWidget);
      // Search is for player lists only.
      expect(find.byKey(const ValueKey('rankings_search')), findsNothing);
    },
  );

  testWidgets(
    'top-3 layout: the leader row is taller and its numeral larger than rows 2–3',
    (t) async {
      FakeApi(discoverFixtures);
      await pumpScreen(t);
      await t.pumpAndSettle();
      final r1 = t.getSize(find.byKey(const ValueKey('ranking_top_1')));
      final r2 = t.getSize(find.byKey(const ValueKey('ranking_top_2')));
      final r3 = t.getSize(find.byKey(const ValueKey('ranking_top_3')));
      expect(r1.height, greaterThan(r2.height));
      expect(r2.height, r3.height);
      double numeral(String rank, String key) => t
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.text(rank),
                )
                .first,
          )
          .style!
          .fontSize!;
      expect(
        numeral('1', 'ranking_top_1'),
        greaterThan(numeral('2', 'ranking_top_2')),
      );
      // Rank 4 onwards are dense table rows, not leader rows.
      expect(find.byKey(const ValueKey('ranking_top_4')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              '${(w.key as ValueKey).value}'.startsWith('ranking_row_4-'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'control switching sends the right params for every combination',
    (t) async {
      final api = FakeApi(discoverFixtures);
      await pumpScreen(t);
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('segment_ODI')));
      await settle(t);
      expect(api.requests.last.queryParameters, {
        'gender': 'MALE',
        'matchType': 'ODI',
      });

      await t.tap(find.byKey(const ValueKey('segment_FEMALE')));
      await settle(t);
      expect(api.requests.last.path, '/rank');
      expect(api.requests.last.queryParameters, {
        'gender': 'FEMALE',
        'matchType': 'ODI',
      });
      expect(find.text("Women's ODI team rankings"), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('tab_batting')));
      await settle(t);
      expect(api.requests.last.path, '/rank/player');
      expect(api.requests.last.queryParameters, {
        'gender': 'FEMALE',
        'matchType': 'ODI',
        'type': 'BATSMAN',
      });

      await t.tap(find.byKey(const ValueKey('tab_bowling')));
      await settle(t);
      expect(api.requests.last.queryParameters['type'], 'BOWLER');

      await t.ensureVisible(find.byKey(const ValueKey('tab_allRounders')));
      await t.tap(find.byKey(const ValueKey('tab_allRounders')));
      await settle(t);
      expect(api.requests.last.queryParameters, {
        'gender': 'FEMALE',
        'matchType': 'ODI',
        'type': 'ALL_ROUNDER',
      });

      await t.tap(find.byKey(const ValueKey('segment_T20')));
      await settle(t);
      expect(api.requests.last.queryParameters, {
        'gender': 'FEMALE',
        'matchType': 'T20',
        'type': 'ALL_ROUNDER',
      });
      expect(find.text("Women's T20 all-rounder rankings"), findsOneWidget);

      // Every request carried gender + matchType.
      for (final u in api.requests) {
        expect(u.queryParameters.keys, containsAll(['gender', 'matchType']));
      }

      // Going back to a cached selection does not refetch.
      final before = api.requests.length;
      await t.tap(find.byKey(const ValueKey('segment_ODI')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('segment_T20')));
      await settle(t);
      expect(api.requests.length, before); // both selections are cached
    },
  );

  testWidgets(
    'players: search filters (rank 1 included), tap opens the profile with the row as initial player',
    (t) async {
      FakeApi(discoverFixtures);
      await pumpScreen(t);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('tab_batting')));
      await settle(t);
      expect(find.text('Shubman Gill'), findsOneWidget);
      expect(find.text('Ranks 4 to 100'), findsOneWidget);
      expect(find.text('Points'), findsNothing);

      await t.enterText(find.byKey(const ValueKey('rankings_search')), 'gill');
      await t.pumpAndSettle();
      expect(find.text('Shubman Gill'), findsOneWidget);
      expect(find.byKey(const ValueKey('ranking_leaders')), findsNothing);
      expect(find.textContaining('result'), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('rankings_search')), 'zzzz');
      await t.pumpAndSettle();
      expect(find.text('No player named "zzzz" in this list'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('empty_state_action')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ranking_leaders')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('ranking_top_1')));
      await t.tap(
        find.byKey(const ValueKey('ranking_top_1')),
        warnIfMissed: false,
      );
      await t.pumpAndSettle();
      expect(find.text('detail:shubman_gill:Shubman Gill'), findsOneWidget);
    },
  );

  testWidgets('team rows are not tappable', (t) async {
    FakeApi(discoverFixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ranking_top_1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('stub_detail')), findsNothing);
  });

  testWidgets('rapid toggling sends one request for the final selection', (
    t,
  ) async {
    final api = FakeApi(discoverFixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    final start = api.requests.length;
    await t.tap(find.byKey(const ValueKey('segment_ODI')));
    await t.pump(const Duration(milliseconds: 30));
    await t.tap(find.byKey(const ValueKey('segment_T20')));
    await t.pump(const Duration(milliseconds: 30));
    await t.tap(find.byKey(const ValueKey('segment_FEMALE')));
    await settle(t);
    expect(api.requests.length, start + 1);
    expect(api.requests.last.queryParameters, {
      'gender': 'FEMALE',
      'matchType': 'T20',
    });
  });

  testWidgets('out-of-order responses never show stale results', (t) async {
    final slow = Completer<http.Response>();
    FakeApi((r) {
      if (r.url.queryParameters['matchType'] == 'ODI') return slow.future;
      if (r.url.queryParameters['matchType'] == 'T20') {
        return jsonRes({
          'data': [
            {'name': 'T20 Kings', 'order': 1, 'rating': 270, 'points': 9000},
          ],
        });
      }
      return jsonRes(fixture('rank_team'));
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('segment_ODI')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('segment_T20')));
    await settle(t);
    slow.complete(
      jsonRes({
        'data': [
          {'name': 'Stale ODI', 'order': 1, 'rating': 1},
        ],
      }),
    );
    await t.pumpAndSettle();
    expect(find.text('T20 Kings'), findsOneWidget);
    expect(find.text('Stale ODI'), findsNothing);
  });

  testWidgets('server error says what failed; Try again recovers', (t) async {
    var fail = true;
    FakeApi(
      (r) => fail
          ? jsonRes({'message': 'boom'}, 500)
          : jsonRes(fixture('rank_team')),
    );
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('rankings_error')), findsOneWidget);
    expect(find.text("Rankings didn't load"), findsOneWidget);
    fail = false;
    await t.tap(find.byKey(const ValueKey('empty_state_action')));
    await t.pumpAndSettle();
    expect(find.text('India'), findsOneWidget);
  });

  testWidgets('empty data explains and points to the controls', (t) async {
    FakeApi((r) => jsonRes({'message': 'ok', 'data': []}));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text("No Men's Test team rankings published"), findsOneWidget);
    expect(find.textContaining('Pick another format'), findsOneWidget);
  });

  testWidgets(
    'malformed payload: no crash, no fake zeros, missing rating shows a dash',
    (t) async {
      FakeApi(
        (r) => jsonRes({
          'data': [
            null,
            'x',
            {'name': 'Alpha', 'order': '1', 'rating': '', 'points': null},
            {'name': 'Beta', 'order': 2, 'rating': 100},
            {'order': 3},
            {'name': 'Gamma', 'rating': 'NaN?'},
            {'name': 'Delta', 'order': 5, 'rating': 90, 'points': 1800},
            {
              'name': 'Epsilon',
              'order': 6,
              'rating': {'x': 1},
            },
          ],
        }),
      );
      await pumpScreen(t);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('–'), findsWidgets);
    },
  );

  testWidgets('lists of 100 render lazily', (t) async {
    FakeApi(discoverFixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab_batting')));
    await settle(t);
    expect(
      find.byKey(const ValueKey('ranking_row_virat_kohli')),
      findsNothing,
    ); // rank 3 → leader
    expect(find.byKey(const ValueKey('ranking_top_3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ranking_row_vikramjit_singh')),
      findsNothing,
    ); // rank 101 is cut
  });

  testWidgets('refresh failure keeps data and shows a snackbar', (t) async {
    var fail = false;
    FakeApi(
      (r) =>
          fail ? jsonRes({'message': 'x'}, 500) : jsonRes(fixture('rank_team')),
    );
    await t.pumpWidget(
      routerApp(testRouter('/ranking', const RankingScreen())),
    );
    await t.pumpAndSettle();
    fail = true;
    await t.fling(
      find.byKey(const ValueKey('rankings_list')),
      const Offset(0, 500),
      1000,
    );
    await t.pumpAndSettle();
    expect(find.text('India'), findsOneWidget);
    expect(find.textContaining("Rankings didn't refresh"), findsOneWidget);
  });

  testWidgets('controls fit at 320 px with large text', (t) async {
    FakeApi(discoverFixtures);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(t, size: const Size(320, 640));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // Format and gender are stacked (not side by side) at this width.
    final f = t.getRect(find.byKey(const ValueKey('rankings_format')));
    final g = t.getRect(find.byKey(const ValueKey('rankings_gender')));
    expect(g.top, greaterThanOrEqualTo(f.bottom));
  });
}
