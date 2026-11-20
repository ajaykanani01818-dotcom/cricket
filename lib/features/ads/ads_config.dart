import 'dart:convert';

/// Ads placement configuration — ported from RN `src/config/adsConfig.ts`.
///
/// Defaults are applied on startup; [AdsConfig.mergeRemoteJson] can merge an
/// override JSON string (same shape as RN) if one is ever provided.
///
/// Frequency caps follow the Flutter port brief (interstitial: 120s min gap,
/// 5 per session; app-open: 60s and only on resume-from-background; rewarded
/// "no ads": 30 min).

/// RN `BannerScreenName`.
const bannerScreens = <String>[
  'home',
  'matches',
  'match_detail',
  'series',
  'series_detail',
  'players',
  'player_detail',
  'ranking',
  'more',
  'legal',
];

/// RN `BannerPosition`.
const bannerPositions = <String>['top', 'middle', 'bottom'];

/// RN `NativePlacementKey`.
const nativePlacements = <String>[
  'home_feed',
  'player_detail_feed',
  'matches_list',
  'series_list',
  'series_detail',
  'match_detail',
];

/// RN `RewardedPlacementKey`.
const rewardedPlacements = <String>[
  'match_detail_scoreboard',
  'match_detail_scorecard',
  'match_detail_commentary',
  'match_detail_playing_xi',
  'player_detail_stats',
  'series_detail_points',
  'more_no_ads_30min',
  'more_support',
];

class BannerPlacement {
  BannerPlacement({required this.enabled, required this.positions});
  bool enabled;
  List<String> positions;
}

class InterstitialConfig {
  InterstitialConfig({
    this.enabled = true,
    this.minSecondsBetweenAds = 120,
    this.detailExitsBeforeShow = 2,
    this.maxPerSession = 5,
  });
  bool enabled;
  int minSecondsBetweenAds;
  int detailExitsBeforeShow;
  int maxPerSession;
}

class RewardedPlacement {
  RewardedPlacement({required this.enabled, required this.label});
  bool enabled;
  String label;
}

class NativePlacement {
  NativePlacement({required this.enabled, required this.interval});
  bool enabled;
  int interval;
}

class AppOpenConfig {
  AppOpenConfig({this.enabled = true, this.minIntervalSeconds = 60});

  /// Only fires on resume-from-background, never on first launch.
  bool enabled;
  int minIntervalSeconds;
}

class AdsConfig {
  AdsConfig._();

  /// Fresh copy of the RN defaults.
  factory AdsConfig.defaults() {
    final c = AdsConfig._();
    for (final s in bannerScreens) {
      c.bannerPlacement[s] = BannerPlacement(enabled: true, positions: ['top', 'bottom']);
    }
    c.rewardedPlacement.addAll({
      'match_detail_scoreboard': RewardedPlacement(enabled: true, label: 'Watch ad to view full scoreboard'),
      'match_detail_scorecard': RewardedPlacement(enabled: false, label: 'Watch ad to view full scorecard'),
      'match_detail_commentary': RewardedPlacement(enabled: false, label: 'Watch ad to see ball-by-ball'),
      'match_detail_playing_xi': RewardedPlacement(enabled: true, label: 'Watch ad to view Playing XI'),
      'player_detail_stats': RewardedPlacement(enabled: false, label: 'Watch ad to see full career stats'),
      'series_detail_points': RewardedPlacement(enabled: false, label: 'Watch ad to view full points table'),
      'more_no_ads_30min': RewardedPlacement(enabled: true, label: 'Watch ad – no ads for 30 min'),
      'more_support': RewardedPlacement(enabled: false, label: 'Watch an ad to support us'),
    });
    c.nativePlacement.addAll({
      'home_feed': NativePlacement(enabled: true, interval: 1),
      'player_detail_feed': NativePlacement(enabled: true, interval: 1),
      'matches_list': NativePlacement(enabled: true, interval: 3),
      'series_list': NativePlacement(enabled: true, interval: 3),
      'series_detail': NativePlacement(enabled: true, interval: 3),
      'match_detail': NativePlacement(enabled: true, interval: 4),
    });
    return c;
  }

  /// When false: no AdMob init, no ad requests.
  /// TEMPORARILY DISABLED: all ads off until the owner asks to re-enable.
  /// Remote config cannot turn this back on while [adsHardDisabled] is true.
  /// A plain static (not const) only so tests can switch it off; the
  /// production value stays true.
  static bool adsHardDisabled = true;
  bool masterEnabled = !adsHardDisabled;

  bool bannerEnabled = true;
  int bannerRefreshSeconds = 30;
  final Map<String, BannerPlacement> bannerPlacement = {};

  final InterstitialConfig interstitial = InterstitialConfig();

  bool rewardedEnabled = true;
  int rewardDurationMinutes = 30;
  final Map<String, RewardedPlacement> rewardedPlacement = {};

