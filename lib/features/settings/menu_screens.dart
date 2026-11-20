import '../search/recent_searches.dart';
import 'package:flutter/material.dart';

import '../../core/brand/brand.dart';
import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../review/review_controller.dart';
import 'contact_details.dart';
import 'legal_layout.dart';
import 'settings_widgets.dart';

/// Short description shown in Settings › About and on the About page.
const String kAppDescription =
    'Live cricket scores, ball-by-ball commentary, scorecards, fixtures and '
    'results from around the world. Free, with no account needed.';

/// Data-source note (PRD §4.5: never claim every match in the world).
const String kCoverageNote =
    'Coverage depends on the data available from our providers.';

/// Guards against double taps pushing the same page twice.
class _NavGuard {
  bool _busy = false;
  Future<void> push(BuildContext context, String page) async {
    if (_busy) return;
    _busy = true;
    try {
      await AppNav.page<void>(context, page);
    } catch (_) {
      // Not under the app router (e.g. isolated tests): ignore.
    } finally {
      _busy = false;
    }
  }
}

/// "Rate Cric Ticker": opens the store listing (never a custom star dialog).
Future<void> openStoreForRating(BuildContext context) => LinkLauncher.open(
  context,
  storeListingUri(),
  via: (_) async {
    final c = ReviewScope.read(context);
    return c != null ? c.openStoreListing() : defaultOpenStoreListing();
  },
);

/// Settings tab root.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.themeController,
    this.contact = ContactInfo.brand,
  });

  /// Defaults to [ThemeController.instance] (injected in tests).
  final ThemeController? themeController;
  final ContactInfo contact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Column(
        children: [
          const ScreenTitle(title: 'Settings', showBack: false),
          const ScreenBannerSlots(screen: 'more', onlyPosition: 'top'),
          Expanded(
            child: SettingsBody(
              listKey: const ValueKey('settings_list'),
              themeController: themeController,
              contact: contact,
            ),
          ),
          const FixedBottomBanner(screen: 'more'),
        ],
      ),
    );
  }
}

/// The Settings list (also used by the legacy "More" page).
class SettingsBody extends StatefulWidget {
  const SettingsBody({
    super.key,
    this.listKey,
    this.themeController,
    this.contact = ContactInfo.brand,
    this.leading = const [],
  });
  final Key? listKey;
  final ThemeController? themeController;
  final ContactInfo contact;

  /// Extra rows above the sections (the More page's rewarded-ad row).
  final List<Widget> leading;

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  final _nav = _NavGuard();

  ThemeController get _theme =>
      widget.themeController ?? ThemeController.instance;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = Responsive.of(context);
    final info = widget.contact;

