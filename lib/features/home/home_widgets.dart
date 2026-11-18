import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/shimmer_box.dart';
import '../common/gradient_card.dart';
import '../common/live_match_card.dart';
import 'home_models.dart';

/// Ported from RN `TopPlayerCard` (108px wide, rank badge, avatar, name, points).
class TopPlayerCard extends StatelessWidget {
  const TopPlayerCard({super.key, required this.player, this.onTap});
  final TopPlayer player;
  final VoidCallback? onTap;

  static const width = 108.0;

  (Color, Color) get _rankStyle => switch (player.order) {
        1 => (AppColors.gold, AppColors.pitchDark),
        2 => (AppColors.silver, AppColors.pitchDark),
        3 => (AppColors.bronze, AppColors.white),
        _ => (AppColors.borderSubtle, AppColors.text),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _rankStyle;
    final name = player.name;
    final card = Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(bottom: 10),
            child: player.logo != null
                ? NetImage(url: player.logo, size: 56, fit: BoxFit.cover, fallbackLetter: name, background: AppColors.bg)
                : Container(
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x180B5CD4), shape: BoxShape.circle),
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.pitch)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, Spacing.xs + 2),
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.33)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(player.pointsLabel,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.pitch, letterSpacing: 0.2)),
              const SizedBox(width: 2),
              const Text('PTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
            ]),
          ),
        ]),
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 26),
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
            child: Text('#${player.orderLabel}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
          ),
        ),
      ]),
    );
    return Semantics(button: onTap != null, label: '$name, rank ${player.orderLabel}', child: Pressable(onTap: onTap, child: card));
  }
}

/// RN HomeScreen `SeriesRowCard`.
class SeriesRowCard extends StatelessWidget {
  const SeriesRowCard({super.key, required this.item, this.onTap});
  final UpcomingSeriesItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget team(SeriesTeam? t) => Expanded(
          child: Row(children: [
            t?.logo != null
                ? NetImage(url: t!.logo, size: 26, fallbackLetter: t.label, background: AppColors.cardAlt)
                : const DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
                    child: SizedBox(width: 26, height: 26),
                  ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(t?.label ?? 'TBD',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
          ]),
        );

    return Pressable(
      onTap: onTap,
      child: GradientCard(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(children: [
              const Text('UPCOMING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.pitch, letterSpacing: 0.8)),
              const Spacer(),
              Text(item.dateRange,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.1)),
            ]),
          ),
          Text(item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.2, height: 1.3)),
          if (item.hasFirstMatch)
            Container(
              margin: const EdgeInsets.only(top: Spacing.md),
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
              child: Row(children: [
                team(item.team1),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Text('vs', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
                ),
                team(item.team2),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// RN HomeScreen category pill.
class CategoryPill extends StatelessWidget {
  const CategoryPill({super.key, required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(Radii.full),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: active ? AppColors.text : AppColors.bg,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(color: active ? AppColors.text : AppColors.borderStrong),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: active ? AppColors.white : AppColors.graphite)),
        ),
      );
}

/// Ported from RN `HomeShimmer`.
class HomeShimmer extends StatelessWidget {
  const HomeShimmer({super.key, this.bottomPadding = 0});
  final double bottomPadding;

  Widget _head() => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShimmerBox(width: 70, height: 9, radius: 4, margin: EdgeInsets.only(bottom: 6)),
            ShimmerBox(width: 140, height: 20, radius: 4),
          ]),
          Spacer(),
          ShimmerBox(width: 56, height: 12, radius: 4),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cardW = MediaQuery.sizeOf(context).width - 32;
    return ShimmerGroup(
      key: const ValueKey('home_shimmer'),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 16, bottom: bottomPadding),
        children: [
          _head(),
          SizedBox(
            height: 200,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(left: 10),
              children: const [
                ShimmerBox(width: liveCardWidth, height: 200, radius: 18, margin: EdgeInsets.only(right: liveCardMargin)),
                ShimmerBox(width: liveCardWidth, height: 200, radius: 18),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 28),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ShimmerBox(width: 20, height: 6, radius: 3),
              ShimmerBox(width: 6, height: 6, radius: 3, margin: EdgeInsets.only(left: 6)),
              ShimmerBox(width: 6, height: 6, radius: 3, margin: EdgeInsets.only(left: 6)),
            ]),
          ),
          _head(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: Column(children: [
                for (var i = 0; i < 4; i++)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      ShimmerBox(width: 36, height: 36, radius: 18),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          FractionallySizedBox(widthFactor: 0.6, child: ShimmerBox(height: 13, radius: 4, margin: EdgeInsets.only(bottom: 6))),
                          FractionallySizedBox(widthFactor: 0.4, child: ShimmerBox(height: 11, radius: 4)),
                        ]),
                      ),
                      ShimmerBox(width: 36, height: 36, radius: 18),
                    ]),
                  ),
              ]),
            ),
          ),
          _head(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              ShimmerBox(width: 68, height: 28, radius: 999),
              ShimmerBox(width: 68, height: 28, radius: 999),
              ShimmerBox(width: 88, height: 28, radius: 999),
              SizedBox(width: 8),
              ShimmerBox(width: 50, height: 26, radius: 999),
            ]),
          ),
          SizedBox(
            height: 170,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [
                ShimmerBox(width: 140, height: 170, radius: 16, margin: EdgeInsets.only(right: 12)),
                ShimmerBox(width: 140, height: 170, radius: 16, margin: EdgeInsets.only(right: 12)),
                ShimmerBox(width: 140, height: 170, radius: 16),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _head(),
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ShimmerBox(width: cardW, height: 140, radius: 18),
            ),
        ],
      ),
    );
  }
}
