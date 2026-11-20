import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/features/players/player_detail_screen.dart';
import 'package:crickbex/features/players/players_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  JsonMap listItem() =>
      J.maps(fixtureJson('players_country')['data']).first; // Yashasvi Jaiswal

  Future<void> pumpDetail(
    WidgetTester t,
    String key, {
    JsonMap? initial,
    Size? size,
    double text = 1,
  }) async {
    if (size != null) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }
    await t.pumpWidget(const SizedBox());
    if (text != 1) {
      t.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await t.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PlayerDetailScreen(playerKey: key, initialPlayer: initial),
        ),
      ),
    );
  }

  Finder scroll() => find
      .descendant(
        of: find.byKey(const ValueKey('player_detail_scroll')),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets(
    'no initial player: skeleton → header facts, ranks, career tables, debuts, teams, bio',
    (t) async {
      final pending = Completer<http.Response>();
      final api = FakeApi((r) => pending.future);
      await pumpDetail(t, 'aiden_markram');
      expect(
        find.byKey(const ValueKey('player_detail_shimmer')),
        findsOneWidget,
      );
      expect(api.requests.single.path, '/players/aiden_markram/info');

      pending.complete(jsonRes(fixture('player_info')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('player_detail_shimmer')), findsNothing);
      expect(find.text('Aiden Markram'), findsOneWidget);
      expect(find.text('South Africa'), findsOneWidget);
      expect(find.text('Batter'), findsOneWidget);
      expect(find.text('Right-hand bat'), findsOneWidget);
      expect(find.text('Right-arm off-break'), findsOneWidget);
      // Unranked bowling / all-rounder rows are left out of the ranks table.
      expect(find.byKey(const ValueKey('player_ranks_table')), findsOneWidget);
      expect(find.text('#17'), findsOneWidget);
      expect(find.text('#29'), findsOneWidget);
      expect(find.text('All-rounder'), findsNothing);

      await t.scrollUntilVisible(
        find.byKey(const ValueKey('player_batting_table')),
        200,
        scrollable: scroll(),
      );
      expect(find.text('Batting career'), findsOneWidget);
      expect(find.text('3315'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('player_bowling_table')),
        200,
        scrollable: scroll(),
      );
      await t.scrollUntilVisible(
        find.text('Lucknow Super Giants'),
        300,
        scrollable: scroll(),
      );
      expect(find.text('Debuts'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('player_bio')),
        300,
        scrollable: scroll(),
      );
      expect(find.textContaining('<p>'), findsNothing);
      // No follow / favourite (PRD §12).
      expect(find.textContaining('Follow'), findsNothing);
      expect(find.byIcon(Icons.star_border), findsNothing);
    },
  );

  testWidgets('bio collapses to 4 lines and expands', (t) async {
    FakeApi((r) => jsonRes(fixture('player_info')));
    await pumpDetail(t, 'aiden_markram');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('player_bio_toggle')),
      300,
      scrollable: scroll(),
    );
    await t.drag(scroll(), const Offset(0, -200));
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(const ValueKey('player_bio'))).maxLines,
      4,
    );
    await t.tap(find.byKey(const ValueKey('player_bio_toggle')));
    await t.pump();
    expect(
      t.widget<Text>(find.byKey(const ValueKey('player_bio'))).maxLines,
      isNull,
    );
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets(
    'career tables at 320 px: format column fixed, stats scroll sideways, no overflow (text 1.0 and 2.0)',
    (t) async {
      for (final text in [1.0, 2.0]) {
        FakeApi((r) => jsonRes(fixture('player_info')));
        await pumpDetail(
          t,
          'aiden_markram',
          size: const Size(320, 640),
          text: text,
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('player_batting_table')),
          200,
          scrollable: scroll(),
        );
        await t.pumpAndSettle();
        final table = find.byKey(const ValueKey('player_batting_table'));
        final h = find.descendant(
          of: table,
          matching: find.byKey(const ValueKey('player_batting_scroll')),
        );
        final sc = t.widget<SingleChildScrollView>(h);
        expect(sc.scrollDirection, Axis.horizontal);
        final state = t.state<ScrollableState>(
          find.descendant(of: h, matching: find.byType(Scrollable)),
        );
        expect(
          state.position.maxScrollExtent,
          greaterThan(0),
          reason: 'columns do not fit in 320 px',
        );
        final testRect = t.getRect(
          find.descendant(of: table, matching: find.text('Test')),
        );
        await t.drag(h, const Offset(-400, 0));
        await t.pumpAndSettle();
        expect(state.position.pixels, greaterThan(0));
        expect(
          t.getRect(find.descendant(of: table, matching: find.text('Test'))),
          testRect,
          reason: 'format column stays put',
        );
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets('wide screens: the table stretches instead of scrolling', (
    t,
  ) async {
    FakeApi((r) => jsonRes(fixture('player_info')));
    await pumpDetail(t, 'aiden_markram', size: const Size(1440, 900));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('player_batting_table')),
      200,
      scrollable: scroll(),
    );
    final h = find.byKey(const ValueKey('player_batting_scroll'));
    final state = t.state<ScrollableState>(
      find.descendant(of: h, matching: find.byType(Scrollable)),
    );
    expect(state.position.maxScrollExtent, lessThan(1));
    // Content is capped at 720 px.
    expect(
      t.getSize(find.byKey(const ValueKey('player_batting_table'))).width,
      lessThanOrEqualTo(720),
    );
  });

  testWidgets('initial player renders the header while info loads', (t) async {
    final pending = Completer<http.Response>();
    FakeApi((r) => pending.future);
    await pumpDetail(t, 'yashasvi_jaiswal', initial: listItem());
    await t.pump();
    expect(find.byKey(const ValueKey('player_detail_name')), findsOneWidget);
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    expect(find.text('Left-hand bat'), findsOneWidget);
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsOneWidget);

    final info = fixtureJson('player_info');
    (info['data'] as Map)['name'] = 'Yashasvi Jaiswal';
    pending.complete(jsonRes(info));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_shimmer')), findsNothing);
    expect(find.text('ICC rankings'), findsOneWidget);
  });

  testWidgets('404 with an initial player: header + "not available yet"', (
    t,
  ) async {
    FakeApi((r) => jsonRes({'message': 'Player not found!!'}, 404));
    await pumpDetail(t, 'yashasvi_jaiswal', initial: listItem());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_name')), findsOneWidget);
    expect(find.text('Career stats not available yet'), findsOneWidget);
  });

  testWidgets('404 with a ranking row (name only) shows no empty facts', (
    t,
  ) async {
    FakeApi((r) => jsonRes({'message': 'Player not found!!'}, 404));
    await pumpDetail(t, 'x', initial: {'playerKey': 'x', 'name': 'Only Name'});
    await t.pumpAndSettle();
    expect(find.text('Only Name'), findsOneWidget);
    expect(find.text('Role'), findsNothing);
    expect(find.text('Born'), findsNothing);
  });

  testWidgets('404 without initial player / empty body: not found page', (
    t,
  ) async {
    FakeApi((r) => jsonRes({'message': 'ok', 'data': {}}));
    await pumpDetail(t, 'ghost');
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player_detail_not_found')),
      findsOneWidget,
    );
    expect(find.text('No profile for this player yet'), findsOneWidget);
  });

  testWidgets(
    'server error: Try again recovers (with and without initial player)',
    (t) async {
      for (final initial in [null, listItem()]) {
        var fail = true;
        FakeApi(
          (r) => fail
              ? jsonRes({'message': 'x'}, 500)
              : jsonRes(fixture('player_info')),
        );
        await pumpDetail(t, 'aiden_markram', initial: initial);
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('player_detail_error')),
          findsOneWidget,
        );
        fail = false;
        await t.tap(find.byKey(const ValueKey('empty_state_action')));
        await t.pumpAndSettle();
        expect(find.text('ICC rankings'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'malformed info payload degrades without crashing or fake zeros',
    (t) async {
      FakeApi(
        (r) => jsonRes({
          'data': {
            'name': 'Odd Player',
            'role': 'x',
            'dob': 0,
            'iccRanking': {
              'batting': {'test': ''},
            },
            'battingStats': [
              null,
              {
                'name': 'ODI',
                'stats': {'runs': null, 'innings': 0},
              },
            ],
            'bowlingStats': 'nope',
            'teams': 'nope',
            'debuts': [{}],
            'description': null,
          },
        }),
      );
      await pumpDetail(t, 'odd');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Odd Player'), findsOneWidget);
      expect(find.text('Role'), findsNothing);
      expect(find.text('ICC rankings'), findsNothing);
      expect(find.text('Bowling career'), findsNothing);
      expect(find.text('About'), findsNothing);
      expect(find.text('0'), findsWidgets); // innings 0 is real data
      expect(find.text('–'), findsWidgets);
    },
  );

  testWidgets('end to end: Players list → profile with initial player → back', (
    t,
  ) async {
    FakeApi((r) {
      if (r.url.path.endsWith('/info')) {
        return jsonRes({'message': 'Player not found!!'}, 404);
      }
      return discoverFixtures(r);
    });
    final router = testRouter(
      '/players',
      const PlayersScreen(),
      detail: (key, extra) =>
          PlayerDetailScreen(playerKey: key, initialPlayer: extra),
    );
    await t.pumpWidget(routerApp(router));
    await t.pumpAndSettle();
    await t.tap(find.text('Yashasvi Jaiswal'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_name')), findsOneWidget);
    expect(find.byKey(const ValueKey('screen_title_back')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('screen_title_back')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('player_detail_name')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
