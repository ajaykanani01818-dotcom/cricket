import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';

/// Opens external links (mailto/https). Swappable in tests.
class LinkLauncher {
  LinkLauncher._();

  static Future<bool> Function(Uri uri) opener = _defaultOpen;

  static Future<bool> _defaultOpen(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    // canLaunchUrl can be a false negative on Android 11+ without <queries>;
    // still try once, guarded.
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Opens [uri]; shows a SnackBar naming the fix when nothing can handle it.
  static Future<bool> open(
    BuildContext context,
    Uri uri, {
    Future<bool> Function(Uri uri)? via,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool ok;
    try {
      ok = await (via ?? opener)(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      final message = uri.scheme == 'mailto'
          ? 'No email app found. Copy the address instead.'
          : "Couldn't open the link. Check your connection, then try again.";
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
    }
    return ok;
  }
}

/// Back that works under GoRouter and a plain Navigator.
void goBack(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
  } else {
    Navigator.maybePop(context);
  }
}

/// Readable line length for long text on tablets and desktops.
const double kReadingMaxWidth = 680;

/// Info page shell: top bar with back, optional legal banners (zero height
/// while no ad is loaded) and a scrolling, width-capped column.
class LegalPageLayout extends StatelessWidget {
  const LegalPageLayout({
    super.key,
    required this.title,
    required this.children,
    this.showBanners = true,
    this.footer,
  });
  final String title;
  final List<Widget> children;
  final bool showBanners;

  /// Shown after [children] (e.g. "Open on web").
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = Responsive.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: Column(
        children: [
          ScreenTitle(title: title),
          if (showBanners)
            const ScreenBannerSlots(screen: 'legal', onlyPosition: 'top'),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('legal_scroll'),
              padding: EdgeInsets.fromLTRB(
                r.horizontalPadding,
                Spacing.xl,
                r.horizontalPadding,
                Spacing.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...children,
                      if (footer != null)
                        Align(alignment: Alignment.centerLeft, child: footer),
                      if (showBanners)
                        const ScreenBannerSlots(
                          screen: 'legal',
                          onlyPosition: 'bottom',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled block of reading text (About / Support pages).
class LegalSection extends StatelessWidget {
  const LegalSection({
    super.key,
    this.title,
    this.paragraphs = const [],
    this.children = const [],
  });
  final String? title;
  final List<String> paragraphs;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Text(
                title!,
                style: AppText.sectionTitle.copyWith(color: p.ink),
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          for (final t in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(t, style: AppText.reading.copyWith(color: p.ink)),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// "Open on web" link under a bundled legal document.
class OpenOnWebLink extends StatelessWidget {
  const OpenOnWebLink({
    super.key,
    required this.url,
    this.label = 'Open on web',
  });
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.lg),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: p.brandText,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        ),
        onPressed: () => LinkLauncher.open(context, Uri.parse(url)),
        icon: Icon(Icons.open_in_new, size: 18, color: p.brandText),
        label: Text(label, style: AppText.name.copyWith(color: p.brandText)),
      ),
    );
  }
}
