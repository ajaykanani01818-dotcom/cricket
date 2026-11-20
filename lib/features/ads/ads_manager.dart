import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ad_unit_ids.dart';
import 'ads_backend.dart';
import 'ads_config.dart';
import 'ads_policy.dart';
import 'google_ads_backend.dart';

/// App-wide ads controller — ported from RN AdsContext + adsService +
/// interstitialService + appOpenService + noAdsStorage.
///
/// Nothing touches the ad SDK until [initialize] is called (from main.dart
/// after the first frame). Until then [adsReady] is false and every ad widget
/// renders `SizedBox.shrink()` — which is also what happens in widget tests.
class AdsManager {
  AdsManager._();
  static final AdsManager instance = AdsManager._();

  /// google_mobile_ads has no web implementation: ads are disabled on web.
  AdsBackend _backend = kIsWeb ? const NoopAdsBackend() : GoogleAdsBackend();
  Clock _clock = systemClock;
  AdsConfig config = AdsConfig.defaults();
  AdUnitIds ids = resolveAdUnitIds();
  late NoAdsStore noAds = NoAdsStore(clock: () => _clock());

  late InterstitialPolicy _interstitialPolicy = InterstitialPolicy(config.interstitial);
  late AppOpenPolicy _appOpenPolicy = AppOpenPolicy(config.appOpen);

  /// True once consent + SDK init succeeded (RN `adsReady`).
  final ValueNotifier<bool> adsReady = ValueNotifier(false);

  AdsBackend get backend => _backend;
  DateTime now() => _clock();

  Future<bool>? _initFuture;
  FullScreenAd? _interstitial;
  bool _interstitialLoading = false;
  FullScreenAd? _appOpen;
  bool _appOpenLoading = false;
  bool _fullScreenShowing = false;
  StreamSubscription<bool>? _fgSub;

  bool get noAdsActive => noAds.isActiveSync;
  bool get isFullScreenShowing => _fullScreenShowing;
  bool get interstitialLoaded => _interstitial != null;
  bool get appOpenLoaded => _appOpen != null;
  InterstitialPolicy get interstitialPolicy => _interstitialPolicy;
  AppOpenPolicy get appOpenPolicy => _appOpenPolicy;

  /// Initialize once at launch (idempotent). Never throws; resolves to whether
  /// ads are available. Order matters: UMP consent → request config → init.
  Future<bool> initialize() => _initFuture ??= _doInit();

  Future<bool> _doInit() async {
    try {
      await noAds.refresh();
      if (kIsWeb) {
        adLog('Skipping AdMob (not supported on web).');
        return false;
      }
      if (!config.masterEnabled) {
        adLog('Skipping AdMob (ads_master_enabled=false).');
        return false;
      }
      bool allowed;
      try {
        allowed = await _backend.gatherConsent();
      } catch (_) {
        allowed = true; // fail open (RN consentService)
      }
      if (!allowed) return false;
      final ok = await _backend.initialize(testDeviceIds: testDeviceIds);
      if (!ok) return false;
      adsReady.value = true;
      adLog('AdMob initialized. mode=${isUsingTestAds() ? 'TEST' : 'LIVE'} banner=${ids.adaptiveBanner}');
      _preloadInterstitial();
      _preloadAppOpen();
      _fgSub = _backend.foregroundStream().listen(_onForegroundChanged, onError: (_) {});
      return true;
    } catch (e) {
      adLog('init failed: $e');
      adsReady.value = false;
      return false;
    }
  }

  // ---------------------------------------------------------------- interstitial

  void _preloadInterstitial() {
    if (!adsReady.value || !config.isInterstitialEnabled) return;
    if (_interstitial != null || _interstitialLoading) return;
    _interstitialLoading = true;
    _backend.loadInterstitial(adUnitId: ids.interstitial).then((ad) {
      _interstitialLoading = false;
      _interstitial = ad;
    }, onError: (_) => _interstitialLoading = false);
  }

