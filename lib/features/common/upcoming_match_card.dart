import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/fixture_status.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/live_pill.dart';
import '../../core/widgets/net_image.dart';
import 'countdown_timer.dart';
import 'match_parsing.dart';
import 'match_time.dart';

enum UpcomingCardVariant { upcoming, completed, cancelled }

enum SeriesStatusChipVariant { upcoming, live, finished, cancelled, abandoned }

class SeriesStatusChip {
  const SeriesStatusChip(this.label, this.variant);
  final String label;
  final SeriesStatusChipVariant variant;
}

String ordinalSuffix(int n) {
  final j = n % 10, k = n % 100;
  if (j == 1 && k != 11) return 'st';
  if (j == 2 && k != 12) return 'nd';
  if (j == 3 && k != 13) return 'rd';
  return 'th';
}

/// In play per the provider `status` word (never the `isLive` flag).
bool isMatchLiveForCard(
  MatchSummary m, {
  bool completed = false,
  bool cancelled = false,
}) {
  if (completed || cancelled) return false;
  final k = m.fixtureCardKind;
  if (k == FixtureCardKind.cancelled || k == FixtureCardKind.abandoned) {
    return false;
  }
  return m.isInPlay;
}

/// A real result line exists (the provider's message, not just a status
/// word such as "Result" or "COMPLETED").
bool hasDisplayableResult(MatchSummary m) {
  final msg = m.resultMessage?.trim();
  if (msg != null && msg.isNotEmpty) return true;
  final s = m.status.trim();
  return s.length > 2 && s != m.statusLabel && s.toUpperCase() != s;
}

StatusKind _chipKind(SeriesStatusChipVariant v) => switch (v) {
  SeriesStatusChipVariant.upcoming => StatusKind.upcoming,
  SeriesStatusChipVariant.live => StatusKind.live,
  SeriesStatusChipVariant.finished => StatusKind.completed,
  SeriesStatusChipVariant.cancelled ||
  SeriesStatusChipVariant.abandoned => StatusKind.cancelled,
};

/// Ported from RN `UpcomingMatchCard`: fixture card with meta pills, teams,
/// "Starts in" countdown (upcoming) or result row (completed). The
/// series-detail props are kept so the Series feature can reuse it.
class UpcomingMatchCard extends StatelessWidget {
  const UpcomingMatchCard({
    super.key,
    required this.match,
    this.onTap,
    this.variant = UpcomingCardVariant.upcoming,
    this.embedded = false,
    this.listMatchNumber,
    this.seriesDetailLayout = false,
    this.seriesDetailStatusChip,
    this.seriesDetailExternalResultFooter = false,
    this.matchesListFrame = false,
  });

  final MatchSummary match;
  final VoidCallback? onTap;
  final UpcomingCardVariant variant;
  final bool embedded;
  final int? listMatchNumber;
  final bool seriesDetailLayout;
  final SeriesStatusChip? seriesDetailStatusChip;
  final bool seriesDetailExternalResultFooter;
  final bool matchesListFrame;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = match;
    final isCompleted = variant == UpcomingCardVariant.completed;
    final isCancelled = variant == UpcomingCardVariant.cancelled;
    final hasResult = isCompleted && hasDisplayableResult(m);
    final hideResultDup =
        isCompleted && seriesDetailLayout && seriesDetailExternalResultFooter;
    final statusFromChip = seriesDetailLayout && seriesDetailStatusChip != null;
    final showMatchNo = seriesDetailLayout && (listMatchNumber ?? 0) > 0;
    final showFormat = !seriesDetailLayout && m.format != null;
    final showSeries = !seriesDetailLayout && m.series.isNotEmpty;
    final showResultPill = hasResult && !hideResultDup && !statusFromChip;
    final showVoidPill = isCancelled && !statusFromChip;
    final showLivePill =
        !statusFromChip &&
        isMatchLiveForCard(m, completed: isCompleted, cancelled: isCancelled);
    final voidLabel = m.fixtureCardKind == FixtureCardKind.abandoned
        ? 'Abandoned'
        : 'Cancelled';
    const voidShort = {'Cancelled', 'Abandoned', 'cancelled', 'abandoned'};
    final st = m.status.trim();
    final showVoidDetail =
        isCancelled && st.isNotEmpty && !voidShort.contains(st);
    final venue = m.venue.trim();
    final win = isCompleted ? m.winnerSide : null;

