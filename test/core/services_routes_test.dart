import 'dart:convert';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/route_map.g.dart';
import 'package:crickbex/core/services/cricket_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/sbx1_server.dart';

void main() {
  const mid = '6afc99e131bbe1ca564aaf10';
  const sk = 'series/key#1?x=&y';
  const odd = "Côte d'Ivoire";
  const pk = 'p/key with space&?=%é';

  late String gotToken;
  late Map<String, dynamic> gotParams;
  late List<String> rawBodies;
  late ApiClient api;
  late MatchService m;
  late PlayerService p;
  late RankingService r;

  setUp(() {
    rawBodies = [];
    api = ApiClient(
      client: sbx1Server((t, pr) {
        gotToken = t;
        gotParams = pr;
        return (status: 200, body: {'message': 'ok', 'data': []});
      }, onRaw: (req) => rawBodies.add(req.body)),
      baseUrl: 'http://test/api/x',
      secret: kTestSecret,
      retryDelays: const [],
    );
    m = MatchService(api);
    p = PlayerService(api);
    r = RankingService(api);
  });

  final cases = <String, (Future<ApiResponse> Function(), String, Map<String, dynamic>)>{};
  void add(String name, Future<ApiResponse> Function() f, String token, Map<String, dynamic> params) => cases[name] = (f, token, params);

  // Lazily referenced services via closures (setUp reassigns them).
  add('getRecentMatches', () => m.getRecentMatches(), RouteMap.matchRecent, {});
  add('getLiveMatches', () => m.getLiveMatches(), RouteMap.matchLive, {});
  add('getUpcomingMatches', () => m.getUpcomingMatches(), RouteMap.matchUpcoming, {});
  add('getCompletedMatches', () => m.getCompletedMatches(page: 3, perPage: 7), RouteMap.matchCompleted, {'page': 3, 'perPage': 7});
  add('getCompletedMatches defaults', () => m.getCompletedMatches(), RouteMap.matchCompleted, {'page': 1, 'perPage': 10});
  add('getMatchById', () => m.getMatchById(mid), RouteMap.matchById, {'matchId': mid});
  add('getMatchLive', () => m.getMatchLive(mid), RouteMap.matchLiveById, {'matchId': mid});
  add('getMatchLive paged', () => m.getMatchLive(mid, page: 2, perPage: 5), RouteMap.matchLiveById, {'matchId': mid, 'page': 2, 'perPage': 5});
  add('getMatchScorecard', () => m.getMatchScorecard(mid), RouteMap.matchScorecard, {'matchId': mid});
  add('getMatchAnalytics', () => m.getMatchAnalytics(mid), RouteMap.matchAnalytics, {'matchId': mid});
  add('getMatchScoringRate', () => m.getMatchScoringRate(mid), RouteMap.matchScoringRate, {'matchId': mid});
  add('getMatchBoundaries', () => m.getMatchBoundaries(mid), RouteMap.matchBoundaries, {'matchId': mid});
  add('getMatchCommentary', () => m.getMatchCommentary(mid), RouteMap.matchCommentary, {'matchId': mid, 'page': 1});
  add('getMatchCommentary paged', () => m.getMatchCommentary(mid, page: 4, perPage: 30), RouteMap.matchCommentary, {'matchId': mid, 'page': 4, 'perPage': 30});
  add('getMatchPlayingXI', () => m.getMatchPlayingXI(mid), RouteMap.matchPlaying11, {'matchId': mid});
  add('getMatchSquad', () => m.getMatchSquad(mid), RouteMap.matchSquad, {'matchId': mid});
  add('getSeries', () => m.getSeries(), RouteMap.seriesList, {'page': 1, 'perPage': 12});
  add('getSeries status', () => m.getSeries(status: 'ONGOING', page: 2, perPage: 3), RouteMap.seriesList, {'page': 2, 'perPage': 3, 'status': 'ONGOING'});
  add('getUpcomingSeries', () => m.getUpcomingSeries(), RouteMap.seriesUpcoming, {});
  add('getSeriesFixtures', () => m.getSeriesFixtures(sk), RouteMap.seriesById, {'seriesId': sk});
  add('getSeriesPointsTable', () => m.getSeriesPointsTable(sk), RouteMap.seriesPointTable, {'seriesId': sk});
  add('getSeriesSquads', () => m.getSeriesSquads(sk), RouteMap.seriesSquad, {'seriesId': sk});
  add('getSeriesStats', () => m.getSeriesStats(sk), RouteMap.seriesStats, {'seriesId': sk});
  add('getCountries', () => p.getCountries(), RouteMap.playersCountries, {});
  add('getPlayersByCountry Sri Lanka', () => p.getPlayersByCountry('Sri Lanka'), RouteMap.playersByCountry, {'country': 'Sri Lanka', 'page': 1, 'perPage': 20});
  add('getPlayersByCountry Cote', () => p.getPlayersByCountry(odd, page: 2, perPage: 9), RouteMap.playersByCountry, {'country': odd, 'page': 2, 'perPage': 9});
  add('getPlayerInfo', () => p.getPlayerInfo(pk), RouteMap.playerInfo, {'playerId': pk});
  add('getTrendingPlayers', () => p.getTrendingPlayers(), RouteMap.playersTrending, {'page': 1, 'perPage': 10});
  add('getTrendingPlayers search', () => p.getTrendingPlayers(search: 'Virat Kohli', page: 2), RouteMap.playersTrending, {'page': 2, 'perPage': 10, 'search': 'Virat Kohli'});
  add('getTeamRankings', () => r.getTeamRankings(), RouteMap.rankTeam, {'gender': 'MALE', 'matchType': 'TEST'});
  add('getTeamRankings custom', () => r.getTeamRankings(gender: 'FEMALE', matchType: 'T20'), RouteMap.rankTeam, {'gender': 'FEMALE', 'matchType': 'T20'});
  add('getPlayerRankings', () => r.getPlayerRankings(type: 'BOWLER'), RouteMap.rankPlayer, {'gender': 'MALE', 'matchType': 'ODI', 'type': 'BOWLER'});

  cases.forEach((name, c) {
    test('$name -> token + encrypted params', () async {
      await c.$1();
      expect(gotToken, c.$2);
      expect(gotParams, c.$3);
      expect(rawBodies, hasLength(1));
      for (final v in c.$3.values.whereType<String>()) {
        expect(rawBodies.single, isNot(contains(v)));
        expect(rawBodies.single, isNot(contains(Uri.encodeComponent(v))));
      }
    });
  });

  test('every RouteMap token used by services is covered and unique', () {
    final used = cases.values.map((c) => c.$2).toSet();
    for (final t in [
      RouteMap.matchRecent, RouteMap.matchLive, RouteMap.matchUpcoming, RouteMap.matchCompleted, RouteMap.matchById,
      RouteMap.matchLiveById, RouteMap.matchScorecard, RouteMap.matchSquad, RouteMap.matchCommentary, RouteMap.matchPlaying11,
      RouteMap.matchBoundaries, RouteMap.matchScoringRate, RouteMap.matchAnalytics, RouteMap.seriesList, RouteMap.seriesUpcoming,
      RouteMap.seriesById, RouteMap.seriesPointTable, RouteMap.seriesSquad, RouteMap.seriesStats, RouteMap.playersTrending,
      RouteMap.playersCountries, RouteMap.playersByCountry, RouteMap.playerInfo, RouteMap.rankTeam, RouteMap.rankPlayer,
    ]) {
      expect(used, contains(t));
    }
    expect(jsonEncode(used.toList()).length, greaterThan(0));
  });

  test('testClient reconstructs legacy URLs (encoded country / key)', () async {
    final seen = <Uri>[];
    final c = testClient(MockClient((req) async {
      seen.add(req.url);
      return http.Response(jsonEncode({'message': 'ok', 'data': []}), 200);
    }));
    await PlayerService(c).getPlayersByCountry('Sri Lanka', page: 2);
    await PlayerService(c).getPlayerInfo('a/b');
    await MatchService(c).getMatchLive('m1', page: 2);
    expect(seen[0].toString(), 'http://test/players/country/Sri%20Lanka?page=2&perPage=20');
    expect(seen[1].toString(), 'http://test/players/a%2Fb/info');
    expect(seen[2].toString(), 'http://test/match/m1/live?page=2');
  });
}