    final sections = <Widget>[
      ...widget.leading,
      const SettingsSectionLabel('Appearance'),
      ListenableBuilder(
        listenable: _theme,
        builder: (context, _) => SettingsGroup(
          key: const ValueKey('settings_theme'),
          children: [
            for (final (mode, title, subtitle, icon) in const [
              (
                ThemeMode.system,
                'System',
                'Match your device setting',
                Icons.brightness_auto_outlined,
              ),
              (ThemeMode.light, 'Light', null, Icons.light_mode_outlined),
              (ThemeMode.dark, 'Dark', null, Icons.dark_mode_outlined),
            ])
              SettingsChoiceRow(
                key: ValueKey('settings_theme_${mode.name}'),
                title: title,
                subtitle: subtitle,
                icon: icon,
                selected: _theme.mode == mode,
                onTap: () => _theme.setMode(mode),
              ),
          ],
        ),
      ),
      const SettingsSectionLabel('Support'),
      SettingsGroup(
        children: [
          SupportEmailBlock(
            key: const ValueKey('settings_support_email'),
            info: info,
            keyPrefix: 'settings',
            note: 'We usually reply within a few working days.',
          ),
          SettingsRow(
            key: const ValueKey('settings_feedback'),
            icon: Icons.chat_bubble_outline,
            title: 'Send feedback',
            subtitle: 'Tell us what to fix or add',
            external: true,
            onTap: () => LinkLauncher.open(context, info.mailUri()),
          ),
          SettingsRow(
            key: const ValueKey('settings_item_contact'),
            icon: Icons.help_outline,
            title: 'Help and support',
            subtitle: 'Common questions',
            onTap: () => _nav.push(context, 'contact'),
          ),
          ...optionalContactRows(context, info),
        ],
      ),
      const SettingsSectionLabel('Your data'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('settings_clear_searches'),
            icon: Icons.history,
            title: 'Clear recent searches',
            subtitle: 'Stored only on this device',
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await RecentSearches.clear();
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Recent searches cleared')),
                );
            },
          ),
        ],
      ),
      const SettingsSectionLabel('Rate the app'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('settings_rate'),
            icon: Icons.star_outline_rounded,
            title: 'Rate ${Brand.appName}',
            subtitle: 'Opens the store listing',
            external: true,
            onTap: () => openStoreForRating(context),
          ),
        ],
      ),
      const SettingsSectionLabel('Legal'),
      SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('settings_item_privacy'),
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            onTap: () => _nav.push(context, 'privacy'),
          ),
          SettingsRow(
            key: const ValueKey('settings_item_terms'),
            icon: Icons.description_outlined,
            title: 'Terms of use',
            onTap: () => _nav.push(context, 'terms'),
          ),
        ],
      ),
      const SettingsSectionLabel('About'),
      SettingsGroup(
        children: [
          Padding(
            key: const ValueKey('settings_about'),
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Brand.appName, style: AppText.h3.copyWith(color: p.ink)),
                const SizedBox(height: 2),
                const AppVersionText(),
                const SizedBox(height: Spacing.sm),
                Text(
                  kAppDescription,
                  style: AppText.reading.copyWith(color: p.ink),
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: p.inkMuted,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        kCoverageNote,
                        key: const ValueKey('settings_coverage_note'),
                        style: AppText.meta.copyWith(color: p.inkMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SettingsRow(
            key: const ValueKey('settings_item_about'),
            icon: Icons.sports_cricket_outlined,
            title: 'About ${Brand.appName}',
            onTap: () => _nav.push(context, 'about'),
          ),
          if (info.websiteUrl case final url?)
            SettingsRow(
              key: const ValueKey('settings_website'),
              icon: Icons.language,
              title: 'Website',
              external: true,
              onTap: () => LinkLauncher.open(context, Uri.parse(url)),
            ),
        ],
      ),
    ];

    return ListView(
      key: widget.listKey,
      padding: EdgeInsets.fromLTRB(
        r.horizontalPadding,
        Spacing.xs,
        r.horizontalPadding,
        Spacing.xxxl,
      ),
      children: [
        for (final s in sections)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              // Full width up to the cap, so labels align left.
              child: SizedBox(width: double.infinity, child: s),
            ),
          ),
      ],
    );
  }
}

/// Legacy "More" page (`…/more`): the Settings list plus the rewarded
/// "no ads for 30 min" row when ads are available.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
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
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Column(
        children: [
          const ScreenTitle(title: 'More'),
          const ScreenBannerSlots(screen: 'more', onlyPosition: 'top'),
          Expanded(
            child: SettingsBody(
              listKey: const ValueKey('more_list'),
              leading: [
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _rewarded,
                    AdsManager.instance.adsReady,
                  ]),
                  builder: (context, _) {
                    if (!_rewarded.enabled) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: Spacing.lg),
                      child: SettingsGroup(
                        children: [
                          SettingsRow(
                            key: const ValueKey('more_rewarded'),
                            icon: Icons.videocam_outlined,
                            title: _rewarded.isLoading
                                ? 'Loading ad…'
                                : _rewarded.label,
                            onTap: _rewarded.isLoading ? null : _rewarded.show,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const FixedBottomBanner(screen: 'more'),
        ],
      ),
    );
  }
}
