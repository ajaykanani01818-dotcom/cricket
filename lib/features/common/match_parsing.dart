import '../../core/api/json.dart';
import '../../core/utils/match_transform.dart';

/// Transforms an API match list once when it arrives (never in build).
/// Malformed entries (non-maps) are skipped; missing fields degrade to ''.
List<MatchSummary> parseMatchList(dynamic data) => transformApiMatches(J.maps(data));
