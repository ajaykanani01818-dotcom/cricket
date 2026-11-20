import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/brand/brand.dart';
import '../../core/theme/app_theme.dart';
import 'startup_video.dart';

/// Cold-start intro (brand brief §9.6, owner storyboard
/// docs/brand/source/splash_source.gif):
///
/// | ms        | what happens                                              |
/// |-----------|-----------------------------------------------------------|
/// | 0         | identical to the native splash: icon mark centred on #17130F |
/// | 0–380     | stadium fades in behind (slight 1.05 → 1 settle)          |
/// | 60–640    | glowing comet arc sweeps 270° round the mark, ball at head |
/// | 640–720   | ball lands in the C; arc fades (to 800)                   |
/// | 620–860   | mark pulse 1 → 1.07 → 1 (the one overshoot)               |
/// | 640–1000  | speed lines shoot out left of the mark, then fade         |
/// | 700–1000  | mark settles up to make room for the wordmark             |
/// | 780–1060  | "Cric Ticker" fades / slides in; tagline 880–1140         |
/// | 1140–1220 | hold                                                      |
/// | 1220–1400 | whole scene fades out to the (already loaded) Home        |
///
/// One [AnimationController]; every element reads it through an [Interval].
/// No MaskFilter blur, no saveLayer: the glow is stacked strokes and all
/// fades are paint alpha (no Opacity layers).
class IntroTimeline {
  IntroTimeline._();

  static const total = Duration(milliseconds: 1500);
  static const reducedHold = Duration(milliseconds: 350);

  /// Never block: whatever happens (slow first frame, background, ticker
  /// muted) the app is revealed this long after the intro was mounted.
  static const failSafe = Duration(milliseconds: 1550);

  static const double _ms = 1500;
  static Interval _i(double a, double b, [Curve c = Curves.linear]) =>
      Interval(a / _ms, b / _ms, curve: c);

  /// Fast out, slow in ("crisp").
  static const crisp = Cubic(0.2, 0, 0, 1);

  static final stadiumIn = _i(0, 480, Curves.easeOutCubic);
  static final comet = _i(60, 820, const Cubic(0.45, 0.05, 0.2, 1));
  static final ballLand = _i(820, 920, Curves.easeIn);
  static final arcFade = _i(780, 1000, Curves.easeOut);
  static final pulseUp = _i(800, 920, Curves.easeOutCubic);
  static final pulseDown = _i(920, 1080, Curves.easeInOutCubic);
  static final linesOut = _i(820, 1020, Curves.easeOutCubic);
  static final linesFade = _i(1020, 1220, Curves.easeIn);
  static final rise = _i(880, 1220, crisp);
  static final wordmark = _i(960, 1300, crisp);
  static final tagline = _i(1060, 1380, crisp);

  /// Home is made visible (under the scene) when the exit fade starts.
  static const double revealAt = 1360 / _ms;
  static final exit = _i(1360, 1500, Curves.easeInCubic);
}

/// Geometry shared by the native splash and the intro's first frame.
@immutable
class IntroGeometry {
  const IntroGeometry({required this.size, required this.platform});

  final Size size;
  final TargetPlatform platform;

  /// iOS LaunchScreen: LaunchImage (mark fitted in 150 pt) centred.
  /// Android 12+: splash_icon = mark fitted in 176 dp (+2 dp x) on a 288 dp
  /// canvas, centred. Everything else uses the Android geometry.
  bool get _ios => platform == TargetPlatform.iOS;
  double get markBox => _ios ? 150 : 176;
  Size get markSize => Size(markBox, markBox / Brand.iconMarkAspect);
  Offset get startCenter =>
      Offset(size.width / 2 + (_ios ? 0 : 2), size.height / 2);

  static const wordmarkGap = 18.0;
  static const wordmarkSize = 36.0;
  static const taglineGap = 6.0;
  static const taglineSize = 15.0;

  /// How far the mark settles up so mark + wordmark + tagline end centred.
  double get rise => (wordmarkGap + 44 + taglineGap + 20) / 2;

  /// Mark pixels decoded for this screen (matches [IntroAssets.markProvider]).
  static int markCacheWidth(double box, double dpr) =>
      (box * dpr).ceil().clamp(1, Brand.iconMarkPx.width.toInt());

  /// Stadium decode width: enough to cover the screen, rounded to 64 px
  /// buckets so warm-up and widget agree.
  static int stadiumCacheWidth(Size size, double dpr) {
    final need = math.max(size.width, size.height * Brand.splashBgAspect) * dpr;
    final bucket = ((need / 64).ceil() * 64);
    return bucket.clamp(64, 1080);
  }
}

