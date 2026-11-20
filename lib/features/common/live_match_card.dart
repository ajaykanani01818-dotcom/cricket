import 'package:flutter/material.dart';

import '../../core/motion/hero_tags.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/live_pill.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/score_text.dart';
import '../../core/widgets/seam_strip.dart';
import 'match_parsing.dart';

const double liveCardWidth = 312;
const double liveCardHeight = 188;
const double liveCardCompactHeight = 150;
const double liveCardMargin = 12;

/// "126/2 (19.0)" -> ("126/2", "19.0"); a score without overs -> (s, null).
(String runs, String? overs) splitScore(String score) {
  final m = RegExp(r'^(.*?)\s*\(([\d.]+)\)\s*$').firstMatch(score.trim());
  if (m == null) return (score.trim(), null);
  return (m.group(1)!.trim(), m.group(2));
}

/// Sentence-case status chip for a match: [LivePill] while in play (key
/// `common_live_badge`), a quiet word for every other state ("Stumps",
/// "Upcoming", "Result", "No result", "Abandoned"). Nothing for an empty
/// status.
class MatchStatusChip extends StatelessWidget {
  const MatchStatusChip({super.key, required this.match});
  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    final label = match.statusLabel;
    switch (match.phase) {
      case MatchPhase.live:
        return const LivePill(key: ValueKey('common_live_badge'), dense: true);
      case MatchPhase.upcoming:
        return StatusChip(kind: StatusKind.upcoming, label: label);
      case MatchPhase.abandoned || MatchPhase.cancelled:
        return StatusChip(kind: StatusKind.cancelled, label: label);
      case MatchPhase.unknown when label.isEmpty:
        return const SizedBox.shrink();
      default:
        return StatusChip(kind: StatusKind.completed, label: label);
    }
  }
}

/// One team line used by the card and the flat rows: logo, name, score
/// (runs in tabular Archivo wdth 72 + overs in muted figures), winner mark.
class TeamScoreLine extends StatelessWidget {
  const TeamScoreLine({
    super.key,
    required this.name,
    required this.logo,
    required this.score,
    this.scoreStyle,
    this.logoSize = 28,
    this.winner,
    this.logoTag,
    this.scoreTag,
    this.heroTags = false,
  });

  final String name;
  final String? logo;

  /// null = no score slot (upcoming / not available).
  final String? score;
  final TextStyle? scoreStyle;
  final double logoSize;

  /// true = this side won (bold + check), false = lost (muted), null = n/a.
  final bool? winner;
  final String? logoTag, scoreTag;
  final bool heroTags;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lost = winner == false;
    final nameStyle = winner == true
        ? AppFont.withWeight(AppText.name, FontWeight.w800)
        : lost
        ? AppText.name.copyWith(color: p.inkMuted)
        : AppText.name;
    final s = score;
    Widget? scoreWidget;
    if (s != null) {
      final yetToBat = s == '—';
      final (runs, overs) = splitScore(s);
      final base = scoreStyle ?? AppText.scoreCard;
      scoreWidget = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (overs != null) ...[
            Text('$overs ov', style: AppText.figures, maxLines: 1),
            const SizedBox(width: Spacing.sm),
          ],
          ScoreText(
            runs,
            style: lost || yetToBat ? base.copyWith(color: p.inkMuted) : base,
            heroTag: heroTags ? scoreTag : null,
            semanticsLabel: yetToBat
                ? 'Yet to bat'
                : overs == null
                ? runs
                : '$runs in $overs overs',
          ),
        ],
      );
    }
    return Row(
      children: [
        MatchHero(
          tag: logoTag ?? 'logo:$name',
          enabled: heroTags && logoTag != null,
          child: TeamLogo(url: logo, name: name, size: logoSize),
        ),
        const SizedBox(width: Spacing.sm + 2),
        Expanded(
          child: Text(
            name.isEmpty ? 'To be announced' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          ),
        ),
        if (scoreWidget != null) ...[
          const SizedBox(width: Spacing.sm),
          // Align fills the flexible slot so the score sits flush right on
          // wide cards instead of floating mid-row.
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: scoreWidget,
              ),
            ),
          ),
        ],
        // Both sides reserve the mark's width so the score columns align.
        if (winner != null) ...[
          const SizedBox(width: Spacing.xs),
          winner == true
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: p.positive,
                  semanticLabel: 'Won',
                )
              : const SizedBox(width: 16),
        ],
      ],
    );
  }
}

