import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/live_pill.dart';
import '../../core/widgets/net_image.dart';
import '../common/match_time.dart';
import '../common/match_parsing.dart';
import 'match_filters.dart';

/// View-model for one dense match row (Matches tab and Series fixtures).
class MatchRowData {
  const MatchRowData({
    required this.team1,
    required this.team2,
    this.team1Logo,
    this.team2Logo,
    this.team1Score,
    this.team2Score,
    this.winner,
    required this.phase,
    this.start,
    this.footer,
    this.detail,
    this.format,
    this.liveLabel,
  });

  /// Badge text when the match is paused (Stumps, Innings break); null = "Live".
  final String? liveLabel;

  final String team1, team2;
  final String? team1Logo, team2Logo;

  /// Raw provider score strings ("137/4 (9.5)"); null/blank = not available.
  final String? team1Score, team2Score;

  /// 1 or 2 when the provider names a winner.
  final int? winner;
  final RowPhase phase;
  final DateTime? start;

  /// Result line, live situation or readable status.
  final String? footer;

  /// Secondary context (match name, venue) for upcoming rows.
  final String? detail;
  final String? format;

  factory MatchRowData.fromSummary(MatchSummary m) {
    final phase = rowPhaseOf(m);
    final String? footer = switch (phase) {
      RowPhase.upcoming => null,
      RowPhase.live => m.chaseSummaryLine ?? m.statusLine,
      RowPhase.completed || RowPhase.stopped => m.resultMessage ?? m.statusLine ?? m.statusLabel,
    };
    final parts = <String>[if ((m.name ?? '').trim().isNotEmpty) m.name!.trim(), if (m.venue.trim().isNotEmpty) m.venue.trim()];
    String team(String name, int side) => name.trim().isNotEmpty ? name.trim() : (m.shortName(side) ?? 'To be decided');
    return MatchRowData(
      team1: team(m.team1, 1),
      team2: team(m.team2, 2),
      team1Logo: m.team1Logo,
      team2Logo: m.team2Logo,
      team1Score: phase == RowPhase.upcoming ? null : m.team1Score,
      team2Score: phase == RowPhase.upcoming ? null : m.team2Score,
      winner: phase == RowPhase.completed ? m.winnerSide : null,
      phase: phase,
      start: m.startTime,
      footer: footer,
      detail: parts.isEmpty ? null : parts.join(', '),
      format: formatLabel(m.format),
      liveLabel: phase == RowPhase.live && m.phase == MatchPhase.paused ? m.statusLabel : null,
    );
  }

  String semanticsLabel() {
    final b = StringBuffer('$team1 versus $team2');
    if (format != null) b.write(', $format');
    if (_hasScore(team1Score)) b.write(', $team1 ${team1Score!.trim()}');
    if (_hasScore(team2Score)) b.write(', $team2 ${team2Score!.trim()}');
    if (footer != null && footer!.isNotEmpty) b.write(', $footer');
    return b.toString();
  }
}

/// Row layout family, from the provider status (never `isLive`).
enum RowPhase { live, upcoming, completed, stopped }

RowPhase rowPhaseOf(MatchSummary m) => switch (m.phase) {
  MatchPhase.live || MatchPhase.paused => RowPhase.live,
  MatchPhase.upcoming => RowPhase.upcoming,
  MatchPhase.result => RowPhase.completed,
  MatchPhase.noResult || MatchPhase.abandoned || MatchPhase.cancelled => RowPhase.stopped,
  MatchPhase.unknown => m.resultMessage != null ? RowPhase.completed : RowPhase.upcoming,
};

bool _hasScore(String? s) {
  final t = s?.trim() ?? '';
  return t.isNotEmpty && t != '-';
}

/// Splits "137/4 (9.5)" into ("137/4", "9.5 ov"). Unknown shapes come back
/// as-is with no overs.
(String, String?) splitScore(String raw) {
  final m = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*$').firstMatch(raw.trim());
  if (m == null) return (raw.trim(), null);
  final overs = m.group(2)!.trim();
  return (m.group(1)!.trim(), overs.isEmpty ? null : (RegExp(r'^[\d.]+$').hasMatch(overs) ? '$overs ov' : overs));
}

