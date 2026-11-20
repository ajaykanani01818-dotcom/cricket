import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../motion/motion.dart';
import '../theme/app_theme.dart';

/// What happened on one delivery.
enum BallKind { dot, runs, four, six, wicket, extra, unknown }

/// Extras type (wide / no-ball are not legal deliveries; bye / leg-bye are).
enum ExtraType { wide, noBall, bye, legBye }

/// One delivery parsed from the API's ball label ("0", "1", "4", "6", "WK",
/// "W", "NB", "1WD", "2LB", "B", "•" …). Unknown labels are kept raw.
@immutable
class Ball {
  const Ball._(this.kind, this.raw, {this.runs = 0, this.extra});

  final BallKind kind;
  final String raw;
  final int runs;
  final ExtraType? extra;

  static final _extraRe = RegExp(r'^(\d*)\s*(WD|NB|LB|B)\s*(\d*)$');

  factory Ball.parse(String? label) {
    final raw = (label ?? '').trim();
    final u = raw.toUpperCase();
    if (u.isEmpty || u == '0' || u == '•' || u == '.' || u == '·') {
      return Ball._(BallKind.dot, raw);
    }
    if (u == 'W' ||
        u == 'WK' ||
        u == 'WKT' ||
        RegExp(r'^W\+?\d$').hasMatch(u)) {
      return Ball._(BallKind.wicket, raw);
    }
    final n = int.tryParse(u);
    if (n != null) {
      if (n == 4) return Ball._(BallKind.four, raw, runs: 4);
      if (n == 6) return Ball._(BallKind.six, raw, runs: 6);
      return Ball._(BallKind.runs, raw, runs: n);
    }
    final m = _extraRe.firstMatch(u);
    if (m != null) {
      final runs =
          int.tryParse(m.group(1)!.isNotEmpty ? m.group(1)! : m.group(3)!) ?? 0;
      final type = switch (m.group(2)) {
        'WD' => ExtraType.wide,
        'NB' => ExtraType.noBall,
        'LB' => ExtraType.legBye,
        _ => ExtraType.bye,
      };
      return Ball._(BallKind.extra, raw, runs: runs, extra: type);
    }
    return Ball._(BallKind.unknown, raw);
  }

  /// Wides and no-balls are not legal deliveries (PRD).
  bool get isLegal =>
      !(kind == BallKind.extra &&
          (extra == ExtraType.wide || extra == ExtraType.noBall));

  /// Text drawn on the bead.
  String get glyph => switch (kind) {
    BallKind.dot => '',
    BallKind.runs || BallKind.four || BallKind.six => '$runs',
    BallKind.wicket => 'W',
    BallKind.extra => switch (extra!) {
      ExtraType.wide => 'wd',
      ExtraType.noBall => 'nb',
      ExtraType.bye => 'b',
      ExtraType.legBye => 'lb',
    },
    BallKind.unknown => raw,
  };

  /// Spoken description, e.g. "Four", "2 runs", "No ball, 1 run".
  String get description {
    String runsText(int r) => r == 1 ? '1 run' : '$r runs';
    return switch (kind) {
      BallKind.dot => 'Dot ball',
      BallKind.runs => runsText(runs),
      BallKind.four => 'Four',
      BallKind.six => 'Six',
      BallKind.wicket => 'Wicket',
      BallKind.extra =>
        '${switch (extra!) {
          ExtraType.wide => 'Wide',
          ExtraType.noBall => 'No ball',
          ExtraType.bye => 'Bye',
          ExtraType.legBye => 'Leg bye',
        }}${runs > 0 ? ', ${runsText(runs)}' : ''}',
      BallKind.unknown => raw.isEmpty ? 'Unknown ball' : raw,
    };
  }

  @override
  bool operator ==(Object other) => other is Ball && other.raw == raw;
  @override
  int get hashCode => raw.hashCode;
  @override
  String toString() => 'Ball($raw)';
}

/// How a new list of balls relates to the previous one.
enum SeamChange { none, oneNew, catchUp, newOver }

/// Diff used for the "only animate genuinely new balls" rule.
/// - [SeamChange.oneNew]: exactly one ball appended → that bead drops in.
/// - [SeamChange.catchUp]: >1 appended in one update → NO replay, the
///   final state shows with a "+N balls" chip (research §9.3).
/// - [SeamChange.newOver]: not a continuation (new over / different
///   innings) → no animation.
({SeamChange change, int added}) diffBalls(
  List<Ball> before,
  List<Ball> after,
) {
  if (before.length == after.length && _prefix(before, after)) {
    return (change: SeamChange.none, added: 0);
  }
  if (after.length > before.length && _prefix(before, after)) {
    final added = after.length - before.length;
    return (
      change: added == 1 ? SeamChange.oneNew : SeamChange.catchUp,
      added: added,
    );
  }
  return (change: SeamChange.newOver, added: 0);
}

