import 'package:flutter/material.dart';

import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../review/review_controller.dart';
import 'legal_layout.dart';

const feedbackEmail = 'crickbex@gmail.com';

/// `mailto:` with a %20-encoded subject (mail apps show '+' literally).
Uri feedbackMailUri() => Uri.parse('mailto:$feedbackEmail?subject=${Uri.encodeComponent('CrickBex Feedback')}');

/// Guards against double taps pushing the same page twice.
class _NavGuard {
  bool _busy = false;
  Future<void> push(BuildContext context, String page) async {
    if (_busy) return;
    _busy = true;
    try {
      await AppNav.page<void>(context, page);
    } catch (_) {
      // Not under the app router (e.g. isolated tests) — ignore.
    } finally {
      _busy = false;
    }
  }
}

class _MenuItem {
  const _MenuItem(this.id, this.title, this.icon, this.page);
  final String id, title, page;
  final IconData icon;
}

/// White menu row with a tinted icon (RN `styles.row`).
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.title, required this.onTap, this.marginBottom = 10, this.enabled = true});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final double marginBottom;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: marginBottom),
      child: Material(
        color: AppColors.card,
        elevation: 1,
        shadowColor: const Color(0x0A000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: const BorderSide(color: AppColors.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.pitch.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(Radii.xl)),
                child: Icon(icon, size: 22, color: AppColors.pitch),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Gold-bordered "Rate CrickBex" row (RN `styles.rateRow`).
class RateRow extends StatelessWidget {
  const RateRow({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Material(
        color: AppColors.card,
        elevation: 2,
        shadowColor: AppColors.goldDark.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.21), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(children: [
              ClipOval(
                child: Image.asset('assets/images/rating-star.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    semanticLabel: 'Rate us',
                    errorBuilder: (_, _, _) => const Icon(Icons.star, size: 32, color: AppColors.gold)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Rate CrickBex', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)),
                  SizedBox(height: 2),
                  Text('A quick rating helps others discover us',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ]),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md, left: Spacing.xs, right: Spacing.xs),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
      );
}

const _settingsItems = [
  _MenuItem('ContactUs', 'Contact Us', Icons.mail_outline, 'contact'),
  _MenuItem('PrivacyPolicy', 'Privacy Policy', Icons.verified_user_outlined, 'privacy'),
];

/// Settings tab root — ported from RN `screens/SettingsScreen.tsx`.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nav = _NavGuard();

  @override
  Widget build(BuildContext context) {
    final review = ReviewScope.maybeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        Column(children: [
          const ScreenTitle(title: 'Settings'),
          const ScreenBannerSlots(screen: 'more', onlyPosition: 'top'),
          Expanded(
            child: ListView(
              key: const ValueKey('settings_list'),
              padding: EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, scrollBottomReserve(context)),
              children: [
                if (review != null) RateRow(key: const ValueKey('settings_rate'), onTap: review.showRatingModal),
                for (final item in _settingsItems)
                  MenuRow(
                    key: ValueKey('settings_item_${item.page}'),
                    icon: item.icon,
                    title: item.title,
                    onTap: () => _nav.push(context, item.page),
                  ),
              ],
            ),
          ),
        ]),
        const FixedBottomBanner(screen: 'more'),
      ]),
    );
  }
}

const _moreItems = [
  _MenuItem('PrivacyPolicy', 'Privacy Policy', Icons.verified_user_outlined, 'privacy'),
  _MenuItem('Terms', 'Terms & Conditions', Icons.description_outlined, 'terms'),
  _MenuItem('AboutUs', 'About Us', Icons.info_outline, 'about'),
  _MenuItem('ContactUs', 'Contact Us', Icons.mail_outline, 'contact'),
  _MenuItem('AppInfo', 'App Info', Icons.apps, 'app-info'),
];

/// "More" page (rewarded no-ads, rating, feedback, legal) — ported from RN
/// `screens/MoreScreen.tsx`.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _nav = _NavGuard();
  late final RewardedAdController _rewarded = RewardedAdController(
    'more_no_ads_30min',
    onReward: () => AdsManager.instance.grantNoAdsReward(),
  );

  @override
  void dispose() {
    _rewarded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = ReviewScope.maybeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        Column(children: [
          BackHeader(title: 'More', onBack: () => goBack(context)),
          const ScreenBannerSlots(screen: 'more', onlyPosition: 'top'),
          Expanded(
            child: ListView(
              key: const ValueKey('more_list'),
              padding: EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, scrollBottomReserve(context)),
              children: [
                ListenableBuilder(
                  listenable: Listenable.merge([_rewarded, AdsManager.instance.adsReady]),
                  builder: (context, _) {
                    if (!_rewarded.enabled) return const SizedBox.shrink();
                    return MenuRow(
                      key: const ValueKey('more_rewarded'),
                      icon: Icons.videocam_outlined,
                      title: _rewarded.isLoading ? 'Loading ad...' : _rewarded.label,
                      enabled: !_rewarded.isLoading,
                      marginBottom: Spacing.lg,
                      onTap: _rewarded.show,
                    );
                  },
                ),
                if (review != null) ...[
                  const _SectionLabel('We’d love your feedback'),
                  RateRow(key: const ValueKey('more_rate'), onTap: review.showRatingModal),
                  MenuRow(
                    key: const ValueKey('more_feedback'),
                    icon: Icons.chat_bubble_outline,
                    title: 'Send Feedback',
                    onTap: () => LinkLauncher.open(context, feedbackMailUri()),
                  ),
                ],
                const _SectionLabel('Legal & support'),
                for (final item in _moreItems)
                  MenuRow(
                    key: ValueKey('more_item_${item.page}'),
                    icon: item.icon,
                    title: item.title,
                    onTap: () => _nav.push(context, item.page),
                  ),
              ],
            ),
          ),
        ]),
        const FixedBottomBanner(screen: 'more'),
      ]),
    );
  }
}
