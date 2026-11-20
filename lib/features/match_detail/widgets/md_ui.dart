import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/seam_strip.dart';
import '../logic/commentary_html.dart';

/// Shared Match Centre building blocks: section titles, the single-ball
/// bead, tabular number tables and the commentary paragraph. Containment is
/// by hierarchy (hairlines and spacing), never a stack of identical cards.

/// Section heading inside a tab ("At the crease", "Batting").
class MdSectionTitle extends StatelessWidget {
  const MdSectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(0, Spacing.xl, 0, Spacing.sm)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Spacing.md,
        runSpacing: Spacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(text, style: AppFont.style(size: 16, weight: FontWeight.w700, color: p.ink, height: 1.25)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Muted one-line note ("Partnership runs are derived from fall of wickets").
class MdNote extends StatelessWidget {
  const MdNote(this.text, {super.key, this.padding = const EdgeInsets.only(top: Spacing.sm)});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text, style: AppText.meta.copyWith(color: context.palette.inkMuted)));
}

/// Small sentence-case tag ("not out", "C", "WK", "derived").
class MdTag extends StatelessWidget {
  const MdTag(this.text, {super.key, this.strong = false});
  final String text;

  /// Ink fill (e.g. "on strike"); default is an outlined chip.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: strong ? p.ink : null,
        border: strong ? null : Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: AppFont.style(size: 12, weight: FontWeight.w700, color: strong ? p.surface : p.inkMuted, height: 1.2),
      ),
    );
  }
}

/// One delivery as a bead, same encoding as the Seam strip (never
/// colour-only): dot = small neutral dot; 1-3 = hairline ring + digit; 4 =
/// brandText ring; 6 = solid brand + onBrand digit; W = inverted ink, squarer
/// corners; extras / unknown = dashed outline + label.
class BallBead extends StatelessWidget {
  const BallBead(this.label, {super.key, this.size = 30});
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ball = Ball.parse(label);
    return Semantics(
      label: ball.description,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: CustomPaint(size: Size.square(size), painter: _BeadPainter(ball, context.palette)),
      ),
    );
  }
}

class _BeadPainter extends CustomPainter {
  _BeadPainter(this.ball, this.p);
  final Ball ball;
  final AppPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;
    var text = p.ink;
    switch (ball.kind) {
      case BallKind.dot:
        canvas.drawCircle(c, r * 0.86, fill..color = p.surface);
        canvas.drawCircle(c, r * 0.86, stroke..color = p.hairline..strokeWidth = 1);
        canvas.drawCircle(c, r * 0.22, Paint()..color = p.inkMuted);
        return;
      case BallKind.runs:
        canvas.drawCircle(c, r * 0.86, fill..color = p.surface);
        canvas.drawCircle(c, r * 0.86, stroke..color = p.inkMuted.withValues(alpha: 0.6)..strokeWidth = 1.2);
      case BallKind.four:
        canvas.drawCircle(c, r * 0.9, fill..color = p.surface);
        canvas.drawCircle(c, r * 0.9 - 1.25, stroke..color = p.brandText..strokeWidth = 2.5);
        text = p.brandText;
      case BallKind.six:
        canvas.drawCircle(c, r * 0.95, fill..color = p.brand);
        text = p.onBrand;
      case BallKind.wicket:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: r * 0.9), Radius.circular(r * 0.35)),
          fill..color = p.ink,
        );
        text = p.surface;
      case BallKind.extra:
      case BallKind.unknown:
        canvas.drawCircle(c, r * 0.86, fill..color = p.surface);
        final path = Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.86));
        final paint = stroke
          ..color = p.inkMuted
          ..strokeWidth = 1.3;
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 4.5) {
            canvas.drawPath(m.extractPath(d, math.min(d + 2.5, m.length)), paint);
          }
        }
    }
    final glyph = ball.glyph;
    final small = ball.kind == BallKind.extra || glyph.length > 1;
    _text(canvas, glyph.length > 3 ? glyph.substring(0, 3) : glyph, c, small ? r * 0.62 : r * 0.82, text);
    if (ball.kind == BallKind.extra && ball.runs > 0) {
      _text(canvas, '${ball.runs}', c.translate(r * 0.62, -r * 0.62), r * 0.5, p.ink);
    }
  }

  void _text(Canvas canvas, String s, Offset c, double size, Color color) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: s, style: AppFont.style(size: size, weight: FontWeight.w800, color: color, tabularFigures: true, height: 1)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_BeadPainter old) => old.ball != ball || old.p != p;
}

