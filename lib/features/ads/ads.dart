/// Public ads API (google_mobile_ads port of RN components/ads + services/ads).
///
/// screen names (BannerScreenName): home, matches, series, series_detail, ranking,
/// players, player_detail, match_detail, more, legal
/// positions (BannerPosition): top, middle, bottom
/// native placements: home_feed, matches_list, match_detail, series_list,
/// series_detail, player_detail_feed
///
/// - `ScreenBannerSlots(screen:, onlyPosition:, fullBleed:)` — inline banner slot(s).
/// - `FixedBottomBanner(screen:)` — banner pinned above the tab bar.
/// - `ListNativeAd(placement:)` — native ad row inside a list.
/// - `AdsManager.instance.initialize()` — once, after the first frame.
/// - `AdsManager.instance.recordDetailExit()` — from a detail screen's dispose().
///
/// Every widget renders `SizedBox.shrink()` until [AdsManager.initialize]
/// succeeds (so tests never touch the ad SDK), and collapses on no fill.
library;

export 'ad_unit_ids.dart' show AdMode, adMode, isUsingTestAds;
export 'ad_widgets.dart' show ScreenBannerSlots, FixedBottomBanner, ListNativeAd, ScreenBannerAd, kFixedBottomReserve;
export 'ads_config.dart' show AdsConfig;
export 'ads_manager.dart' show AdsManager;
export 'rewarded_ad_controller.dart' show RewardedAdController;
