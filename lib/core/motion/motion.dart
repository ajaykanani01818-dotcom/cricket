import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Motion tokens (research §9). One orchestrated moment (match card → Match
/// Centre) plus feedback motion that answers REAL new data or a tap. No
/// entrance animations on lists or sections.
///
/// Every duration must go through [Motion.of]/[MotionSpec.d] so reduced
/// motion (`MediaQuery.disableAnimations`) turns it into a 100 ms crossfade
/// (or nothing).
class Motion {
  Motion._();

  // ── durations ──
  static const tap = Duration(milliseconds: 110);
  static const digitRoll = Duration(milliseconds: 220);
  static const beadDrop = Duration(milliseconds: 180);
  static const boundaryRing = Duration(milliseconds: 400);
  static const wicketBandIn = Duration(milliseconds: 240);
  static const wicketBandOut = Duration(milliseconds: 200);
  static const wicketBandHold = Duration(milliseconds: 2500);
  static const wicketFlash = Duration(milliseconds: 600);
  static const overCompress = Duration(milliseconds: 260);
  static const statusCrossfade = Duration(milliseconds: 200);
  static const sharedElement = Duration(milliseconds: 320);
  static const sharedElementReverse = Duration(milliseconds: 250);
  static const tabSwitch = Duration(milliseconds: 250);
  static const reduced = Duration(milliseconds: 100);
  static const livePulsePeriod = Duration(milliseconds: 1600);

  // ── curves ──
  /// M3 emphasized decelerate: the shared-element moment.
  static const emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const standard = Curves.easeOutCubic;
  static const enter = Curves.easeOut;

  /// Max simultaneous transient animations (plus one shared live pulse).
  static const maxTransient = 3;

  static bool reducedOf(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static MotionSpec of(BuildContext context) =>
      MotionSpec(reduced: reducedOf(context));
}

/// Resolved motion for one build.
@immutable
class MotionSpec {
  const MotionSpec({required this.reduced});
  final bool reduced;

  /// [d] normally; [Motion.reduced] (a short crossfade) when reduced.
  Duration d(Duration d) => reduced ? Motion.reduced : d;

  /// [d] normally; zero when reduced (for movement that has no crossfade
  /// equivalent, e.g. scale on press).
  Duration orZero(Duration d) => reduced ? Duration.zero : d;
}

/// ONE ticker shared by every live dot on screen (research §9: "one shared
/// AnimationController drives every live dot"). Value pulses 1.0 → 0.35 →
/// 1.0 every [Motion.livePulsePeriod]. The ticker runs only while at least
/// one listener is attached, so offstage tabs (which detach) and a disposed
/// tree cost nothing; frames stop anyway while the app is backgrounded.
class SharedPulse extends ChangeNotifier implements ValueListenable<double> {
  SharedPulse._();
  static final SharedPulse instance = SharedPulse._();

  Ticker? _ticker;
  int _listeners = 0;
  double _value = 1;

  @override
  double get value => _value;

  bool get isTicking => _ticker?.isActive ?? false;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listeners++;
    if (_listeners == 1) {
      _ticker ??= Ticker(_onTick, debugLabel: 'SharedPulse');
      if (!_ticker!.isActive) _ticker!.start();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listeners = (_listeners - 1).clamp(0, 1 << 30);
    if (_listeners == 0) {
      _ticker?.stop();
      _value = 1;
    }
  }

  void _onTick(Duration elapsed) {
    final period = Motion.livePulsePeriod.inMicroseconds;
    final t = (elapsed.inMicroseconds % period) / period; // 0..1
    // Triangle 0→1→0, eased.
    final tri = t < 0.5 ? t * 2 : (1 - t) * 2;
    _value = 1 - 0.65 * Curves.easeInOut.transform(tri);
    notifyListeners();
  }
}
