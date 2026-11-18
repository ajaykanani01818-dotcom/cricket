import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Colors matched to crickbex.com — ported 1:1 from RN `src/constants/theme.ts`.
class AppColors {
  AppColors._();
  // Brand
  static const pitch = Color(0xFF0B5CD4); // primary brand blue
  static const pitchLight = Color(0xFF3B82F6);
  static const pitchDark = Color(0xFF0860C4);
  static const gold = Color(0xFFF59E0B); // upcoming amber
  static const goldLight = Color(0xFFFBBF24);
  static const goldDark = Color(0xFFB45309);
  static const silver = Color(0xFF8A8D93);
  static const silverLight = Color(0xFFA0A3A8);
  static const bronze = Color(0xFFCD7F32);
  static const bronzeLight = Color(0xFFE0924A);
  // Surfaces
  static const bg = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const cardAlt = Color(0xFFF1F5F9);
  static const border = Color(0xFFE4E8EF);
  static const borderSubtle = Color(0xFFEEF2F7);
  static const borderStrong = Color(0xFFD8DEE9);
  static const borderNeutral = Color(0xFFE5E5E5);
  static const text = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);
  static const graphite = Color(0xFF334155);
  // Semantic
  static const live = Color(0xFFEF3B3B);
  static const win = Color(0xFF22C55E);
  static const dot = Color(0x40000000);
  static const run = Color(0x66000000);
  static const taglineBlue = Color(0x1F0B5CD4);
  static const glassBorder = Color(0x2E0B5CD4);
  static const tableHeaderBg = Color(0xFF0F172A);
  static const tableHeaderText = Color(0xFFFFFFFF);
  static const commentaryWicketBg = Color(0x14EF3B3B);
  static const commentaryBoundaryBg = Color(0x14F59E0B);
  static const white = Color(0xFFFFFFFF);
  static const error = Color(0xFFEF3B3B);
  static const errorBg = Color(0x14EF3B3B);
  static const redTint = Color(0xFFFEF2F2);
  static const neutralSurface = Color(0xFFF3F4F6);
  static const voidText = Color(0xFF57534E);
  static const surfaceFaint = Color(0xFFFAFAFA);
  static const surfaceSubtle = Color(0xFFF7F7F8);
  static const winTintSoft = Color(0x0F22C55E);
  static const navy = Color(0xFF04264D);
}

class Spacing {
  Spacing._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 24, xxxl = 32;
}

class Radii {
  Radii._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, full = 999;
}

/// Ported from RN `src/constants/typography.ts`.
class AppText {
  AppText._();
  static const h1 = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text);
  static const h2 = TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text);
  static const h3 = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text);
  static const h4 = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.text);
  static const bodyBold = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary);
  static const captionBold = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
  static const label = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted);
  static const score = TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text);
  static const scoreLarge = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.text);
  static const badge = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5);
}

/// Ported from RN `src/utils/responsive.ts`.
class Responsive {
  final double width;
  const Responsive(this.width);
  factory Responsive.of(BuildContext context) => Responsive(MediaQuery.sizeOf(context).width);
  bool get isSmall => width < 360;
  bool get isMedium => width >= 360 && width < 400;
  bool get isLargePhone => width >= 400 && width < 768;
  bool get isTablet => width >= 768;
  double get horizontalPadding => isTablet ? 20 : isLargePhone ? 14 : isSmall ? 10 : 12;
  double get contentMaxWidth => isTablet ? 920 : 10000;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.pitch, primary: AppColors.pitch, surface: AppColors.card),
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.pitch),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

/// App-wide scroll behaviour: Android glow overscroll (what the RN app showed)
/// instead of Material 3's stretch effect, which applies an image filter to the
/// whole scrolling subtree every frame at the edges (measurable jank on
/// mid-range phones).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    switch (getPlatform(context)) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return GlowingOverscrollIndicator(axisDirection: details.direction, color: AppColors.pitch, child: child);
      default:
        return super.buildOverscrollIndicator(context, child, details);
    }
  }
}
