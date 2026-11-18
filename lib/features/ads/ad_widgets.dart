import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'ads_backend.dart';
import 'ads_manager.dart';

/// Approximate adaptive banner height — reserve this at the bottom of scroll
/// content on screens with a [FixedBottomBanner] (RN FIXED_BOTTOM_RESERVE).
const double kFixedBottomReserve = 60;

/// Listens to everything that decides whether an ad may render.
Listenable _adsListenable(AdsManager m) => Listenable.merge([m.adsReady, m.noAds.active]);

/// Config-driven banner for one screen + position (RN `ScreenBannerAd`).
///
/// Renders nothing until the SDK is ready; reserves the banner footprint while
/// loading so the layout does not jump; collapses to zero height on no fill.
class ScreenBannerAd extends StatefulWidget {
  const ScreenBannerAd({super.key, required this.screen, required this.position, this.fullBleed = false, this.manager});
  final String screen;
  final String position;
  final bool fullBleed;
  final AdsManager? manager;

  @override
  State<ScreenBannerAd> createState() => _ScreenBannerAdState();
}

class _ScreenBannerAdState extends State<ScreenBannerAd> {
  AdsManager get _m => widget.manager ?? AdsManager.instance;
  LoadedBanner? _banner;
  bool _loading = false;
  bool _failed = false;
  bool _disposed = false;
  Timer? _refresh;
  late final Listenable _listenable = _adsListenable(_m);

  bool get _shouldShow =>
      _m.adsReady.value && !_m.noAds.isActiveSync && _m.config.isBannerPositionEnabled(widget.screen, widget.position);

  @override
  void initState() {
    super.initState();
    _listenable.addListener(_onAdsState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAdsState());
  }

  void _onAdsState() {
    if (_disposed) return;
    if (_shouldShow) {
      if (_banner == null && !_loading && !_failed) _load();
      _startRefresh();
    } else {
      _refresh?.cancel();
    }
    if (mounted) setState(() {});
  }

  void _startRefresh() {
    final secs = _m.config.bannerRefreshSeconds;
    if (_refresh != null || secs <= 0) return;
    _refresh = Timer.periodic(Duration(seconds: secs), (_) {
      if (_disposed || !mounted || !_shouldShow) return;
      // Skip while offstage (inactive tab) or backgrounded.
      if (!TickerMode.valuesOf(context).enabled) return;
      final life = WidgetsBinding.instance.lifecycleState;
      if (life != null && life != AppLifecycleState.resumed) return;
      _load(refresh: true);
    });
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading || !mounted) return;
    _loading = true;
    final pad = widget.fullBleed ? 0.0 : 16.0;
    final width = (MediaQuery.sizeOf(context).width - pad).floor().clamp(32, 4000);
    final orientation = MediaQuery.orientationOf(context);
    LoadedBanner? next;
    try {
      next = await _m.backend.loadBanner(adUnitId: _m.ids.adaptiveBanner, width: width, orientation: orientation);
    } catch (_) {
      next = null;
    }
    _loading = false;
    if (_disposed || !mounted) {
      next?.dispose();
      return;
    }
    if (next == null) {
      // A failed refresh keeps the current ad; a failed first load collapses.
      if (!refresh) setState(() => _failed = true);
      return;
    }
    final old = _banner;
    setState(() {
      _banner = next;
      _failed = false;
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _listenable.removeListener(_onAdsState);
    _refresh?.cancel();
    _banner?.dispose();
    _banner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow || _failed) return const SizedBox.shrink();
    final banner = _banner;
    if (banner == null) {
      // Reserve ~adaptive banner height while loading (RN slot reserve).
      return SizedBox(
        key: ValueKey('ads_banner_reserve_${widget.screen}_${widget.position}'),
        height: widget.fullBleed ? 56 : 52 + 12,
        width: double.infinity,
        child: ColoredBox(color: widget.fullBleed ? Colors.transparent : AppColors.white),
      );
    }
    return Container(
      key: ValueKey('ads_banner_${widget.screen}_${widget.position}'),
      width: double.infinity,
      color: widget.fullBleed ? null : AppColors.white,
      padding: widget.fullBleed ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      // heightFactor: 1 → the slot is exactly the banner's height (an
      // unbounded `alignment` would fill a Stack and cover the screen).
      child: Center(
        heightFactor: 1,
        child: SizedBox(width: banner.size.width, height: banner.size.height, child: banner.build()),
      ),
    );
  }
}

