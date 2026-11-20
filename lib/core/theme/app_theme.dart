import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_typography.dart';

export 'app_palette.dart';
export 'app_typography.dart';

/// LEGACY colour names, kept so screens written for the old light-blue app
/// still compile. Each name reads the ACTIVE palette ([AppPalette.active]),
/// so it follows Light/Dark. New code: use `context.palette.<token>`.
///
/// Mapping (old → token): pitch/pitchDark/gold/goldDark → brandText,
/// pitchLight/goldLight → brand, bg → canvas, card → surface, cardAlt →
/// surfaceAlt, border* → hairline, text/graphite/navy → ink,
/// textSecondary/textMuted/voidText → inkMuted, live → live, win → positive,
/// error → negative, white → surface (white was "card" or "text on a pitch
/// fill"; surface keeps both readable in both themes).
class AppColors {
  AppColors._();
  static AppPalette get _p => AppPalette.active;

  // Brand
  static Color get pitch => _p.brandText;
  static Color get pitchLight => _p.brand;
  static Color get pitchDark => _p.brandText;
  static Color get gold => _p.brandText;
  static Color get goldLight => _p.brand;
  static Color get goldDark => _p.brandText;
  // Medal colours (rankings podium): data colours, theme independent.
  static Color get silver => const Color(0xFF8A8D93);
  static Color get silverLight => const Color(0xFFA0A3A8);
  static Color get bronze => const Color(0xFFCD7F32);
  static Color get bronzeLight => const Color(0xFFE0924A);
  // Surfaces
  static Color get bg => _p.canvas;
  static Color get card => _p.surface;
  static Color get cardAlt => _p.surfaceAlt;
  static Color get border => _p.hairline;
  static Color get borderSubtle => _p.hairline;
  static Color get borderStrong => _p.hairline;
  static Color get borderNeutral => _p.hairline;
  static Color get text => _p.ink;
  static Color get textSecondary => _p.inkMuted;
  static Color get textMuted => _p.inkMuted;
  static Color get graphite => _p.ink;
  // Semantic
  static Color get live => _p.live;
  static Color get win => _p.positive;
  static Color get dot => _p.ink.withValues(alpha: 0.25);
  static Color get run => _p.ink.withValues(alpha: 0.4);
  static Color get taglineBlue => _p.brandTint;
  static Color get glassBorder => _p.hairline;
  static Color get tableHeaderBg => _p.surfaceAlt;
  static Color get tableHeaderText => _p.ink;
  static Color get commentaryWicketBg => _p.liveTint;
  static Color get commentaryBoundaryBg => _p.brandTint;
  static Color get white => _p.surface;
  static Color get error => _p.negative;
  static Color get errorBg => _p.negativeTint;
  static Color get redTint => _p.liveTint;
  static Color get neutralSurface => _p.surfaceAlt;
  static Color get voidText => _p.inkMuted;
  static Color get surfaceFaint => _p.surfaceAlt;
  static Color get surfaceSubtle => _p.surfaceAlt;
  static Color get winTintSoft => _p.positiveTint;
  static Color get navy => _p.ink;
}

class Spacing {
  Spacing._();
  static const double xs = 4,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 20,
      xxl = 24,
      xxxl = 32;
}

/// Radii by hierarchy (no single radius on everything): chips 4-6, live
/// card 12, sheets 18.
class Radii {
  Radii._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, full = 999;
  static const double chip = 6, card = 12, sheet = 18;
}

/// Type scale (Archivo). Legacy names (h1 … badge) keep their old sizes so
/// existing screens do not reflow; the new names are the spec scale.
/// Colours come from the active palette.
class AppText {
  AppText._();
  static AppPalette get _p => AppPalette.active;
  static TextStyle _s(
    double size,
    FontWeight w,
    Color c, {
    double? height,
    double width = 100,
    bool tab = false,
  }) => AppFont.style(
    size: size,
    weight: w,
    color: c,
    height: height,
    width: width,
    tabularFigures: tab,
  );