/// Score card. Live/paused: surface + 3 dp brand left edge, radius 12 (the
/// raised card). Anything else: flat surface with a hairline.
///
/// Layout: meta line (status chip, series, format), one row per team, the
/// current over as a [SeamStrip] when [overBalls] (or the item's own
/// `currentOver`) has balls, then the status / chase line. Upcoming
/// matches show no score; a side yet to bat shows "—".
///
/// [heroTags]: wrap logos and scores in [MatchHero]s for the card → Match
/// Centre moment. Only enable it where the match appears once on screen.
/// The legacy fixed-size rail mode (neither [fullWidth] nor [compact]) is
/// kept for callers that still use it.
class LiveMatchCard extends StatelessWidget {
  const LiveMatchCard({
    super.key,
    required this.match,
    required this.onTap,
    this.fullWidth = false,
    this.compact = false,
    this.heroTags = false,
    this.showSeries = true,
    this.overBalls,
    this.overNumber,
  });

  final MatchSummary match;
  final VoidCallback? onTap;
  final bool fullWidth;
  final bool compact;
  final bool heroTags;

  /// False under a series group header (the Live list).
  final bool showSeries;

  /// Current-over ball labels ("0", "4", "WK", "1NB"...). Null = use the
  /// item's own `currentOver` when present.
  final List<String>? overBalls;
  final int? overNumber;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final raised = match.isInProgress;
    final line = match.statusLine;
    final isChase = match.chaseSummaryLine != null;
    final id = match.id;
    final win = match.winnerSide;
    final balls = overBalls ?? match.currentOverBalls;
    final overNo = overNumber ?? match.currentOverNumber;

    final meta = Row(
      children: [
        MatchStatusChip(match: match),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: showSeries
              ? Text(
                  match.series,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.small.copyWith(color: p.inkMuted),
                )
              : const SizedBox.shrink(),
        ),
        if (match.format != null) ...[
          const SizedBox(width: Spacing.sm),
          FormatChip(match.format!),
        ],
      ],
    );

    Widget team(int side) => Padding(
      padding: const EdgeInsets.only(top: Spacing.sm + 2),
      child: TeamScoreLine(
        name: side == 1 ? match.team1 : match.team2,
        logo: side == 1 ? match.team1Logo : match.team2Logo,
        score: match.displayScore(side),
        winner: win == null ? null : win == side,
        heroTags: heroTags,
        logoTag: side == 1
            ? MatchHeroTags.team1Logo(id)
            : MatchHeroTags.team2Logo(id),
        scoreTag: side == 1
            ? MatchHeroTags.team1Score(id)
            : MatchHeroTags.team2Score(id),
      ),
    );

    final teams = Column(
      mainAxisSize: MainAxisSize.min,
      children: [team(1), team(2)],
    );

    final seam = balls.isEmpty || !raised
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: SeamStrip.labels(
              balls,
              key: const ValueKey('common_live_seam'),
              overLabel: overNo == null ? 'This over' : 'Over $overNo',
            ),
          );

    final status = line == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: Spacing.sm + 2),
            child: Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: isChase
                  ? AppFont.withWeight(
                      AppText.meta.copyWith(color: p.ink),
                      FontWeight.w700,
                    )
                  : AppText.meta.copyWith(
                      color: match.isFinished ? p.ink : p.inkMuted,
                    ),
            ),
          );

    // Fixed-height rail card: the team block scales down instead of
    // overflowing at large text sizes. List cards: natural height.
    final fixedHeight = !fullWidth && !compact;
    final body = fixedHeight
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              meta,
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(width: liveCardWidth - 30, child: teams),
                ),
              ),
              ?status,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [meta, teams, ?seam, ?status],
          );

    final radius = BorderRadius.circular(Radii.card);
    final label = StringBuffer('${match.team1} vs ${match.team2}');
    if (match.statusLabel.isNotEmpty) label.write(', ${match.statusLabel}');
    return Semantics(
      button: true,
      label: label.toString(),
      child: Pressable(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          width: fullWidth ? double.infinity : liveCardWidth,
          height: fixedHeight ? liveCardHeight : null,
          margin: fullWidth
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: liveCardMargin / 2),
          padding: EdgeInsets.fromLTRB(raised ? 13 : 14, 12, 14, 14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: radius,
            border: raised
                ? Border(left: BorderSide(color: p.brand, width: 3))
                : Border.all(color: p.hairline),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// Legacy name: now a [LiveDot] driven by the shared pulse.
class BlinkingDot extends StatelessWidget {
  const BlinkingDot({super.key, required this.color, this.size = 6});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => LiveDot(size: size, color: color);
}
