import 'package:flutter/material.dart';

/// Colour tokens of the owner-approved "Orange #ED800C" direction
/// (docs/design/BUILD_SPEC.md). One instance per brightness.
///
/// Rules:
/// - [brand] is a FILL (bottom bar, six bead, primary buttons, live-card
///   edge). Never use it for text: orange text is [brandText].
/// - Text/icons on a [brand] fill use [onBrand] (white on #ED800C is 2.7:1).
/// - [live] is reserved for the live pill/dot and live state only.
///
/// Read it with `context.palette` (rebuilds on theme change) or, from code
/// without a context, [AppPalette.active].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.hairline,
    required this.brand,
    required this.onBrand,
    required this.brandText,
    required this.brandTint,
    required this.live,
    required this.positive,
    required this.negative,
    required this.logoChip,
  });

  final Brightness brightness;

  /// Page background.
  final Color canvas;

  /// Cards, sheets, header, nav-adjacent surfaces.
  final Color surface;

  /// Table header rows, pressed states, skeleton base.
  final Color surfaceAlt;

  /// Primary text.
  final Color ink;

  /// Secondary text (>= 4.5:1 on canvas, surface and surfaceAlt).
  final Color inkMuted;

  /// Dividers, outlines.
  final Color hairline;

  /// #ED800C fill.
  final Color brand;

  /// Text/icons on a [brand] fill.
  final Color onBrand;

  /// Orange used as text/icon on surface/canvas.
  final Color brandText;

  /// Selected chips, highlight rows, tap feedback.
  final Color brandTint;

  /// Live pill/dot and live state only.
  final Color live;

  /// Winner marker, rank up.
  final Color positive;

  /// Rank down, errors.
  final Color negative;

  /// Light chip behind team logos (logos are drawn for light backgrounds).
  final Color logoChip;

  bool get isDark => brightness == Brightness.dark;

  /// Low-alpha washes derived from the semantic colours.
  Color get liveTint => live.withValues(alpha: isDark ? 0.16 : 0.08);
  Color get negativeTint => negative.withValues(alpha: isDark ? 0.16 : 0.08);
  Color get positiveTint => positive.withValues(alpha: isDark ? 0.16 : 0.08);

  static const light = AppPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F4F3),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEEDEB),
    ink: Color(0xFF1C1814),
    inkMuted: Color(0xFF5E574F),
    hairline: Color(0xFFE6E2DD),
    brand: Color(0xFFED800C),
    onBrand: Color(0xFF1C1814),
    brandText: Color(0xFFA65300),
    brandTint: Color(0x1FED800C), // 12 %
    live: Color(0xFFC8102E),
    positive: Color(0xFF1E7A4C),
    negative: Color(0xFFB42318),
    logoChip: Color(0xFFF4F4F3),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF17130F),
    surface: Color(0xFF221C16),
    surfaceAlt: Color(0xFF2B241D),
    ink: Color(0xFFF7F1EA),
    inkMuted: Color(0xFFBDB1A3),
    hairline: Color(0xFF3A3129),
    brand: Color(0xFFED800C),
    onBrand: Color(0xFF17130F),
    brandText: Color(0xFFFF9A3C),
    brandTint: Color(0x2EED800C), // 18 %
    live: Color(0xFFFF5A6A),
    positive: Color(0xFF5BD08F),
    negative: Color(0xFFFF7A6E),
    logoChip: Color(0xFFF1ECE6),
  );

  static AppPalette forBrightness(Brightness b) =>
      b == Brightness.dark ? dark : light;

  /// The palette of the theme currently on screen. Kept in sync by
  /// `ThemeController` (and `buildAppTheme`'s callers); used by the legacy
  /// `AppColors.*` getters and by code without a BuildContext.
  static AppPalette active = light;

  /// Every text token, by name (contrast tests iterate this).
  Map<String, Color> get textTokens => {
    'ink': ink,
    'inkMuted': inkMuted,
    'brandText': brandText,
    'live': live,
    'positive': positive,
    'negative': negative,
  };

  /// Every background a text token may sit on, by name.
  Map<String, Color> get surfaceTokens => {
    'canvas': canvas,
    'surface': surface,
    'surfaceAlt': surfaceAlt,
  };

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkMuted,
    Color? hairline,
    Color? brand,
    Color? onBrand,
    Color? brandText,
    Color? brandTint,
    Color? live,
    Color? positive,
    Color? negative,
    Color? logoChip,
  }) => AppPalette(
    brightness: brightness,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    ink: ink ?? this.ink,
    inkMuted: inkMuted ?? this.inkMuted,
    hairline: hairline ?? this.hairline,
    brand: brand ?? this.brand,
    onBrand: onBrand ?? this.onBrand,
    brandText: brandText ?? this.brandText,
    brandTint: brandTint ?? this.brandTint,
    live: live ?? this.live,
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    logoChip: logoChip ?? this.logoChip,
  );

  /// Theme switches are instant (no colour tween), so lerp snaps.
  @override
  AppPalette lerp(covariant AppPalette? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension AppPaletteContext on BuildContext {
  /// Palette of the nearest Theme (registers a dependency, so the caller
  /// rebuilds when the theme changes). Falls back to [AppPalette.active].
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.active;
}
