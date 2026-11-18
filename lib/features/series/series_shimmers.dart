import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/shimmer_box.dart';

/// Ported from RN `SeriesShimmer` (6 skeleton series cards).
class SeriesShimmer extends StatelessWidget {
  const SeriesShimmer({super.key, this.bottomPadding = 0});
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    Widget card() => Container(
          margin: const EdgeInsets.only(bottom: Spacing.md),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const ShimmerBox(width: 8, height: 8, radius: 4),
              const SizedBox(width: Spacing.sm),
              const ShimmerBox(width: 48, height: 12, radius: 4),
              const SizedBox(width: Spacing.sm),
              Container(width: 1, height: 12, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 2)),
              const SizedBox(width: Spacing.sm),
              const ShimmerBox(width: 32, height: 12, radius: 4),
              const Spacer(),
              const ShimmerBox(width: 64, height: 12, radius: 4),
            ]),
            const SizedBox(height: Spacing.md),
            const FractionallySizedBox(widthFactor: 0.85, child: ShimmerBox(height: 16, radius: 4)),
            const SizedBox(height: Spacing.sm),
            const FractionallySizedBox(widthFactor: 0.6, child: ShimmerBox(height: 16, radius: 4)),
            const SizedBox(height: Spacing.md),
            const Align(alignment: Alignment.centerRight, child: ShimmerBox(width: 16, height: 16, radius: 4)),
          ]),
        );
    return ShimmerGroup(
      key: const ValueKey('series_shimmer'),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, bottomPadding),
        children: List.generate(6, (_) => card()),
      ),
    );
  }
}

/// Ported from RN `SeriesDetailShimmer` (5 fixture skeleton rows in one card).
class SeriesDetailShimmer extends StatelessWidget {
  const SeriesDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerGroup(
      key: const ValueKey('series_detail_shimmer'),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                const Row(children: [
                  ShimmerBox(width: 24, height: 24, radius: 6),
                  SizedBox(width: 10),
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: ShimmerBox(width: 180, height: 14, radius: 4))),
                  ShimmerBox(width: 60, height: 20, radius: 6),
                ]),
                const SizedBox(height: 10),
                const Row(children: [
                  ShimmerBox(width: 40, height: 40, radius: 20),
                  SizedBox(width: 10),
                  Expanded(child: ShimmerBox(height: 12, radius: 4)),
                  SizedBox(width: 10),
                  ShimmerBox(width: 28, height: 12, radius: 4),
                  SizedBox(width: 10),
                  Expanded(child: ShimmerBox(height: 12, radius: 4)),
                  SizedBox(width: 10),
                  ShimmerBox(width: 40, height: 40, radius: 20),
                ]),
                if (i < 4) Container(height: 1, color: AppColors.borderSubtle, margin: const EdgeInsets.only(top: 16)),
              ]),
            ),
        ]),
      ),
    );
  }
}
