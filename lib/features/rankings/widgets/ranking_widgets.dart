import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../../players/widgets/gradient_card.dart';
import '../ranking_models.dart';

/// Ported from RN `RankingPodium`: top 3 with medal rings (2 · 1 · 3).
class RankingPodium extends StatelessWidget {
  const RankingPodium({super.key, required this.items, this.onItemPress});
  final List<RankingRowItem> items;
  final ValueChanged<RankingRowItem>? onItemPress;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]..sort((a, b) => a.rank.compareTo(b.rank));
    final top = sorted.take(3).toList();
    RankingRowItem? pick(int rank, int index) {
      for (final i in top) {
        if (i.rank == rank) return i;
      }
      return index < top.length ? top[index] : null;
    }

    final r1 = pick(1, 0);
    if (r1 == null) return const SizedBox.shrink();
    final r2 = pick(2, 1);
    final r3 = pick(3, 2);

    Widget col(RankingRowItem? item, int rank, double h) => Expanded(
          child: item == null ? const SizedBox.shrink() : _PodiumColumn(item: item, rank: rank, height: h, onPress: onItemPress),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xBFFFFBEF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x40F59E0B)),
          boxShadow: const [BoxShadow(color: Color(0x24B45309), blurRadius: 18, offset: Offset(0, 8))],
        ),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            col(r2, 2, 86),
            const SizedBox(width: 8),
            col(r1, 1, 104),
            const SizedBox(width: 8),
            col(r3, 3, 70),
          ],
        ),
      ),
    );
  }
}

const _medal = {1: AppColors.gold, 2: AppColors.silver, 3: AppColors.bronze};
const _medalGradient = {
  1: [AppColors.goldLight, AppColors.gold],
  2: [AppColors.silverLight, AppColors.silver],
  3: [AppColors.bronzeLight, AppColors.bronze],
};
const _stepTint = {
  1: [Color(0xFFFFF8E8), AppColors.white],
  2: [Color(0xFFF5F6F7), AppColors.white],
  3: [Color(0xFFFBF0E8), AppColors.white],
};

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({required this.item, required this.rank, required this.height, this.onPress});
  final RankingRowItem item;
  final int rank;
  final double height;
  final ValueChanged<RankingRowItem>? onPress;

  @override
  Widget build(BuildContext context) {
    final grad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _medalGradient[rank]!);
    return Pressable(
      key: ValueKey('ranking_podium_$rank'),
      pressScale: 0.96,
      onTap: onPress == null ? null : () => onPress!(item),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (rank == 1)
          const Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.emoji_events, size: 20, color: AppColors.gold))
        else
          const SizedBox(height: 24),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              rank == 1
                  ? const BoxShadow(color: Color(0x66F59E0B), blurRadius: 10, offset: Offset(0, 3))
                  : const BoxShadow(color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                  child: NetImage(url: item.image, size: 62, fallbackLetter: item.name, fit: BoxFit.cover, background: AppColors.cardAlt),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: grad, border: Border.all(color: AppColors.white, width: 2)),
                  child: Text('$rank', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.white)),
                ),
              ),
            ]),
          ),
        ),
        Container(
          width: double.infinity,
          // Min height (not fixed) so large system font scales never overflow.
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _medal[rank]!.withValues(alpha: 0.2)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _stepTint[rank]!),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.1)),
            const SizedBox(height: 4),
            Text(item.ratingText,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: rank == 1 ? AppColors.goldDark : AppColors.text)),
            const SizedBox(height: 1),
            const Text('RATING', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
          ]),
        ),
      ]),
    );
  }
}

/// Ported from RN RankingScreen's inline `RankingListRow` (ranks 4–100).
class RankingListRow extends StatelessWidget {
  const RankingListRow({super.key, required this.item, required this.isTeam, this.onPress});
  final RankingRowItem item;
  final bool isTeam;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: isTeam ? null : onPress,
        child: Container(
          margin: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Spacing.md),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
              child: FittedBox(
                child: Text('${item.rank}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: -0.2)),
              ),
            ),
            const SizedBox(width: Spacing.md),
            RingAvatar(url: item.image, name: item.name, size: 40, ringPadding: 1.5),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.1)),
            ),
            const SizedBox(width: Spacing.md),
            Container(
              constraints: const BoxConstraints(minWidth: 54),
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs, horizontal: Spacing.sm),
              decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(10)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(item.ratingText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.text, letterSpacing: -0.3)),
                const SizedBox(height: 1),
                const Text('RATING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6)),
              ]),
            ),
          ]),
        ),
      );
}

/// Section label between podium and rows (blue accent + uppercase text).
class RankingSectionLabel extends StatelessWidget {
  const RankingSectionLabel({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 22, Spacing.lg, 10),
        child: Row(children: [
          Container(width: 3, height: 12, decoration: BoxDecoration(color: AppColors.pitch, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(text.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
          ),
        ]),
      );
}

/// Ported from RN `RankingShimmer`. [showControls] false when rendered below
/// the real segmented controls (RN repeated the control skeleton there).
class RankingShimmer extends StatelessWidget {
  const RankingShimmer({super.key, this.showControls = true});
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    Widget podiumCol(double h) => Expanded(
          child: Column(children: [
            const ShimmerBox(width: 72, height: 72, radius: 36, margin: EdgeInsets.only(bottom: 10)),
            ShimmerBox(height: h, radius: 14),
          ]),
        );
    return ShimmerGroup(
      key: const ValueKey('rankings_shimmer'),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomReserve(context)),
        children: [
          if (showControls)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(children: [
                ShimmerBox(height: 40, radius: 12),
                ShimmerBox(height: 36, radius: 12, margin: EdgeInsets.only(top: 8)),
                ShimmerBox(height: 36, radius: 12, margin: EdgeInsets.only(top: 8)),
              ]),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              podiumCol(86),
              const SizedBox(width: 8),
              podiumCol(104),
              const SizedBox(width: 8),
              podiumCol(70),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
            child: Align(alignment: Alignment.centerLeft, child: ShimmerBox(width: 120, height: 11, radius: 4)),
          ),
          for (var i = 0; i < 8; i++)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: const Row(children: [
                ShimmerBox(width: 28, height: 14, radius: 4),
                SizedBox(width: 12),
                ShimmerBox(width: 40, height: 40, radius: 20),
                SizedBox(width: 12),
                Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.6, child: ShimmerBox(height: 14, radius: 4))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  ShimmerBox(width: 36, height: 16, radius: 4, margin: EdgeInsets.only(bottom: 4)),
                  ShimmerBox(width: 40, height: 9, radius: 4),
                ]),
              ]),
            ),
        ],
      ),
    );
  }
}