  bool nativeEnabled = true;
  final Map<String, NativePlacement> nativePlacement = {};

  final AppOpenConfig appOpen = AppOpenConfig();

  // ---- getters (same names/semantics as RN) ----

  bool isBannerEnabled(String screen) {
    final p = bannerPlacement[screen];
    return masterEnabled && bannerEnabled && (p?.enabled ?? false);
  }

  List<String> bannerPositionsFor(String screen) => bannerPlacement[screen]?.positions ?? const ['bottom'];

  bool isBannerPositionEnabled(String screen, String position) =>
      isBannerEnabled(screen) && bannerPositionsFor(screen).contains(position);

  bool isRewardedEnabled(String key) => masterEnabled && rewardedEnabled && (rewardedPlacement[key]?.enabled ?? false);

  String rewardedLabel(String key) {
    final l = rewardedPlacement[key]?.label ?? '';
    return l.isEmpty ? 'Watch ad' : l;
  }

  bool isNativeEnabled(String placement) => masterEnabled && nativeEnabled && (nativePlacement[placement]?.enabled ?? false);

  int nativeInterval(String placement) => nativePlacement[placement]?.interval ?? 5;

  bool get isInterstitialEnabled => masterEnabled && interstitial.enabled;

  bool get isAppOpenEnabled => masterEnabled && appOpen.enabled;

  // ---- remote merge (RN setAdsConfigFromRemote) ----

  static List<String> _parsePositions(Object? raw) {
    if (raw is! List) return const ['bottom'];
    final out = raw.whereType<String>().where(bannerPositions.contains).toList();
    return out.isEmpty ? const ['bottom'] : out;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  /// Merges a JSON override over the current values. Returns false when the
  /// string is not a JSON object (config left untouched).
  bool mergeRemoteJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return false;
    Object? parsed;
    try {
      parsed = jsonDecode(jsonString);
    } catch (_) {
      return false;
    }
    if (parsed is! Map) return false;
    final src = parsed;

    if (!adsHardDisabled && src['ads_master_enabled'] is bool) masterEnabled = src['ads_master_enabled'] as bool;

    final b = src['banner'];
    if (b is Map) {
      if (b['enabled'] is bool) bannerEnabled = b['enabled'] as bool;
      final r = _int(b['refresh_seconds']);
      if (r != null && r > 0) bannerRefreshSeconds = r;
      final pl = b['placement'];
      if (pl is Map) {
        for (final s in bannerPlacement.keys) {
          final p = pl[s];
          if (p is Map) {
            if (p['enabled'] is bool) bannerPlacement[s]!.enabled = p['enabled'] as bool;
            if (p.containsKey('position')) bannerPlacement[s]!.positions = _parsePositions(p['position']);
          }
        }
      }
    }

    final i = src['interstitial'];
    if (i is Map) {
      if (i['enabled'] is bool) interstitial.enabled = i['enabled'] as bool;
      interstitial.minSecondsBetweenAds = _int(i['min_seconds_between_ads']) ?? interstitial.minSecondsBetweenAds;
      interstitial.detailExitsBeforeShow = _int(i['detail_exits_before_show']) ?? interstitial.detailExitsBeforeShow;
      interstitial.maxPerSession = _int(i['max_per_session']) ?? interstitial.maxPerSession;
    }

    final r = src['rewarded'];
    if (r is Map) {
      if (r['enabled'] is bool) rewardedEnabled = r['enabled'] as bool;
      rewardDurationMinutes = _int(r['reward_duration_minutes']) ?? rewardDurationMinutes;
      final pl = r['placement'];
      if (pl is Map) {
        for (final k in rewardedPlacement.keys) {
          final p = pl[k];
          if (p is Map) {
            if (p['enabled'] is bool) rewardedPlacement[k]!.enabled = p['enabled'] as bool;
            final label = p['label'];
            if (label is String && label.trim().isNotEmpty) rewardedPlacement[k]!.label = label.trim();
          }
        }
      }
    }

    final n = src['native'];
    if (n is Map) {
      if (n['enabled'] is bool) nativeEnabled = n['enabled'] as bool;
      final pl = n['placement'];
      if (pl is Map) {
        for (final k in nativePlacement.keys) {
          final p = pl[k];
          if (p is Map) {
            if (p['enabled'] is bool) nativePlacement[k]!.enabled = p['enabled'] as bool;
            final iv = _int(p['interval']);
            if (iv != null && iv > 0) nativePlacement[k]!.interval = iv;
          }
        }
      }
    }

    final ao = src['app_open'];
    if (ao is Map) {
      if (ao['enabled'] is bool) appOpen.enabled = ao['enabled'] as bool;
      final m = _int(ao['min_interval_seconds']);
      if (m != null && m > 0) appOpen.minIntervalSeconds = m;
    }
    return true;
  }
}
