import 'dart:async';

import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/widgets/shimmer_box.dart';
import 'package:crickbex/features/discover/discover_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../players/test_helpers.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/discover',
  routes: [
    GoRoute(
      path: '/discover',
      builder: (_, _) => const Scaffold(body: DiscoverScreen()),
      routes: [
        for (final s in ['series', 'rankings', 'players'])
          GoRoute(
            path: s,
            builder: (_, _) => Scaffold(body: Text('page:$s')),
          ),
        GoRoute(
          path: 'player/:k',
          builder: (_, st) =>
              Scaffold(body: Text('player:${st.pathParameters['k']}')),
        ),
        GoRoute(
          path: 'series-detail/:id',
          builder: (_, st) => Scaffold(
            body: Text('series:${st.pathParameters['id']}:${st.extra}'),
          ),
        ),
      ],
    ),
  ],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<GoRouter> pumpHub(
    WidgetTester t, {
    Brightness brightness = Brightness.light,
  }) async {
    final r = _router();
    await t.pumpWidget(
      MaterialApp.router(
        theme: buildAppTheme(brightness: brightness),
        routerConfig: r,
      ),
    );
    return r;
  }

  testWidgets(
    'previews: loading skeletons, then series count, #1 per format and trending players',
    (t) async {
      final gate = Completer<void>();
      final api = FakeApi((r) async {
        await gate.future;
        return discoverFixtures(r);
      });
      await pumpHub(t);
      await t.pump();
      // The three entries are usable while previews load.
      for (final s in ['series', 'rankings', 'players']) {
        expect(find.byKey(ValueKey('discover_$s')), findsOneWidget);
      }
      expect(find.byType(ShimmerGroup), findsWidgets);
      expect(
        find.byKey(const ValueKey('discover_series_preview')),
        findsNothing,
      );

      gate.complete();
      await t.pumpAndSettle();
      expect(find.text('470 series in progress'), findsOneWidget);
      expect(find.text('Mens Cricket World Cup 2027'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover_rankings_preview')),
        findsOneWidget,
      );
      for (final f in ['Test', 'ODI', 'T20']) {
        expect(find.text(f), findsOneWidget);
      }
      expect(
        find.text('India'),
        findsNWidgets(3),
      ); // fixture is the same for each format
      expect(find.text('116'), findsNWidgets(3));
      expect(find.text('Trending now'), findsOneWidget);
      expect(find.text('Ibrahim Zadran'), findsOneWidget);

      // Every team-ranking call carried gender + matchType.
      final rank = api.where((u) => u.path == '/rank');
      expect(rank.map((u) => u.queryParameters['matchType']).toSet(), {
        'TEST',
        'ODI',
        'T20',
      });
      expect(rank.every((u) => u.queryParameters['gender'] == 'MALE'), isTrue);
      expect(
        api.where((u) => u.path == '/series').single.queryParameters['status'],
        'ONGOING',
      );
    },
  );

  testWidgets('previews are cached: reopening the hub sends no new requests', (
    t,
  ) async {
    final api = FakeApi(discoverFixtures);
    await pumpHub(t);
    await t.pumpAndSettle();
    final n = api.requests.length;
    await t.pumpWidget(const SizedBox());
    await pumpHub(t);
    await t.pumpAndSettle();
    expect(api.requests.length, n);
    expect(find.text('470 series in progress'), findsOneWidget);
  });

  testWidgets(
    'preview errors are quiet, say what to do, and the entries still open',
    (t) async {
      FakeApi((r) => http.Response('{"message":"x"}', 500));
      final r = await pumpHub(t);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discover_series_error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discover_rankings_error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discover_players_error')),
        findsOneWidget,
      );
      expect(find.textContaining('Open Rankings to try again'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      await t.tap(find.byKey(const ValueKey('discover_rankings')));
      await t.pumpAndSettle();
      expect(r.state.uri.path, '/discover/rankings');
    },
  );

  testWidgets('one failing format still shows the others', (t) async {
    FakeApi((r) {
      if (r.url.path == '/rank' &&
          r.url.queryParameters['matchType'] == 'ODI') {
        return http.Response('{"message":"x"}', 500);
      }
      return discoverFixtures(r);
    });
    await pumpHub(t);
    await t.pumpAndSettle();
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('ODI'), findsNothing);
    expect(find.text('T20'), findsOneWidget);
  });

  testWidgets('malformed preview payloads do not crash', (t) async {
    FakeApi((r) {
      if (r.url.path == '/series') {
        return jsonRes({
          'data': [
            null,
            {'name': ''},
            {'sb_series_key': 'k'},
          ],
        });
      }
      if (r.url.path == '/rank') return jsonRes({'data': 'oops'});
      if (r.url.path == '/players/trending') {
        return jsonRes({
          'data': [
            {'name': 'No Key'},
          ],
        });
      }
      return discoverFixtures(r);
    });
    await pumpHub(t);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('discover_series_error')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discover_rankings_error')),
      findsOneWidget,
    );
  });

  testWidgets('preview items open the series, player and section pages', (
    t,
  ) async {
    FakeApi(discoverFixtures);
    final r = await pumpHub(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Mens Cricket World Cup 2027'));
    await t.pumpAndSettle();
    expect(
      find.text('series:j5C4a58:Mens Cricket World Cup 2027'),
      findsOneWidget,
    );
    r.pop();
    await t.pumpAndSettle();
    await t.tap(find.text('Ibrahim Zadran'));
    await t.pumpAndSettle();
    expect(find.text('player:ibrahim_zadran'), findsOneWidget);
    r.pop();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('discover_players')));
    await t.pumpAndSettle();
    expect(r.state.uri.path, '/discover/players');
  });
}
