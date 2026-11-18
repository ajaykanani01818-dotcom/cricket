import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/shimmer_box.dart';
import '../ads/ads.dart';

/// Opens external links (mailto/https). Swappable in tests.
class LinkLauncher {
  LinkLauncher._();

  static Future<bool> Function(Uri uri) opener = _defaultOpen;

  static Future<bool> _defaultOpen(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    // canLaunchUrl can be a false negative on Android 11+ without <queries>;
    // still try once, guarded.
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Opens [uri]; shows a SnackBar when nothing can handle it.
  static Future<void> open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool ok;
    try {
      ok = await opener(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text("Couldn't open the link"), duration: Duration(seconds: 2)));
    }
  }
}

/// RN `navigation.goBack()` — works under GoRouter and plain Navigator.
void goBack(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
  } else {
    Navigator.maybePop(context);
  }
}

/// Header with a glass back button + title (RN legal/More header).
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 3,
      shadowColor: const Color(0x0A000000),
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: Spacing.lg),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderSubtle))),
          child: Row(children: [
            Semantics(
              button: true,
              label: 'Go back',
              child: InkResponse(
                key: const ValueKey('settings_back'),
                onTap: onBack,
                radius: 24,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Icon(Icons.chevron_left, size: 22, color: AppColors.text),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: 0.2)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Bottom padding for scroll content: floating tab bar inset (provided by the
/// shell via MediaQuery) + fixed banner reserve (RN TAB_BAR_HEIGHT + FIXED_BOTTOM_RESERVE).
double scrollBottomReserve(BuildContext context) => MediaQuery.paddingOf(context).bottom + kFixedBottomReserve + Spacing.xl;

/// RN `LegalPageLayout`: back header, legal top banner, scrolling content with
/// a bottom banner after the content.
class LegalPageLayout extends StatelessWidget {
  const LegalPageLayout({super.key, required this.title, required this.children, this.onBack, this.showBanners = true});
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool showBanners;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        BackHeader(title: title, onBack: onBack ?? () => goBack(context)),
        if (showBanners) const ScreenBannerSlots(screen: 'legal', onlyPosition: 'top'),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('legal_scroll'),
            padding: EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, scrollBottomReserve(context)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ...children,
              if (showBanners) const ScreenBannerSlots(screen: 'legal', onlyPosition: 'bottom'),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// RN `sectionStyles`.
class LegalText {
  LegalText._();
  static const sectionTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: 0.2);
  static const paragraph = TextStyle(fontSize: 14, height: 22 / 14, color: AppColors.textSecondary);
  static const lastUpdated = TextStyle(fontSize: 12, color: AppColors.textMuted);
}

/// A titled section (RN `sectionStyles.section` + `sectionTitle` + paragraphs).
class LegalSection extends StatelessWidget {
  const LegalSection({super.key, this.title, this.paragraphs = const [], this.bullets = const [], this.children = const []});
  final String? title;
  final List<String> paragraphs;
  final List<String> bullets;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) ...[Text(title!, style: LegalText.sectionTitle), const SizedBox(height: Spacing.md)],
        ...children,
        for (final p in paragraphs) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(p, style: LegalText.paragraph)),
        for (final b in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: Spacing.lg),
            child: Text('• $b', style: LegalText.paragraph),
          ),
      ]),
    );
  }
}

/// RN `LegalPageShimmer`.
class LegalPageShimmer extends StatelessWidget {
  const LegalPageShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerGroup(
      key: const ValueKey('legal_shimmer'),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShimmerBox(width: w * 0.9, height: 28, radius: 6, margin: const EdgeInsets.only(bottom: 16)),
            for (var i = 0; i < 10; i++)
              ShimmerBox(width: i.isEven ? w : w * 0.85, height: 14, radius: 4, margin: const EdgeInsets.only(bottom: 10)),
            const SizedBox(height: 60),
          ]);
        },
      ),
    );
  }
}

/// RN `MoreShimmer` — skeleton for the More menu (kept for future async use).
class MoreShimmer extends StatelessWidget {
  const MoreShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ShimmerBox(width: 100, height: 12, radius: 4, margin: EdgeInsets.only(bottom: 12, left: 4)),
        for (var i = 0; i < 5; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: const Row(children: [
              ShimmerBox(width: 40, height: 40, radius: 20),
              SizedBox(width: 14),
              Expanded(child: Align(alignment: Alignment.centerLeft, child: ShimmerBox(width: 160, height: 16, radius: 4))),
              ShimmerBox(width: 20, height: 20, radius: 4),
            ]),
          ),
        const SizedBox(height: 40),
      ]),
    );
  }
}

/// Short initial shimmer (RN Terms/About: 100ms) before rendering content.
class DelayedContent extends StatefulWidget {
  const DelayedContent({super.key, required this.builder, this.delay = const Duration(milliseconds: 100)});
  final WidgetBuilder builder;
  final Duration delay;

  @override
  State<DelayedContent> createState() => _DelayedContentState();
}

class _DelayedContentState extends State<DelayedContent> {
  bool _ready = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(widget.delay, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready ? widget.builder(context) : const LegalPageShimmer();
}