/// Dense flat row: two team lines (score or start time on the right) and a
/// footer line (result, live situation or countdown). No card: rows are
/// separated by hairlines and grouped under a series header.
class MatchRow extends StatelessWidget {
  const MatchRow({super.key, required this.data, this.onTap, this.showLiveBadge = true});
  final MatchRowData data;
  final VoidCallback? onTap;
  final bool showLiveBadge;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = data;
    final upcoming = d.phase == RowPhase.upcoming;
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    Widget teamLine(int side) {
      final name = side == 1 ? d.team1 : d.team2;
      final logo = side == 1 ? d.team1Logo : d.team2Logo;
      final score = side == 1 ? d.team1Score : d.team2Score;
      final isWinner = d.winner == side;
      final isLoser = d.winner != null && !isWinner;
      final nameStyle = AppFont.style(
        size: 15,
        weight: isWinner ? FontWeight.w800 : FontWeight.w600,
        color: isLoser ? p.inkMuted : p.ink,
        height: 1.25,
      );
      return Row(
        children: [
          TeamLogo(url: logo, name: name, size: 22),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
          ),
          if (_hasScore(score)) ...[const SizedBox(width: Spacing.sm), _Score(raw: score!, muted: isLoser, stacked: big)],
        ],
      );
    }

    final footerColor = d.phase == RowPhase.live ? p.ink : p.inkMuted;
    final footer = <Widget>[
      if (d.phase == RowPhase.live && showLiveBadge) ...[
        LivePill(dense: true, label: d.liveLabel ?? 'Live'),
        const SizedBox(width: Spacing.sm),
      ],
      if (upcoming)
        Expanded(
          child: _StartLine(start: d.start, detail: d.detail),
        )
      else
        Expanded(
          child: Text(
            (d.footer ?? '').isNotEmpty ? d.footer! : (d.phase == RowPhase.live ? (d.detail ?? '') : 'Status not available'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.meta.copyWith(color: footerColor),
          ),
        ),
      if (d.format != null) ...[const SizedBox(width: Spacing.sm), FormatChip(d.format!)],
    ];

    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                teamLine(1),
                const SizedBox(height: 6),
                teamLine(2),
                const SizedBox(height: Spacing.sm),
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: footer),
              ],
            ),
          ),
          if (upcoming && d.start != null) ...[const SizedBox(width: Spacing.md), _StartTime(start: d.start!)],
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: d.semanticsLabel(),
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.raw, required this.muted, required this.stacked});
  final String raw;
  final bool muted;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (runs, overs) = splitScore(raw);
    final runStyle = AppText.scoreRow.copyWith(color: muted ? p.inkMuted : p.ink);
    final oversStyle = AppText.figures;
    final Widget child = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(runs, maxLines: 1, style: runStyle),
              if (overs != null) Text(overs, maxLines: 1, style: oversStyle),
            ],
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: runs, style: runStyle),
                if (overs != null) TextSpan(text: '  $overs', style: oversStyle),
              ],
            ),
            maxLines: 1,
          );
    // Scores are never truncated: very long strings scale down instead.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: child),
    );
  }
}

/// Right column of an upcoming row: local start time, day underneath.
class _StartTime extends StatelessWidget {
  const _StartTime({required this.start});
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = MinuteClock.now();
    final local = start.toLocal();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat.jm('en_US').format(local),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.scoreRow.copyWith(color: p.ink),
          ),
          const SizedBox(height: 2),
          Text(dayLabel(dayOf(local), now), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.small),
        ],
      ),
    );
  }
}

/// Footer of an upcoming row: "Starts in 2h 15m" (within 24 h, ticking each
/// minute on the shared clock), otherwise the match name / venue.
class _StartLine extends StatefulWidget {
  const _StartLine({required this.start, required this.detail});
  final DateTime? start;
  final String? detail;

  @override
  State<_StartLine> createState() => _StartLineState();
}

class _StartLineState extends State<_StartLine> {
  bool _listening = false;

  bool get _soon {
    final s = widget.start;
    if (s == null) return false;
    final diff = s.difference(MinuteClock.now());
    return diff > Duration.zero && diff <= const Duration(hours: 24);
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_StartLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final want = widget.start != null && widget.start!.isAfter(MinuteClock.now());
    if (want && !_listening) {
      MinuteClock.instance.addListener(_tick);
      _listening = true;
    } else if (!want && _listening) {
      MinuteClock.instance.removeListener(_tick);
      _listening = false;
    }
  }

  void _tick() {
    if (!mounted) return;
    setState(_sync);
  }

  @override
  void dispose() {
    if (_listening) MinuteClock.instance.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.start;
    if (s != null && _soon) {
      final left = countdownWithin24h(s, MinuteClock.now())!;
      return Text(
        'Starts in $left',
        key: const ValueKey('match_row_countdown'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppFont.style(size: 13, weight: FontWeight.w700, color: p.brandText, tabularFigures: true, height: 1.3),
      );
    }
    final started = s != null && !s.isAfter(MinuteClock.now());
    final text = started ? 'Yet to start${widget.detail != null ? ', ${widget.detail}' : ''}' : (widget.detail ?? 'Not started');
    return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.meta);
  }
}
