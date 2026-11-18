import 'package:flutter/foundation.dart';

import 'ads_manager.dart';

/// Rewarded ad for one placement — ported from RN `useRewardedAd`.
///
/// No network request until the user calls [show]: the first tap starts the
/// load and the ad is presented as soon as it loads. Dispose with the widget.
class RewardedAdController extends ChangeNotifier {
  RewardedAdController(this.placement, {required this.onReward, AdsManager? manager})
      : _manager = manager ?? AdsManager.instance;

  final String placement;
  final VoidCallback onReward;
  final AdsManager _manager;

  bool _loading = false;
  bool _disposed = false;

  bool get isLoading => _loading;

  /// RN: `isAdsMasterEnabled() && config.enabled`, plus the SDK must be ready
  /// so the row never shows when ads can't load (e.g. tests, init failed).
  bool get enabled => _manager.adsReady.value && _manager.config.isRewardedEnabled(placement);

  String get label => _manager.config.rewardedLabel(placement);

  void _set(bool loading) {
    if (_disposed || _loading == loading) return;
    _loading = loading;
    notifyListeners();
  }

  Future<void> show() async {
    if (!enabled || _loading || _manager.isFullScreenShowing) return;
    _set(true);
    try {
      final ad = await _manager.backend.loadRewarded(adUnitId: _manager.ids.rewarded);
      if (ad == null) {
        _set(false);
        return;
      }
      if (_disposed) {
        ad.dispose();
        return;
      }
      _set(false);
      await _manager.showRewarded(ad, onReward: () {
        try {
          onReward();
        } catch (_) {}
      });
    } catch (_) {
      _set(false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
