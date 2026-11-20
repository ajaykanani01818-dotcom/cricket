import 'dart:async';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/json.dart';
import 'package:crickbex/core/utils/match_transform.dart';
import 'package:crickbex/features/common/match_parsing.dart';
import 'package:crickbex/features/matches/match_filters.dart';
import 'package:crickbex/features/matches/match_row.dart';
import 'package:crickbex/features/matches/matches_controller.dart';
import 'package:crickbex/features/matches/matches_tab_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../common/helpers.dart';

/// Page 2 of /match/completed: 3 matches with distinct ids, total 13.
String completedPage2() {
  final rows = J.maps(fixtureJson('match_completed')['data']).take(3).toList();
  for (var i = 0; i < rows.length; i++) {
    rows[i]['sb_match_key'] = 'P2_$i';
    rows[i]['seriesName'] = 'Page Two Series';
  }
  return body(rows, pageInfo: {'total': 13, 'perPage': 10, 'page': 2, 'totalPages': 2});
}

Responder completedPaged({Completer<void>? page2Gate, bool failPage2 = false}) => (req) async {
  final page = req.url.queryParameters['page'];
  if (page == '1') return FakeApi.fixture('match_completed')(req);
  if (page2Gate != null) await page2Gate.future;
  if (failPage2) return http.Response('{"message":"Page failed"}', 500);
  return http.Response(completedPage2(), 200);
};

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('computeHasMore', () {
    expect(computeHasMore(const PageInfo(total: 13, perPage: 10, page: 1), 10), isTrue);
    expect(computeHasMore(const PageInfo(total: 13, perPage: 10, page: 2), 3), isFalse);
    expect(computeHasMore(null, 10), isTrue);
    expect(computeHasMore(null, 4), isFalse);
  });

  test('matchesErrorMessage', () {
    expect(matchesErrorMessage(const ApiException(500, 'Boom')), 'Boom');
    expect(matchesErrorMessage(const ApiException(500, ' ')), 'Something went wrong on our side.');
    expect(matchesErrorMessage(StateError('x')), 'Something went wrong on our side.');
  });

  group('buildMatchSections', () {
    test('groups every match of a series under one section and interleaves ads', () {
      final list = parseMatchList(fixtureJson('match_completed')['data']);
      final sections = buildMatchSections(MatchesTab.completed, list);
      final titles = sections.map((s) => s.title).toList();
      expect(titles.toSet(), hasLength(titles.length), reason: 'one section per series, even when not consecutive');
      expect(titles.first, 'Abu Dhabi T10 League 2026');
      final abu = sections.first;
      expect(abu.matchCount, 4, reason: '4 T10 matches spread over the page');
      final items = [for (final s in sections) ...s.items];
      expect(items.whereType<MatchItem>(), hasLength(10));
      expect(items.whereType<NativeAdItem>(), hasLength(3));
      expect(
        {...items.map((e) => e.key), ...sections.map((s) => s.key)},
        hasLength(items.length + sections.length),
        reason: 'keys are unique',
      );
      expect(items.whereType<MatchItem>().first.key, startsWith('match-completed-'));
    });

    test('no ads when disabled; blank series -> "Other matches"; duplicate ids still unique keys', () {
      final m = parseMatchList([
        {'sb_match_key': 'a'},
        {'sb_match_key': 'a'},
      ]);
      final sections = buildMatchSections(MatchesTab.live, m, showNativeSlots: false);
      expect(sections.single.title, 'Other matches');
      expect(sections.single.items.whereType<NativeAdItem>(), isEmpty);
      expect(sections.single.items.map((e) => e.key).toSet(), hasLength(2));
      expect(buildMatchSections(MatchesTab.live, const []), isEmpty);
    });
  });

  group('filters', () {
    MatchSummary match({
      String format = 'T20',
      String series = 'Big Bash League',
      String t1 = 'Sydney Sixers',
      String t2 = 'Perth Scorchers',
      String date = '2026-11-18T10:00:00Z',
    }) => parseMatchList([
      {
        'sb_match_key': 'x',
        'format': format,
        'seriesName': series,
        'startDate': date,
        'status': 'NOT_STARTED',
        'teams': {
          't1': {'name': t1},
          't2': {'name': t2},
        },
      },
    ]).single;

    test('format buckets', () {
      expect(formatBucket('TEST'), FormatFilter.test);
      expect(formatBucket('Test'), FormatFilter.test);
      expect(formatBucket('ODI'), FormatFilter.odi);
      expect(formatBucket('T20'), FormatFilter.t20);
      expect(formatBucket('t20i'), FormatFilter.t20);
      expect(formatBucket('T10'), FormatFilter.other);
      expect(formatBucket('100-ball'), FormatFilter.other);
      expect(formatBucket(null), FormatFilter.other);
      expect(formatBucket(''), FormatFilter.other);
      expect(formatLabel('TEST'), 'Test');
      expect(formatLabel('T20'), 'T20');
      expect(formatLabel(' '), isNull);
    });

    test('women rule: "Women"/"Womens"/"Women\'s" in series or team names, or a " W" team suffix', () {
      expect(isWomenMatch(match(series: 'Womens Big Bash League 2026')), isTrue);
      expect(isWomenMatch(match(series: "Women's Premier League")), isTrue);
      expect(isWomenMatch(match(series: 'Emerging Nations', t1: 'Ireland Women')), isTrue);
      expect(isWomenMatch(match(t1: 'India W', t2: 'Australia W')), isTrue);
      expect(isWomenMatch(match()), isFalse);
      expect(isWomenMatch(match(t1: 'West Indies', series: 'Wowen Cup')), isFalse);
      expect(isWomenMatch(match(t1: 'Sydney Thunder WC')), isFalse);
    });

    test('apply combines format, women and local day; day ignored when applyDay is false', () {
      final list = [
        match(format: 'T20', series: 'Womens Cup', date: '2026-11-18T10:00:00Z'),
        match(format: 'ODI', date: '2026-11-18T10:00:00Z'),
        match(format: 'T10', date: '2026-11-20T10:00:00Z'),
        match(format: 'TEST', date: ''),
      ];
      expect(const MatchFilters().apply(list), same(list));
      expect(const MatchFilters(format: FormatFilter.odi).apply(list).single.format, 'ODI');
      expect(const MatchFilters(format: FormatFilter.other).apply(list).single.format, 'T10');
      expect(const MatchFilters(format: FormatFilter.test).apply(list).single.format, 'TEST');
      expect(const MatchFilters(women: true).apply(list).single.series, 'Womens Cup');
      final day = dayOf(DateTime.parse('2026-11-18T10:00:00Z'));
      expect(MatchFilters(day: day).apply(list), hasLength(2));
      expect(MatchFilters(day: day).apply(list, applyDay: false), same(list));
      expect(MatchFilters(day: day, format: FormatFilter.t20).apply(list).single.series, 'Womens Cup');
      expect(MatchFilters(day: day).copyWith(clearDay: true).day, isNull);
    });

    test('day labels', () {
      final now = DateTime(2026, 11, 18, 9);
      expect(dayLabel(DateTime(2026, 11, 18), now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 17), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 11, 19), now), 'Tomorrow');
      expect(dayLabel(DateTime(2026, 11, 20), now), 'Fri 20 Nov');
      expect(dayLabel(DateTime(2027, 1, 2), now), '2 Jan 2027');
    });

    test('row data: winner from winnerTeamKey, result line, no score for upcoming', () {
      final done = parseMatchList(fixtureJson('match_completed')['data']).first;
      final d = MatchRowData.fromSummary(done);
      expect(d.phase, RowPhase.completed);
      expect(d.footer, 'UAE Bulls won by 6 wickets');
      expect(d.winner, isNotNull);
      final up = MatchRowData.fromSummary(parseMatchList(fixtureJson('match_upcoming')['data']).first);
      expect(up.phase, RowPhase.upcoming);
      expect(up.team1Score, isNull);
      expect(up.team2Score, isNull);
      expect(up.format, 'ODI');
      expect(splitScore('137/4 (9.5)'), ('137/4', '9.5 ov'));
      expect(splitScore('98'), ('98', null));
      expect(splitScore('135/4 & 98 (42.0)'), ('135/4 & 98', '42.0 ov'));
    });
  });

  group('MatchesController', () {
    test('start loads all three tabs', () async {
      FakeApi({...defaultRoutes(), '/match/completed': completedPaged()}).install();
      final c = MatchesController()..start();
      expect(c[MatchesTab.live].loading, isTrue);
      await _flush();
      expect(c[MatchesTab.live].matches, isEmpty);
      expect(c[MatchesTab.live].loading, isFalse);
      expect(c[MatchesTab.upcoming].matches, hasLength(6));
      expect(c[MatchesTab.completed].matches, hasLength(10));
      expect(c.completedHasMore, isTrue);
      c.dispose();
    });

    test('filters never send requests; Women offered only when the data has women\'s matches', () async {
      final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged()})..install();
      final c = MatchesController()..start();
      await _flush();
      final calls = api.log.length;
      expect(c.womenAvailable, isTrue);
      var notified = 0;
      c.addListener(() => notified++);
      c.setFilters(const MatchFilters(format: FormatFilter.odi, women: true));
      c.setFilters(const MatchFilters(format: FormatFilter.odi, women: true));
      expect(notified, 1, reason: 'same filters do not notify');
      await _flush();
      expect(api.log.length, calls);
      c.dispose();

      FakeApi({
        '/match/live': FakeApi.ok(body([])),
        '/match/upcoming': FakeApi.ok(
          body([
            {
              'sb_match_key': 'm',
              'seriesName': 'Big Bash League',
              'teams': {
                't1': {'name': 'Sixers'},
                't2': {'name': 'Heat'},
              },
            },
          ]),
        ),
        '/match/completed': FakeApi.ok(body([])),
      }).install();
      final c2 = MatchesController()..start();
      await _flush();
      expect(c2.womenAvailable, isFalse);
      c2.dispose();
    });

    test('live falls back to /match/recent filtered to live matches', () async {
      final recent = fixtureJson('match_recent')['data'] as List;
      FakeApi({
        ...defaultRoutes(),
        '/match/live': FakeApi.status(500),
        '/match/recent': FakeApi.ok(body([liveMatchJson(), ...recent])),
      }).install();
      final c = MatchesController();
      await c.fetchLive();
      expect(c[MatchesTab.live].matches.single.id, 'LIVE01');
      expect(c[MatchesTab.live].error, isNull);
      c.dispose();
    });

    test('live: both endpoints failing → error', () async {
      FakeApi({'/match/live': FakeApi.status(500), '/match/recent': FakeApi.status(502, 'Gateway')}).install();
      final c = MatchesController();
      await c.fetchLive();
      expect(c[MatchesTab.live].error, 'Gateway');
      c.dispose();
    });

    test('load-more appends next page once even when called repeatedly, then stops', () async {
      final gate = Completer<void>();
      final api = FakeApi({...defaultRoutes(), '/match/completed': completedPaged(page2Gate: gate)})..install();
      final c = MatchesController();
      await c.fetchCompleted();
      final a = c.loadMoreCompleted();
      c.loadMoreCompleted();
      c.loadMoreCompleted();
      expect(c.completedLoadingMore, isTrue);
      gate.complete();
      await a;
      await _flush();
      expect(api.log.where((u) => u.queryParameters['page'] == '2'), hasLength(1));
      expect(c[MatchesTab.completed].matches, hasLength(13));
      expect(c.completedPage, 2);
      expect(c.completedHasMore, isFalse);
      await c.loadMoreCompleted();
      expect(api.count('/match/completed'), 2, reason: 'no request past the last page');
      c.dispose();
    });

    test('refresh during a load-more discards the stale page', () async {
      final gate = Completer<void>();
      FakeApi({...defaultRoutes(), '/match/completed': completedPaged(page2Gate: gate)}).install();
      final c = MatchesController();
      await c.fetchCompleted();
      final more = c.loadMoreCompleted();
      final refresh = c.refresh();
      await _flush();
      gate.complete();
      await Future.wait([more, refresh]);
      expect(c[MatchesTab.completed].matches, hasLength(10));
      expect(c.completedPage, 1);
      expect(c.completedLoadingMore, isFalse);
      expect(c.refreshing, isFalse);
      c.dispose();
    });

    test('failed load-more keeps the list and can be retried', () async {
      var fail = true;
      FakeApi({...defaultRoutes(), '/match/completed': (req) => completedPaged(failPage2: fail)(req)}).install();
      final c = MatchesController();
      await c.fetchCompleted();
      await c.loadMoreCompleted();
      expect(c.loadMoreError, 'Page failed');
      expect(c[MatchesTab.completed].matches, hasLength(10));
      expect(c[MatchesTab.completed].error, isNull);
      fail = false;
      await c.loadMoreCompleted();
      expect(c.loadMoreError, isNull);
      expect(c[MatchesTab.completed].matches, hasLength(13));
      c.dispose();
    });

    test('no load-more on empty list or first-page error; page-size fallback without pageInfo', () async {
      FakeApi({'/match/completed': FakeApi.ok(body(J.maps(fixtureJson('match_completed')['data']).take(4).toList()))}).install();
      final c = MatchesController();
      await c.fetchCompleted();
      expect(c.completedHasMore, isFalse, reason: '4 < page size and no pageInfo');

      FakeApi({'/match/completed': FakeApi.status(500)}).install();
      final c2 = MatchesController();
      await c2.fetchCompleted();
      expect(c2[MatchesTab.completed].error, isNotNull);
      await c2.loadMoreCompleted();
      expect(c2.completedLoadingMore, isFalse);
      c.dispose();
      c2.dispose();
    });

    test('dispose mid-request is safe', () async {
      final gate = Completer<void>();
      FakeApi({for (final e in defaultRoutes().entries) e.key: FakeApi.gated(gate, e.value)}).install();
      final c = MatchesController()..start();
      c.dispose();
      gate.complete();
      await _flush();
    });
  });
}
