import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_config.dart';

/// Injectable clock (tests pass a fake).
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

/// Interstitial frequency cap — RN `interstitialService.recordDetailExit`.
///
/// Shows only on a detail-screen exit (a natural transition) when:
/// exits since last show >= detailExitsBeforeShow, min gap elapsed, and the
/// per-session cap is not reached.
class InterstitialPolicy {
  InterstitialPolicy(this.config);
  final InterstitialConfig config;

  int detailExitCount = 0;
  DateTime? lastShowTime;
  int sessionShowCount = 0;

  /// Records one detail exit and returns whether an ad should be shown now.
  /// When true the counters are already advanced (marked as shown up front so
  /// a slow show() cannot let a second exit slip past the cap).
  bool onDetailExit(DateTime now) {
    detailExitCount += 1;
    final minGap = Duration(seconds: config.minSecondsBetweenAds);
    final byTime = lastShowTime == null || now.difference(lastShowTime!) >= minGap;
    final byExits = detailExitCount >= config.detailExitsBeforeShow;
    final bySession = sessionShowCount < config.maxPerSession;
    if (!byExits || !byTime || !bySession) return false;
    detailExitCount = 0;
    lastShowTime = now;
    sessionShowCount += 1;
    return true;
  }
}

/// App-open cap — RN `appOpenService`: only on resume-from-background (never
/// on first launch), with a minimum interval between shows.
class AppOpenPolicy {
  AppOpenPolicy(this.config);
  final AppOpenConfig config;

  bool hasBeenInBackground = false;
  DateTime? lastShowTime;

  void markWentToBackground() => hasBeenInBackground = true;

  /// Returns whether an app-open ad may be shown now; marks it as shown.
  bool onResume(DateTime now) {
    if (!hasBeenInBackground) return false;
    final minGap = Duration(seconds: config.minIntervalSeconds);
    if (lastShowTime != null && now.difference(lastShowTime!) < minGap) return false;
    lastShowTime = now;
    return true;
  }
}

/// "No ads for 30 min" reward window — RN `noAdsStorage` + `useNoAdsActive`.
/// [active] notifies listeners when the reward is granted and when it expires.
class NoAdsStore {
  NoAdsStore({Clock? clock}) : _clock = clock ?? systemClock;

  static const prefsKey = 'ads_free_until';

  final Clock _clock;
  int? _untilMs;
  Timer? _expiry;

  /// True while the no-ads window is active.
  final ValueNotifier<bool> active = ValueNotifier(false);

  int? get untilMs => _untilMs;

  bool get isActiveSync => _untilMs != null && _clock().millisecondsSinceEpoch < _untilMs!;

  void _sync() {
    _expiry?.cancel();
    final on = isActiveSync;
    active.value = on;
    if (on) {
      final left = Duration(milliseconds: _untilMs! - _clock().millisecondsSinceEpoch);
      _expiry = Timer(left, _sync);
    }
  }

  /// Loads the persisted window; clears it when already expired.
  Future<bool> refresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get(prefsKey);
      final until = raw is int ? raw : int.tryParse('${raw ?? ''}');
      if (until != null && _clock().millisecondsSinceEpoch >= until) {
        _untilMs = null;
        await prefs.remove(prefsKey);
      } else {
        _untilMs = until;
      }
    } catch (_) {
      // Storage failure: keep the in-memory value.
    }
    _sync();
    return isActiveSync;
  }

  Future<void> setUntil(int timestampMs) async {
    _untilMs = timestampMs;
    _sync();
    try {
      (await SharedPreferences.getInstance()).setInt(prefsKey, timestampMs);
    } catch (_) {}
  }

  /// Grants the reward window from now.
  Future<void> grant(Duration duration) => setUntil(_clock().add(duration).millisecondsSinceEpoch);

  Future<void> clear() async {
    _untilMs = null;
    _sync();
    try {
      await (await SharedPreferences.getInstance()).remove(prefsKey);
    } catch (_) {}
  }

  void dispose() {
    _expiry?.cancel();
    _expiry = null;
  }
}
