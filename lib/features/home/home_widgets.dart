import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/shimmer_box.dart';
import '../../core/widgets/skeletons.dart';
import '../common/countdown_timer.dart';
import '../common/match_parsing.dart';
import '../common/match_time.dart';
import 'home_models.dart';

/// First-load skeleton mirroring Home: section title, live card, rows.
class HomeShimmer extends StatelessWidget {
  const HomeShimmer({super.key});

  Widget _head() => const Padding(
    padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, 0),
    child: ShimmerGroup(
      child: Align(
        alignment: Alignment.centerLeft,
        child: ShimmerBox(width: 120, height: 18),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('home_shimmer'),
    physics: const NeverScrollableScrollPhysics(),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            _head(),
            const SkeletonLiveCard(),
            const SkeletonMatchRow(),
            _head(),
            const SkeletonMatchRow(),
            const SkeletonMatchRow(),
            const SkeletonMatchRow(),
          ],
        ),
      ),
    ),
  );
}

/// "No matches are live right now" with the next start counting down per
/// minute (tap opens that match) and the way to the schedule. Never a blank
/// screen (PRD §6.2).
class NoLivePanel extends StatelessWidget {
  const NoLivePanel({
    super.key,
    required this.next,
    required this.onOpenNext,
    required this.onSchedule,
  });

  /// Soonest upcoming match, when known.
  final MatchSummary? next;
  final VoidCallback onOpenNext;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = next;
    final start = n?.startTime;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.md,
            ),
            child: Text('No matches are live right now', style: AppText.name),
          ),
          if (n != null && start != null)
            Pressable(
              key: const ValueKey('home_next_start'),
              onTap: onOpenNext,
              borderRadius: BorderRadius.zero,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.md,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.hairline)),
                ),
                child: MinuteBuilder(
                  builder: (context, now) {
                    final soon = startsInLabel(start, now);
                    final t = formatMatchTime(start, now);
                    final teams =
                        '${n.shortName(1) ?? n.team1} v ${n.shortName(2) ?? n.team2}';
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Next to start',
                                style: AppText.small.copyWith(
                                  color: p.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                teams,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppFont.withWeight(
                                  AppText.name,
                                  FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${t.dayLabel} ${t.time}',
                                style: AppText.small.copyWith(
                                  color: p.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Flexible(
                          child: Text(
                            soon == null ? 'Starting' : 'in $soon',
                            key: const ValueKey('home_next_start_countdown'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.scoreCard,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.hairline)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('home_live_empty_action'),
              onPressed: onSchedule,
              child: Text(
                'See the full schedule',
                style: AppFont.style(
                  size: 14,
                  weight: FontWeight.w700,
                  color: p.brandText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet series chip for the "Upcoming series" strip: name and dates.
class SeriesChip extends StatelessWidget {
  const SeriesChip({super.key, required this.item, this.onTap});
  final UpcomingSeriesItem item;
  final VoidCallback? onTap;

  static const width = 220.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(Radii.chip);
    return Semantics(
      button: true,
      label: '${item.name}, ${item.dateRange}',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: radius,
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.name,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                item.dateRange,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.small.copyWith(color: p.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
