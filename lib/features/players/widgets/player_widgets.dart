import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../player_models.dart';
import 'gradient_card.dart';

/// Ported from RN `PlayersTableByCountry` › `PlayerRow`.
class PlayerRow extends StatelessWidget {
  const PlayerRow({super.key, required this.player, this.onPress});
  final CountryPlayer player;
  final ValueChanged<CountryPlayer>? onPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${player.name}, ${player.roleText}',
        child: Pressable(
          onTap: onPress == null ? null : () => onPress!(player),
          child: GradientCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Row(children: [
              RingAvatar(url: player.logo, name: player.name, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Text(player.roleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.1)),
                ]),
              ),
              const SizedBox(width: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 36),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('AGE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text(player.ageText,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: -0.5)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Ported from RN `PlayersShimmer`.
class PlayersShimmer extends StatelessWidget {
  const PlayersShimmer({super.key});

  @override
  Widget build(BuildContext context) => ShimmerGroup(
        key: const ValueKey('players_shimmer'),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(14, 12, 14, bottomReserve(context)),
          children: [
            for (var i = 0; i < 8; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.borderStrong),
                ),
                child: const Row(children: [
                  ShimmerBox(width: 60, height: 60, radius: 30),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ShimmerBox(width: 140, height: 16, radius: 4, margin: EdgeInsets.only(bottom: 6)),
                      ShimmerBox(width: 100, height: 12, radius: 4),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    ShimmerBox(width: 28, height: 9, radius: 4, margin: EdgeInsets.only(bottom: 4)),
                    ShimmerBox(width: 26, height: 18, radius: 4),
                  ]),
                ]),
              ),
          ],
        ),
      );
}

/// Section label used on the Player Detail screen.
class DetailSectionLabel extends StatelessWidget {
  const DetailSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 26, Spacing.lg, 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
      );
}

/// Label/value row inside a stat card (RN StatRow).
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md, horizontal: Spacing.lg),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.1)),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.1)),
          ),
        ]),
      );
}

const _hairline = Divider(height: 0.5, thickness: 0.5, color: AppColors.border, indent: Spacing.lg, endIndent: Spacing.lg);

/// GradientCard containing [StatRow]s separated by hairlines.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.rows});
  final List<StatLine> rows;

  @override
  Widget build(BuildContext context) => GradientCard(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) _hairline,
            StatRow(label: rows[i].label, value: rows[i].value),
          ],
        ]),
      );
}

/// Teams card (names separated by hairlines).
class TeamsCard extends StatelessWidget {
  const TeamsCard({super.key, required this.teams});
  final List<String> teams;

  @override
  Widget build(BuildContext context) => GradientCard(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < teams.length; i++) ...[
            if (i > 0) _hairline,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: Spacing.lg),
              child: Text(teams[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
            ),
          ],
        ]),
      );
}

/// Ported from RN `PlayerDetailShimmer`. [showHero] false when the real
/// header (from the list item) is already on screen.
class PlayerDetailShimmer extends StatelessWidget {
  const PlayerDetailShimmer({super.key, this.showHero = true, bool? showPersonal}) : showPersonal = showPersonal ?? showHero;
  final bool showHero;
  final bool showPersonal;

  static Widget _statRows(int rows) => Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Column(children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) _hairline,
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                ShimmerBox(width: 80, height: 13, radius: 4),
                ShimmerBox(width: 70, height: 14, radius: 4),
              ]),
            ),
          ],
        ]),
      );

  static Widget _label(double w) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
        child: Align(alignment: Alignment.centerLeft, child: ShimmerBox(width: w, height: 11, radius: 4)),
      );

  @override
  Widget build(BuildContext context) => ShimmerGroup(
        key: const ValueKey('player_detail_shimmer'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (showHero)
            const SizedBox(
              height: 280,
              child: Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  ShimmerBox(width: 128, height: 128, radius: 64, margin: EdgeInsets.only(bottom: 16)),
                  ShimmerBox(width: 200, height: 26, radius: 4, margin: EdgeInsets.only(bottom: 8)),
                  ShimmerBox(width: 140, height: 13, radius: 4, margin: EdgeInsets.only(bottom: 12)),
                  ShimmerBox(width: 24, height: 2, radius: 1),
                ]),
              ),
            ),
          if (showPersonal) ...[
            _label(80),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _statRows(5)),
          ],
          _label(100),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              const ShimmerBox(height: 36, radius: 12, margin: EdgeInsets.only(bottom: 12)),
              _statRows(3),
            ]),
          ),
          _label(110),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ShimmerBox(width: 50, height: 11, radius: 4, margin: EdgeInsets.only(bottom: 8)),
              _statRows(6),
            ]),
          ),
          const SizedBox(height: 32),
        ]),
      );
}