    final pills = <Widget>[
      if (showMatchNo)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Text(
            '$listMatchNumber${ordinalSuffix(listMatchNumber!)} match',
            style: AppFont.withWeight(AppText.small, FontWeight.w700),
          ),
        ),
      if (seriesDetailStatusChip != null)
        StatusChip(
          kind: _chipKind(seriesDetailStatusChip!.variant),
          label: seriesDetailStatusChip!.label,
        ),
      if (showLivePill)
        const LivePill(key: ValueKey('common_upcoming_live_pill'), dense: true),
      if (showVoidPill)
        StatusChip(kind: StatusKind.cancelled, label: voidLabel),
      if (showResultPill)
        const StatusChip(
          key: ValueKey('common_result_pill'),
          kind: StatusKind.completed,
          label: 'Result',
        ),
      if (showFormat) FormatChip(m.format!),
    ];

    final hasMeta = pills.isNotEmpty || showSeries || venue.isNotEmpty;
    final time = DateTime.tryParse(m.date);
    final timeInfo = time == null
        ? null
        : formatMatchTime(time, MinuteClock.now());

    Widget team(int side) {
      final name = side == 1 ? m.team1 : m.team2;
      final logo = side == 1 ? m.team1Logo : m.team2Logo;
      final score = isCompleted ? m.displayScore(side) : null;
      final lost = win != null && win != side;
      return Expanded(
        child: Column(
          children: [
            TeamLogo(url: logo, name: name, size: 40),
            const SizedBox(height: 6),
            Text(
              name.isEmpty ? 'To be announced' : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: win == side
                  ? AppFont.withWeight(AppText.name, FontWeight.w800)
                  : lost
                  ? AppText.name.copyWith(color: p.inkMuted)
                  : AppText.name,
            ),
            if (score != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    score,
                    maxLines: 1,
                    style: lost
                        ? AppText.scoreRow.copyWith(color: p.inkMuted)
                        : AppText.scoreRow,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMeta)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final w in pills) ...[
                      w,
                      const SizedBox(width: Spacing.sm),
                    ],
                    if (showSeries)
                      Flexible(
                        child: Text(
                          m.series,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small.copyWith(color: p.inkMuted),
                        ),
                      ),
                  ],
                ),
                if (venue.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: p.inkMuted,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Expanded(
                          child: Text(
                            venue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.small.copyWith(color: p.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              team(1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.sm,
                  12,
                  Spacing.sm,
                  0,
                ),
                child: Text('v', style: AppText.meta),
              ),
              team(2),
            ],
          ),
        ),
        if (variant == UpcomingCardVariant.upcoming && m.date.isNotEmpty)
          StartsInBig(targetDate: m.date),
        if (hasResult && !hideResultDup)
          Padding(
            key: const ValueKey('common_result_row'),
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (win != null) ...[
                  Icon(Icons.check, size: 16, color: p.positive),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    m.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.withWeight(
                      AppText.meta.copyWith(color: p.ink),
                      FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (showVoidDetail)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: p.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    st,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(color: p.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final radius = BorderRadius.circular(embedded ? 10.0 : Radii.card);
    return Semantics(
      button: true,
      label:
          '${m.team1} vs ${m.team2}${m.format != null ? ', ${m.format}' : ''}'
          '${timeInfo != null ? ', ${timeInfo.dayLabel} ${timeInfo.time}' : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: radius,
          border: embedded ? null : Border.all(color: p.hairline),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(embedded ? Spacing.sm : Spacing.lg),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
