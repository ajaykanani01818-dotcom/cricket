import 'package:crickbex/features/ads/ads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ads_backend.dart';

void main() {
  late FakeAdsBackend backend;
  late FakeClock clock;
  final m = AdsManager.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAdsBackend();
    clock = FakeClock();
    m.debugReset(backend: backend, clock: clock.call);
  });

  tearDown(() => m.debugReset());

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('nothing touches the SDK before initialize()', () {
    m.recordDetailExit();
    m.tryShowAppOpenAd();
    expect(backend.calls, isEmpty);
    expect(m.adsReady.value, isFalse);
  });

  test('initialize: consent → init → preload interstitial + app open (idempotent)', () async {
    expect(await m.initialize(), isTrue);
    expect(await m.initialize(), isTrue);
    await settle();
    expect(backend.calls.take(2), ['consent', 'init']);
    expect(backend.calls.where((c) => c == 'init').length, 1);
    expect(backend.calls, containsAll(['interstitial', 'app_open']));
    expect(m.adsReady.value, isTrue);
  });

  test('master switch off → no SDK calls at all', () async {
    final cfg = AdsConfig.defaults()..masterEnabled = false;
    m.debugReset(backend: backend, clock: clock.call, config: cfg);
    expect(await m.initialize(), isFalse);
    expect(backend.calls, isEmpty);
  });

  test('consent that throws fails open', () async {
    backend.consentThrows = true;
    expect(await m.initialize(), isTrue);
  });

  test('init failure → ads not ready, widgets stay hidden', () async {
    backend.initOk = false;
    expect(await m.initialize(), isFalse);
    expect(m.adsReady.value, isFalse);
  });

  test('interstitial: shown on 2nd detail exit, re-preloaded after dismiss, 120s gap', () async {
    await m.initialize();
    await settle();
    m.recordDetailExit();
    await settle();
    expect(backend.interstitials.single.shows, 0);
    m.recordDetailExit();
    await settle();
    expect(backend.interstitials.first.shows, 1);
    expect(m.isFullScreenShowing, isTrue);
    backend.interstitials.first.dismiss();
    await settle();
    expect(m.isFullScreenShowing, isFalse);
    expect(backend.interstitials.length, 2, reason: 'next one preloaded');

    clock.advance(const Duration(seconds: 30));
    m.recordDetailExit();
    m.recordDetailExit();
    await settle();
    expect(backend.interstitials[1].shows, 0, reason: 'within 120s');
    clock.advance(const Duration(seconds: 90));
    m.recordDetailExit();
    m.recordDetailExit();
    await settle();
    expect(backend.interstitials[1].shows, 1);
  });

  test('interstitial: failed load is retried lazily on next exit, never crashes', () async {
    backend.failInterstitial = true;
    await m.initialize();
    await settle();
    m.recordDetailExit();
    m.recordDetailExit();
    await settle();
    expect(backend.calls.where((c) => c == 'interstitial').length, greaterThanOrEqualTo(2));
    expect(m.interstitialLoaded, isFalse);
  });

  test('no-ads reward window suppresses interstitial and app open', () async {
    await m.initialize();
    await settle();
    await m.grantNoAdsReward();
    m.recordDetailExit();
    m.recordDetailExit();
    m.markAppWentToBackground();
    m.tryShowAppOpenAd();
    await settle();
    expect(backend.interstitials.single.shows, 0);
    expect(backend.appOpens.single.shows, 0);
    clock.advance(const Duration(minutes: 31));
    // Exits during the window were not counted (RN returns early).
    m.recordDetailExit();
    m.recordDetailExit();
    await settle();
    expect(backend.interstitials.single.shows, 1);
  });

  test('app open: only on resume after background, 60s min interval', () async {
    await m.initialize();
    await settle();
    backend.fg.add(true); // resume without a background first (first launch)
    await settle();
    expect(backend.appOpens.single.shows, 0);

    backend.fg.add(false);
    backend.fg.add(true);
    await settle();
    expect(backend.appOpens.first.shows, 1);
    backend.appOpens.first.dismiss();
    await settle();
    expect(backend.appOpens.length, 2);

    clock.advance(const Duration(seconds: 30));
    backend.fg.add(false);
    backend.fg.add(true);
    await settle();
    expect(backend.appOpens[1].shows, 0);
    clock.advance(const Duration(seconds: 31));
    backend.fg.add(false);
    backend.fg.add(true);
    await settle();
    expect(backend.appOpens[1].shows, 1);
  });

  test('app open never stacks on top of an interstitial', () async {
    await m.initialize();
    await settle();
    m.recordDetailExit();
    m.recordDetailExit();
    await settle();
    expect(m.isFullScreenShowing, isTrue);
    backend.fg.add(false); // interstitial activity is not a real background
    backend.fg.add(true);
    await settle();
    expect(backend.appOpens.single.shows, 0);
    expect(m.appOpenPolicy.hasBeenInBackground, isFalse);
  });

  test('RewardedAdController: loads on tap, shows, grants 30 min no-ads', () async {
    await m.initialize();
    var rewarded = 0;
    final c = RewardedAdController('more_no_ads_30min', onReward: () {
      rewarded++;
      m.grantNoAdsReward();
    });
    expect(c.enabled, isTrue);
    expect(backend.calls.contains('rewarded'), isFalse, reason: 'no prefetch');
    await c.show();
    await settle();
    expect(backend.rewardeds.single.shows, 1);
    expect(rewarded, 1);
    expect(m.noAdsActive, isTrue);
    expect(m.noAds.untilMs, clock.now.add(const Duration(minutes: 30)).millisecondsSinceEpoch);
    c.dispose();
  });

  test('RewardedAdController: disabled placement / not ready → no-op', () async {
    final c = RewardedAdController('more_support', onReward: () => fail('no reward'));
    expect(c.enabled, isFalse);
    await c.show();
    expect(backend.calls, isEmpty);
    c.dispose();
  });

  test('RewardedAdController: failed load resets loading state', () async {
    backend.failRewarded = true;
    await m.initialize();
    final c = RewardedAdController('more_no_ads_30min', onReward: () => fail('no reward'));
    await c.show();
    expect(c.isLoading, isFalse);
    c.dispose();
  });
}
