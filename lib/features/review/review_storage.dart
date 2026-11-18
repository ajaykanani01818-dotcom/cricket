import 'package:shared_preferences/shared_preferences.dart';

/// Review prompt rules — ported from RN `src/services/reviewStorage.ts`:
/// - don't ask in the first 2 sessions,
/// - ask only after meaningful engagement (3+ match details),
/// - don't ask more than once per 30 days.
class ReviewRules {
  ReviewRules._();
  static const cooldownDays = 30;
  static const minMeaningfulActions = 3;
  static const minSessionsBeforeAsk = 2;
}

/// Pure eligibility check (unit-tested with an explicit [now]).
bool canAskForReview({required int sessionCount, required int actionCount, required int? lastRequestMs, required DateTime now}) {
  if (sessionCount < ReviewRules.minSessionsBeforeAsk) return false;
  if (actionCount < ReviewRules.minMeaningfulActions) return false;
  if (lastRequestMs != null) {
    final daysSince = (now.millisecondsSinceEpoch - lastRequestMs) / Duration.millisecondsPerDay;
    if (daysSince < ReviewRules.cooldownDays) return false;
  }
  return true;
}

/// Persisted counters (SharedPreferences, same keys as RN AsyncStorage).
class ReviewStore {
  ReviewStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const keyLastRequest = '@crickbex/review_last_request';
  static const keyActionCount = '@crickbex/review_action_count';
  static const keySessionCount = '@crickbex/review_session_count';

  final DateTime Function() _clock;

  DateTime now() => _clock();

  /// Tolerates values stored as int or string (and garbage → fallback).
  static int? _readInt(SharedPreferences p, String key) {
    final raw = p.get(key);
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<int?> lastRequestMs() async {
    try {
      return _readInt(await SharedPreferences.getInstance(), keyLastRequest);
    } catch (_) {
      return null;
    }
  }

  Future<int> _count(String key) async {
    try {
      final n = _readInt(await SharedPreferences.getInstance(), key) ?? 0;
      return n < 0 ? 0 : n;
    } catch (_) {
      return 0;
    }
  }

  Future<int> meaningfulActionCount() => _count(keyActionCount);
  Future<int> sessionCount() => _count(keySessionCount);

  Future<int> _increment(String key) async {
    final next = await _count(key) + 1;
    try {
      await (await SharedPreferences.getInstance()).setInt(key, next);
    } catch (_) {}
    return next;
  }

  Future<int> recordMeaningfulAction() => _increment(keyActionCount);
  Future<int> recordSession() => _increment(keySessionCount);

  Future<void> recordReviewRequested() async {
    try {
      await (await SharedPreferences.getInstance()).setInt(keyLastRequest, _clock().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<bool> canAsk() async {
    final results = await Future.wait([sessionCount(), meaningfulActionCount(), lastRequestMs()]);
    return canAskForReview(
      sessionCount: results[0] ?? 0,
      actionCount: results[1] ?? 0,
      lastRequestMs: results[2],
      now: _clock(),
    );
  }
}