bool _prefix(List<Ball> a, List<Ball> b) {
  if (a.length > b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The Seam strip: this over's balls as beads on a dashed seam arc.
///
/// Encoding (never colour-only): dot = small neutral bead; 1-3 (and 5) =
/// neutral bead with the digit; 4 = brandText ring; 6 = solid brand bead with
/// an onBrand digit; W = inverted ink bead with squarer corners; extras =
/// dashed outline + "wd"/"nb"/"b"/"lb" and a runs superscript. Each bead is
/// its own semantics node ("Ball 3: Four").
///
/// Motion: a bead drops in only when exactly ONE new ball is appended after
/// the first build; several at once (catch-up) show the final state plus a
/// "+N balls" chip. Painted in a RepaintBoundary; the animation repaints
/// only, never rebuilds.
class SeamStrip extends StatefulWidget {
  const SeamStrip({
    super.key,
    required this.balls,
    this.overLabel,
    this.summary,
    this.minSlots = 6,
  });

  /// Raw labels convenience: `SeamStrip.labels(['1','0','4'])`.
  SeamStrip.labels(
    List<String> labels, {
    Key? key,
    String? overLabel,
    String? summary,
  }) : this(
         key: key,
         balls: [for (final l in labels) Ball.parse(l)],
         overLabel: overLabel,
         summary: summary,
       );

  final List<Ball> balls;

  /// e.g. "Ov 61" (left of the strip header).
  final String? overLabel;

  /// e.g. "5 runs" (right of the strip header).
  final String? summary;

  /// Bead slots on the arc (width comes from the count, never assumed 6;
  /// extras add slots).
  final int minSlots;

  @override
  State<SeamStrip> createState() => _SeamStripState();
}

class _SeamStripState extends State<SeamStrip>
    with SingleTickerProviderStateMixin {
  AnimationController? _drop;
  int _catchUp = 0;

  AnimationController get _ctrl => _drop ??= AnimationController(
    vsync: this,
    duration: Motion.beadDrop,
    value: 1,
  );

  @override
  void didUpdateWidget(SeamStrip old) {
    super.didUpdateWidget(old);
    final d = diffBalls(old.balls, widget.balls);
    switch (d.change) {
      case SeamChange.none:
        break;
      case SeamChange.oneNew:
        _catchUp = 0;
        if (!Motion.reducedOf(context) &&
            TickerMode.valuesOf(context).enabled) {
          _ctrl.forward(from: 0);
        }
      case SeamChange.catchUp:
        _drop?.value = 1;
        _catchUp = d.added;
      case SeamChange.newOver:
        _drop?.value = 1;
        _catchUp = 0;
    }
  }

  @override
  void dispose() {
    _drop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final bead = width < 360 ? 28.0 : 32.0;
    final header =
        (widget.overLabel != null || widget.summary != null || _catchUp > 1)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.overLabel != null)
                  Text(
                    widget.overLabel!,
                    style: AppText.small.copyWith(color: p.ink),
                  ),
                if (widget.summary != null)
                  Text(widget.summary!, style: AppText.small),
                if (_catchUp > 1)
                  Container(
                    key: const ValueKey('seam_catch_up'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: p.brandTint,
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Text(
                      '+$_catchUp balls',
                      style: AppText.small.copyWith(color: p.ink),
                    ),
                  ),
              ],
            ),
          )
        : null;
    final strip = RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('seam_strip_paint'),
        size: Size(double.infinity, bead * 2),
        painter: SeamPainter(
          balls: widget.balls,
          palette: p,
          bead: bead,
          minSlots: widget.minSlots,
          drop: _drop,
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: 1.3),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [?header, strip],
    );
  }
}

/// Paints the seam and beads. Public for golden/unit tests.
class SeamPainter extends CustomPainter {
  SeamPainter({
    required this.balls,
    required this.palette,
    required this.bead,
    this.minSlots = 6,
    this.drop,
    this.textScaler = TextScaler.noScaling,
  }) : super(repaint: drop);

  final List<Ball> balls;
  final AppPalette palette;
  final double bead;
  final int minSlots;
  final Animation<double>? drop;
  final TextScaler textScaler;

  int get slots => math.max(minSlots, balls.length);

