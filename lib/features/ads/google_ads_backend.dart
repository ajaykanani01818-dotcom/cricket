import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/theme/app_theme.dart';
import 'ads_backend.dart';

void adLog(String msg) {
  if (kDebugMode) debugPrint('[Ads] $msg');
}

/// Real implementation on top of `google_mobile_ads`. Every call is guarded:
/// errors/timeouts resolve to null/false so ads never block or crash the UI.
class GoogleAdsBackend implements AdsBackend {
  GoogleAdsBackend({this.loadTimeout = const Duration(seconds: 30), this.consentTimeout = const Duration(seconds: 12)});

  final Duration loadTimeout;
  final Duration consentTimeout;

  static const _request = AdRequest();

  @override
  Future<bool> gatherConsent() async {
    // Fails open: if the UMP request errors, ads are still requested (the SDK
    // itself enforces non-personalised ads when consent is missing).
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((FormError? e) {
              if (e != null) adLog('consent form error: ${e.message}');
            });
          } catch (e) {
            adLog('consent form failed: $e');
          }
          if (!done.isCompleted) done.complete();
        },
        (FormError e) {
          adLog('consent info update failed: ${e.message}');
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(consentTimeout, onTimeout: () {});
      final can = await ConsentInformation.instance.canRequestAds().timeout(const Duration(seconds: 3), onTimeout: () => true);
      adLog('consent canRequestAds=$can');
      // Fail open (RN: `info.canRequestAds !== false` and true on any error).
      return true;
    } catch (e) {
      adLog('consent gathering failed: $e');
      return true;
    }
  }

  @override
  Future<bool> initialize({required List<String> testDeviceIds}) async {
    try {
      // Request configuration BEFORE initialize() so the first requests use it.
      await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
        // Cricket scores app — keep inventory family-safe and Play-listing appropriate.
        maxAdContentRating: MaxAdContentRating.t,
        testDeviceIds: testDeviceIds,
      ));
      await MobileAds.instance.initialize();
      return true;
    } catch (e) {
      adLog('AdMob not available: $e');
      return false;
    }
  }

  @override
  Stream<bool> foregroundStream() {
    // ProcessLifecycleOwner-based: an interstitial/app-open activity on top of
    // the app does NOT count as background (unlike AppLifecycleState).
    try {
      AppStateEventNotifier.startListening();
      return AppStateEventNotifier.appStateStream.map((s) => s == AppState.foreground).handleError((Object e) => adLog('app state stream: $e'));
    } catch (e) {
      adLog('app state listener failed: $e');
      return const Stream.empty();
    }
  }

  Future<T?> _guard<T>(Future<T?> Function() body, String what) async {
    try {
      return await body();
    } catch (e) {
      adLog('$what failed: $e');
      return null;
    }
  }

  @override
  Future<LoadedBanner?> loadBanner({required String adUnitId, required int width, required Orientation orientation}) =>
      _guard(() async {
        AdSize size = AdSize.banner;
        try {
          final adaptive = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
          if (adaptive != null) size = adaptive;
        } catch (_) {}
        final c = Completer<LoadedBanner?>();
        late final BannerAd ad;
        ad = BannerAd(
          adUnitId: adUnitId,
          size: size,
          request: _request,
          listener: BannerAdListener(
            onAdLoaded: (a) async {
              Size s = Size(size.width.toDouble(), size.height.toDouble());
              try {
                final platform = await ad.getPlatformAdSize();
                if (platform != null) s = Size(platform.width.toDouble(), platform.height.toDouble());
              } catch (_) {}
              if (c.isCompleted) {
                a.dispose();
              } else {
                c.complete(_GoogleBanner(ad, s));
              }
            },
            onAdFailedToLoad: (a, err) {
              adLog('banner failed: ${err.code} ${err.message}');
              a.dispose();
              if (!c.isCompleted) c.complete(null);
            },
          ),
        );
        await ad.load();
        return c.future.timeout(loadTimeout, onTimeout: () {
          // Late load (after timeout) is disposed in onAdLoaded via isCompleted.
          return null;
        });
      }, 'banner');

  @override
  Future<LoadedNative?> loadNative({required String adUnitId}) => _guard(() async {
        final c = Completer<LoadedNative?>();
        final ad = NativeAd(
          adUnitId: adUnitId,
          request: _request,
          listener: NativeAdListener(
            onAdLoaded: (a) {
              if (c.isCompleted) {
                a.dispose();
              } else {
                c.complete(_GoogleNative(a as NativeAd));
              }
            },
            onAdFailedToLoad: (a, err) {
              adLog('native failed: ${err.code} ${err.message}');
              a.dispose();
              if (!c.isCompleted) c.complete(null);
            },
          ),
          nativeTemplateStyle: NativeTemplateStyle(
            templateType: TemplateType.small,
            mainBackgroundColor: AppColors.card,
            cornerRadius: 12,
            callToActionTextStyle: NativeTemplateTextStyle(textColor: AppColors.white, backgroundColor: AppColors.pitch, size: 13),
            primaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.text, size: 15),
            secondaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.textSecondary, size: 13),
            tertiaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.textMuted, size: 12),
          ),
        );
        await ad.load();
        return c.future.timeout(loadTimeout, onTimeout: () => null);
      }, 'native');

  @override
  Future<FullScreenAd?> loadInterstitial({required String adUnitId}) => _guard(() async {
        final c = Completer<FullScreenAd?>();
        await InterstitialAd.load(
          adUnitId: adUnitId,
          request: _request,
          adLoadCallback: InterstitialAdLoadCallback(
            onAdLoaded: (ad) => c.isCompleted ? ad.dispose() : c.complete(_GoogleFullScreen.interstitial(ad)),
            onAdFailedToLoad: (err) {
              adLog('interstitial failed: ${err.code} ${err.message}');
              if (!c.isCompleted) c.complete(null);
            },
          ),
        );
        return c.future.timeout(loadTimeout, onTimeout: () => null);
      }, 'interstitial');

  @override
  Future<FullScreenAd?> loadAppOpen({required String adUnitId}) => _guard(() async {
        final c = Completer<FullScreenAd?>();
        await AppOpenAd.load(
          adUnitId: adUnitId,
          request: _request,
          adLoadCallback: AppOpenAdLoadCallback(
            onAdLoaded: (ad) => c.isCompleted ? ad.dispose() : c.complete(_GoogleFullScreen.appOpen(ad)),
            onAdFailedToLoad: (err) {
              adLog('app_open failed: ${err.code} ${err.message}');
              if (!c.isCompleted) c.complete(null);
            },
          ),
        );
        return c.future.timeout(loadTimeout, onTimeout: () => null);
      }, 'app_open');

  @override
  Future<FullScreenAd?> loadRewarded({required String adUnitId}) => _guard(() async {
        final c = Completer<FullScreenAd?>();
        await RewardedAd.load(
          adUnitId: adUnitId,
          request: _request,
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) => c.isCompleted ? ad.dispose() : c.complete(_GoogleFullScreen.rewarded(ad)),
            onAdFailedToLoad: (err) {
              adLog('rewarded failed: ${err.code} ${err.message}');
              if (!c.isCompleted) c.complete(null);
            },
          ),
        );
        return c.future.timeout(loadTimeout, onTimeout: () => null);
      }, 'rewarded');
}

