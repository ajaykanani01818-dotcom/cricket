import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum GradientCardVariant { standard, featured, live, dark }

/// Ported from RN `GradientCard`: subtle vertical gradient, 1px border, soft shadow.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.variant = GradientCardVariant.standard,
    this.radius = 18,
    this.noShadow = false,
    this.padding,
    this.margin,
  });

  final Widget child;
  final GradientCardVariant variant;
  final double radius;
  final bool noShadow;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  static const _gradients = {
    GradientCardVariant.standard: [AppColors.white, Color(0xFFFAFAFA)],
    GradientCardVariant.featured: [AppColors.white, Color(0xFFF5F5F7)],
    GradientCardVariant.live: [AppColors.white, AppColors.redTint],
    GradientCardVariant.dark: [Color(0xFF18181B), Color(0xFF0A0A0B)],
  };

  @override
  Widget build(BuildContext context) {
    final isDark = variant == GradientCardVariant.dark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: isDark ? AppColors.text : AppColors.borderStrong),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _gradients[variant]!,
        ),
        boxShadow: noShadow ? null : const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}