  /// Call from a detail screen's dispose() (RN useRecordDetailExit): may show a
  /// frequency-capped interstitial. Never throws.
  void recordDetailExit() {
    try {
      if (!adsReady.value || !config.isInterstitialEnabled || noAdsActive) return;
      final ad = _interstitial;
      if (ad == null) {
        // RN never retried after a failed load; retry lazily here.
        _preloadInterstitial();
        return;
      }
      if (_fullScreenShowing) return;
      if (!_interstitialPolicy.onDetailExit(_clock())) return;
      _interstitial = null;
      // Show after the current frame so it never runs inside a widget dispose().
      scheduleMicrotask(() => _showFullScreen(ad, onDone: _preloadInterstitial));
    } catch (e) {
      adLog('recordDetailExit failed: $e');
    }
  }

  // ---------------------------------------------------------------- app open

  void _preloadAppOpen() {
    if (!adsReady.value || !config.isAppOpenEnabled) return;
    if (_appOpen != null || _appOpenLoading) return;
    _appOpenLoading = true;
    _backend.loadAppOpen(adUnitId: ids.appOpen).then((ad) {
      _appOpenLoading = false;
      _appOpen = ad;
    }, onError: (_) => _appOpenLoading = false);
  }

  void _onForegroundChanged(bool foreground) {
    if (foreground) {
      tryShowAppOpenAd();
    } else {
      markAppWentToBackground();
    }
  }

  /// Must be called when the app goes to background, so app-open only shows on
  /// resume and never on first launch.
  void markAppWentToBackground() {
    if (_fullScreenShowing) return; // our own ad activity, not a real background
    _appOpenPolicy.markWentToBackground();
  }

  /// Call when the app returns to foreground after having been in background.
  void tryShowAppOpenAd() {
    try {
      if (!adsReady.value || !config.isAppOpenEnabled || noAdsActive) return;
      if (_fullScreenShowing) return;
      final ad = _appOpen;
      if (ad == null) {
        _preloadAppOpen();
        return;
      }
      if (!_appOpenPolicy.onResume(_clock())) return;
      _appOpen = null;
      _showFullScreen(ad, onDone: _preloadAppOpen);
    } catch (e) {
      adLog('app open failed: $e');
    }
  }

  // ---------------------------------------------------------------- shared

  Future<bool> _showFullScreen(FullScreenAd ad, {VoidCallback? onDone, VoidCallback? onReward}) async {
    _fullScreenShowing = true;
    try {
      final shown = await ad.show(
        onReward: onReward,
        onDismissed: () {
          _fullScreenShowing = false;
          onDone?.call();
        },
      );
      if (!shown) {
        _fullScreenShowing = false;
        onDone?.call();
      }
      return shown;
    } catch (e) {
      _fullScreenShowing = false;
      ad.dispose();
      onDone?.call();
      return false;
    }
  }

  /// Shows a rewarded ad (used by [RewardedAdController]).
  Future<bool> showRewarded(FullScreenAd ad, {required VoidCallback onReward}) =>
      _showFullScreen(ad, onReward: onReward);

  /// RN "no ads for N min" reward.
  Future<void> grantNoAdsReward() => noAds.grant(Duration(minutes: config.rewardDurationMinutes));

  // ---------------------------------------------------------------- testing

  /// Replaces SDK/clock/config and resets all state. Tests only.
  @visibleForTesting
  void debugReset({AdsBackend? backend, Clock? clock, AdsConfig? config, AdUnitIds? ids, bool ready = false}) {
    _fgSub?.cancel();
    _fgSub = null;
    noAds.dispose();
    _backend = backend ?? const NoopAdsBackend();
    _clock = clock ?? systemClock;
    this.config = config ?? AdsConfig.defaults();
    this.ids = ids ?? testIdsFor(TargetPlatform.android);
    noAds = NoAdsStore(clock: () => _clock());
    _interstitialPolicy = InterstitialPolicy(this.config.interstitial);
    _appOpenPolicy = AppOpenPolicy(this.config.appOpen);
    _initFuture = null;
    _interstitial = null;
    _interstitialLoading = false;
    _appOpen = null;
    _appOpenLoading = false;
    _fullScreenShowing = false;
    adsReady.value = ready;
  }
}
