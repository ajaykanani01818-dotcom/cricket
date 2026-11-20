import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/live_pill.dart';
import 'countdown_timer.dart';
import 'live_match_card.dart';
import 'match_parsing.dart';
import 'match_time.dart';

/// "Abu Dhabi T10 League 2026, T10" (series and format; no middle dots).
String matchMetaLine(MatchSummary m, {bool series = true}) {
  final parts = <String>[
    if (series && m.series.trim().isNotEmpty) m.series.trim(),
    if (m.format != null && m.format!.trim().isNotEmpty) m.format!.trim(),
  ];
  return parts.join(', ');
}

/// Countdown text for an upcoming start: "2h 15m" within 24 h, else null.
String? startsInShort(DateTime start, DateTime now) =>
    countdownWithin24h(start, now);

/// Flat match row (no card): two team lines, then one or two quiet lines.
/// Rows sit in a [MatchRowGroup] separated by hairlines (containment by
/// hierarchy: only the live card is raised).
///
/// - In progress: scores, a live pill (or "Stumps" etc.), the chase line.
/// - Upcoming: no scores; a per-minute countdown on the right
///   ("2h 15m" / "Tomorrow" + local time), driven by the shared minute clock.
/// - Finished: the winner's line bold with a check, the loser muted, the
///   result message.
class MatchRow extends StatelessWidget {
  const MatchRow({
    super.key,
    required this.match,
    required this.onTap,
    this.showSeries = true,
  });

  final MatchSummary match;
  final VoidCallback? onTap;
  final bool showSeries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = match;
    final upcoming = m.isUpcoming;
    final win = m.winnerSide;

    Widget team(int side) => TeamScoreLine(
      name: side == 1 ? m.team1 : m.team2,
      logo: side == 1 ? m.team1Logo : m.team2Logo,
      score: upcoming ? null : m.displayScore(side),
      scoreStyle: AppText.scoreRow,
      logoSize: 24,
      winner: win == null ? null : win == side,
    );

    final teams = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        team(1),
        const SizedBox(height: Spacing.sm),
        team(2),
      ],
    );

    final line = m.statusLine;
    final meta = matchMetaLine(m, series: showSeries);
    final lines = <Widget>[
      if (m.isInProgress || (!upcoming && line == null && m.isFinished))
        Padding(
          padding: const EdgeInsets.only(top: Spacing.sm),
          child: Row(
            children: [
              if (m.isInPlay)
                const LivePill(dense: true)
              else
                Text(
                  m.statusLabel,
                  style: AppFont.withWeight(
                    AppText.small,
                    FontWeight.w700,
                  ).copyWith(color: p.ink),
                ),
              if (line != null) ...[
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.withWeight(
                      AppText.meta.copyWith(color: p.ink),
                      FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        )
      else if (line != null && !upcoming)
        Padding(
          padding: const EdgeInsets.only(top: Spacing.sm),
          child: Text(
            line,
            key: const ValueKey('common_row_result'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.meta.copyWith(color: p.ink),
          ),
        ),
      if (meta.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.small.copyWith(color: p.inkMuted),
          ),
        ),
    ];

    final start = m.startTime;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (upcoming && start != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: teams),
              const SizedBox(width: Spacing.md),
              StartCountdown(start: start),
            ],
          )
        else
          teams,
        ...lines,
      ],
    );

    final sem = StringBuffer('${m.team1} vs ${m.team2}');
    if (m.statusLabel.isNotEmpty) sem.write(', ${m.statusLabel}');
    return Semantics(
      button: onTap != null,
      label: sem.toString(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// Right-hand countdown of an upcoming row, refreshed every minute:
/// "2h 15m" over "Today 9:30 PM" within 24 h, the day over the time
/// beyond that, "Starting" once the start time has passed.
class StartCountdown extends StatelessWidget {
  const StartCountdown({super.key, required this.start});
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MinuteBuilder(
      builder: (context, now) {
        final t = formatMatchTime(start, now);
        final clock = DateFormat('h:mm a', 'en_US').format(start.toLocal());
        final soon = startsInShort(start, now);
        final String top;
        final String bottom;
        final String sem;
        if (!start.isAfter(now)) {
          top = 'Starting';
          bottom = clock;
          sem = 'Starting, scheduled $clock';
        } else if (soon != null) {
          top = soon;
          bottom = '${t.dayLabel} $clock';
          sem = 'Starts in $soon, ${t.dayLabel} $clock';
        } else {
          top = t.dayLabel;
          bottom = clock;
          sem = 'Starts ${t.dayLabel} $clock';
        }
        return Semantics(
          label: sem,
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  top,
                  key: const ValueKey('common_row_countdown'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: soon != null
                      ? AppText.scoreRow.copyWith(color: p.ink)
                      : AppFont.withWeight(AppText.name, FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  bottom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.small.copyWith(color: p.inkMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A flat block of rows on the surface with hairline dividers between them
/// and hairline edges top and bottom (no card, no shadow).
class MatchRowGroup extends StatelessWidget {
  const MatchRowGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // A Material (not a DecoratedBox) so the rows' ink ripples show.
    return Material(
      color: p.surface,
      shape: Border.symmetric(horizontal: BorderSide(color: p.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: Spacing.lg,
                color: p.hairline,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
