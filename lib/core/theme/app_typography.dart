import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/painting.dart';

/// Archivo variable font (assets/fonts/Archivo.ttf, OFL; subset to Latin +
/// figures; axes wght 400-900, wdth 72-100, default instance wght 400 /
/// wdth 100).
///
/// Variable axes are always set explicitly through [AppFont.axes]: the
/// engine does not derive `wght` from [TextStyle.fontWeight] on every
/// platform. The pubspec registers the same file at weights 400-900 so the
/// engine never adds synthetic bold on top of the variation.
class AppFont {
  AppFont._();

  static const family = 'Archivo';

  /// Narrow width used for every score numeral.
  static const double scoreWidth = 72;

  static List<FontVariation> axes(FontWeight weight, [double width = 100]) => [
    FontVariation('wght', weight.value.toDouble()),
    if (width != 100) FontVariation('wdth', width),
  ];

  static const tabular = [FontFeature.tabularFigures()];

  /// One Archivo style. [width] 72 = score numerals, 100 = everything else.
  static TextStyle style({
    required double size,
    FontWeight weight = FontWeight.w400,
    double width = 100,
    bool tabularFigures = false,
    double? height,
    double? letterSpacing,
    Color? color,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    fontVariations: axes(weight, width),
    fontFeatures: tabularFigures ? tabular : null,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
  );

  /// Re-applies the `wght` axis after a `copyWith(fontWeight: ...)`.
  static TextStyle withWeight(TextStyle s, FontWeight w) {
    final width =
        s.fontVariations
            ?.where((v) => v.axis == 'wdth')
            .map((v) => v.value)
            .firstOrNull ??
        100;
    return s.copyWith(fontWeight: w, fontVariations: axes(w, width));
  }

  /// Archivo + the variation matching each style's weight, for a Material
  /// [TextTheme].
  static TextTheme textTheme(TextTheme base, Color ink, Color muted) {
    TextStyle f(TextStyle? s, {Color? color}) {
      final w = s?.fontWeight ?? FontWeight.w400;
      // Variations are NOT set here: a TextStyle merges with this default,
      // and an inherited `wght` axis would override a child's fontWeight.
      return (s ?? const TextStyle()).copyWith(
        fontFamily: family,
        fontWeight: w,
        color: color ?? ink,
        letterSpacing: 0,
      );
    }

    return base.copyWith(
      displayLarge: f(base.displayLarge),
      displayMedium: f(base.displayMedium),
      displaySmall: f(base.displaySmall),
      headlineLarge: f(base.headlineLarge),
      headlineMedium: f(base.headlineMedium),
      headlineSmall: f(base.headlineSmall),
      titleLarge: f(base.titleLarge),
      titleMedium: f(base.titleMedium),
      titleSmall: f(base.titleSmall),
      bodyLarge: f(base.bodyLarge),
      bodyMedium: f(base.bodyMedium),
      bodySmall: f(base.bodySmall, color: muted),
      labelLarge: f(base.labelLarge),
      labelMedium: f(base.labelMedium),
      labelSmall: f(base.labelSmall, color: muted),
    );
  }
}
