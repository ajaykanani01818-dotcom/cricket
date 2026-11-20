import '../api/api_client.dart';
import '../api/route_map.g.dart';

/// Ported from RN `src/services/matchService.ts`. Each method calls an opaque
/// SBX1 route token; path params travel inside the encrypted params map.
class MatchService {
  MatchService([ApiClient? client]) : _c = client ?? ApiClient.instance;
  final ApiClient _c;
  static MatchService instance = MatchService();

  /// No query params (params can cause 422).
  Future<ApiResponse> getRecentMatches() => _c.call(RouteMap.matchRecent);
  Future<ApiResponse> getLiveMatches() => _c.call(RouteMap.matchLive);
  Future<ApiResponse> getUpcomingMatches() => _c.call(RouteMap.matchUpcoming);
  Future<ApiResponse> getCompletedMatches({int page = 1, int perPage = 10}) =>
      _c.call(RouteMap.matchCompleted, {'page': page, 'perPage': perPage});

  Future<ApiResponse> getMatchById(String matchId) =>
      _c.call(RouteMap.matchById, {'matchId': matchId});
  Future<ApiResponse> getMatchLive(String matchId, {int? page, int? perPage}) =>
      _c.call(RouteMap.matchLiveById, {
        'matchId': matchId,
        'page': page,
        'perPage': perPage,
      });
  Future<ApiResponse> getMatchScorecard(String matchId) =>
      _c.call(RouteMap.matchScorecard, {'matchId': matchId});
  Future<ApiResponse> getMatchAnalytics(String matchId) =>
      _c.call(RouteMap.matchAnalytics, {'matchId': matchId});
  Future<ApiResponse> getMatchScoringRate(String matchId) =>
      _c.call(RouteMap.matchScoringRate, {'matchId': matchId});
  Future<ApiResponse> getMatchBoundaries(String matchId) =>
      _c.call(RouteMap.matchBoundaries, {'matchId': matchId});
  Future<ApiResponse> getMatchCommentary(
    String matchId, {
    int page = 1,
    int? perPage,
  }) => _c.call(RouteMap.matchCommentary, {
    'matchId': matchId,
    'page': page,
    'perPage': perPage,
  });
  Future<ApiResponse> getMatchPlayingXI(String matchId) =>
      _c.call(RouteMap.matchPlaying11, {'matchId': matchId});
  Future<ApiResponse> getMatchSquad(String matchId) =>
      _c.call(RouteMap.matchSquad, {'matchId': matchId});

  /// status: ONGOING | UPCOMING | COMPLETED
  Future<ApiResponse> getSeries({
    String? status,
    int page = 1,
    int perPage = 12,
  }) => _c.call(RouteMap.seriesList, {
    'page': page,
    'perPage': perPage,
    'status': status,
  });
  Future<ApiResponse> getUpcomingSeries() => _c.call(RouteMap.seriesUpcoming);
  Future<ApiResponse> getSeriesFixtures(String seriesId) =>
      _c.call(RouteMap.seriesById, {'seriesId': seriesId});
  Future<ApiResponse> getSeriesPointsTable(String seriesId) =>
      _c.call(RouteMap.seriesPointTable, {'seriesId': seriesId});
  Future<ApiResponse> getSeriesSquads(String seriesId) =>
      _c.call(RouteMap.seriesSquad, {'seriesId': seriesId});
  Future<ApiResponse> getSeriesStats(String sbSeriesKey) =>
      _c.call(RouteMap.seriesStats, {'seriesId': sbSeriesKey});
}

/// Ported from RN `src/services/playerService.ts`.
class PlayerService {
  PlayerService([ApiClient? client]) : _c = client ?? ApiClient.instance;
  final ApiClient _c;
  static PlayerService instance = PlayerService();

  Future<ApiResponse> getCountries() => _c.call(RouteMap.playersCountries);
  Future<ApiResponse> getPlayersByCountry(
    String country, {
    int page = 1,
    int perPage = 20,
  }) => _c.call(RouteMap.playersByCountry, {
    'country': country,
    'page': page,
    'perPage': perPage,
  });
  Future<ApiResponse> getPlayerInfo(String playerKey) =>
      _c.call(RouteMap.playerInfo, {'playerId': playerKey});
  Future<ApiResponse> getTrendingPlayers({
    int page = 1,
    int perPage = 10,
    String? search,
  }) => _c.call(RouteMap.playersTrending, {
    'page': page,
    'perPage': perPage,
    'search': search,
  });
}

/// Ported from RN `src/services/rankingService.ts`.
/// gender: MALE | FEMALE; matchType: ODI | T20 | TEST; type: BATSMAN | BOWLER | ALL_ROUNDER
class RankingService {
  RankingService([ApiClient? client]) : _c = client ?? ApiClient.instance;
  final ApiClient _c;
  static RankingService instance = RankingService();

  Future<ApiResponse> getTeamRankings({
    String gender = 'MALE',
    String matchType = 'TEST',
  }) => _c.call(RouteMap.rankTeam, {'gender': gender, 'matchType': matchType});
  Future<ApiResponse> getPlayerRankings({
    String gender = 'MALE',
    String matchType = 'ODI',
    required String type,
  }) => _c.call(RouteMap.rankPlayer, {
    'gender': gender,
    'matchType': matchType,
    'type': type,
  });
}
