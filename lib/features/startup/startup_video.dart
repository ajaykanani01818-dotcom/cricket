import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Cold-start brand intro played from `assets/video/splash.mp4`
/// (1080x1920, 60 fps, rendered by docs/brand/source/make_splash_video.py).
///
/// Decoding happens on the platform's video decoder, so the animation stays
/// smooth even while Dart is busy building Home underneath.
///
/// Same contract as the code-drawn intro: [onReveal] when the exit fade
/// starts (Home must be painted underneath), [onDone] when finished. If the
/// video cannot be loaded in time, [onUnavailable] is called so the host can
/// fall back to the code-drawn intro.
class StartupVideoIntro extends StatefulWidget {
  const StartupVideoIntro({
    super.key,
    required this.onReveal,
    required this.onDone,
    required this.onUnavailable,
  });

  final VoidCallback onReveal;
  final VoidCallback onDone;
  final VoidCallback onUnavailable;

  static const asset = 'assets/video/splash.mp4';

  /// Tests turn this off (no platform video decoder there) and exercise the
  /// code-drawn intro instead.
  static bool enabled = true;

  /// Fade into Home starts here (the last frames are a hold on the logo).
  static const revealAt = Duration(milliseconds: 1780);
  static const fade = Duration(milliseconds: 220);

  /// The video must be ready by then, otherwise fall back.
  static const initTimeout = Duration(milliseconds: 8000);

  /// Hard stop: never block the app on the intro.
  static const failSafe = Duration(milliseconds: 4000);

  static VideoPlayerController? _preloaded;
  static Future<void>? _preloadInit;

  /// Call at the very start of `main()`: the decoder spins up while the
  /// native splash is still on screen, so the video is ready on first frame.
  static void preload() {
    if (!enabled || _preloaded != null) return;
    final c = VideoPlayerController.asset(
      asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _preloaded = c;
    _preloadInit = c.initialize();
  }

  @override
  State<StartupVideoIntro> createState() => _StartupVideoIntroState();
}

class _StartupVideoIntroState extends State<StartupVideoIntro> {
  late final VideoPlayerController _v;
  late final Future<void> _init;
  Timer? _initTimer;
  Timer? _failSafe;
  bool _ready = false;
  bool _fading = false;
  bool _finished = false;
  final _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    _sw.start();
    StartupVideoIntro.preload();
    _v = StartupVideoIntro._preloaded!;
    _init = StartupVideoIntro._preloadInit!;
    StartupVideoIntro._preloaded = null;
    StartupVideoIntro._preloadInit = null;
    _initTimer = Timer(StartupVideoIntro.initTimeout, () {
      if (!_ready && mounted) _fallback();
    });
    _init.then((_) async {
      if (!mounted || _finished) return;
      await _v.setVolume(0);
      await _v.setLooping(false);
      _v.addListener(_onTick);
      await _v.play();
      if (!mounted) return;
      _initTimer?.cancel();
      debugPrint('[Intro] video ready in ${_sw.elapsedMilliseconds} ms');
      _failSafe = Timer(StartupVideoIntro.failSafe, _finish);
      setState(() => _ready = true);
    }, onError: (Object e) {
      debugPrint('[Intro] video init error: $e');
      if (mounted) _fallback();
    });
  }

  void _fallback() {
    if (_finished) return;
    _finished = true;
    _initTimer?.cancel();
    debugPrint('[Intro] video unavailable -> code-drawn fallback');
    widget.onUnavailable();
  }

  void _onTick() {
    final v = _v.value;
    if (v.hasError) {
      _finish();
      return;
    }
    if (!_fading &&
        (v.position >= StartupVideoIntro.revealAt ||
            (v.duration > Duration.zero && v.position >= v.duration))) {
      _fading = true;
      widget.onReveal();
      setState(() {});
      Timer(StartupVideoIntro.fade, _finish);
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _failSafe?.cancel();
    _initTimer?.cancel();
    widget.onReveal();
    widget.onDone();
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    _failSafe?.cancel();
    _v.removeListener(_onTick);
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _v.value.size;
    return Semantics(
      container: true,
      label: 'Cric Ticker. Every match. Every ball.',
      onTapHint: 'Skip intro',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: StartupVideoIntro.fade,
          curve: Curves.easeIn,
          child: ColoredBox(
            color: const Color(0xFF17130F),
            child: _ready && size.width > 0
                ? SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: VideoPlayer(_v),
                      ),
                    ),
                  )
                : const ColoredBox(
                    color: Color(0xFF17130F),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Image(
                          image: AssetImage('assets/brand/icon_mark.png'),
                          width: 176,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
