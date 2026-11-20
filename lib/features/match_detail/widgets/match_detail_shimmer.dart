import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_box.dart';

/// Loading skeleton that mirrors the Match Centre header (meta row, big
/// score, figures, situation line, other team, seam strip) and the tab bar.
/// Static blocks, one [ShimmerGroup].
class MatchDetailShimmer extends StatelessWidget {
  const MatchDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Loading match',
      child: ShimmerGroup(
        key: const ValueKey('match_detail_shimmer'),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              ShimmerBox(width: 52, height: 20, radius: 6),
              SizedBox(width: Spacing.sm),
              ShimmerBox(width: 40, height: 20, radius: 4),
            ]),
            const SizedBox(height: Spacing.lg),
            const Row(children: [
              ShimmerBox(width: 32, height: 32, radius: 7),
              SizedBox(width: Spacing.sm),
              ShimmerBox(width: 44, height: 22, radius: 4),
              SizedBox(width: Spacing.md),
              ShimmerBox(width: 128, height: 44, radius: 6),
            ]),
            const SizedBox(height: Spacing.sm),
            const ShimmerBox(width: 160, height: 14, radius: 4),
            const SizedBox(height: Spacing.md),
            const ShimmerBox(width: 220, height: 18, radius: 4),
            const SizedBox(height: Spacing.md),
            const Row(children: [
              ShimmerBox(width: 22, height: 22, radius: 5),
              SizedBox(width: Spacing.sm),
              ShimmerBox(width: 90, height: 16, radius: 4),
            ]),
            const SizedBox(height: Spacing.lg),
            const ShimmerBox(height: 64, radius: 8),
            const SizedBox(height: Spacing.lg),
            Container(height: 1, color: p.hairline),
            const SizedBox(height: Spacing.lg),
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: Spacing.md),
                child: ShimmerBox(height: 36, radius: 4),
              ),
          ]),
        ),
      ),
    );
  }
}