/// Image providers used by the intro. [warmUp] (called from main before
/// runApp) decodes the mark so the first Flutter frame already shows it and
/// the hand-off from the native splash is invisible.
class IntroAssets {
  IntroAssets._();

  static ImageProvider markProvider(double box, double dpr) => ResizeImage(
    const AssetImage(Brand.iconMark),
    width: IntroGeometry.markCacheWidth(box, dpr),
  );

  static ImageProvider stadiumProvider(Size size, double dpr) => ResizeImage(
    const AssetImage(Brand.splashBackground),
    width: IntroGeometry.stadiumCacheWidth(size, dpr),
  );

  /// Decodes the mark (awaited, capped by [timeout]) and starts decoding the
  /// stadium (not awaited). Never throws.
  static Future<void> warmUp({
    Duration timeout = const Duration(milliseconds: 300),
  }) async {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final view = views.first;
      final dpr = view.devicePixelRatio;
      final size = view.physicalSize / dpr;
      final geo = IntroGeometry(size: size, platform: defaultTargetPlatform);
      final config = ImageConfiguration(
        devicePixelRatio: dpr,
        platform: defaultTargetPlatform,
        bundle: rootBundle,
      );
      unawaited(_decode(stadiumProvider(size, dpr), config));
      await _decode(
        markProvider(geo.markBox, dpr),
        config,
      ).timeout(timeout, onTimeout: () {});
    } catch (_) {}
  }

  static Future<void> _decode(ImageProvider provider, ImageConfiguration c) {
    final done = Completer<void>();
    final stream = provider.resolve(c);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(l);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(l);
      },
    );
    stream.addListener(l);
    return done.future;
  }
}

/// Puts the intro on top of the app on a cold start. The app ([child]) is
/// built underneath from the first frame, so Home starts its data requests
/// while the intro plays; it is kept unpainted (but alive, tickers on) until
/// the exit fade, then revealed. Not shown again on resume (state lives as
/// long as the app).
class StartupIntroHost extends StatefulWidget {
  const StartupIntroHost({
    super.key,
    required this.child,
    this.enabled = true,
    this.freezeAt,
  });

  final Widget child;

  /// false: [child] only (tests, web shots).
  final bool enabled;

  /// Debug/screenshot aid: hold the intro at this time (no auto-advance, no
  /// fail-safe). Tap still dismisses.
  final Duration? freezeAt;

  @override
  State<StartupIntroHost> createState() => _StartupIntroHostState();
}

class _StartupIntroHostState extends State<StartupIntroHost> {
  late bool _overlay = widget.enabled;
  late bool _appVisible = !widget.enabled;

  /// Video intro on real cold starts; the code-drawn intro is the fallback
  /// (video missing / slow to load), and is used for reduced motion and the
  /// screenshot freeze mode.
  bool _useVideo = true;

  void _reveal() {
    if (!mounted || _appVisible) return;
    setState(() => _appVisible = true);
  }

  void _done() {
    if (!mounted || !_overlay) return;
    setState(() {
      _appVisible = true;
      _overlay = false;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // maintainSize/State/Animation: the app stays mounted, laid out and
      // ticking (pollers see it as visible) but is not painted, hit-tested
      // or exposed to semantics while the opaque intro covers it.
      Visibility(
        visible: _appVisible,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: widget.child,
      ),
      if (_overlay)
        if (_useVideo &&
            StartupVideoIntro.enabled &&
            widget.freezeAt == null &&
            !(MediaQuery.maybeOf(context)?.disableAnimations ?? false))
          StartupVideoIntro(
            key: const ValueKey('startup_video'),
            onReveal: _reveal,
            onDone: _done,
            onUnavailable: () {
              if (mounted) setState(() => _useVideo = false);
            },
          )
        else
          StartupIntro(
            key: const ValueKey('startup_intro'),
            onReveal: _reveal,
            onDone: _done,
            freezeAt: widget.freezeAt,
          ),
    ],
  );
}

/// The intro scene itself. Always dark (#17130F), in both themes.
class StartupIntro extends StatefulWidget {
  const StartupIntro({
    super.key,
    required this.onDone,
    this.onReveal,
    this.freezeAt,
  });

  /// Called once when the intro has finished (or was skipped).
  final VoidCallback onDone;

  /// Called when the exit fade starts (the app underneath must be painted).
  final VoidCallback? onReveal;
  final Duration? freezeAt;

