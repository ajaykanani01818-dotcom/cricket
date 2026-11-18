import 'package:flutter/foundation.dart';

/// AdMob ad unit IDs — ported from RN `src/services/ads/adsConfig.ts`.
///
/// Live IDs live in [_liveIds] — the ONLY place to edit them. [adMode] decides
/// whether test or live ads are served.

enum AdMode {
  /// Test IDs in debug/profile builds, live IDs in release builds. Recommended.
  auto,

  /// Always Google test IDs (e.g. testing a release APK on your own device).
  test,

  /// Always live IDs. Do NOT click your own live ads (AdMob invalid traffic).
  live,
}

const AdMode adMode = AdMode.auto;

/// Device IDs that always receive test ads even in a live release build.
/// Find yours in logcat ("Use RequestConfiguration.Builder.setTestDeviceIds…").
const List<String> testDeviceIds = [];

class AdUnitIds {
  const AdUnitIds({
    required this.banner,
    required this.adaptiveBanner,
    required this.interstitial,
    required this.rewarded,
    required this.native,
    required this.appOpen,
  });

  final String banner, adaptiveBanner, interstitial, rewarded, native, appOpen;

  Map<String, String> toMap() => {
        'banner': banner,
        'adaptive_banner': adaptiveBanner,
        'interstitial': interstitial,
        'rewarded': rewarded,
        'native': native,
        'app_open': appOpen,
      };

  static AdUnitIds fromMap(Map<String, String> m) => AdUnitIds(
        banner: m['banner'] ?? '',
        adaptiveBanner: m['adaptive_banner'] ?? '',
        interstitial: m['interstitial'] ?? '',
        rewarded: m['rewarded'] ?? '',
        native: m['native'] ?? '',
        appOpen: m['app_open'] ?? '',
      );
}

/// Google's test ad unit IDs — safe for development.
const _testAndroid = AdUnitIds(
  banner: 'ca-app-pub-3940256099942544/6300978111',
  adaptiveBanner: 'ca-app-pub-3940256099942544/9214589741',
  interstitial: 'ca-app-pub-3940256099942544/1033173712',
  rewarded: 'ca-app-pub-3940256099942544/5224354917',
  native: 'ca-app-pub-3940256099942544/2247696110',
  appOpen: 'ca-app-pub-3940256099942544/9257395921',
);

const _testIos = AdUnitIds(
  banner: 'ca-app-pub-3940256099942544/2934735716',
  adaptiveBanner: 'ca-app-pub-3940256099942544/2435281174',
  interstitial: 'ca-app-pub-3940256099942544/4411468910',
  rewarded: 'ca-app-pub-3940256099942544/1712485313',
  native: 'ca-app-pub-3940256099942544/3986624511',
  appOpen: 'ca-app-pub-3940256099942544/5575463023',
);

/// LIVE AdMob ad unit IDs (RN LIVE_AD_UNIT_IDS). Publisher pub-4606250338441432 —
/// must match the APPLICATION_ID meta-data in AndroidManifest
/// (ca-app-pub-4606250338441432~6523566345).
const _liveAndroid = AdUnitIds(
  banner: 'ca-app-pub-4606250338441432/3202539485',
  // Only one banner unit exists; screen banners (anchored adaptive) reuse it.
  adaptiveBanner: 'ca-app-pub-4606250338441432/3202539485',
  interstitial: 'ca-app-pub-4606250338441432/7645076321',
  rewarded: 'ca-app-pub-4606250338441432/5524666677',
  native: 'ca-app-pub-4606250338441432/6467726026',
  appOpen: 'ca-app-pub-4606250338441432/7472173165',
);

/// No iOS AdMob app/units yet — empty keys fall back to Google test IDs.
const _liveIos = AdUnitIds(banner: '', adaptiveBanner: '', interstitial: '', rewarded: '', native: '', appOpen: '');

/// AdMob IDs are `ca-app-pub-<digits>/<digits>`. Placeholders break loads.
final _validId = RegExp(r'^ca-app-pub-\d+/\d+$');

bool isValidAdUnitId(String? id) => id != null && _validId.hasMatch(id.trim());

bool _isIos(TargetPlatform p) => p == TargetPlatform.iOS;

AdUnitIds testIdsFor(TargetPlatform platform) => _isIos(platform) ? _testIos : _testAndroid;

/// Live IDs, each key falling back to the test ID for THAT format when unset
/// or malformed; adaptive banner reuses the live banner id when only one
/// banner unit exists.
AdUnitIds liveIdsFor(TargetPlatform platform, {AdUnitIds? live}) {
  final test = testIdsFor(platform).toMap();
  final src = (live ?? (_isIos(platform) ? _liveIos : _liveAndroid)).toMap();
  final out = Map<String, String>.from(test);
  for (final e in src.entries) {
    final v = e.value.trim();
    if (isValidAdUnitId(v)) out[e.key] = v;
  }
  final liveAdaptive = src['adaptive_banner']?.trim();
  final liveBanner = src['banner']?.trim();
  if (!isValidAdUnitId(liveAdaptive) && isValidAdUnitId(liveBanner)) out['adaptive_banner'] = liveBanner!;
  return AdUnitIds.fromMap(out);
}

bool hasLiveAdUnitIds(TargetPlatform platform, {AdUnitIds? live}) =>
    (live ?? (_isIos(platform) ? _liveIos : _liveAndroid)).toMap().values.any(isValidAdUnitId);

/// Whether test ad unit IDs are served. 'auto' → test in non-release builds,
/// and stays on test until live IDs are actually filled in.
bool isUsingTestAds({AdMode mode = adMode, bool isRelease = kReleaseMode, TargetPlatform? platform, AdUnitIds? live}) {
  switch (mode) {
    case AdMode.test:
      return true;
    case AdMode.live:
      return false;
    case AdMode.auto:
      if (!isRelease) return true;
      return !hasLiveAdUnitIds(platform ?? defaultTargetPlatform, live: live);
  }
}

/// Ad unit IDs for the running build/platform.
AdUnitIds resolveAdUnitIds({AdMode mode = adMode, bool isRelease = kReleaseMode, TargetPlatform? platform, AdUnitIds? live}) {
  final p = platform ?? defaultTargetPlatform;
  if (isUsingTestAds(mode: mode, isRelease: isRelease, platform: p, live: live)) return testIdsFor(p);
  return liveIdsFor(p, live: live);
}
