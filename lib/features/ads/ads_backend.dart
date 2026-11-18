import 'package:flutter/widgets.dart';

/// Abstraction over the ad SDK so every SDK call is injectable: the app uses
/// [GoogleAdsBackend] (google_mobile_ads), tests use a fake or [NoopAdsBackend].
///
/// Contract: implementations NEVER throw — failures resolve to `false`/`null`.
abstract class AdsBackend {
  /// UMP consent (EEA/UK). Returns whether ads may be requested. Fails open.
  Future<bool> gatherConsent();

  /// Applies the request configuration and initializes the SDK.
  Future<bool> initialize({required List<String> testDeviceIds});

  /// Process-level foreground/background events (true = foreground).
  /// Must not fire when a full-screen ad activity covers the app.
  Stream<bool> foregroundStream();

  /// Loads an anchored-adaptive banner sized for [width] logical pixels.
  Future<LoadedBanner?> loadBanner({required String adUnitId, required int width, required Orientation orientation});

  /// Loads a native ad rendered with the SDK's native template.
  Future<LoadedNative?> loadNative({required String adUnitId});

  Future<FullScreenAd?> loadInterstitial({required String adUnitId});

  Future<FullScreenAd?> loadAppOpen({required String adUnitId});

  Future<FullScreenAd?> loadRewarded({required String adUnitId});
}

/// A loaded banner. [build] returns the platform ad view; call [dispose] once.
abstract class LoadedBanner {
  Size get size;
  Widget build();
  void dispose();
}

abstract class LoadedNative {
  double get height;
  Widget build();
  void dispose();
}

/// A loaded interstitial / app-open / rewarded ad. Single use.
abstract class FullScreenAd {
  /// Shows the ad. [onDismissed] runs when the ad closes or fails to show;
  /// [onReward] runs when a rewarded ad grants its reward.
  /// Returns false when the ad could not be presented.
  Future<bool> show({VoidCallback? onDismissed, VoidCallback? onReward});

  void dispose();
}

/// Does nothing — every load resolves to null.
class NoopAdsBackend implements AdsBackend {
  const NoopAdsBackend();
  @override
  Future<bool> gatherConsent() async => true;
  @override
  Future<bool> initialize({required List<String> testDeviceIds}) async => false;
  @override
  Stream<bool> foregroundStream() => const Stream.empty();
  @override
  Future<LoadedBanner?> loadBanner({required String adUnitId, required int width, required Orientation orientation}) async => null;
  @override
  Future<LoadedNative?> loadNative({required String adUnitId}) async => null;
  @override
  Future<FullScreenAd?> loadInterstitial({required String adUnitId}) async => null;
  @override
  Future<FullScreenAd?> loadAppOpen({required String adUnitId}) async => null;
  @override
  Future<FullScreenAd?> loadRewarded({required String adUnitId}) async => null;
}