  @override
  State<StartupIntro> createState() => _StartupIntroState();
}

class _StartupIntroState extends State<StartupIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: IntroTimeline.total,
  );
  late final Animation<double> _exitOpacity = Tween(
    begin: 1.0,
    end: 0.0,
  ).animate(CurvedAnimation(parent: _c, curve: IntroTimeline.exit));

  Timer? _failSafe;
  bool _started = false;
  bool _reduced = false;
  bool _revealed = false;
  bool _finished = false;

  ImageProvider? _markProvider;
  ImageProvider? _stadiumProvider;
  ImageStream? _stadiumStream;
  ImageStreamListener? _stadiumListener;
  ImageInfo? _stadium;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final geo = IntroGeometry(
      size: mq.size,
      platform: Theme.of(context).platform,
    );
    _markProvider ??= IntroAssets.markProvider(geo.markBox, dpr);
    if (_stadiumProvider == null) {
      _stadiumProvider = IntroAssets.stadiumProvider(mq.size, dpr);
      _resolveStadium();
    }
    if (!_started) {
      _started = true;
      _reduced = mq.disableAnimations || mq.accessibleNavigation;
      unawaited(precacheImage(_markProvider!, context, onError: (_, _) {}));
      _start();
    }
  }

  void _resolveStadium() {
    final stream = _stadiumProvider!.resolve(
      createLocalImageConfiguration(context),
    );
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        void apply() {
          _stadium?.dispose();
          _stadium = info;
        }

        // Already decoded (warm-up): the listener fires synchronously while
        // this widget is being built; no setState needed then.
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          apply();
        } else {
          setState(apply);
        }
      },
      onError: (_, _) {}, // stadium missing: plain #17130F scene.
    );
    stream.addListener(listener);
    _stadiumStream = stream;
    _stadiumListener = listener;
  }

  void _start() {
    final freeze = widget.freezeAt;
    if (freeze != null) {
      // After the first frame: the reveal / done callbacks rebuild the host.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _c.value = (freeze.inMicroseconds / IntroTimeline.total.inMicroseconds)
            .clamp(0.0, 1.0);
      });
      return;
    }
    if (_reduced) {
      // Static logo, no motion; then straight to the app.
      _c.value = 0;
      _failSafe = Timer(IntroTimeline.reducedHold, _finish);
      return;
    }
    _c.forward();
    _failSafe = Timer(IntroTimeline.failSafe, _finish);
  }

  void _onTick() {
    if (!_revealed && _c.value >= IntroTimeline.revealAt) {
      _revealed = true;
      widget.onReveal?.call();
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _failSafe?.cancel();
    _c.stop();
    widget.onReveal?.call();
    widget.onDone();
  }

  @override
  void dispose() {
    _failSafe?.cancel();
    final l = _stadiumListener;
    if (l != null) _stadiumStream?.removeListener(l);
    _stadium?.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final geo = IntroGeometry(size: size, platform: Theme.of(context).platform);
    final mark = geo.markSize;
    final start = geo.startCenter;
    final reduced = _reduced && widget.freezeAt == null;

    Widget markImage = Image(
      image: _markProvider!,
      width: mark.width,
      height: mark.height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      opacity: _exitOpacity,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => SizedBox.fromSize(size: mark),
    );

    return Semantics(
      container: true,
      label: '${Brand.appName}. ${Brand.tagline}',
      onTapHint: 'Skip intro',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: RepaintBoundary(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background, stadium, comet, ball, speed lines.
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _ScenePainter(
                      t: _c,
                      geo: geo,
                      stadium: _stadium?.image,
                      reduced: reduced,
                    ),
                  ),
                ),
                // The mark: same size / position as the native splash at t=0.
                Positioned(
                  left: start.dx - mark.width / 2,
                  top: start.dy - mark.height / 2,
                  width: mark.width,
                  height: mark.height,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, child) {
                      final v = _c.value;
                      final up = IntroTimeline.pulseUp.transform(v);
                      final down = IntroTimeline.pulseDown.transform(v);
                      final scale = 1 + 0.07 * up - 0.07 * down;
                      final dy = reduced
                          ? 0.0
                          : -geo.rise * IntroTimeline.rise.transform(v);
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.translationValues(0, dy, 0)
                          ..multiply(Matrix4.diagonal3Values(scale, scale, 1)),
                        child: child,
                      );
                    },
                    child: RepaintBoundary(child: markImage),
                  ),
                ),
                // Wordmark + tagline.
                Positioned(
                  left: 16,
                  right: 16,
                  top:
                      start.dy +
                      mark.height / 2 +
                      IntroGeometry.wordmarkGap -
                      (reduced ? 0 : geo.rise),
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) =>
                          _Lettering(t: _c.value, reduced: reduced),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Lettering extends StatelessWidget {
  const _Lettering({required this.t, required this.reduced});
  final double t;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final exit = 1 - IntroTimeline.exit.transform(t);
    final w = reduced ? 1.0 : IntroTimeline.wordmark.transform(t);
    final g = reduced ? 1.0 : IntroTimeline.tagline.transform(t);
    if (w == 0 && g == 0) return const SizedBox.shrink();
    Color a(Color c, double o) => c.withValues(alpha: c.a * o * exit);
    final word = AppFont.style(
      size: IntroGeometry.wordmarkSize,
      weight: FontWeight.w800,
      height: 1.15,
      letterSpacing: -0.6,
    ).copyWith(decoration: TextDecoration.none);
    final tag = AppFont.style(
      size: IntroGeometry.taglineSize,
      weight: FontWeight.w500,
      height: 1.3,
      letterSpacing: 0.2,
      color: a(Brand.splashInk.withValues(alpha: 0.78), g),
    ).copyWith(decoration: TextDecoration.none);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: Offset(0, 14 * (1 - w)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  style: word,
                  children: [
                    TextSpan(
                      text: 'Cric ',
                      style: TextStyle(color: a(Brand.splashInk, w)),
                    ),
                    TextSpan(
                      text: 'Ticker',
                      style: TextStyle(color: a(Brand.orange, w)),
                    ),
                  ],
                ),
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: IntroGeometry.taglineGap),
          Transform.translate(
            offset: Offset(0, 10 * (1 - g)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Brand.tagline,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: tag,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the whole scene except the mark and lettering. Repaints from the
/// controller (no widget rebuilds).
class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.t,
    required this.geo,
    required this.stadium,
    required this.reduced,
  }) : super(repaint: t);

  final Animation<double> t;
  final IntroGeometry geo;
  final ui.Image? stadium;
  final bool reduced;

  static const _bg = Brand.splashBg;
  static const _orange = Brand.orange;
  static const _hot = Color(0xFFFFC46B);
  static const _ballRed = Color(0xFFC63A1C);
  static const _ballLight = Color(0xFFE5603A);

  final _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final exit = 1 - IntroTimeline.exit.transform(v);
    _paint
      ..shader = null
      ..style = PaintingStyle.fill
      ..color = _bg.withValues(alpha: exit);
    canvas.drawRect(Offset.zero & size, _paint);
    if (exit <= 0) return;

    if (!reduced) _stadium(canvas, size, v, exit);
    if (reduced) return;

    final center = geo.startCenter.translate(
      0,
      -geo.rise * IntroTimeline.rise.transform(v),
    );
    _comet(canvas, center, v, exit);
    _speedLines(canvas, center, v, exit);
  }

  void _stadium(Canvas canvas, Size size, double v, double exit) {
    final img = stadium;
    if (img == null) return;
    final fade = IntroTimeline.stadiumIn.transform(v) * exit;
    if (fade <= 0) return;
    // Cover-fit, biased low so the floodlights + pitch glow stay in view on
    // wide screens; tiny 1.05 → 1 settle while it fades in.
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final s = math.max(size.width / iw, size.height / ih);
    final sw = size.width / s, sh = size.height / s;
    final src = Rect.fromLTWH((iw - sw) / 2, (ih - sh) * 0.86, sw, sh);
    final zoom = 1.05 - 0.05 * fade;
    final dst = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * zoom,
      height: size.height * zoom,
    );
    _paint
      ..color = Color.fromRGBO(255, 255, 255, fade)
      ..filterQuality = FilterQuality.low;
    canvas.drawImageRect(img, src, dst, _paint);
  }

  void _comet(Canvas canvas, Offset c, double v, double exit) {
    final p = IntroTimeline.comet.transform(v);
    if (p <= 0) return;
    final fade = (1 - IntroTimeline.arcFade.transform(v)) * exit;
    final mark = geo.markSize;
    final r = mark.width * 0.62;
    final rect = Rect.fromCircle(center: c, radius: r);
    const start = -math.pi / 4; // top-right
    const sweep = -1.5 * math.pi; // anticlockwise round the left: a "C"
    final head = start + sweep * p;
    final travelled = (sweep * p).abs();
    final tail = math.min(travelled, math.pi * 0.95);

    if (fade > 0 && tail > 0.001) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt;
      const n = 6;
      final seg = tail / n;
      for (var i = n - 1; i >= 0; i--) {
        // 1 at the head, tapering towards the tail end.
        final f = math.pow(1 - i / n, 0.7).toDouble();
        final a0 = head + seg * i;
        // three stacked strokes: wide faint glow → core
        _arc(canvas, rect, a0, seg, 28 * f, _orange, 0.14 * f * fade);
        _arc(canvas, rect, a0, seg, 14 * f, _orange, 0.38 * f * fade);
        _arc(canvas, rect, a0, seg, 5.5 * f, _hot, 1.0 * f * fade);
      }
    }

    // Ball at the head; lands into the C (shrinks + fades) after the sweep.
    final land = IntroTimeline.ballLand.transform(v);
    if (land >= 1) return;
    final ballPos = Offset.lerp(
      c + Offset(math.cos(head), math.sin(head)) * r,
      c + Offset(mark.width * 0.18, mark.height * 0.12),
      land,
    )!;
    final br = 11.0 * (1 - 0.7 * land);
    final ba = (1 - land) * exit;
    _ball(canvas, ballPos, br, ba, head * 2.2);
  }

  void _arc(
    Canvas canvas,
    Rect rect,
    double start,
    double sweep,
    double width,
    Color color,
    double alpha,
  ) {
    if (alpha <= 0 || width <= 0) return;
    _paint
      ..strokeWidth = width
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
    // +0.002 overlap hides hairline seams between butt-capped segments.
    canvas.drawArc(rect, start, sweep + 0.002, false, _paint);
  }

  void _ball(Canvas canvas, Offset o, double r, double alpha, double spin) {
    if (alpha <= 0 || r <= 0) return;
    _paint
      ..style = PaintingStyle.fill
      ..color = _orange.withValues(alpha: 0.22 * alpha);
    canvas.drawCircle(o, r * 1.9, _paint);
    _paint.color = _orange.withValues(alpha: 0.30 * alpha);
    canvas.drawCircle(o, r * 1.35, _paint);
    _paint.color = _ballRed.withValues(alpha: alpha);
    canvas.drawCircle(o, r, _paint);
    _paint.color = _ballLight.withValues(alpha: 0.85 * alpha);
    canvas.drawCircle(o.translate(-r * 0.28, -r * 0.3), r * 0.5, _paint);

    // Seam: two parallel stitched curves across the ball.
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(spin);
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, r * 0.13)
      ..color = Brand.splashInk.withValues(alpha: 0.9 * alpha);
    final big = Rect.fromCircle(center: Offset(-r * 1.9, 0), radius: r * 2.0);
    canvas.drawArc(big, -0.6, 1.2, false, _paint);
    final big2 = Rect.fromCircle(
      center: Offset(-r * 1.9, 0),
      radius: r * 2.0 + r * 0.32,
    );
    canvas.drawArc(big2, -0.55, 1.1, false, _paint);
    canvas.restore();
  }

  void _speedLines(Canvas canvas, Offset c, double v, double exit) {
    final out = IntroTimeline.linesOut.transform(v);
    if (out <= 0) return;
    final fade = (1 - IntroTimeline.linesFade.transform(v)) * exit;
    if (fade <= 0) return;
    final m = geo.markSize;
    // Rows line up with the speed lines baked into the mark's left side.
    const rows = [-0.33, -0.12, 0.08, 0.27];
    const lengths = [62.0, 96.0, 80.0, 52.0];
    final x0 = c.dx - m.width * 0.5 - 4;
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < rows.length; i++) {
      final y = c.dy + rows[i] * m.height;
      final len = lengths[i] * out;
      // Slight stagger: the lower lines trail a little.
      final head = x0 - 6 * i * (1 - out);
      final tailX = head - len;
      // Two stacked strokes (glow + core), each split in 3 fading segments.
      for (var s = 0; s < 3; s++) {
        final f = 1 - s / 3;
        final a = head - len * s / 3;
        final b = head - len * (s + 1) / 3;
        if (a <= tailX) break;
        _paint
          ..strokeWidth = 8
          ..color = _orange.withValues(alpha: 0.16 * f * fade);
        canvas.drawLine(Offset(a, y), Offset(b, y), _paint);
        _paint
          ..strokeWidth = 3.4
          ..color = (i.isEven ? _orange : _hot).withValues(
            alpha: 0.9 * f * fade,
          );
        canvas.drawLine(Offset(a, y), Offset(b, y), _paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.stadium != stadium ||
      old.geo.size != geo.size ||
      old.reduced != reduced ||
      old.t != t;
}
