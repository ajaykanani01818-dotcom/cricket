import '../api/api_client.dart';

/// Ported from RN `src/services/matchService.ts`. Paths are relative to
/// Env.apiBaseUrl (which already ends in /api/cricbex).
class MatchService {
  MatchService([ApiClient? client]) : _c = client ?? ApiClient.instance;
  final ApiClient _c;
  static MatchService instance = MatchService();

  /// No query params (params can cause 422).
  Future<ApiResponse> getRecentMatches() => _c.get('/match/recent');
  Future<ApiResponse> getLiveMatches() => _c.get('/match/live');
  Future<ApiResponse> getUpcomingMatches() => _c.get('/match/upcoming');
  Future<ApiResponse> getCompletedMatches({int page = 1, int perPage = 10}) =>
      _c.get('/match/completed', {'page': page, 'perPage': perPage});

  Future<ApiResponse> getMatchById(String matchId) => _c.get('/match/$matchId');
  Future<ApiResponse> getMatchLive(String matchId, {int? page, int? perPage}) =>
      _c.get('/match/$matchId/live', {'page': page, 'perPage': perPage});
  Future<ApiResponse> getMatchScorecard(String matchId) => _c.get('/match/$matchId/scorecard');
  Future<ApiResponse> getMatchAnalytics(String matchId) => _c.get('/match/$matchId/analytics');
  Future<ApiResponse> getMatchScoringRate(String matchId) => _c.get('/match/$matchId/scoring-rate');
  Future<ApiResponse> getMatchBoundaries(String matchId) => _c.get('/match/$matchId/boundaries');
  Future<ApiResponse> getMatchCommentary(String matchId, {int page = 1, int? perPage}) =>
      _c.get('/match/$matchId/commentary', {'page': page, 'perPage': perPage});
  Future<ApiResponse> getMatchPlayingXI(String matchId) => _c.get('/match/$matchId/playing11');
  Future<ApiResponse> getMatchSquad(String matchId) => _c.get('/match/$matchId/squad');

  /// status: ONGOING | UPCOMING | COMPLETED
  Future<ApiResponse> getSeries({String? status, int page = 1, int perPage = 12}) =>
      _c.get('/series', {'page': page, 'perPage': perPage, 'status': status});
  Future<ApiResponse> getUpcomingSeries() => _c.get('/series/upcoming');
  Future<ApiResponse> getSeriesFixtures(String seriesId) => _c.get('/series/$seriesId');
  Future<ApiResponse> getSeriesPointsTable(String seriesId) => _c.get('/series/$seriesId/point-table');
  Future<ApiResponse> getSeriesSquads(String seriesId) => _c.get('/series/$seriesId/squad');
  Future<ApiResponse> getSeriesStats(String sbSeriesKey) => _c.get('/series/$sbSeriesKey/stats');
}

/// Ported from RN `src/services/playerService.ts`.
class PlayerService {
  PlayerService([ApiClient? client]) : _c = client ?? ApiClient.instance;
  final ApiClient _c;
  static PlayerService instance = PlayerService();

  Future<ApiResponse> getCountries() => _c.get('/players/countries');
  Future<ApiResponse> getPlayersByCountry(String country, {int page = 1, int perPage = 20}) =>
      _c.get('/players/country/${Uri.encodeComponent(country)}', {'page': page, 'perPage': perPage});
  Future<ApiResponse> getPlayerInfo(String playerKey) => _c.get('/players/${Uri.encodeComponent(playerKey)}/info');
  Future<ApiResponse> getTrendingPlayers({int page = 1, int perPage = 10, String? search}) =>
      _c.get('/players/trending', {'page': page, 'perPage': perPage, 'search': search});
}

/// Ported from RN `src/services/rankingService.ts`.
/// gender: MALE | FEMALE; matchType: ODI | T20 | TEST; type: BATSMAN | BOWLER | ALL_ROUNDER
class RankingService {
  RankingService([ApiClient? client]) : _c = client ?? ApiClient.instance;
  final ApiClient _c;
  static RankingService instance = RankingService();

  Future<ApiResponse> getTeamRankings({String gender = 'MALE', String matchType = 'TEST'}) =>
      _c.get('/rank', {'gender': gender, 'matchType': matchType});
  Future<ApiResponse> getPlayerRankings({String gender = 'MALE', String matchType = 'ODI', required String type}) =>
      _c.get('/rank/player', {'gender': gender, 'matchType': matchType, 'type': type});
}
