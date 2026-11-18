import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ported from RN `GlassCard` (rendered as a crisp white card with a hairline border).
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.radius = Radii.lg, this.noBorder = false, this.padding, this.margin, this.color = AppColors.card});
  final Widget child;
  final double radius;
  final bool noBorder;
  final EdgeInsetsGeometry? padding, margin;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: noBorder ? null : Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: child,
      );
}

/// LIVE / Completed / Upcoming style pill.
enum StatusKind { live, completed, upcoming, cancelled }

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.kind, this.label});
  final StatusKind kind;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String text) = switch (kind) {
      StatusKind.live => (AppColors.live, AppColors.redTint, 'LIVE'),
      StatusKind.completed => (const Color(0xFF15803D), const Color(0xFFDCFCE7), 'COMPLETED'),
      StatusKind.upcoming => (AppColors.goldDark, const Color(0xFFFEF3C7), 'UPCOMING'),
      StatusKind.cancelled => (AppColors.voidText, AppColors.neutralSurface, 'CANCELLED'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.full)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (kind == StatusKind.live) ...[
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
          const SizedBox(width: 4),
        ],
        Text(label ?? text, style: AppText.badge.copyWith(color: fg)),
      ]),
    );
  }
}
