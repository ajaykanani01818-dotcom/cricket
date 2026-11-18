import 'dart:async';

import 'package:crickbex/features/ads/ads_backend.dart';
import 'package:flutter/widgets.dart';

class FakeBanner implements LoadedBanner {
  FakeBanner(this.id);
  final int id;
  bool disposed = false;
  @override
  Size get size => const Size(320, 50);
  @override
  Widget build() => SizedBox(key: ValueKey('fake_banner_$id'), width: 320, height: 50);
  @override
  void dispose() => disposed = true;
}

class FakeNative implements LoadedNative {
  bool disposed = false;
  @override
  double get height => 100;
  @override
  Widget build() => const SizedBox(key: ValueKey('fake_native'), height: 100);
  @override
  void dispose() => disposed = true;
}

class FakeFullScreen implements FullScreenAd {
  FakeFullScreen(this.kind, {this.grantReward = false});
  final String kind;
  final bool grantReward;
  int shows = 0;
  bool disposed = false;
  VoidCallback? _onDismissed;

  @override
  Future<bool> show({VoidCallback? onDismissed, VoidCallback? onReward}) async {
    shows++;
    _onDismissed = onDismissed;
    if (grantReward) onReward?.call();
    return true;
  }

  /// Simulates the user closing the ad.
  void dismiss() {
    final cb = _onDismissed;
    _onDismissed = null;
    cb?.call();
  }

  @override
  void dispose() => disposed = true;
}

/// Records every SDK call; loads succeed unless the matching `fail*` flag is set.
class FakeAdsBackend implements AdsBackend {
  bool consent = true;
  bool consentThrows = false;
  bool initOk = true;
  bool failBanner = false;
  bool failNative = false;
  bool failInterstitial = false;
  bool failAppOpen = false;
  bool failRewarded = false;
  bool rewardOnShow = true;

  final calls = <String>[];
  final banners = <FakeBanner>[];
  final natives = <FakeNative>[];
  final interstitials = <FakeFullScreen>[];
  final appOpens = <FakeFullScreen>[];
  final rewardeds = <FakeFullScreen>[];
  final fg = StreamController<bool>.broadcast(sync: true);

  /// When set, rewarded loads wait for this completer.
  Completer<void>? rewardedGate;

  @override
  Future<bool> gatherConsent() async {
    calls.add('consent');
    if (consentThrows) throw StateError('ump');
    return consent;
  }

  @override
  Future<bool> initialize({required List<String> testDeviceIds}) async {
    calls.add('init');
    return initOk;
  }

  @override
  Stream<bool> foregroundStream() => fg.stream;

  @override
  Future<LoadedBanner?> loadBanner({required String adUnitId, required int width, required Orientation orientation}) async {
    calls.add('banner:$adUnitId');
    if (failBanner) return null;
    final b = FakeBanner(banners.length);
    banners.add(b);
    return b;
  }

  @override
  Future<LoadedNative?> loadNative({required String adUnitId}) async {
    calls.add('native');
    if (failNative) return null;
    final n = FakeNative();
    natives.add(n);
    return n;
  }

  @override
  Future<FullScreenAd?> loadInterstitial({required String adUnitId}) async {
    calls.add('interstitial');
    if (failInterstitial) return null;
    final a = FakeFullScreen('interstitial');
    interstitials.add(a);
    return a;
  }

  @override
  Future<FullScreenAd?> loadAppOpen({required String adUnitId}) async {
    calls.add('app_open');
    if (failAppOpen) return null;
    final a = FakeFullScreen('app_open');
    appOpens.add(a);
    return a;
  }

  @override
  Future<FullScreenAd?> loadRewarded({required String adUnitId}) async {
    calls.add('rewarded');
    if (rewardedGate != null) await rewardedGate!.future;
    if (failRewarded) return null;
    final a = FakeFullScreen('rewarded', grantReward: rewardOnShow);
    rewardeds.add(a);
    return a;
  }
}

/// Mutable test clock.
class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime(2026, 1, 1, 12);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}
