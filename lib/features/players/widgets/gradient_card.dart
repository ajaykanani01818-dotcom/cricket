import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';

/// Ported from RN `GradientCard` (variant "standard": white → #FAFAFA,
/// 18px radius, borderStrong hairline, soft shadow). Used by the Ranking,
/// Players and Player Detail screens.
class GradientCard extends StatelessWidget {
  const GradientCard({super.key, required this.child, this.padding, this.margin, this.radius = 18});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.borderStrong),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.white, AppColors.surfaceFaint],
          ),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: child,
      );
}

/// Circular avatar with a hairline ring + letter fallback (RN avatarRing +
/// CachedImage/avatarPlaceholder).
class RingAvatar extends StatelessWidget {
  const RingAvatar({
    super.key,
    required this.url,
    required this.name,
    required this.size,
    this.ringPadding = 2,
    this.ringColor = AppColors.border,
  });
  final String? url;
  final String name;
  final double size;
  final double ringPadding;
  final Color ringColor;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(ringPadding),
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: ringColor),
        ),
        child: NetImage(
          url: url,
          size: size - ringPadding * 2 - 2,
          fallbackLetter: name,
          fit: BoxFit.cover,
          background: AppColors.cardAlt,
        ),
      );
}

/// Bottom padding so the last list item clears the floating tab bar (the
/// shell uses extendBody, so MediaQuery bottom padding includes the bar).
double bottomReserve(BuildContext context, [double extra = Spacing.lg]) => MediaQuery.paddingOf(context).bottom + extra;

/// Dark "Try Again" button used by RN error cards.
class TryAgainButton extends StatelessWidget {
  const TryAgainButton({super.key, required this.onPressed, this.label = 'Try Again'});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.text,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
      );
}