/// API commentary HTML (bold/italic only) as one rich Text, parsed once.
class CommentaryRichParagraph extends StatelessWidget {
  const CommentaryRichParagraph({super.key, required this.runs, this.style});
  final List<CommentaryTextRun> runs;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? AppText.reading.copyWith(color: context.palette.ink);
    return Text.rich(
      TextSpan(children: [
        for (final r in runs)
          TextSpan(
            text: r.text,
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.w700 : FontWeight.w400,
              fontVariations: AppFont.axes(r.bold ? FontWeight.w700 : FontWeight.w400),
              fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
      ]),
      style: base,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Number table
// ─────────────────────────────────────────────────────────────────────────────

/// One row of a [NumTable].
class NumRow {
  const NumRow({
    this.key,
    required this.name,
    this.detail,
    this.tags = const [],
    this.leading,
    required this.values,
    this.strongValue = 0,
    this.semanticsLabel,
    this.onTap,
  });
  final Key? key;
  final String name;

  /// Second line under the name (dismissal, "on strike" …), muted.
  final String? detail;
  final List<Widget> tags;
  final Widget? leading;
  final List<String> values;

  /// Column index drawn bold (runs for batters, wickets for bowlers); -1 none.
  final int strongValue;
  final String? semanticsLabel;
  final VoidCallback? onTap;
}

/// Batting / bowling style table: a flexible name column and right-aligned
/// tabular number columns. Column widths are measured with the current text
/// scale; when they no longer fit (narrow phones, large text) the table
/// scrolls horizontally instead of squeezing or overflowing.
class NumTable extends StatelessWidget {
  const NumTable({super.key, required this.nameHeader, required this.columns, required this.rows, this.minNameWidth = 128});
  final String nameHeader;
  final List<String> columns;
  final List<NumRow> rows;
  final double minNameWidth;

  static const double _hPad = Spacing.sm;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scaler = MediaQuery.textScalerOf(context);
    final numStyle = AppFont.style(size: 14, weight: FontWeight.w500, color: p.ink, tabularFigures: true, height: 1.25);
    final headStyle = AppFont.style(size: 12, weight: FontWeight.w600, color: p.inkMuted, height: 1.25);
    double measure(String s, TextStyle st) {
      final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
        ..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final widths = <double>[
      for (var i = 0; i < columns.length; i++)
        math.max(
          36,
          [
            measure(columns[i], headStyle),
            for (final r in rows)
              if (i < r.values.length) measure(r.values[i], AppFont.withWeight(numStyle, FontWeight.w800)),
          ].fold<double>(0, math.max) +
              Spacing.md,
        ),
    ];
    final nameMin = minNameWidth * scaler.scale(14) / 14;
    final needed = nameMin + widths.fold<double>(0, (a, b) => a + b) + _hPad * 2;

    Widget table(double width) {
      Widget cells(List<Widget> named, List<String> vals, TextStyle Function(int) st) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: named)),
              for (var i = 0; i < widths.length; i++)
                SizedBox(
                  width: widths[i],
                  child: Text(i < vals.length ? vals[i] : '', textAlign: TextAlign.right, maxLines: 1, style: st(i)),
                ),
            ],
          );
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: p.surfaceAlt,
              padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: Spacing.xs + 2),
              child: cells([Text(nameHeader, style: headStyle, maxLines: 1)], columns, (_) => headStyle),
            ),
            for (var r = 0; r < rows.length; r++)
              _row(context, rows[r], r == 0, cells, numStyle),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      if (!c.hasBoundedWidth || c.maxWidth >= needed) return table(c.hasBoundedWidth ? c.maxWidth : needed);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: table(needed),
      );
    });
  }

  Widget _row(
    BuildContext context,
    NumRow row,
    bool first,
    Widget Function(List<Widget>, List<String>, TextStyle Function(int)) cells,
    TextStyle numStyle,
  ) {
    final p = context.palette;
    final name = <Widget>[
      Wrap(
        spacing: Spacing.xs + 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ?row.leading,
          Text(row.name, style: AppFont.style(size: 14, weight: FontWeight.w600, color: p.ink, height: 1.3)),
          ...row.tags,
        ],
      ),
      if (row.detail != null && row.detail!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2, right: Spacing.sm),
          child: Text(row.detail!, style: AppFont.style(size: 13, weight: FontWeight.w400, color: p.inkMuted, height: 1.3)),
        ),
    ];
    Widget child = Container(
      key: row.key,
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: Spacing.sm + 2),
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: p.hairline))),
      child: cells(name, row.values, (i) => i == row.strongValue ? AppFont.withWeight(numStyle, FontWeight.w800) : numStyle),
    );
    if (row.onTap != null) child = InkWell(onTap: row.onTap, child: child);
    if (row.semanticsLabel != null) {
      child = Semantics(label: row.semanticsLabel, container: true, excludeSemantics: true, button: row.onTap != null, child: child);
    }
    return child;
  }
}

/// Label / value list used by the Info tab and the over-end card.
class MdKeyValue extends StatelessWidget {
  const MdKeyValue({super.key, required this.label, required this.value, this.onTap, this.valueKey});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = Text(
      value,
      key: valueKey,
      style: AppFont.style(size: 15, weight: FontWeight.w500, color: onTap != null ? p.brandText : p.ink, height: 1.35),
    );
    Widget child = Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm + 2),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.4;
        final l = Text(label, style: AppFont.style(size: 13, weight: FontWeight.w500, color: p.inkMuted, height: 1.35));
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [l, const SizedBox(height: 2), v]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: l),
          const SizedBox(width: Spacing.md),
          Expanded(child: v),
        ]);
      }),
    );
    if (onTap != null) child = InkWell(onTap: onTap, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: child,
    );
  }
}
