import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/shimmer_box.dart';
import '../../core/widgets/skeletons.dart';

/// First-load skeleton for the series list: flat rows (name + meta line).
class SeriesShimmer extends StatelessWidget {
  const SeriesShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row() => Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(widthFactor: 0.75, child: ShimmerBox(height: 15)),
          SizedBox(height: Spacing.sm),
          ShimmerBox(width: 140, height: 12),
        ],
      ),
    );
    return ShimmerGroup(
      key: const ValueKey('series_shimmer'),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: Spacing.xxl),
        children: List.generate(8, (_) => row()),
      ),
    );
  }
}

/// First-load skeleton for a series hub tab: flat match rows.
class SeriesDetailShimmer extends StatelessWidget {
  const SeriesDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const ValueKey('series_detail_shimmer'),
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < 5; i++) ColoredBox(color: p.surface, child: const SkeletonMatchRow())],
    );
  }
}