  // ── legacy names ──
  static TextStyle get h1 => _s(24, FontWeight.w800, _p.ink);
  static TextStyle get h2 => _s(20, FontWeight.w800, _p.ink);
  static TextStyle get h3 => _s(18, FontWeight.w700, _p.ink);
  static TextStyle get h4 => _s(16, FontWeight.w700, _p.ink);
  static TextStyle get body => _s(14, FontWeight.w400, _p.ink);
  static TextStyle get bodyBold => _s(14, FontWeight.w700, _p.ink);
  static TextStyle get caption => _s(12, FontWeight.w500, _p.inkMuted);
  static TextStyle get captionBold => _s(12, FontWeight.w700, _p.inkMuted);
  static TextStyle get label => _s(11, FontWeight.w700, _p.inkMuted);
  static TextStyle get score => scoreCard.copyWith(fontSize: 20);
  static TextStyle get scoreLarge => scoreCard.copyWith(fontSize: 28);
  static TextStyle get badge => _s(11, FontWeight.w800, _p.ink);

  // ── spec scale ──
  /// Screen title in the top bar.
  static TextStyle get screenTitle =>
      _s(22, FontWeight.w800, _p.ink, height: 1.15);

  /// Section header ("Live now", "Starting soon").
  static TextStyle get sectionTitle =>
      _s(18, FontWeight.w700, _p.ink, height: 1.2);

  /// Team / player names and labels (wdth 100, wght 600).
  static TextStyle get name => _s(15, FontWeight.w600, _p.ink, height: 1.25);

  /// Body copy 15/1.45.
  static TextStyle get reading => _s(15, FontWeight.w400, _p.ink, height: 1.45);

  /// Secondary line (series, venue, status).
  static TextStyle get meta =>
      _s(13, FontWeight.w500, _p.inkMuted, height: 1.3);

  /// Smallest readable label (12 sp minimum).
  static TextStyle get small =>
      _s(12, FontWeight.w600, _p.inkMuted, height: 1.25);

  /// Match Centre header score: 48 sp, wdth 72, wght 800, tabular.
  static TextStyle get scoreHero => _s(
    48,
    FontWeight.w800,
    _p.ink,
    height: 1.0,
    width: AppFont.scoreWidth,
    tab: true,
  );

  /// Live-card score: 22 sp, wdth 72, wght 800, tabular.
  static TextStyle get scoreCard => _s(
    22,
    FontWeight.w800,
    _p.ink,
    height: 1.1,
    width: AppFont.scoreWidth,
    tab: true,
  );

  /// Compact row score: 17 sp, wdth 72, wght 800, tabular.
  static TextStyle get scoreRow => _s(
    17,
    FontWeight.w800,
    _p.ink,
    height: 1.15,
    width: AppFont.scoreWidth,
    tab: true,
  );

  /// Overs / run-rate figures next to a score.
  static TextStyle get figures =>
      _s(13, FontWeight.w600, _p.inkMuted, height: 1.2, tab: true);
}

/// Ported from RN `src/utils/responsive.ts`.
class Responsive {
  final double width;
  const Responsive(this.width);
  factory Responsive.of(BuildContext context) =>
      Responsive(MediaQuery.sizeOf(context).width);
  bool get isSmall => width < 360;
  bool get isMedium => width >= 360 && width < 400;
  bool get isLargePhone => width >= 400 && width < 768;
  bool get isTablet => width >= 768;
  double get horizontalPadding => isTablet
      ? 20
      : isLargePhone
      ? 14
      : isSmall
      ? 10
      : 12;
  double get contentMaxWidth => isTablet ? 920 : 10000;
}

/// Status/nav bar styling per theme. The Android navigation bar shows the
/// brand orange so it continues the bottom bar.
SystemUiOverlayStyle systemOverlayFor(AppPalette p) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
  statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
  systemNavigationBarColor: p.brand,
  systemNavigationBarDividerColor: p.brand,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

final _themeCache = <Brightness, ThemeData>{};

/// Material 3 theme built from the tokens. [brightness] picks the palette.
/// Memoised: the same instance per brightness (an unequal ThemeData on
/// rebuild would start a theme tween).
ThemeData buildAppTheme({Brightness brightness = Brightness.light}) =>
    _themeCache[brightness] ??= _buildTheme(brightness);

