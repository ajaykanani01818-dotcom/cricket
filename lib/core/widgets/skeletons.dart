import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'shimmer_box.dart';

/// Skeletons that mirror the real layouts (Home: live card, then flat
/// rows). Use them for first loads only; refreshes keep showing data.

/// Mirrors [LiveMatchCard]: surface, 3 dp brand edge, meta line, two team
/// rows with scores, status line.
class SkeletonLiveCard extends StatelessWidget {
  const SkeletonLiveCard({
    super.key,
    this.margin = const EdgeInsets.symmetric(
      horizontal: Spacing.lg,
      vertical: Spacing.sm,
    ),
  });
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget team() => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: const [
          ShimmerBox(width: 28, height: 28, radius: 6),
          SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ShimmerBox(width: 90, height: 14),
            ),
          ),
          ShimmerBox(width: 64, height: 20),
        ],
      ),
    );
    return ShimmerGroup(
      child: Container(
        margin: margin,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border(left: BorderSide(color: p.surfaceAlt, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(width: 160, height: 12),
            team(),
            team(),
            const SizedBox(height: 12),
            const ShimmerBox(width: 200, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Mirrors a flat match row (teams + score on one line, meta below).
class SkeletonMatchRow extends StatelessWidget {
  const SkeletonMatchRow({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.palette.hairline)),
    ),
    child: const ShimmerGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ShimmerBox(width: 120, height: 14),
                ),
              ),
              ShimmerBox(width: 56, height: 16),
            ],
          ),
          SizedBox(height: 8),
          ShimmerBox(width: 180, height: 12),
        ],
      ),
    ),
  );
}

/// A first-load list: [cards] live cards then [rows] flat rows. Not
/// scrollable (put it where the list will be).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.cards = 1, this.rows = 4});
  final int cards, rows;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('skeleton_list'),
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < cards; i++) const SkeletonLiveCard(),
      for (var i = 0; i < rows; i++) const SkeletonMatchRow(),
    ],
  );
}
