import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/app_theme.dart';

/// The live dot. Every dot on screen is driven by the ONE [SharedPulse]
/// ticker; it repaints (never rebuilds) inside its own RepaintBoundary, and
/// the colour alpha changes (no Opacity layer). It detaches from the pulse
/// while its subtree is offstage (TickerMode off) and is static with reduced
/// motion.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8, this.color});
  final double size;

  /// Defaults to the palette's live colour.
  final Color? color;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> {
  bool _attached = false;
  final _repaint = _Relay();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldPulse =
        TickerMode.valuesOf(context).enabled && !Motion.reducedOf(context);
    if (shouldPulse != _attached) {
      _attached = shouldPulse;
      if (shouldPulse) {
        SharedPulse.instance.addListener(_repaint.ping);
      } else {
        SharedPulse.instance.removeListener(_repaint.ping);
      }
    }
  }

  @override
  void dispose() {
    if (_attached) SharedPulse.instance.removeListener(_repaint.ping);
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _DotPainter(
        color: widget.color ?? context.palette.live,
        pulse: _attached,
        repaint: _repaint,
      ),
    ),
  );
}

class _Relay extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.color,
    required this.pulse,
    required Listenable repaint,
  }) : super(repaint: repaint);
  final Color color;
  final bool pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final a = pulse ? SharedPulse.instance.value : 1.0;
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      Paint()..color = color.withValues(alpha: color.a * a),
    );
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color || old.pulse != pulse;
}

/// "Live" pill: pulsing dot + the word, in the live colour (the word means
/// it is never colour-only). [label] lets a caller say e.g. "Live, 2nd inns".
class LivePill extends StatelessWidget {
  const LivePill({
    super.key,
    this.label = 'Live',
    this.filled = false,
    this.dense = false,
  });
  final String label;

  /// Filled: live-tinted background (headers); default text-only (cards).
  final bool filled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = AppFont.style(
      size: dense ? 12 : 13,
      weight: FontWeight.w800,
      color: p.live,
      height: 1.1,
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveDot(size: dense ? 7 : 8),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text,
          ),
        ),
      ],
    );
    return Semantics(
      label: label,
      container: true,
      excludeSemantics: true,
      child: filled
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: dense ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: p.liveTint,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
              child: row,
            )
          : row,
    );
  }
}