ThemeData _buildTheme(Brightness brightness) {
  final p = AppPalette.forBrightness(brightness);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.brand,
    onPrimary: p.onBrand,
    primaryContainer: p.brandTint,
    onPrimaryContainer: p.ink,
    secondary: p.ink,
    onSecondary: p.surface,
    secondaryContainer: p.brandTint,
    onSecondaryContainer: p.ink,
    tertiary: p.positive,
    onTertiary: p.surface,
    error: p.negative,
    onError: p.surface,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.inkMuted,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceAlt,
    surfaceContainerHighest: p.surfaceAlt,
    outline: p.inkMuted,
    outlineVariant: p.hairline,
    inverseSurface: p.ink,
    onInverseSurface: p.surface,
    inversePrimary: p.brandText,
    shadow: Colors.transparent,
    scrim: const Color(0x99000000),
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final text = AppFont.textTheme(base.textTheme, p.ink, p.inkMuted);
  final label = AppFont.style(size: 14, weight: FontWeight.w700);
  final shape8 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.sm),
  );

  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    cardColor: p.surface,
    dividerColor: p.hairline,
    disabledColor: p.inkMuted,
    hintColor: p.inkMuted,
    // InkRipple, not InkSparkle (shader per splash; perf budget).
    splashFactory: InkRipple.splashFactory,
    splashColor: p.brandTint,
    highlightColor: p.brandTint.withValues(alpha: p.brandTint.a * 0.6),
    hoverColor: p.brandTint.withValues(alpha: p.brandTint.a * 0.5),
    focusColor: p.brandTint,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: p.ink, size: 22),
    primaryIconTheme: IconThemeData(color: p.onBrand),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppFont.style(
        size: 20,
        weight: FontWeight.w800,
        color: p.ink,
      ),
      systemOverlayStyle: systemOverlayFor(p),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: p.hairline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.brandTint,
      disabledColor: p.surfaceAlt,
      side: BorderSide(color: p.hairline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      labelStyle: AppFont.style(
        size: 13,
        weight: FontWeight.w600,
        color: p.ink,
      ),
      secondaryLabelStyle: AppFont.style(
        size: 13,
        weight: FontWeight.w700,
        color: p.ink,
      ),
      checkmarkColor: p.ink,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
      titleTextStyle: AppFont.style(
        size: 20,
        weight: FontWeight.w800,
        color: p.ink,
      ),
      contentTextStyle: AppFont.style(size: 15, height: 1.45, color: p.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: p.hairline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: AppFont.style(
        size: 14,
        weight: FontWeight.w600,
        color: p.surface,
      ),
      actionTextColor: p.brand,
      elevation: 0,
      behavior: SnackBarBehavior.fixed,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      hintStyle: AppFont.style(size: 15, color: p.inkMuted),
      labelStyle: AppFont.style(size: 15, color: p.inkMuted),
      floatingLabelStyle: AppFont.style(
        size: 13,
        weight: FontWeight.w600,
        color: p.brandText,
      ),
      prefixIconColor: p.inkMuted,
      suffixIconColor: p.inkMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: p.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: p.brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: p.negative),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.brandText,
      selectionColor: p.brandTint,
      selectionHandleColor: p.brand,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.ink,
      unselectedLabelColor: p.inkMuted,
      labelStyle: AppFont.style(size: 14, weight: FontWeight.w700),
      unselectedLabelStyle: AppFont.style(size: 14, weight: FontWeight.w600),
      indicatorColor: p.brand,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: p.brand, width: 3),
      ),
      dividerColor: p.hairline,
      overlayColor: WidgetStatePropertyAll(p.brandTint),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onBrand : p.inkMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.brand : p.surfaceAlt,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.brand : p.hairline,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.brandText : p.inkMuted,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.brand : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(p.onBrand),
      side: BorderSide(color: p.inkMuted, width: 1.5),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.brand,
      linearTrackColor: p.surfaceAlt,
      circularTrackColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: p.ink,
      textColor: p.ink,
      titleTextStyle: AppFont.style(
        size: 15,
        weight: FontWeight.w600,
        color: p.ink,
      ),
      subtitleTextStyle: AppFont.style(size: 13, color: p.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
        textStyle: label,
        minimumSize: const Size(64, 48),
        shape: shape8,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
        textStyle: label,
        minimumSize: const Size(64, 48),
        shape: shape8,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.hairline),
        textStyle: label,
        minimumSize: const Size(64, 48),
        shape: shape8,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brandText,
        textStyle: label,
        minimumSize: const Size(48, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: p.hairline),
      ),
      textStyle: AppFont.style(size: 15, color: p.ink),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      textStyle: AppFont.style(
        size: 12,
        weight: FontWeight.w600,
        color: p.surface,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// App-wide scroll behaviour: Android glow overscroll instead of Material 3's
/// stretch effect, which applies an image filter to the whole scrolling
/// subtree every frame at the edges (measurable jank on mid-range phones).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (getPlatform(context)) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return GlowingOverscrollIndicator(
          axisDirection: details.direction,
          color: context.palette.brand,
          child: child,
        );
      default:
        return super.buildOverscrollIndicator(context, child, details);
    }
  }
}
