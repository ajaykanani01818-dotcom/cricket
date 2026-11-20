import 'dart:convert';

import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/search/recent_searches.dart';
import 'package:crickbex/features/search/search_index.dart';
import 'package:crickbex/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_test_router.dart';
import '../common/helpers.dart';

/// Trending players, filtered by the `search` query like the server does.
http.Response _players(http.Request req) {
  final q = (req.url.queryParameters['search'] ?? '').toLowerCase();
  final all = (fixtureJson('players_trending')['data'] as List).cast<Map>();
  final hits = [
    for (final p in all)
      if (q.isEmpty || '${p['name']}'.toLowerCase().contains(q)) p,
  ];
  return http.Response.bytes(utf8.encode(body(hits)), 200);
}

Map<String, Responder> _routes() => {
  ...defaultRoutes(),
  '/match/live': FakeApi.ok(body(const [])),
  '/series': FakeApi.fixture('series_list'),
  '/players/trending': (req) => _players(req),
};

Future<GoRouter> _pump(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  api.install();
  final r = appTestRouter(initialLocation: '/home/search');
  await tester.pumpWidget(routerApp(r));
  await settle(tester);
  return r;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('search_field')), text);
  await tester.pump(SearchScreen.debounce);
  await settle(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SearchIndex.instance = SearchIndex();
  });

  group('matching', () {
    test('normalises case, accents, & and punctuation', () {
      expect(normalizeForSearch("Côte d'Ivoire & Co."), 'cote divoire and co');
    });

    test('prefix, substring and one-typo matches; all tokens required', () {
      const hay = 'australia england aus eng the ashes bellerive oval hobart';
      expect(scoreText(queryTokens('aus'), hay), greaterThan(0));
      expect(scoreText(queryTokens('ENG ashes'), hay), greaterThan(0));
      expect(
        scoreText(queryTokens('austrlia'), hay),
        greaterThan(0),
        reason: 'one typo',
      );
      expect(scoreText(queryTokens('aus india'), hay), 0);
      expect(scoreText(queryTokens('xy'), hay), 0);
      expect(
        scoreText(queryTokens('aus'), hay),
        lessThan(scoreText(queryTokens('aus eng'), hay)),
      );
    });

    test('index: team codes, venues; in-progress matches rank first', () {
      final idx = SearchIndex()
        ..addMatches(parseMatchList(fixtureJson('match_upcoming')['data']))
        ..addMatches(parseMatchList([liveMatchJson(key: 'LV')]));
      expect(idx.search('hobart').matches.single.id, 'w2bXPRS');
      expect(idx.search('ENG').matches.map((m) => m.id), contains('w2bXPRS'));
      expect(idx.search('').isEmpty, isTrue);
      final uae = idx.search('united arab emirates');
      expect(uae.matches, isNotEmpty);
    });
  });

  group('ranking and edge cases', () {
    JsonMap match(String key, String t1, String t2, {String status = 'COMPLETED', String ground = 'Dubai', String series = 'League'}) {
      final m = liveMatchJson(key: key, series: series);
      m
        ..['status'] = status
        ..['ground'] = ground;
      J.map(m['teams'])
        ..['t1'] = {'key': t1.toLowerCase(), 'name': t1, 'short_name': t1.substring(0, 2).toUpperCase(), 'score': '1/0 (1.0)'}
        ..['t2'] = {'key': t2.toLowerCase(), 'name': t2, 'short_name': t2.substring(0, 2).toUpperCase(), 'score': '2/0 (1.0)'};
      return m;
    }

    SearchIndex build() => SearchIndex()
      ..addMatches(
        parseMatchList([
          // Eight upcoming fixtures played in the Emirates...
          for (var i = 0; i < 9; i++) match('UP$i', 'Alpha$i', 'Beta$i', status: 'UPCOMING', ground: 'Sheikh Zayed, United Arab Emirates'),
          // ...and one finished match of a team called Emirates Eagles.
          match('EE1', 'Emirates Eagles', 'United Tigers', ground: 'Abu Dhabi'),
        ]),
      );

    test('a typo on a team name finds the team before venue-only matches (cap of 8 must not hide it)', () {
      final ids = build().search('emirats').matches.map((m) => m.id).toList();
      expect(ids.first, 'EE1');
    });

    test('exact team name beats the match phase; live still ranks first', () {
      final idx = build()..addMatches(parseMatchList([match('LV', 'Gamma', 'Delta', status: 'LIVE')]));
      expect(idx.search('eagles').matches.single.id, 'EE1');
      expect(idx.search('gamma').matches.first.id, 'LV');
    });

    test('multi-word and code queries', () {
      final idx = build();
      expect(idx.search('eagles tigers').matches.single.id, 'EE1');
      expect(idx.search('tigers eagles').matches.single.id, 'EE1', reason: 'token order is free');
      expect(idx.search('EM').matches.map((m) => m.id), contains('EE1'), reason: 'team code / prefix');
      expect(idx.search('eagles india').isEmpty, isTrue, reason: 'every token must match');
    });

    test('whitespace, punctuation and one-letter queries do not match everything', () {
      final idx = build();
      expect(idx.search('   ').isEmpty, isTrue);
      expect(idx.search('!!!').isEmpty, isTrue);
      expect(idx.search('e').matches.length, lessThanOrEqualTo(8));
    });

    test('results are capped per group and the same match is indexed once', () {
      final idx = build()..addMatches(parseMatchList([match('EE1', 'Emirates Eagles', 'United Tigers')]));
      expect(idx.search('alpha').matches.length, 8);
      expect(idx.search('eagles').matches.length, 1, reason: 're-adding the same id replaces it');
    });

    test('clear() empties the index', () {
      final idx = build()..clear();
      expect(idx.size, 0);
      expect(idx.search('eagles').isEmpty, isTrue);
    });
  });

  group('RecentSearches', () {
    test('newest first, unique ignoring case, capped, clearable', () async {
      for (var i = 0; i < 10; i++) {
        await RecentSearches.add('q$i');
      }
      expect(await RecentSearches.load(), hasLength(RecentSearches.max));
      await RecentSearches.add('India');
      await RecentSearches.add('INDIA');
      final l = await RecentSearches.load();
      expect(l.first, 'INDIA');
      expect(l.where((e) => e.toLowerCase() == 'india'), hasLength(1));
      await RecentSearches.add(' x ');
      expect((await RecentSearches.load()).first, 'INDIA', reason: 'too short');
      await RecentSearches.clear();
      expect(await RecentSearches.load(), isEmpty);
    });

    test('corrupt storage reads as empty', () async {
      SharedPreferences.setMockInitialValues({
        RecentSearches.prefsKey: '{oops',
      });
      expect(await RecentSearches.load(), isEmpty);
    });
  });

  testWidgets(
    'idle → debounced results grouped; match opens and is remembered',
    (tester) async {
      final api = FakeApi(_routes());
      final r = await _pump(tester, api);
      expect(find.byKey(const ValueKey('search_idle')), findsOneWidget);
      final warmCalls = api.count('/players/trending');

      // Typing fast: one debounced player lookup.
      await tester.enterText(find.byKey(const ValueKey('search_field')), 'au');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const ValueKey('search_field')), 'aus');
      await tester.pump(const Duration(milliseconds: 100));
      await _type(tester, 'australia');
      expect(api.count('/players/trending'), warmCalls + 1);

      expect(find.text('Matches'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search_match_w2bXPRS')),
        findsOneWidget,
      );
      expect(find.text('Series'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search_series_87s5QyQ')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('search_match_w2bXPRS')));
      await settle(tester);
      expect(r.state.uri.path, '/home/match/w2bXPRS');
      expect(await RecentSearches.load(), ['australia']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('players come from the trending search and open the profile', (
    tester,
  ) async {
    final r = await _pump(tester, FakeApi(_routes()));
    await _type(tester, 'cummins');
    expect(find.text('Players'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search_player_pat_cummins')));
    await settle(tester);
    expect(r.state.uri.path, '/home/player/pat_cummins');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('series result opens the series hub', (tester) async {
    final r = await _pump(tester, FakeApi(_routes()));
    await _type(tester, 'ashes');
    await tester.tap(find.byKey(const ValueKey('search_series_BH2euj2')));
    await settle(tester);
    expect(r.state.uri.path, '/home/series-detail/BH2euj2');
    expect(find.text('series:BH2euj2:The Ashes 2027'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recent searches: shown, reusable, clearable', (tester) async {
    SharedPreferences.setMockInitialValues({
      RecentSearches.prefsKey: jsonEncode(['hobart', 'ashes']),
    });
    await _pump(tester, FakeApi(_routes()));
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('hobart'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search_recent_0')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search_match_w2bXPRS')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search_clear_query')));
    await settle(tester);
    expect(find.text('Recent searches'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search_recent_clear')));
    await settle(tester);
    expect(find.text('Recent searches'), findsNothing);
    expect(find.byKey(const ValueKey('search_idle')), findsOneWidget);
    expect(await RecentSearches.load(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('search_back')));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no result: honest empty state with a next step', (tester) async {
    final r = await _pump(tester, FakeApi(_routes()));
    await _type(tester, 'zzzzqq');
    expect(find.byKey(const ValueKey('search_empty')), findsOneWidget);
    expect(find.text('Nothing found for "zzzzqq"'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    await settle(tester);
    expect(r.state.uri.path, '/discover/players');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('everything down: error with Try again that recovers', (
    tester,
  ) async {
    var fail = true;
    final ok = _routes();
    final api = FakeApi({
      for (final e in ok.entries)
        e.key: (req) => fail ? FakeApi.status(503, 'Down')(req) : e.value(req),
    });
    await _pump(tester, api);
    await _type(tester, 'hobart');
    expect(find.byKey(const ValueKey('search_error')), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    await settle(tester);
    expect(find.byKey(const ValueKey('search_match_w2bXPRS')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
