import 'package:crickbex/features/ads/ad_unit_ids.dart';
import 'package:crickbex/features/ads/ads_config.dart';
import 'package:crickbex/features/ads/ads_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ads_backend.dart';

void main() {
  group('InterstitialPolicy', () {
    test('defaults: 2 exits, 120s gap, 5 per session', () {
      final c = AdsConfig.defaults().interstitial;
      expect(c.detailExitsBeforeShow, 2);
      expect(c.minSecondsBetweenAds, 120);
      expect(c.maxPerSession, 5);
    });

    test('shows on the 2nd detail exit, then resets the exit count', () {
      final p = InterstitialPolicy(InterstitialConfig());
      final t = DateTime(2026);
      expect(p.onDetailExit(t), isFalse);
      expect(p.onDetailExit(t), isTrue);
      expect(p.detailExitCount, 0);
      expect(p.sessionShowCount, 1);
    });

    test('respects the 120s minimum gap', () {
      final p = InterstitialPolicy(InterstitialConfig());
      var t = DateTime(2026);
      p.onDetailExit(t);
      expect(p.onDetailExit(t), isTrue);
      t = t.add(const Duration(seconds: 60));
      p.onDetailExit(t);
      expect(p.onDetailExit(t), isFalse, reason: 'only 60s since last show');
      t = t.add(const Duration(seconds: 60));
      expect(p.onDetailExit(t), isTrue, reason: 'exactly 120s → allowed');
    });

    test('caps at 5 per session', () {
      final p = InterstitialPolicy(InterstitialConfig());
      var t = DateTime(2026);
      var shown = 0;
      for (var i = 0; i < 40; i++) {
        if (p.onDetailExit(t)) shown++;
        t = t.add(const Duration(minutes: 3));
      }
      expect(shown, 5);
    });
  });

  group('AppOpenPolicy', () {
    test('never on first launch (no background yet)', () {
      final p = AppOpenPolicy(AppOpenConfig());
      expect(p.onResume(DateTime(2026)), isFalse);
    });

    test('after background, then 60s min interval', () {
      final p = AppOpenPolicy(AppOpenConfig());
      var t = DateTime(2026);
      p.markWentToBackground();
      expect(p.onResume(t), isTrue);
      t = t.add(const Duration(seconds: 59));
      expect(p.onResume(t), isFalse);
      t = t.add(const Duration(seconds: 1));
      expect(p.onResume(t), isTrue);
    });
  });

  group('NoAdsStore (reward expiry)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('grant activates for 30 min, then expires via timer', (tester) async {
      final clock = FakeClock();
      final store = NoAdsStore(clock: clock.call);
      await store.grant(const Duration(minutes: 30));
      expect(store.isActiveSync, isTrue);
      expect(store.active.value, isTrue);
      clock.advance(const Duration(minutes: 29, seconds: 59));
      expect(store.isActiveSync, isTrue);
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(minutes: 30));
      expect(store.isActiveSync, isFalse);
      expect(store.active.value, isFalse);
      store.dispose();
    });

    test('persists and refresh() restores an active window', () async {
      final clock = FakeClock();
      final a = NoAdsStore(clock: clock.call);
      await a.grant(const Duration(minutes: 30));
      a.dispose();
      final b = NoAdsStore(clock: clock.call);
      expect(await b.refresh(), isTrue);
      b.dispose();
    });

    test('refresh() clears an expired window from storage', () async {
      final clock = FakeClock();
      SharedPreferences.setMockInitialValues({NoAdsStore.prefsKey: clock.now.millisecondsSinceEpoch - 1000});
      final s = NoAdsStore(clock: clock.call);
      expect(await s.refresh(), isFalse);
      expect((await SharedPreferences.getInstance()).containsKey(NoAdsStore.prefsKey), isFalse);
      s.dispose();
    });

    test('malformed stored value is ignored', () async {
      SharedPreferences.setMockInitialValues({NoAdsStore.prefsKey: 'not-a-number'});
      final s = NoAdsStore(clock: FakeClock().call);
      expect(await s.refresh(), isFalse);
      s.dispose();
    });

    test('clear() deactivates', () async {
      final s = NoAdsStore(clock: FakeClock().call);
      await s.grant(const Duration(minutes: 30));
      await s.clear();
      expect(s.isActiveSync, isFalse);
      s.dispose();
    });
  });

  group('AdsConfig', () {
    test('defaults match RN placements', () {
      final c = AdsConfig.defaults();
      for (final s in bannerScreens) {
        expect(c.isBannerPositionEnabled(s, 'top'), isTrue);
        expect(c.isBannerPositionEnabled(s, 'bottom'), isTrue);
        expect(c.isBannerPositionEnabled(s, 'middle'), isFalse);
      }
      expect(c.isBannerEnabled('unknown_screen'), isFalse);
      expect(c.isRewardedEnabled('more_no_ads_30min'), isTrue);
      expect(c.isRewardedEnabled('more_support'), isFalse);
      expect(c.rewardedLabel('more_no_ads_30min'), 'Watch ad – no ads for 30 min');
      expect(c.rewardedLabel('nope'), 'Watch ad');
      expect(c.isNativeEnabled('home_feed'), isTrue);
      expect(c.nativeInterval('match_detail'), 4);
      expect(c.rewardDurationMinutes, 30);
      expect(c.appOpen.minIntervalSeconds, 60);
    });

    test('master switch disables everything', () {
      final c = AdsConfig.defaults()..masterEnabled = false;
      expect(c.isBannerEnabled('home'), isFalse);
      expect(c.isNativeEnabled('home_feed'), isFalse);
      expect(c.isRewardedEnabled('more_no_ads_30min'), isFalse);
      expect(c.isInterstitialEnabled, isFalse);
      expect(c.isAppOpenEnabled, isFalse);
    });

    test('mergeRemoteJson: malformed input is rejected and leaves config intact', () {
      final c = AdsConfig.defaults();
      expect(c.mergeRemoteJson(null), isFalse);
      expect(c.mergeRemoteJson(''), isFalse);
      expect(c.mergeRemoteJson('{not json'), isFalse);
      expect(c.mergeRemoteJson('[1,2]'), isFalse);
      expect(c.masterEnabled, isTrue);
    });

    test('mergeRemoteJson: merges known keys, ignores wrong types', () {
      final c = AdsConfig.defaults();
      expect(
          c.mergeRemoteJson('{"ads_master_enabled": true, "banner": {"refresh_seconds": -5, "placement": {"home": {"position": ["bogus"]}, "more": {"enabled": false}}},'
              '"interstitial": {"max_per_session": 3, "enabled": "yes"}, "native": {"placement": {"home_feed": {"interval": 0}}},'
              '"rewarded": {"placement": {"more_no_ads_30min": {"label": "  Free 30 min  "}}}, "app_open": {"min_interval_seconds": 90}}'),
          isTrue);
      expect(c.bannerRefreshSeconds, 30, reason: 'non-positive refresh ignored');
      expect(c.bannerPositionsFor('home'), ['bottom'], reason: 'invalid positions → bottom');
      expect(c.isBannerEnabled('more'), isFalse);
      expect(c.interstitial.maxPerSession, 3);
      expect(c.interstitial.enabled, isTrue);
      expect(c.nativeInterval('home_feed'), 1);
      expect(c.rewardedLabel('more_no_ads_30min'), 'Free 30 min');
      expect(c.appOpen.minIntervalSeconds, 90);
    });
  });

  group('Ad unit ids', () {
    test('debug builds use Google test ids', () {
      final ids = resolveAdUnitIds(isRelease: false, platform: TargetPlatform.android);
      expect(ids.interstitial, 'ca-app-pub-3940256099942544/1033173712');
      expect(isUsingTestAds(isRelease: false, platform: TargetPlatform.android), isTrue);
    });

    test('release builds use RN live ids on Android', () {
      final ids = resolveAdUnitIds(isRelease: true, platform: TargetPlatform.android);
      expect(ids.banner, 'ca-app-pub-4606250338441432/3202539485');
      expect(ids.adaptiveBanner, 'ca-app-pub-4606250338441432/3202539485');
      expect(ids.interstitial, 'ca-app-pub-4606250338441432/7645076321');
      expect(ids.rewarded, 'ca-app-pub-4606250338441432/5524666677');
      expect(ids.native, 'ca-app-pub-4606250338441432/6467726026');
      expect(ids.appOpen, 'ca-app-pub-4606250338441432/7472173165');
    });

    test('release on iOS (no live ids) falls back to test ids', () {
      expect(isUsingTestAds(isRelease: true, platform: TargetPlatform.iOS), isTrue);
      expect(resolveAdUnitIds(isRelease: true, platform: TargetPlatform.iOS).banner, 'ca-app-pub-3940256099942544/2934735716');
    });

    test('per-key fallback for empty/malformed live ids; adaptive reuses banner', () {
      const live = AdUnitIds(
          banner: 'ca-app-pub-1/2', adaptiveBanner: 'XXXX', interstitial: '', rewarded: 'ca-app-pub-1/3', native: ' ', appOpen: 'bad');
      final ids = resolveAdUnitIds(isRelease: true, platform: TargetPlatform.android, live: live);
      expect(ids.banner, 'ca-app-pub-1/2');
      expect(ids.adaptiveBanner, 'ca-app-pub-1/2');
      expect(ids.interstitial, 'ca-app-pub-3940256099942544/1033173712');
      expect(ids.rewarded, 'ca-app-pub-1/3');
      expect(ids.native, 'ca-app-pub-3940256099942544/2247696110');
    });

    test('forced modes', () {
      expect(isUsingTestAds(mode: AdMode.test, isRelease: true), isTrue);
      expect(isUsingTestAds(mode: AdMode.live, isRelease: false), isFalse);
      expect(isValidAdUnitId('ca-app-pub-123~456'), isFalse);
    });
  });
}
