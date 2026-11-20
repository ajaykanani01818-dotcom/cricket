import 'dart:async';

import 'package:crickbex/features/players/players_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

Map<String, Object> _page(
  String prefix,
  int page, {
  int count = 20,
  int total = 60,
}) => {
  'message': 'ok',
  'data': [
    for (var i = 0; i < count; i++)
      {
        '_id': '$prefix-$page-$i',
        'playerKey': '$prefix-$page-$i',
        'name': 'Player $prefix $page-$i',
        'role': 0,
      },
  ],
  'pageInfo': {'page': page, 'perPage': 20, 'total': total},
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(WidgetTester t) =>
      t.pumpWidget(routerApp(testRouter('/players', const PlayersScreen())));

  Iterable<Uri> trendingCalls(FakeApi api) =>
      api.where((u) => u.path == '/players/trending');

  testWidgets('skeleton → trending strip, country chips and India players', (
    t,
  ) async {
    final gate = Completer<void>();
    final api = FakeApi((r) async {
      await gate.future;
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    expect(find.byKey(const ValueKey('players_shimmer')), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_shimmer')), findsNothing);
    expect(find.text('Trending'), findsOneWidget);
    expect(find.byKey(const ValueKey('players_trending')), findsOneWidget);
    expect(find.text('Ibrahim Zadran'), findsOneWidget);
    expect(find.byKey(const ValueKey('players_country_India')), findsOneWidget);
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    expect(find.textContaining('Batter, left-hand bat'), findsWidgets);
    expect(find.text('#5 Test'), findsOneWidget);
    expect(
      api
          .where((u) => u.path == '/players/country/India')
          .single
          .queryParameters,
      {'page': '1', 'perPage': '20'},
    );
  });

  testWidgets(
    'search is debounced: one request for the final text, server + local matches',
    (t) async {
      final api = FakeApi((r) {
        if (r.url.path == '/players/trending' &&
            r.url.queryParameters['search'] != null) {
          return jsonRes({
            'data': [
              {
                '_id': 's1',
                'key': 'virat_kohli',
                'name': 'Virat Kohli',
                'country': 'India',
              },
              {
                '_id': 's2',
                'key': 'unrelated',
                'name': 'Someone Else',
                'country': 'Nepal',
              },
            ],
          });
        }
        return discoverFixtures(r);
      });
      await pumpScreen(t);
      await t.pumpAndSettle();
      final before = trendingCalls(api).length;

      final field = find.byKey(const ValueKey('players_search'));
      await t.enterText(field, 'k');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(field, 'ko');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(field, 'kohli');
      await t.pump(const Duration(milliseconds: 100));
      expect(
        trendingCalls(api).length,
        before,
        reason: 'nothing sent while typing',
      );
      await t.pump(PlayersScreen.searchDebounce);
      await t.pumpAndSettle();

      final searches = trendingCalls(
        api,
      ).where((u) => u.queryParameters.containsKey('search')).toList();
      expect(searches.length, 1);
      expect(searches.single.queryParameters['search'], 'kohli');
      expect(find.text('1 player found'), findsOneWidget);
      expect(find.text('Virat Kohli'), findsOneWidget);
      // Rows the server sent that do not match are dropped.
      expect(find.text('Someone Else'), findsNothing);
      expect(find.text('India'), findsWidgets);

      await t.tap(find.text('Virat Kohli'));
      await t.pumpAndSettle();
      expect(find.text('detail:virat_kohli:Virat Kohli'), findsOneWidget);
    },
  );

  testWidgets('one-letter queries do not search; clear returns to browsing', (
    t,
  ) async {
    final api = FakeApi(discoverFixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('players_search')), 'y');
    await t.pump(PlayersScreen.searchDebounce);
    await t.pumpAndSettle();
    expect(api.where((u) => u.queryParameters.containsKey('search')), isEmpty);
    expect(find.byKey(const ValueKey('players_list')), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('players_search')), 'jaiswal');
    await t.pump(PlayersScreen.searchDebounce);
    await t.pumpAndSettle();
    // The server returned the unfiltered trending list; the loaded India
    // page still matches locally.
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('players_search_clear')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_list')), findsOneWidget);
  });

  testWidgets('no search result says what to do and offers browsing', (
    t,
  ) async {
    FakeApi(discoverFixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('players_search')), 'zzqx');
    await t.pump(PlayersScreen.searchDebounce);
    await t.pumpAndSettle();
    expect(find.text('No player named "zzqx"'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('empty_state_action')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_list')), findsOneWidget);
  });

  testWidgets('search failure with nothing local shows Try again', (t) async {
    var fail = true;
    FakeApi((r) {
      if (r.url.queryParameters['search'] != null) {
        return fail
            ? jsonRes({'message': 'x'}, 500)
            : jsonRes({
                'data': [
                  {'key': 'abc', 'name': 'Qwerty Abc'},
                ],
              });
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('players_search')), 'qwerty');
    await t.pump(PlayersScreen.searchDebounce);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_search_error')), findsOneWidget);
    fail = false;
    await t.tap(find.byKey(const ValueKey('empty_state_action')));
    await t.pumpAndSettle();
    expect(find.text('Qwerty Abc'), findsOneWidget);
  });

  testWidgets('infinite scroll loads each page exactly once and appends', (
    t,
  ) async {
    final api = FakeApi((r) {
      if (r.url.path.startsWith('/players/country/')) {
        return jsonRes(_page('in', int.parse(r.url.queryParameters['page']!)));
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await t.drag(
        find.byKey(const ValueKey('players_list')),
        const Offset(0, -1500),
      );
      await t.pumpAndSettle();
    }
    final pages = api
        .where((u) => u.path.startsWith('/players/country/'))
        .map((u) => u.queryParameters['page'])
        .toList();
    expect(pages, ['1', '2', '3']);
    expect(find.text('That is everyone listed for India'), findsOneWidget);
  });

  testWidgets('switching country ignores the stale previous response', (
    t,
  ) async {
    final slow = Completer<http.Response>();
    FakeApi((r) {
      if (r.url.path == '/players/countries') {
        return jsonRes({
          'data': ['India', 'Nepal'],
        });
      }
      if (r.url.path == '/players/country/India') return slow.future;
      if (r.url.path == '/players/country/Nepal') {
        return jsonRes(_page('np', 1, count: 3, total: 3));
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('players_country_Nepal')));
    await t.pumpAndSettle();
    slow.complete(jsonRes(_page('in', 1)));
    await t.pumpAndSettle();
    expect(find.text('Player np 1-0'), findsOneWidget);
    expect(find.text('Player in 1-0'), findsNothing);
  });

  testWidgets(
    'countries failure falls back to India; trending failure hides the strip',
    (t) async {
      FakeApi((r) {
        if (r.url.path == '/players/countries' ||
            r.url.path == '/players/trending') {
          return jsonRes({'message': 'x'}, 500);
        }
        return discoverFixtures(r);
      });
      await pumpScreen(t);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('players_country_India')),
        findsOneWidget,
      );
      expect(find.text('Trending'), findsNothing);
      expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    },
  );

  testWidgets('error shows Try again which recovers', (t) async {
    var fail = true;
    FakeApi((r) {
      if (r.url.path.startsWith('/players/country/') && fail) {
        return jsonRes({'message': 'x'}, 500);
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text("Players didn't load"), findsOneWidget);
    fail = false;
    await t.tap(find.byKey(const ValueKey('empty_state_action')));
    await t.pumpAndSettle();
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
  });

  testWidgets('load-more failure shows inline retry instead of looping', (
    t,
  ) async {
    var failPage2 = true;
    final api = FakeApi((r) {
      if (r.url.path.startsWith('/players/country/')) {
        final page = int.parse(r.url.queryParameters['page']!);
        if (page == 2 && failPage2) return jsonRes({'message': 'x'}, 500);
        return jsonRes(_page('in', page, total: 40));
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await t.drag(
        find.byKey(const ValueKey('players_list')),
        const Offset(0, -2000),
      );
      await t.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey('players_load_more_retry')),
      findsOneWidget,
    );
    expect(api.where((u) => u.queryParameters['page'] == '2').length, 1);
    failPage2 = false;
    await t.tap(find.byKey(const ValueKey('players_load_more_retry')));
    await t.pumpAndSettle();
    expect(find.text('Player in 2-0'), findsOneWidget);
  });

  testWidgets('empty country says what to do', (t) async {
    FakeApi((r) {
      if (r.url.path.startsWith('/players/country/')) {
        return jsonRes({'data': []});
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('No players listed for India'), findsOneWidget);
    expect(
      find.text('Pick another country above, or search by name.'),
      findsOneWidget,
    );
  });

  testWidgets('tap navigates once with the list item as initial player', (
    t,
  ) async {
    FakeApi(discoverFixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Yashasvi Jaiswal'));
    await t.tap(find.text('Yashasvi Jaiswal'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(
      find.text('detail:yashasvi_jaiswal:Yashasvi Jaiswal'),
      findsOneWidget,
    );
  });

  testWidgets('long names and malformed items do not crash at 320 px × 2.0', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    FakeApi((r) {
      if (r.url.path.startsWith('/players/country/')) {
        return jsonRes({
          'data': [
            null,
            {
              '_id': 'a',
              'playerKey': 'a',
              'name': 'Mohammad Abdullah Al-Rahman bin Khalid the Third',
              'role': 3,
              'battingStyle': 1,
              'dob': 900000000,
            },
            {'_id': 'b', 'name': ''},
            {
              '_id': 'c',
              'playerKey': 'c',
              'name': 'X',
              'iccRanking': {
                'all': {'odi': '1'},
              },
              'role': 2,
            },
          ],
        });
      }
      return discoverFixtures(r);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(
      find.text('#1 ODI'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('players_list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Unnamed player'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
