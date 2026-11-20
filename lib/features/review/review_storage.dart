import 'package:shared_preferences/shared_preferences.dart';

/// When the app may ask the OS to show its rating sheet
/// (docs/aso/IN_APP_ASO_CHECKLIST.md §2, Google Play ratings policy, Apple
/// App Store Review Guideline 5.6.1):
/// - never on the first launch: at least [minSessionsBeforeAsk] app launches,
/// - only after real use: at least [minMeaningfulActions] match views,
/// - only right after a positive moment (e.g. viewing a completed match),
/// - at most once per [cooldownDays] days, and at most once per app run,
/// - never on back / exit, never gated by the user's sentiment.
class ReviewRules {
  ReviewRules._();
  static const cooldownDays = 30;
  static const minMeaningfulActions = 3;
  static const minSessionsBeforeAsk = 3;
}

/// Pure eligibility check (unit-tested with an explicit [now]).
///
/// [positiveMoment] is true only when the caller has just finished a positive
/// flow; [askedThisRun] blocks a second request in the same app run.
bool canAskForReview({
  required int sessionCount,
  required int actionCount,
  required int? lastRequestMs,
  required DateTime now,
  bool positiveMoment = true,
  bool askedThisRun = false,
}) {
  if (!positiveMoment || askedThisRun) return false;
  if (sessionCount < ReviewRules.minSessionsBeforeAsk) return false;
  if (actionCount < ReviewRules.minMeaningfulActions) return false;
  if (lastRequestMs != null) {
    final elapsed = now.millisecondsSinceEpoch - lastRequestMs;
    // A clock moved backwards never unlocks a new request.
    if (elapsed < 0) return false;
    if (elapsed / Duration.millisecondsPerDay < ReviewRules.cooldownDays) {
      return false;
    }
  }
  return true;
}

/// Persisted counters (SharedPreferences).
class ReviewStore {
  ReviewStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const keyLastRequest = 'review.lastRequestMs';
  static const keyActionCount = 'review.matchViews';
  static const keySessionCount = 'review.sessions';

  final DateTime Function() _clock;

  DateTime now() => _clock();

  /// Tolerates values stored as int or string (and garbage → null).
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
      await (await SharedPreferences.getInstance()).setInt(
        keyLastRequest,
        _clock().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Eligibility from the stored counters (see [canAskForReview]).
  Future<bool> canAsk({
    bool positiveMoment = true,
    bool askedThisRun = false,
  }) async {
    final results = await Future.wait([
      sessionCount(),
      meaningfulActionCount(),
      lastRequestMs(),
    ]);
    return canAskForReview(
      sessionCount: results[0] ?? 0,
      actionCount: results[1] ?? 0,
      lastRequestMs: results[2],
      now: _clock(),
      positiveMoment: positiveMoment,
      askedThisRun: askedThisRun,
    );
  }
}
