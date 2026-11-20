import 'dart:ui' show Color, Size;

/// User-facing brand strings and assets. Never hard-code the app name
/// anywhere else: swapping the brand (or the pending final logo) is a change
/// to this file and the asset it points at.
class Brand {
  Brand._();

  static const appName = 'Cric Ticker';
  static const tagline = 'Every match. Every ball.';

  // ── Brand artwork (owner-supplied, processed by tool/brand/build_assets.py).
  /// Full logo (orange C + "Cric Ticker" in ink) for LIGHT surfaces.
  static const logoLight = 'assets/brand/logo_light.png';

  /// Same logo with light lettering (#F7F1EA) for DARK surfaces.
  static const logoDark = 'assets/brand/logo_dark.png';

  /// Flat orange C mark; works on any surface.
  static const logoMark = 'assets/brand/logo_mark.png';

  /// Glowing gradient C + speed lines (the launcher / splash mark). Dark
  /// surfaces only.
  static const iconMark = 'assets/brand/icon_mark.png';

  /// 1080x2400 dark stadium (floodlights, orange pitch glow near the bottom)
  /// behind the animated intro.
  static const splashBackground = 'assets/brand/splash_stadium.jpg';

  /// Pixel sizes of the artwork above (for aspect ratios and cacheWidth caps).
  static const logoPx = Size(1200, 315);
  static const iconMarkPx = Size(720, 514);

  /// Width / height of [logoLight] / [logoDark].
  static const logoAspect = 1200 / 315;

  /// Width / height of [splashBackground].
  static const splashBgAspect = 1080 / 2400;

  /// Width / height of [iconMark].
  static const iconMarkAspect = 720 / 514;

  /// Splash / intro scene colours (same in light and dark theme).
  static const splashBg = Color(0xFF17130F);
  static const splashInk = Color(0xFFF7F1EA);
  static const orange = Color(0xFFED800C);

  /// Store listing ids (native applicationId / bundle id are set natively).
  static const playStoreId = 'com.cricticker.app';
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$playStoreId';
  static const appStoreSearchUrl =
      'https://apps.apple.com/search?term=Cric%20Ticker&entity=software';

  // ── Contact & legal (owner-provided). Null = not available: the UI must
  // hide the field entirely, never show placeholder text. ──
  static const supportEmail = 'ajaykanani01818@gmail.com';

  /// Feedback goes to the support inbox.
  static const feedbackEmail = supportEmail;
  static const feedbackSubject = '$appName Feedback';
  static const websiteUrl = 'https://ajaykanani01818-dotcom.github.io/cricket/';
  static const privacyUrl =
      'https://ajaykanani01818-dotcom.github.io/cricket/privacy-policy.html';
  static const termsUrl =
      'https://ajaykanani01818-dotcom.github.io/cricket/terms.html';
  static const supportUrl =
      'https://ajaykanani01818-dotcom.github.io/cricket/support.html';
  static const String? phone = null;
  static const String? address = null;
  static const String? twitterUrl = null;
  static const String? instagramUrl = null;
  static const String? facebookUrl = null;
  static const String? appStoreId = null;

  /// mailto: link for feedback.
  static Uri feedbackMailUri() => Uri.parse(
    'mailto:$feedbackEmail?subject=${Uri.encodeComponent(feedbackSubject)}',
  );
}
