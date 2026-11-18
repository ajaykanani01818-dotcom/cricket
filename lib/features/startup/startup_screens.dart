import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';

export 'app_chrome.dart' show AppChrome;
export 'onboarding_config.dart' show OnboardingConfig, shouldShowOnboarding, markOnboardingComplete;
export 'version_gate.dart' show VersionUpdateGate, VersionGateConfig, versionGateConfig, compareSemver, isUpdateRequired;

/// How long the branded splash is held. The loading bar fills over exactly
/// this long, so it never freezes part-filled when the splash hands off.
const Duration kSplashDuration = Duration(milliseconds: 1400);

/// CrickBex logo aspect (viewBox 1356.59 × 260).
const double _logoAspect = 260 / 1356.59;

/// Premium in-app splash — ported from RN `components/SplashScreen.tsx`.
///
/// No ads here by design: the splash is content-free, so an ad on it is an
/// AdMob policy risk and delays first paint of real content.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinish});

  /// Fired once the branded moment is over.
  final VoidCallback onFinish;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(vsync: this, duration: kSplashDuration);
  Timer? _hardTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // Hard timer as well as the animation: the animation can be interrupted
    // (ticker muted, reduced motion) and the app must never be stuck here.
    _hardTimer = Timer(kSplashDuration, _reportFinished);
    _bar.forward().whenCompleteOrCancel(() {
      if (_bar.isCompleted) _reportFinished();
    });
  }

  void _reportFinished() {
    if (_finished) return;
    _finished = true;
    _hardTimer?.cancel();
    widget.onFinish();
  }

  @override
  void dispose() {
    _hardTimer?.cancel();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final logoW = width * 0.62;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        key: const ValueKey('startup_splash'),
        backgroundColor: AppColors.pitch,
        body: Stack(children: [
          Positioned.fill(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SvgPicture.asset(
                  'assets/images/crickbex-logo.svg',
                  width: logoW,
                  height: logoW * _logoAspect,
                  semanticsLabel: 'CrickBex',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Live Cricket Scores. Real Time.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF), letterSpacing: 0.3),
                ),
              ]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 110 + bottomInset,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  width: width * 0.55,
                  height: 4,
                  color: const Color(0x40FFFFFF),
                  alignment: Alignment.centerLeft,
                  child: AnimatedBuilder(
                    animation: _bar,
                    builder: (_, _) => Container(
                      key: const ValueKey('startup_splash_bar'),
                      width: width * 0.5 * _bar.value,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Slide {
  const _Slide(this.key, this.title, this.subtitle, this.icon, this.colors);
  final String key, title, subtitle;
  final IconData icon;
  final List<Color> colors;
}

// crickbex.com brand: solid blue gradients + a centered icon.
const _slides = <_Slide>[
  _Slide('live', 'Live scores at your fingertips', 'Follow ball-by-ball scores, runs, wickets, and results in real time.',
      Icons.monitor_heart_outlined, [AppColors.pitchDark, AppColors.pitchLight]),
  _Slide('matches', 'Matches & series',
      'Browse live and upcoming fixtures, past results and tournaments from around the world in one place.', Icons.emoji_events,
      [AppColors.pitch, AppColors.pitchLight]),
  _Slide('rankings', 'Rankings & players',
      'Explore ICC rankings, player stats, career highlights and compare batters and bowlers across formats.', Icons.trending_up,
      [AppColors.pitchDark, AppColors.pitch]),
  _Slide('ready', "You're all set", 'Tap Get started to open the app and dive into live cricket scores, series and rankings.',
      Icons.check_circle, [AppColors.pitch, AppColors.pitchDark]),
];

/// Onboarding flow — 4 slides. Ported from RN `screens/OnboardingScreen.tsx`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  int _index = 0;

  /// True while the PageView is moving after Next — disables the button so
  /// fast taps can't stack (prevents index desync).
  bool _busy = false;

  /// Prevents a double "Get started" → onComplete.
  bool _completeLock = false;
  Timer? _fallback;

  /// CTA shimmer sweep: 1200ms sweep, then 3200ms pause (RN loop).
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400))
    ..repeat();

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _fallback?.cancel();
    _shimmer.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _unlock() {
    _fallback?.cancel();
    _fallback = null;
    if (mounted && _busy) setState(() => _busy = false);
  }

  void _goNext() {
    if (_isLast) {
      if (_completeLock) return;
      _completeLock = true;
      widget.onComplete();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    _fallback?.cancel();
    _fallback = Timer(const Duration(milliseconds: 650), _unlock);
    if (!_pages.hasClients) {
      _unlock();
      return;
    }
    _pages
        .animateToPage(_index + 1, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic)
        .whenComplete(_unlock);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final h = size.height;
    final small = h < 700;
    final large = h >= 900;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        key: const ValueKey('startup_onboarding'),
        backgroundColor: AppColors.white,
        body: Column(children: [
          Expanded(
            child: Stack(children: [
              PageView.builder(
                key: const ValueKey('onboarding_page_view'),
                controller: _pages,
                itemCount: _slides.length,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _SlideView(
                  key: ValueKey('onboarding_slide_${_slides[i].key}'),
                  slide: _slides[i],
                  index: i,
                  pages: _pages,
                  small: small,
                  large: large,
                  screenHeight: h,
                ),
              ),
              Positioned(
                top: insets.top + 14,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: SvgPicture.asset('assets/images/crickbex-logo.svg', width: 128, height: 128 * _logoAspect, semanticsLabel: 'CrickBex'),
                  ),
                ),
              ),
            ]),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              small ? 18 : (large ? 26 : 24),
              small ? 10 : (large ? 16 : 14),
              small ? 18 : (large ? 26 : 24),
              insets.bottom > (small ? 14 : 20) ? insets.bottom : (small ? 14 : 20),
            ),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: AppColors.borderNeutral)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    key: ValueKey('onboarding_dot_$i'),
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.pitch : const Color(0xFFD0D0D0),
                      borderRadius: BorderRadius.circular(i == _index ? 12 : 4),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              _CtaButton(
                label: _isLast ? 'Get started' : 'Next',
                icon: _isLast ? Icons.check : Icons.arrow_forward,
                disabled: _busy,
                small: small,
                shimmer: _shimmer,
                onTap: _goNext,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({
    super.key,
    required this.slide,
    required this.index,
    required this.pages,
    required this.small,
    required this.large,
    required this.screenHeight,
  });

  final _Slide slide;
  final int index;
  final PageController pages;
  final bool small, large;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    final textBottom = small ? -4.0 : (large ? 10.0 : 2.0);
    final cardPadY = small ? 14.0 : (large ? 20.0 : 18.0);
    final cardPadX = small ? 16.0 : 20.0;
    final blockPadX = small ? 16.0 : 22.0;
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: const Alignment(-0.6, -1), end: const Alignment(0.6, 1), colors: slide.colors),
          ),
        ),
        LayoutBuilder(
          builder: (context, c) => Padding(
            padding: EdgeInsets.only(top: c.maxHeight * 0.35),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(color: Color(0x1F0B5CD4), shape: BoxShape.circle),
                child: Icon(slide.icon, size: 64, color: AppColors.white),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: screenHeight * (small ? 0.46 : 0.5),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00FFFFFF), Color(0xD9FFFFFF), Color(0xFFFFFFFF)],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: textBottom,
          child: AnimatedBuilder(
            animation: pages,
            builder: (context, child) {
              double page = index.toDouble();
              if (pages.hasClients && pages.position.haveDimensions) page = pages.page ?? page;
              final d = (page - index).abs().clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - 0.55 * d,
                child: Transform.translate(offset: Offset(0, 14 * d), child: child),
              );
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: blockPadX),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: cardPadX, vertical: cardPadY),
                decoration: BoxDecoration(
                  color: const Color(0xEBFFFFFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderNeutral),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(slide.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: small ? 23 : (large ? 28 : 26), fontWeight: FontWeight.w800, color: const Color(0xFF1A1A1A))),
                  const SizedBox(height: 10),
                  Text(slide.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: small ? 14 : 15, height: (small ? 20 : 22) / (small ? 14 : 15), color: const Color(0xFF555555))),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.icon,
    required this.disabled,
    required this.small,
    required this.shimmer,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool disabled, small;
  final Animation<double> shimmer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = disabled ? AppColors.textMuted : AppColors.white;
    return Stack(clipBehavior: Clip.none, children: [
      if (!disabled)
        Positioned(
          left: -2,
          right: -2,
          top: -2,
          bottom: -2,
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.pitchLight.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)),
          ),
        ),
      Semantics(
        button: true,
        enabled: !disabled,
        label: label,
        child: Opacity(
          opacity: disabled ? 0.9 : 1,
          child: Material(
            elevation: disabled ? 0 : 8,
            shadowColor: AppColors.pitchDark.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('onboarding_next'),
              onTap: disabled ? null : onTap,
              child: Ink(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: disabled ? const [AppColors.border, AppColors.border] : const [AppColors.pitchLight, AppColors.pitch],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, c) => Stack(alignment: Alignment.center, children: [
                    if (!disabled)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: shimmer,
                          builder: (context, _) {
                            // Sweep during the first 1200ms of each 4400ms cycle.
                            final t = shimmer.value * 4400 / 1200;
                            if (t >= 1) return const SizedBox.shrink();
                            final travel = c.maxWidth < 120 ? 120.0 : c.maxWidth;
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: Offset(c.maxWidth / 2 - 22 + (-travel + 2 * travel * t), 0),
                                child: Transform.rotate(
                                  angle: 18 * 3.1415926535 / 180,
                                  child: Container(width: 44, height: 68, color: const Color(0x57FFFFFF)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(label, style: TextStyle(fontSize: small ? 15 : 16, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: fg)),
                      const SizedBox(width: 8),
                      Icon(icon, size: small ? 18 : 20, color: fg),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
