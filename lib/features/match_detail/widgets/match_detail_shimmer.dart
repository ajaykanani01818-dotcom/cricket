import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shimmer_box.dart';

/// Ported from RN `MatchDetailShimmer` — skeleton for the match detail screen
/// (ESPN-style horizontal score layout). One [ShimmerGroup] for the whole
/// skeleton = a single animation.
class MatchDetailShimmer extends StatelessWidget {
  const MatchDetailShimmer({super.key});

  static const _card = BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.all(Radius.circular(8)),
    border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
  );

  Widget _teamRow({bool border = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: border ? const Border(top: BorderSide(color: AppColors.border, width: 0.5)) : null),
        child: const Row(children: [
          ShimmerBox(width: 28, height: 28, radius: 14),
          SizedBox(width: 10),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: ShimmerBox(width: 80, height: 14, radius: 4))),
          SizedBox(width: 10),
          ShimmerBox(width: 70, height: 18, radius: 4),
        ]),
      );

  Widget _playerRow(double w1, double w2) => Row(children: [
        const ShimmerBox(width: 28, height: 28, radius: 14),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShimmerBox(width: c.maxWidth * w1, height: 13, radius: 4),
              const SizedBox(height: 4),
              ShimmerBox(width: c.maxWidth * w2, height: 11, radius: 3),
            ]),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return ShimmerGroup(
      key: const ValueKey('match_detail_shimmer'),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header: series + live badge, meta, score rows
            Container(
              padding: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    ShimmerBox(width: w * 0.5, height: 14, radius: 4),
                    const ShimmerBox(width: 48, height: 20, radius: 4),
                  ]),
                ),
                ShimmerBox(width: w * 0.65, height: 11, radius: 3, margin: const EdgeInsets.fromLTRB(16, 0, 16, 8)),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [_teamRow(), _teamRow(border: true)]),
                ),
              ]),
            ),
            // Tab bar
            Container(
              decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
              child: Row(children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: Stack(alignment: Alignment.center, children: [
                        const ShimmerBox(width: 48, height: 12, radius: 3),
                        if (i == 0)
                          Positioned(
                            bottom: 0,
                            child: Container(
                              width: w / 5 * 0.6,
                              height: 3,
                              decoration: BoxDecoration(color: AppColors.pitch, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                      ]),
                    ),
                  ),
              ]),
            ),
            // Tab content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: _card,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const ShimmerBox(width: 120, height: 15, radius: 4, margin: EdgeInsets.only(bottom: 12)),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var i = 0; i < 6; i++) const ShimmerBox(width: 34, height: 34, radius: 17),
                    ]),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: _card,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const ShimmerBox(width: 100, height: 15, radius: 4, margin: EdgeInsets.only(bottom: 12)),
                    _playerRow(0.7, 0.45),
                    const SizedBox(height: 10),
                    _playerRow(0.6, 0.4),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: _card,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const ShimmerBox(width: 110, height: 15, radius: 4, margin: EdgeInsets.only(bottom: 12)),
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          const ShimmerBox(width: 36, height: 36, radius: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (_, c2) => Align(
                                alignment: Alignment.centerLeft,
                                child: ShimmerBox(width: c2.maxWidth * 0.8, height: 13, radius: 4),
                              ),
                            ),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}
