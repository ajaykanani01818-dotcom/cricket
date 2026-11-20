import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../theme/app_theme.dart';
import 'live_pill.dart';

/// The Cric Ticker logo (orange C + "Cric Ticker"). Picks the light or dark
/// artwork from the current theme brightness ([brightness] overrides it, e.g.
/// on a dark band in the light theme) and decodes it at the display size.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 32, this.brightness});

  /// Rendered height of the whole logo (the C is the tallest part; the
  /// lettering is about half of it).
  final double height;

  /// Brightness of the surface the logo sits on; defaults to the theme's.
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final dark =
        (brightness ?? Theme.of(context).brightness) == Brightness.dark;
    final width = height * Brand.logoAspect;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final cacheWidth = (width * dpr).ceil().clamp(
      1,
      Brand.logoPx.width.toInt(),
    );
    return Image.asset(
      dark ? Brand.logoDark : Brand.logoLight,
      key: ValueKey(dark ? 'brand_wordmark_dark' : 'brand_wordmark_light'),
      height: height,
      width: width,
      cacheWidth: cacheWidth,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: Brand.appName,
      errorBuilder: (context, _, _) => SizedBox(
        height: height,
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Brand.appName,
            style: AppFont.style(
              size: height * 0.55,
              weight: FontWeight.w800,
              color: dark ? Brand.splashInk : context.palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 48 dp icon button used in the top bars (ink icon, brandTint ripple).
class TopBarIconButton extends StatelessWidget {
  const TopBarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, color: color ?? context.palette.ink, size: 24),
  );
}

bool _isBrandTitle(String t) =>
    t == Brand.appName || t.toLowerCase() == 'crickbex';

/// App top bar: surface, hairline bottom edge, no shadow. Wordmark (or a
/// title) on the left, actions on the right: [onSearch] adds the search
/// icon (key `app_bar_search`), [actions] any others, [onMorePress] the menu.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title = Brand.appName,
    this.subtitle,
    this.onBack,
    this.onMorePress,
    this.moreOnLeft = false,
    this.rightAccessory,
    this.onSearch,
    this.actions = const [],
  });

  /// [Brand.appName] renders the wordmark; anything else renders as text.
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onMorePress;
  final bool moreOnLeft;
  final Widget? rightAccessory;

  /// Search slot (PRD: search icon in the Home and Matches bars).
  final VoidCallback? onSearch;
  final List<Widget> actions;

  static const double barHeight = 56;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = Responsive.of(context);
    final leading = <Widget>[
      if (onBack != null)
        Semantics(
          button: true,
          label: 'Back',
          child: IconButton(
            key: const ValueKey('app_bar_back'),
            onPressed: onBack,
            icon: Icon(Icons.arrow_back, color: p.ink),
          ),
        )
      else if (onMorePress != null && moreOnLeft)
        IconButton(
          key: const ValueKey('app_bar_menu'),
          onPressed: onMorePress,
          tooltip: 'Menu',
          icon: Icon(Icons.menu, color: p.ink),
        ),
    ];
    final trailing = <Widget>[
      ...actions,
      if (onSearch != null)
        IconButton(
          key: const ValueKey('app_bar_search'),
          onPressed: onSearch,
          tooltip: 'Search',
          icon: Icon(Icons.search, color: p.ink),
        ),
      ?rightAccessory,
      if (onMorePress != null && !moreOnLeft)
        IconButton(
          key: const ValueKey('app_bar_menu'),
          onPressed: onMorePress,
          tooltip: 'Menu',
          icon: Icon(Icons.menu, color: p.ink),
        ),
    ];
    final titleWidget = _isBrandTitle(title)
        ? Align(
            alignment: Alignment.centerLeft,
            child: BrandWordmark(height: r.isSmall ? 28 : 32),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.screenTitle.copyWith(fontSize: 20),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.small,
                ),
            ],
          );
    return Material(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: barHeight),
          padding: EdgeInsets.only(
            left: leading.isEmpty ? r.horizontalPadding + 4 : 4,
            right: 4,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.hairline)),
          ),
          child: Row(
            children: [
              ...leading,
              Expanded(child: titleWidget),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen header used by every tab/detail screen: surface bar with a
/// left-aligned sentence-case title (the old blue band with spaced capitals
/// is gone). Shows a back arrow automatically when the route can pop
/// ([showBack] overrides), plus an optional action ([rightIcon]) and a
/// search slot.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({
    super.key,
    required this.title,
    this.rightIcon,
    this.onRightPress,
    this.onSearch,
    this.showBack,
    this.actions = const [],
  });
  final String title;
  final IconData? rightIcon;
  final VoidCallback? onRightPress;
  final VoidCallback? onSearch;

  /// null = automatic (route can pop).
  final bool? showBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = Responsive.of(context);
    final canPop = showBack ?? (ModalRoute.of(context)?.canPop ?? false);
    final brand = _isBrandTitle(title);
    return Material(
      color: p.surface,
      child: SizedBox(
        width: double.infinity,
        child: SafeArea(
          bottom: false,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTopBar.barHeight),
            padding: EdgeInsets.only(
              left: canPop ? 4 : r.horizontalPadding + 4,
              right: 4,
              top: 4,
              bottom: 4,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                if (canPop)
                  IconButton(
                    key: const ValueKey('screen_title_back'),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: p.ink),
                  ),
                Expanded(
                  child: brand
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: BrandWordmark(height: r.isSmall ? 28 : 32),
                        )
                      : Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.screenTitle,
                          ),
                        ),
                ),
                ...actions,
                if (onSearch != null)
                  IconButton(
                    key: const ValueKey('app_bar_search'),
                    onPressed: onSearch,
                    tooltip: 'Search',
                    icon: Icon(Icons.search, color: p.ink),
                  ),
                if (rightIcon != null && onRightPress != null)
                  IconButton(
                    key: const ValueKey('screen_title_action'),
                    onPressed: onRightPress,
                    icon: Icon(rightIcon, color: p.ink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// In-content title with optional icon/subtitle.
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.title, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.brandTint,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(icon, color: p.ink, size: 20),
            ),
            const SizedBox(width: Spacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.sectionTitle.copyWith(fontSize: 20)),
                if (subtitle != null) Text(subtitle!, style: AppText.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header: sentence-case title (wraps to 2 lines, then ellipsis),
/// optional live dot, optional action ("See all", brandText). Never
/// overflows: at 320 px × text 2.0 the action is capped at 45 % width and
/// ellipsises. [overline] (legacy) renders as a muted line under the title,
/// never as an all-caps eyebrow.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.overline,
    this.onActionPress,
    this.actionLabel = 'See all',
    this.showLiveDot = false,
    this.padding = const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.sm,
      Spacing.sm,
      Spacing.sm,
    ),
  });
  final String title;
  final String? overline;
  final VoidCallback? onActionPress;
  final String actionLabel;
  final bool showLiveDot;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, c) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showLiveDot) ...[
                const LiveDot(size: 8),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.sectionTitle,
                      ),
                      if (overline != null && overline!.trim().isNotEmpty)
                        Text(
                          overline!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small,
                        ),
                    ],
                  ),
                ),
              ),
              if (onActionPress != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
                  child: InkWell(
                    onTap: onActionPress,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                actionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFont.style(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: p.brandText,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: p.brandText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