/// Inline banner slot(s) for a screen (RN `ScreenBannerSlots`). With
/// [onlyPosition] renders that slot only; otherwise every configured position.
class ScreenBannerSlots extends StatelessWidget {
  const ScreenBannerSlots({super.key, required this.screen, this.onlyPosition, this.fullBleed = false});
  final String screen;
  final String? onlyPosition;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    final m = AdsManager.instance;
    return ListenableBuilder(
      listenable: m.adsReady,
      builder: (context, _) {
        if (!m.adsReady.value || !m.config.isBannerEnabled(screen)) return const SizedBox.shrink();
        final positions = onlyPosition != null ? [onlyPosition!] : m.config.bannerPositionsFor(screen);
        if (positions.length == 1) {
          return ScreenBannerAd(key: ValueKey('${screen}_${positions.first}'), screen: screen, position: positions.first, fullBleed: fullBleed);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in positions) ScreenBannerAd(key: ValueKey('${screen}_$p'), screen: screen, position: p, fullBleed: fullBleed),
        ]);
      },
    );
  }
}

/// Banner pinned to the bottom of the screen, just above the floating tab bar
/// (RN `FixedBottomBanner`). Works as the last child of a `Stack` or `Column`:
/// it aligns itself to the bottom and lifts itself by
/// `MediaQuery.paddingOf(context).bottom` (the shell's tab-bar inset).
/// Renders nothing when there is no ad.
class FixedBottomBanner extends StatelessWidget {
  const FixedBottomBanner({super.key, required this.screen});
  final String screen;

  @override
  Widget build(BuildContext context) {
    final m = AdsManager.instance;
    return ListenableBuilder(
      listenable: m.adsReady,
      builder: (context, _) {
        if (!m.adsReady.value || !m.config.isBannerPositionEnabled(screen, 'bottom')) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: ScreenBannerAd(screen: screen, position: 'bottom'),
          ),
        );
      },
    );
  }
}

/// Native ad row inside a list (RN `ListNativeAd`), rendered with the SDK's
/// small native template inside a "Sponsored" card.
class ListNativeAd extends StatefulWidget {
  const ListNativeAd({super.key, required this.placement, this.manager});
  final String placement;
  final AdsManager? manager;

  @override
  State<ListNativeAd> createState() => _ListNativeAdState();
}

class _ListNativeAdState extends State<ListNativeAd> {
  AdsManager get _m => widget.manager ?? AdsManager.instance;
  LoadedNative? _ad;
  bool _loading = false;
  bool _failed = false;
  bool _disposed = false;
  late final Listenable _listenable = _adsListenable(_m);

  bool get _shouldShow => _m.adsReady.value && !_m.noAds.isActiveSync && _m.config.isNativeEnabled(widget.placement);

  @override
  void initState() {
    super.initState();
    _listenable.addListener(_onAdsState);
    if (_shouldShow) _load();
  }

  void _onAdsState() {
    if (_disposed) return;
    if (_shouldShow && _ad == null && !_loading && !_failed) _load();
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    _loading = true;
    LoadedNative? ad;
    try {
      ad = await _m.backend.loadNative(adUnitId: _m.ids.native);
    } catch (_) {
      ad = null;
    }
    _loading = false;
    if (_disposed || !mounted) {
      ad?.dispose();
      return;
    }
    setState(() {
      _ad = ad;
      _failed = ad == null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _listenable.removeListener(_onAdsState);
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow || _failed) return const SizedBox.shrink();
    final ad = _ad;
    if (ad == null) {
      // Same outer footprint as a loaded card — no spinner, avoids list jump.
      return Container(
        key: ValueKey('ads_native_reserve_${widget.placement}'),
        margin: const EdgeInsets.symmetric(vertical: 12),
        height: 120,
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(18)),
      );
    }
    return Container(
      key: ValueKey('ads_native_${widget.placement}'),
      margin: const EdgeInsets.symmetric(vertical: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x1A0860C4), blurRadius: 12, offset: Offset(0, 5))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 4,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.pitchLight, AppColors.pitch])),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.pitch.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.pitch.withValues(alpha: 0.17)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.campaign_outlined, size: 12, color: AppColors.pitch),
                SizedBox(width: 5),
                Text('Sponsored', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.pitch, letterSpacing: 0.3)),
              ]),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(Radii.full),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: const Text('Ad', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: SizedBox(height: ad.height, child: ad.build()),
        ),
      ]),
    );
  }
}
