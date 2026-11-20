import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'live_pill.dart';

/// Plain surface container: surface fill, hairline outline, NO shadow
/// (containment by hierarchy; perf budget forbids shadows). Old name kept.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = Radii.card,
    this.noBorder = false,
    this.padding,
    this.margin,
    this.color,
  });
  final Widget child;
  final double radius;
  final bool noBorder;
  final EdgeInsetsGeometry? padding, margin;

  /// Defaults to the palette surface.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: noBorder ? null : Border.all(color: p.hairline),
      ),
      child: child,
    );
  }
}

/// Live / Completed / Upcoming / Cancelled.
enum StatusKind { live, completed, upcoming, cancelled }

/// Match status chip. Live = [LivePill] (red is reserved for live); the
/// other states are quiet sentence-case labels distinguished by shape and
/// word, never by colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.kind, this.label});
  final StatusKind kind;

  /// Overrides the default word ("Live", "Result", "Upcoming", "Cancelled").
  final String? label;

  static String defaultLabel(StatusKind k) => switch (k) {
    StatusKind.live => 'Live',
    StatusKind.completed => 'Result',
    StatusKind.upcoming => 'Upcoming',
    StatusKind.cancelled => 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = label ?? defaultLabel(kind);
    if (kind == StatusKind.live) return LivePill(label: text, dense: true);
    final (Color fg, Color? bg, Color? border) = switch (kind) {
      StatusKind.completed => (p.ink, p.surfaceAlt, null),
      StatusKind.upcoming => (p.brandText, null, p.hairline),
      _ => (p.inkMuted, null, p.hairline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.chip),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            AppFont.style(
              size: 12,
              weight: FontWeight.w700,
              color: fg,
              height: 1.2,
            ).copyWith(
              decoration: kind == StatusKind.cancelled
                  ? TextDecoration.lineThrough
                  : null,
            ),
      ),
    );
  }
}

/// Old name for [StatusChip] (same constructor).
class StatusBadge extends StatusChip {
  const StatusBadge({super.key, required super.kind, super.label});
}

/// Format tag ("T20", "ODI", "Test"): outlined 4 px chip, ink text. Format
/// codes are data, so their case is kept.
class FormatChip extends StatelessWidget {
  const FormatChip(this.format, {super.key});
  final String format;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        format,
        maxLines: 1,
        style: AppFont.style(
          size: 12,
          weight: FontWeight.w700,
          color: p.ink,
          height: 1.2,
        ),
      ),
    );
  }
}