  /// Centre of bead [k] for a canvas of [size].
  Offset beadCenter(int k, Size size, double r) {
    final x0 = r + 2, x1 = size.width - r - 2;
    final y0 = size.height - r - 2;
    final yc = 2 * (r + 2) - y0;
    final t = (k + 0.5) / slots;
    final x = x0 + (x1 - x0) * t;
    final y = (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * yc + t * t * y0;
    return Offset(x, y);
  }

  double _radius(Size size) {
    final spacing = (size.width - 4) / slots;
    return math.min(bead, spacing - 3) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = _radius(size);
    if (r <= 2) return;
    // Seam: dashed quadratic arc.
    final x0 = 2.0, x1 = size.width - 2;
    final y0 = size.height - r - 2;
    final yc = 2 * (r + 2) - y0;
    final seam = Path()
      ..moveTo(x0, y0)
      ..quadraticBezierTo(size.width / 2, yc, x1, y0);
    _dashed(
      canvas,
      seam,
      Paint()
        ..color = palette.inkMuted.withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
      3,
      3,
    );

    for (var k = 0; k < balls.length; k++) {
      var c = beadCenter(k, size, r);
      var scale = 1.0;
      final isDropping =
          k == balls.length - 1 && drop != null && drop!.value < 1;
      if (isDropping) {
        final t = Curves.easeOut.transform(drop!.value);
        c = c.translate(0, -12 * (1 - t));
        scale = 0.8 + 0.2 * t;
      }
      _bead(canvas, balls[k], c, r * scale);
    }
  }

  void _bead(Canvas canvas, Ball b, Offset c, double r) {
    final p = palette;
    final stroke = Paint()..style = PaintingStyle.stroke;
    final fill = Paint()..style = PaintingStyle.fill;
    Color textColor = p.ink;
    switch (b.kind) {
      case BallKind.dot:
        canvas.drawCircle(c, r * 0.32, fill..color = p.inkMuted);
        return;
      case BallKind.runs:
        canvas.drawCircle(c, r * 0.86, fill..color = p.surface);
        canvas.drawCircle(
          c,
          r * 0.86,
          stroke
            ..color = p.inkMuted.withValues(alpha: 0.6)
            ..strokeWidth = 1.2,
        );
      case BallKind.four:
        canvas.drawCircle(c, r * 0.9, fill..color = p.surface);
        canvas.drawCircle(
          c,
          r * 0.9 - 1.25,
          stroke
            ..color = p.brandText
            ..strokeWidth = 2.5,
        );
        textColor = p.brandText;
      case BallKind.six:
        canvas.drawCircle(c, r, fill..color = p.brand);
        textColor = p.onBrand;
      case BallKind.wicket:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: c, radius: r * 0.92),
            Radius.circular(r * 0.35),
          ),
          fill..color = p.ink,
        );
        textColor = p.surface;
      case BallKind.extra:
      case BallKind.unknown:
        canvas.drawCircle(c, r * 0.86, fill..color = p.surface);
        _dashed(
          canvas,
          Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.86)),
          stroke
            ..color = p.inkMuted
            ..strokeWidth = 1.3,
          2.5,
          2,
        );
    }
    final small = b.kind == BallKind.extra || b.glyph.length > 1;
    _text(canvas, b.glyph, c, small ? r * 0.62 : r * 0.82, textColor);
    if (b.kind == BallKind.extra && b.runs > 0) {
      _text(
        canvas,
        '${b.runs}',
        c.translate(r * 0.78, -r * 0.72),
        r * 0.5,
        p.ink,
      );
    }
  }

  void _text(Canvas canvas, String s, Offset c, double size, Color color) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: AppFont.style(
          size: size,
          weight: FontWeight.w800,
          color: color,
          tabularFigures: true,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
    final r = _radius(size);
    if (r <= 2) return const [];
    return [
      for (var k = 0; k < balls.length; k++)
        CustomPainterSemantics(
          key: ValueKey('seam_ball_$k'),
          rect: Rect.fromCircle(center: beadCenter(k, size, r), radius: r),
          properties: SemanticsProperties(
            label: 'Ball ${k + 1}: ${balls[k].description}',
            textDirection: ui.TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRepaint(SeamPainter old) =>
      old.palette != palette ||
      old.bead != bead ||
      old.minSlots != minSlots ||
      !_sameBalls(old.balls, balls);

  @override
  bool shouldRebuildSemantics(SeamPainter oldDelegate) =>
      !_sameBalls(oldDelegate.balls, balls) || oldDelegate.bead != bead;

  static bool _sameBalls(List<Ball> a, List<Ball> b) =>
      a.length == b.length && _prefix(a, b);
}