class _GoogleBanner implements LoadedBanner {
  _GoogleBanner(this._ad, this.size);
  final BannerAd _ad;
  @override
  final Size size;
  bool _disposed = false;
  @override
  Widget build() => AdWidget(ad: _ad);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ad.dispose();
  }
}

class _GoogleNative implements LoadedNative {
  _GoogleNative(this._ad);
  final NativeAd _ad;
  bool _disposed = false;
  @override
  double get height => 110;
  @override
  Widget build() => AdWidget(ad: _ad);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ad.dispose();
  }
}

class _GoogleFullScreen implements FullScreenAd {
  _GoogleFullScreen.interstitial(InterstitialAd ad)
      : _ad = ad,
        _setCallback = ((done, fail) => ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
              onAdDismissedFullScreenContent: (_) => done(),
              onAdFailedToShowFullScreenContent: (_, e) => fail('${e.code} ${e.message}'),
            )),
        _show = ((_) => ad.show());
  _GoogleFullScreen.appOpen(AppOpenAd ad)
      : _ad = ad,
        _setCallback = ((done, fail) => ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
              onAdDismissedFullScreenContent: (_) => done(),
              onAdFailedToShowFullScreenContent: (_, e) => fail('${e.code} ${e.message}'),
            )),
        _show = ((_) => ad.show());
  _GoogleFullScreen.rewarded(RewardedAd ad)
      : _ad = ad,
        _setCallback = ((done, fail) => ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
              onAdDismissedFullScreenContent: (_) => done(),
              onAdFailedToShowFullScreenContent: (_, e) => fail('${e.code} ${e.message}'),
            )),
        _show = ((onReward) => ad.show(onUserEarnedReward: (_, _) => onReward?.call()));

  final AdWithoutView _ad;
  final void Function(VoidCallback done, void Function(String) fail) _setCallback;
  final Future<void> Function(VoidCallback? onReward) _show;
  bool _disposed = false;

  @override
  Future<bool> show({VoidCallback? onDismissed, VoidCallback? onReward}) async {
    if (_disposed) return false;
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      onDismissed?.call();
      dispose();
    }

    try {
      _setCallback(finish, (err) {
        adLog('show failed: $err');
        finish();
      });
      await _show(onReward);
      return true;
    } catch (e) {
      adLog('show failed: $e');
      finish();
      return false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _ad.dispose();
    } catch (_) {}
  }
}
