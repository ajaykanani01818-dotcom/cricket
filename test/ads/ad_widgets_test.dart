import 'package:crickbex/features/ads/ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ads_backend.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Column(children: [child, const Expanded(child: SizedBox())])));

void main() {
  late FakeAdsBackend backend;
  final m = AdsManager.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAdsBackend();
  });
  tearDown(() => m.debugReset());

  group('not initialized (default in tests)', () {
    setUp(() => m.debugReset());

    testWidgets('every ad widget renders SizedBox.shrink and never calls the SDK', (tester) async {
      m.debugReset(backend: backend);
      await tester.pumpWidget(_host(const Column(children: [
        ScreenBannerSlots(screen: 'home'),
        ScreenBannerSlots(screen: 'legal', onlyPosition: 'top', fullBleed: true),
        ListNativeAd(placement: 'home_feed'),
      ])));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ScreenBannerAd), findsNothing);
      expect(tester.getSize(find.byType(ScreenBannerSlots).first), Size.zero);
      expect(tester.getSize(find.byType(ListNativeAd)), Size.zero);
      expect(backend.calls, isEmpty);
    });

    testWidgets('FixedBottomBanner in a Stack renders nothing', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Stack(children: [FixedBottomBanner(screen: 'more')]))));
      expect(find.byType(ScreenBannerAd), findsNothing);
      expect(tester.getSize(find.byType(FixedBottomBanner)), Size.zero);
    });
  });

  group('ads ready (fake SDK)', () {
    setUp(() => m.debugReset(backend: backend, ready: true));

    testWidgets('banner loads and shows; disposed with the widget', (tester) async {
      await tester.pumpWidget(_host(const ScreenBannerSlots(screen: 'home', onlyPosition: 'top')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('fake_banner_0')), findsOneWidget);
      expect(backend.calls.first, startsWith('banner:'));
      await tester.pumpWidget(_host(const SizedBox()));
      expect(backend.banners.single.disposed, isTrue);
    });

    testWidgets('no fill → slot collapses to zero height', (tester) async {
      backend.failBanner = true;
      await tester.pumpWidget(_host(const ScreenBannerSlots(screen: 'home', onlyPosition: 'top')));
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(find.byType(ScreenBannerAd)).height, 0);
    });

    testWidgets('both positions when onlyPosition is omitted', (tester) async {
      await tester.pumpWidget(_host(const ScreenBannerSlots(screen: 'matches')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ScreenBannerAd), findsNWidgets(2));
    });

    testWidgets('disabled placement / unknown screen renders nothing', (tester) async {
      m.config.bannerPlacement['home']!.enabled = false;
      await tester.pumpWidget(_host(const Column(children: [ScreenBannerSlots(screen: 'home'), ScreenBannerSlots(screen: 'nope')])));
      await tester.pump();
      expect(find.byType(ScreenBannerAd), findsNothing);
      expect(backend.calls, isEmpty);
    });

    testWidgets('refreshes every 30s, keeping the old ad until the new one loads', (tester) async {
      await tester.pumpWidget(_host(const ScreenBannerSlots(screen: 'home', onlyPosition: 'top')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.byKey(const ValueKey('fake_banner_1')), findsOneWidget);
      expect(backend.banners.first.disposed, isTrue);
      await tester.pumpWidget(_host(const SizedBox()));
    });

    testWidgets('FixedBottomBanner shows the bottom banner', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Stack(children: [FixedBottomBanner(screen: 'more')]))));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('ads_banner_more_bottom')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('regression: loaded FixedBottomBanner in a Stack only covers its own height', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(child: GestureDetector(key: const ValueKey('content'), onTap: () => taps++, child: const ColoredBox(color: Color(0xFF00FF00)))),
            const FixedBottomBanner(screen: 'more'),
          ]),
        ),
      ));
      await tester.pump();
      await tester.pump();
      final h = tester.getSize(find.byKey(const ValueKey('ads_banner_more_bottom'))).height;
      expect(h, 50 + 12);
      await tester.tapAt(const Offset(400, 100));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('native ad: reserve while loading, card when loaded, collapse on failure', (tester) async {
      await tester.pumpWidget(_host(const ListNativeAd(placement: 'home_feed')));
      expect(find.byKey(const ValueKey('ads_native_reserve_home_feed')), findsOneWidget);
      await tester.pump();
      expect(find.byKey(const ValueKey('fake_native')), findsOneWidget);
      expect(find.text('Sponsored'), findsOneWidget);
      await tester.pumpWidget(_host(const SizedBox()));
      expect(backend.natives.single.disposed, isTrue);

      backend.failNative = true;
      await tester.pumpWidget(_host(const ListNativeAd(placement: 'matches_list')));
      await tester.pump();
      expect(tester.getSize(find.byType(ListNativeAd)), Size.zero);
    });

    testWidgets('no-ads reward hides banners and natives', (tester) async {
      await m.noAds.grant(const Duration(minutes: 30));
      await tester.pumpWidget(_host(const Column(children: [ScreenBannerSlots(screen: 'home'), ListNativeAd(placement: 'home_feed')])));
      await tester.pump();
      expect(find.byKey(const ValueKey('fake_native')), findsNothing);
      expect(find.byType(ScreenBannerAd), findsNWidgets(2));
      expect(tester.getSize(find.byType(ListNativeAd)), Size.zero);
      expect(backend.calls, isEmpty);
      await m.noAds.clear();
      m.noAds.dispose();
    });
  });
}
