import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ported from RN `AppBar` (white bar, logo + title/subtitle, optional back/menu).
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title = 'CrickBex',
    this.subtitle = 'Live Scores & Updates',
    this.onBack,
    this.onMorePress,
    this.moreOnLeft = false,
    this.rightAccessory,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onMorePress;
  final bool moreOnLeft;
  final Widget? rightAccessory;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  Widget _sideButton(
    IconData icon,
    VoidCallback onTap,
    Color color,
    String key,
    String label,
  ) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      key: ValueKey(key),
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Icon(icon, size: 22, color: color),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    Widget? left;
    Widget? right;
    if (onBack != null) {
      left = _sideButton(
        Icons.chevron_left,
        onBack!,
        AppColors.pitch,
        'app_bar_back',
        'Back',
      );
    } else if (onMorePress != null && moreOnLeft) {
      left = _sideButton(
        Icons.menu,
        onMorePress!,
        AppColors.text,
        'app_bar_menu',
        'Menu',
      );
    }
    if (onMorePress != null && !moreOnLeft) {
      right = _sideButton(
        Icons.menu,
        onMorePress!,
        AppColors.text,
        'app_bar_menu',
        'Menu',
      );
    }
    return Material(
      color: AppColors.card,
      elevation: 2,
      shadowColor: const Color(0x22000000),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: r.horizontalPadding),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: r.isSmall ? 28 : 32,
                    height: r.isSmall ? 28 : 32,
                    semanticLabel: 'CrickBex logo',
                  ),
                  const SizedBox(width: Spacing.md),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: r.isSmall ? 16 : 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (left != null)
                Align(alignment: Alignment.centerLeft, child: left),
              if (right != null)
                Align(alignment: Alignment.centerRight, child: right),
              if (rightAccessory != null)
                Align(alignment: Alignment.centerRight, child: rightAccessory),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ported from RN `ScreenTitle`: brand-blue band with spaced uppercase title.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({
    super.key,
    required this.title,
    this.rightIcon,
    this.onRightPress,
  });
  final String title;
  final IconData? rightIcon;
  final VoidCallback? onRightPress;

  @override
  Widget build(BuildContext context) {
    final r = Responsive.of(context);
    return Material(
      color: AppColors.pitch,
      elevation: 6,
      // Full-width band (a Stack with only centered children would otherwise
      // shrink to the title's width inside a centered Column).
      child: SizedBox(
        width: double.infinity,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: Spacing.lg,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        3,
                        (_) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: Color(0xB3FFFFFF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: r.isSmall ? 16 : 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 24,
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
                if (rightIcon != null && onRightPress != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: const ValueKey('screen_title_action'),
                      onPressed: onRightPress,
                      icon: Icon(rightIcon, color: AppColors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ported from RN `PageTitle` (in-content title with optional icon/subtitle).
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.title, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
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
              color: AppColors.taglineBlue,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, color: AppColors.pitch, size: 20),
          ),
          const SizedBox(width: Spacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.h2),
              if (subtitle != null) Text(subtitle!, style: AppText.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Ported from RN `SectionHeader`.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.overline,
    this.onActionPress,
    this.actionLabel = 'See all',
    this.showLiveDot = false,
  });
  final String title;
  final String? overline;
  final VoidCallback? onActionPress;
  final String actionLabel;
  final bool showLiveDot;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overline != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      if (showLiveDot) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.live,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        overline!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        if (onActionPress != null)
          InkWell(
            onTap: onActionPress,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
              child: Row(
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
