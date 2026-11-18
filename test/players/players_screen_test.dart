import 'dart:async';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/players/players_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// A page of [n] players for [country] with ids prefixed by page number.
Map<String, Object> page(String country, int pageNum, {int n = 20, int total = 5370}) => {
      'message': 'ok',
      'data': [
        for (var i = 0; i < n; i++)
          {
            '_id': '$country-$pageNum-$i',
            'playerKey': '${country.toLowerCase()}_${pageNum}_$i',
            'name': '$country P$pageNum-$i',
            'country': country,
            'role': 0,
            'battingStyle': 0,
          }
      ],
      'pageInfo': {'page': pageNum, 'perPage': 20, 'total': total},
    };

bool isCountries(Uri u) => u.path == '/players/countries';
bool isCountry(Uri u, String c) => u.path == '/players/country/$c';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(WidgetTester t) async {
    await t.pumpWidget(routerApp(testRouter('/players', const PlayersScreen())));
  }

  http.Response fixtures(http.Request r) {
    if (isCountries(r.url)) return jsonRes(fixture('players_countries'));
    final p = int.parse(r.url.queryParameters['page'] ?? '1');
    if (p == 1 && isCountry(r.url, 'India')) return jsonRes(fixture('players_country'));
    return jsonRes(page(r.url.pathSegments.last, p));
  }

  testWidgets('shimmer → country tabs + India players (fixture)', (t) async {
    final pending = Completer<http.Response>();
    final api = FakeApi((r) => isCountries(r.url) ? jsonRes(fixture('players_countries')) : pending.future);
    await pumpScreen(t);
    expect(find.byKey(const ValueKey('players_shimmer')), findsOneWidget);
    await t.pump();
    expect(api.where((u) => isCountry(u, 'India')).single.queryParameters, {'page': '1', 'perPage': '20'});

    pending.complete(jsonRes(fixture('players_country')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_shimmer')), findsNothing);
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
    expect(find.text('Batsman · Left Handed'), findsWidgets);
    expect(find.byKey(const ValueKey('players_country_India')), findsOneWidget);
    expect(find.byKey(const ValueKey('players_country_Afghanistan')), findsOneWidget);
  });

  testWidgets('infinite scroll loads each page exactly once and appends', (t) async {
    final gate = <int, Completer<void>>{};
    final api = FakeApi((r) async {
      if (isCountries(r.url)) return jsonRes(fixture('players_countries'));
      final p = int.parse(r.url.queryParameters['page']!);
      if (p > 1) await (gate[p] = Completer<void>()).future;
      return jsonRes(page('India', p, total: 45));
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('India P1-0'), findsOneWidget);

    // Many scroll events near the end while page 2 is in flight.
    final list = find.byKey(const ValueKey('players_list'));
    for (var i = 0; i < 6; i++) {
      await t.drag(list, const Offset(0, -800));
      await t.pump();
    }
    expect(api.where((u) => u.queryParameters['page'] == '2').length, 1);
    expect(find.byKey(const ValueKey('players_loading_more')), findsOneWidget);

    gate[2]!.complete();
    await t.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await t.drag(list, const Offset(0, -800));
      await t.pump();
    }
    expect(api.where((u) => u.queryParameters['page'] == '3').length, 1);
    gate[3]!.complete();
    await t.pumpAndSettle();
    await t.drag(list, const Offset(0, -3000));
    await t.pumpAndSettle();
    // total 45 → 3 pages; no page 4 and the end marker is shown.
    expect(api.where((u) => u.queryParameters['page'] == '4'), isEmpty);
    expect(find.text('No more players'), findsOneWidget);
    expect(find.text('India P3-19'), findsOneWidget);
  });

  testWidgets('duplicate rows across pages are dropped', (t) async {
    FakeApi((r) {
      if (isCountries(r.url)) return jsonRes({'data': ['India']});
      final p = int.parse(r.url.queryParameters['page']!);
      // page 2 repeats page 1 entirely.
      final body = page('India', 1, n: 20, total: 40);
      (body['pageInfo'] as JsonMap)['page'] = p;
      return jsonRes(body);
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.drag(find.byKey(const ValueKey('players_list')), const Offset(0, -5000));
    await t.pumpAndSettle();
    await t.drag(find.byKey(const ValueKey('players_list')), const Offset(0, -5000));
    await t.pumpAndSettle();
    expect(find.text('No more players'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('short page without pageInfo has no more pages', (t) async {
    final api = FakeApi((r) => isCountries(r.url)
        ? jsonRes({'data': ['India']})
        : jsonRes({'data': (page('India', 1, n: 3)['data'])}));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('No more players'), findsOneWidget);
    expect(api.where((u) => u.queryParameters['page'] == '2'), isEmpty);
  });

  testWidgets('switching country fetches it and ignores the stale previous response', (t) async {
    final indiaGate = Completer<void>();
    var indiaCalls = 0;
    final api = FakeApi((r) async {
      if (isCountries(r.url)) return jsonRes(fixture('players_countries'));
      if (isCountry(r.url, 'India')) {
        indiaCalls++;
        await indiaGate.future;
        return jsonRes(page('India', 1));
      }
      return jsonRes(page(r.url.pathSegments.last, 1));
    });
    await pumpScreen(t);
    await t.pump();
    await t.pump();
    expect(indiaCalls, 1);

    // Tabs auto-scroll to the selected country; bring Afghanistan back.
    await t.pump(const Duration(milliseconds: 400));
    await t.ensureVisible(find.byKey(const ValueKey('players_country_Afghanistan')));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const ValueKey('players_country_Afghanistan')));
    await t.pump(const Duration(milliseconds: 130));
    await t.pumpAndSettle();
    expect(api.where((u) => isCountry(u, 'Afghanistan')).length, 1);
    expect(find.text('Afghanistan P1-0'), findsOneWidget);

    indiaGate.complete();
    await t.pumpAndSettle();
    expect(find.text('India P1-0'), findsNothing);
    expect(find.text('Afghanistan P1-0'), findsOneWidget);
  });

  testWidgets('falls back to the first country when India is missing', (t) async {
    final api = FakeApi((r) {
      if (isCountries(r.url)) return jsonRes({'data': ['Zimbabwe', 'Australia']});
      return jsonRes(page(r.url.pathSegments.last, 1));
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(api.where((u) => isCountry(u, 'Australia')).length, 1);
    expect(find.text('Australia P1-0'), findsOneWidget);
    expect(find.text('India P1-0'), findsNothing);
  });

  testWidgets('countries failure falls back to India', (t) async {
    FakeApi((r) => isCountries(r.url) ? jsonRes({'message': 'x'}, 500) : jsonRes(page('India', 1)));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_country_India')), findsOneWidget);
    expect(find.text('India P1-0'), findsOneWidget);
  });

  testWidgets('error shows Try Again which recovers', (t) async {
    var fail = true;
    FakeApi((r) {
      if (isCountries(r.url)) return jsonRes(fixture('players_countries'));
      return fail ? jsonRes({'message': 'Players unavailable'}, 500) : jsonRes(fixture('players_country'));
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.text('Players unavailable'), findsOneWidget);
    fail = false;
    await t.tap(find.byKey(const ValueKey('players_retry')));
    await t.pumpAndSettle();
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
  });

  testWidgets('load-more failure shows inline retry instead of looping', (t) async {
    var failPage2 = true;
    final api = FakeApi((r) {
      if (isCountries(r.url)) return jsonRes({'data': ['India']});
      final p = int.parse(r.url.queryParameters['page']!);
      if (p == 2 && failPage2) return jsonRes({'message': 'x'}, 500);
      return jsonRes(page('India', p, total: 40));
    });
    await pumpScreen(t);
    await t.pumpAndSettle();
    final list = find.byKey(const ValueKey('players_list'));
    await t.drag(list, const Offset(0, -5000));
    await t.pumpAndSettle();
    await t.drag(list, const Offset(0, -500));
    await t.pumpAndSettle();
    expect(api.where((u) => u.queryParameters['page'] == '2').length, 1);
    expect(find.byKey(const ValueKey('players_load_more_retry')), findsOneWidget);
    expect(find.text('India P1-0'), findsNothing); // scrolled away, but list kept
    failPage2 = false;
    await t.tap(find.byKey(const ValueKey('players_load_more_retry')));
    await t.pumpAndSettle();
    expect(api.where((u) => u.queryParameters['page'] == '2').length, 2);
    await t.drag(list, const Offset(0, -5000));
    await t.pumpAndSettle();
    expect(find.text('India P2-19'), findsOneWidget);
  });

  testWidgets('empty country shows "No players in this country"', (t) async {
    FakeApi((r) => isCountries(r.url) ? jsonRes({'data': ['India']}) : jsonRes({'data': [], 'pageInfo': {'page': 1, 'perPage': 20, 'total': 0}}));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_empty')), findsOneWidget);
  });

  testWidgets('tap navigates with the list item as initial player (once)', (t) async {
    FakeApi(fixtures);
    final router = testRouter('/players', const PlayersScreen());
    await t.pumpWidget(routerApp(router));
    await t.pumpAndSettle();
    await t.tap(find.text('Yashasvi Jaiswal'));
    await t.tap(find.text('Yashasvi Jaiswal'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('detail:yashasvi_jaiswal:Yashasvi Jaiswal'), findsOneWidget);
    // Root + exactly one detail route.
    expect(router.routerDelegate.currentConfiguration.matches.last.matchedLocation, '/players/player/yashasvi_jaiswal');
    expect(router.routerDelegate.currentConfiguration.matches.length, 2);
  });

  testWidgets('pull-to-refresh refetches countries and page 1', (t) async {
    final api = FakeApi(fixtures);
    await pumpScreen(t);
    await t.pumpAndSettle();
    await t.fling(find.byKey(const ValueKey('players_list')), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(api.where(isCountries).length, 2);
    expect(api.where((u) => isCountry(u, 'India') && u.queryParameters['page'] == '1').length, 2);
    expect(find.text('Yashasvi Jaiswal'), findsOneWidget);
  });

  testWidgets('long names and malformed items do not crash', (t) async {
    FakeApi((r) => isCountries(r.url)
        ? jsonRes({'data': ['India', 42, null]})
        : jsonRes({
            'data': [
              {'_id': 'a', 'playerKey': 'a', 'name': 'A' * 200, 'role': 'x', 'dob': 'bad', 'logo': 'not a url'},
              null,
              {'name': 'no id'},
            ],
          }));
    await pumpScreen(t);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('A' * 200), findsOneWidget);
  });
}
