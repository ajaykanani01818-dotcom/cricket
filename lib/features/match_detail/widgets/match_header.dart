import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/hero_tags.dart';
import '../../../core/motion/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/live_pill.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/score_text.dart';
import '../logic/match_detail_logic.dart';
import '../logic/match_state.dart';
import 'md_ui.dart';

/// Local date + time, e.g. "Tue 18 Nov, 9:00 AM".
String localStartLabel(DateTime d) => DateFormat('EEE d MMM y, h:mm a', 'en_US').format(d);

/// The Match Centre header: full bleed on the canvas, state-aware
/// (research §3.2). Shows the score first; the plain-language situation
/// line sits under it; the other team is quieter. Never prints a score that
/// was not supplied (no fake zeros).
class MatchCentreHeader extends StatelessWidget {
  const MatchCentreHeader({
    super.key,
    required this.matchId,
    required this.match,
    required this.situation,
    this.note,
    this.animateScore = false,
    this.strip,
    this.band,
  });

  /// Route match id (the card's hero tags use it).
  final String matchId;
  final MatchDetailVM match;
  final MatchSituation situation;

  /// Break / stumps note from the latest info commentary.
  final String? note;

  /// Digit roll only for one genuinely new ball (catch-up rule).
  final bool animateScore;

  /// Seam strip for the current over (live / break only).
  final Widget? strip;

  /// Wicket band slot.
  final Widget? band;

  TeamVM _team(TeamSide s) => s == TeamSide.team1 ? match.t1 : match.t2;
  String _logoTag(TeamSide s) => s == TeamSide.team1 ? MatchHeroTags.team1Logo(matchId) : MatchHeroTags.team2Logo(matchId);
  String _scoreTag(TeamSide s) => s == TeamSide.team1 ? MatchHeroTags.team1Score(matchId) : MatchHeroTags.team2Score(matchId);

  @override
  Widget build(BuildContext context) {
    final phase = situation.status.phase;
    final body = switch (phase) {
      MatchPhase.upcoming => _upcoming(context),
      MatchPhase.completed || MatchPhase.abandoned => _finished(context),
      MatchPhase.live || MatchPhase.interrupted || MatchPhase.unknown =>
        situation.current == null ? _finished(context) : _inPlay(context),
    };
    return Padding(
      key: const ValueKey('match_detail_header'),
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      // Score block stays compact on tablets/desktop (scores read together).
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _metaRow(context),
          const SizedBox(height: Spacing.md),
          ...body,
          if (strip != null) ...[const SizedBox(height: Spacing.md), strip!],
          ?band,
        ],
      ),
        ),
      ),
    );
  }

  Widget _metaRow(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusTag(status: situation.status),
        if (match.format != null) FormatChip(match.format!),
        if (match.name != null) Text(match.name!, style: AppText.meta.copyWith(color: p.inkMuted)),
      ],
    );
  }

  // ── live / break ───────────────────────────────────────────────────────────

  List<Widget> _inPlay(BuildContext context) {
    final p = context.palette;
    final cur = situation.current!;
    final bat = cur.side;
    final other = bat == TeamSide.team1 ? TeamSide.team2 : TeamSide.team1;
    final team = _team(bat);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5);
    final figures = <String>[
      if (cur.overs != null && cur.overs!.isNotEmpty) '${cur.overs} ov',
      if (situation.currentRunRate != null) 'CRR ${situation.currentRunRate}',
      if (situation.chase?.requiredRate != null)
        'RRR ${situation.chase!.requiredRate}${situation.chase!.ballsEstimated ? ' (est.)' : ''}',
      if (situation.chase != null) 'Target ${situation.chase!.target}',
      if (situation.projection != null) '${situation.projection} (calc.)',
    ];
    final earlier = situation.inningsOf(bat).where((i) => i != cur).toList();
    final otherLine = situation.scoreLineOf(other);
    return [
      Semantics(
        container: true,
        liveRegion: true,
        label: '${team.name} ${cur.scoreText}${cur.overs != null ? ' after ${cur.overs} overs' : ''}',
        child: Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            ExcludeSemantics(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MatchHero(tag: _logoTag(bat), child: TeamLogo(url: team.logo, name: team.name, size: 32)),
                const SizedBox(width: Spacing.sm),
                Text(team.code, style: AppFont.style(size: 20, weight: FontWeight.w700, width: 90, color: p.ink, height: 1.1)),
              ]),
            ),
            MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: LayoutBuilder(builder: (context, c) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ScoreText(
                      cur.scoreText,
                      key: ValueKey('match_detail_score_${bat.name}'),
                      style: AppText.scoreHero.copyWith(fontSize: 40, color: p.ink),
                      heroTag: _scoreTag(bat),
                      animate: animateScore,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      if (figures.isNotEmpty) ...[
        const SizedBox(height: Spacing.xs),
        Wrap(
          key: const ValueKey('match_detail_figures'),
          spacing: Spacing.lg,
          runSpacing: 2,
          children: [for (final f in figures) Text(f, style: AppText.figures.copyWith(fontSize: 14, color: p.inkMuted))],
        ),
      ],
      if (situation.headline != null) ...[
        const SizedBox(height: Spacing.sm),
        Text(
          situation.headline!,
          key: const ValueKey('match_detail_situation'),
          style: AppFont.style(size: 16, weight: FontWeight.w700, color: p.ink, height: 1.3),
        ),
      ],
      if (situation.subline != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(situation.subline!, key: const ValueKey('match_detail_subline'), style: AppText.meta.copyWith(fontSize: 14, color: p.inkMuted)),
        ),
      if (earlier.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            '${team.code} earlier: ${earlier.map((i) => i.scoreText).join(' & ')}',
            style: AppText.meta.copyWith(color: p.inkMuted),
          ),
        ),
      const SizedBox(height: Spacing.sm),
      _teamLine(
        context,
        other,
        otherLine ?? _rawScore(other),
        emphasis: _Emphasis.normal,
        // Limited overs: the side that has not batted yet.
        yetToBat: !situation.isTest && situation.innings.length == 1,
      ),
      if (note != null && situation.status.phase == MatchPhase.interrupted)
        Padding(
          padding: const EdgeInsets.only(top: Spacing.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.pause_circle_outline, size: 16, color: p.inkMuted),
            ),
            const SizedBox(width: Spacing.xs + 2),
            Expanded(
              child: Text(
                note!,
                key: const ValueKey('match_detail_note'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(color: p.inkMuted),
              ),
            ),
          ]),
        ),
    ];
  }

  String? _rawScore(TeamSide s) {
    final raw = (s == TeamSide.team1 ? match.t1.score : match.t2.score)?.trim();
    if (raw == null || raw.isEmpty || raw == '-') return null;
    return stripJoiners(formatTeamScoreFromApi(raw));
  }

  // ── completed / abandoned / unknown without innings ────────────────────────

  List<Widget> _finished(BuildContext context) {
    final p = context.palette;
    final phase = situation.status.phase;
    final headline = situation.headline ??
        (phase == MatchPhase.abandoned || phase == MatchPhase.completed || phase == MatchPhase.unknown ? situation.status.label : null);
    _Emphasis emph(TeamSide s) {
      final w = situation.winner;
      if (w == null) return _Emphasis.normal;
      return w == s ? _Emphasis.winner : _Emphasis.loser;
    }

    return [
      if (headline != null)
        Text(
          headline,
          key: ValueKey(phase == MatchPhase.completed ? 'match_detail_result' : 'match_detail_situation'),
          style: AppFont.style(size: 22, weight: FontWeight.w800, color: p.ink, height: 1.2),
        ),
      const SizedBox(height: Spacing.md),
      for (final s in TeamSide.values) ...[
        _teamLine(context, s, _finalLine(s) ?? _rawScore(s), emphasis: emph(s), large: true),
        if (s == TeamSide.team1) const SizedBox(height: Spacing.sm),
      ],
    ];
  }

  /// Limited overs keep the overs ("137/4 (9.5)"); Tests join innings.
  String? _finalLine(TeamSide s) {
    final list = situation.inningsOf(s);
    if (list.isEmpty) return null;
    if (situation.isTest || list.length > 1) return situation.scoreLineOf(s);
    final i = list.single;
    return i.overs == null || i.overs!.isEmpty ? i.scoreText : '${i.scoreText} (${i.overs})';
  }

  // ── upcoming ───────────────────────────────────────────────────────────────

  List<Widget> _upcoming(BuildContext context) {
    final p = context.palette;
    final start = match.startTime;
    final w = match.weather;
    final weather = <String>[
      ?w?.condition,
      if (w?.temperature != null) 'Temperature ${w!.temperature}',
      if (w?.rainForecast != null) 'Rain ${w!.rainForecast}%',
    ];
    return [
      for (final s in TeamSide.values) ...[
        _teamLine(context, s, null, emphasis: _Emphasis.normal, large: true),
        if (s == TeamSide.team1) const SizedBox(height: Spacing.sm),
      ],
      const SizedBox(height: Spacing.md),
      if (start != null) Countdown(start: start) else Text('Start time not available', style: AppText.meta.copyWith(color: p.inkMuted)),
      if (start != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(localStartLabel(start), key: const ValueKey('match_detail_start_time'), style: AppText.meta.copyWith(color: p.ink)),
        ),
      if (match.ground != null) _iconLine(context, Icons.place_outlined, match.ground!),
      if (match.toss != null) _iconLine(context, Icons.sports_cricket_outlined, match.toss!),
      if (weather.isNotEmpty) _iconLine(context, Icons.wb_cloudy_outlined, weather.join(', ')),
    ];
  }

  Widget _iconLine(BuildContext context, IconData icon, String text) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs + 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: p.inkMuted)),
        const SizedBox(width: Spacing.xs + 2),
        Expanded(child: Text(text, style: AppText.meta.copyWith(color: p.inkMuted))),
      ]),
    );
  }

  // ── team line ──────────────────────────────────────────────────────────────

  Widget _teamLine(BuildContext context, TeamSide s, String? score, {required _Emphasis emphasis, bool large = false, bool yetToBat = false}) {
    final p = context.palette;
    final t = _team(s);
    final nameColor = emphasis == _Emphasis.loser ? p.inkMuted : p.ink;
    final nameStyle = AppFont.style(
      size: large ? 17 : 16,
      weight: emphasis == _Emphasis.winner ? FontWeight.w800 : FontWeight.w600,
      color: nameColor,
      height: 1.25,
    );
    final scoreStyle = (large ? AppText.scoreCard : AppText.scoreRow).copyWith(
      fontSize: large ? 26 : 22,
      color: emphasis == _Emphasis.loser ? p.inkMuted : p.ink,
    );
    final winner = emphasis == _Emphasis.winner
        ? Row(
            key: ValueKey('match_detail_winner_${s.name}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 14, color: p.positive),
              const SizedBox(width: 3),
              Flexible(child: Text('Winner', style: AppFont.style(size: 12, weight: FontWeight.w700, color: p.positive))),
            ],
          )
        : null;
    final names = Wrap(
      spacing: Spacing.sm,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text(large ? t.name : t.code, style: nameStyle), ?winner],
    );
    final scoreWidget = score == null
        ? null
        : ScoreText(
            score,
            key: ValueKey('match_detail_score_${s.name}'),
            style: scoreStyle,
            heroTag: _scoreTag(s),
            animate: animateScore,
          );
    final logo = MatchHero(tag: _logoTag(s), child: TeamLogo(url: t.logo, name: t.name, size: large ? 30 : 26));
    // Large text: the score drops under the name instead of shrinking.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13.5;
    if (stacked) {
      return Row(
        key: ValueKey('match_detail_team_${s.name}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          logo,
          const SizedBox(width: Spacing.sm + 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              names,
              if (scoreWidget != null)
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: scoreWidget),
            ]),
          ),
        ],
      );
    }
    return LayoutBuilder(
      key: ValueKey('match_detail_team_${s.name}'),
      builder: (context, c) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logo,
          const SizedBox(width: Spacing.sm + 2),
          Expanded(child: names),
          if (scoreWidget != null) ...[
            const SizedBox(width: Spacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.5),
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: scoreWidget),
            ),
          ] else if (yetToBat) ...[
            const SizedBox(width: Spacing.sm),
            Text('Yet to bat', style: AppText.meta.copyWith(color: p.inkMuted)),
          ],
        ],
      ),
    );
  }
}

enum _Emphasis { normal, winner, loser }

/// Status as a word + shape (never colour-only). Red only for live.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.status, this.dense = false});
  final MatchStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    switch (status.phase) {
      case MatchPhase.live:
        return LivePill(key: const ValueKey('match_detail_live_badge'), label: status.label, filled: !dense, dense: true);
      case MatchPhase.completed:
        return StatusChip(key: const ValueKey('match_detail_status_badge'), kind: StatusKind.completed, label: status.label);
      case MatchPhase.upcoming:
        return StatusChip(key: const ValueKey('match_detail_status_badge'), kind: StatusKind.upcoming, label: status.label);
      case MatchPhase.interrupted:
      case MatchPhase.abandoned:
      case MatchPhase.unknown:
        return Container(
          key: const ValueKey('match_detail_status_badge'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: p.hairline), borderRadius: BorderRadius.circular(Radii.chip)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              status.phase == MatchPhase.interrupted ? Icons.pause : (status.phase == MatchPhase.abandoned ? Icons.block : Icons.help_outline),
              size: 12,
              color: p.inkMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.style(size: 12, weight: FontWeight.w700, color: p.ink, height: 1.2),
              ),
            ),
          ]),
        );
    }
  }
}

/// "Starts in 2d 4h", ticking once a minute (not every second).
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.start, this.now});
  final DateTime start;

  /// Test hook.
  final DateTime Function()? now;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final n = _now;
    final toNextMinute = Duration(seconds: 60 - n.second, milliseconds: -n.millisecond);
    _timer = Timer(toNextMinute.isNegative ? const Duration(seconds: 60) : toNextMinute, () {
      if (!mounted) return;
      setState(() {});
      if (widget.start.isAfter(_now)) _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = countdownLabel(widget.start, _now) ?? 'Due to start';
    return Text(
      label,
      key: const ValueKey('match_detail_countdown'),
      style: AppText.scoreCard.copyWith(fontSize: 30, color: p.ink),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collapsed sticky bar
// ─────────────────────────────────────────────────────────────────────────────

/// 56 dp bar shown when the header has scrolled away: short score, status
/// and the last ball (TV-overlay pattern).
class CollapsedScoreBar extends StatelessWidget {
  const CollapsedScoreBar({super.key, required this.match, required this.situation, this.lastBall});
  final MatchDetailVM match;
  final MatchSituation situation;
  final String? lastBall;

  static const double height = 56;

  String get primary {
    final cur = situation.current;
    final phase = situation.status.phase;
    if (cur != null && phase != MatchPhase.completed && phase != MatchPhase.abandoned) {
      final t = cur.side == TeamSide.team1 ? match.t1 : match.t2;
      return '${t.code} ${cur.scoreText}${cur.overs != null && cur.overs!.isNotEmpty ? ' (${cur.overs})' : ''}';
    }
    if (phase == MatchPhase.completed && match.resultMessage != null) return match.resultMessage!;
    return '${match.t1.code} v ${match.t2.code}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = situation.status.phase == MatchPhase.live;
    return Container(
      key: const ValueKey('match_detail_collapsed_bar'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(children: [
        Expanded(
          child: Text(
            primary,
            key: const ValueKey('match_detail_collapsed_score'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.scoreRow.copyWith(color: p.ink),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        if (situation.status.phase != MatchPhase.completed) StatusTag(status: situation.status, dense: true),
        if (live && lastBall != null) ...[
          const SizedBox(width: Spacing.sm),
          BallBead(lastBall!, key: const ValueKey('match_detail_collapsed_last_ball'), size: 26),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wicket band
// ─────────────────────────────────────────────────────────────────────────────

/// Inverted ink band announcing a wicket. Shown only for a genuinely new
/// single delivery (never on first load, cache or catch-up). Slides in
/// (240 ms), holds 2.5 s, collapses (200 ms); reduced motion: 100 ms fades.
class WicketBand extends StatefulWidget {
  const WicketBand({super.key, required this.text, required this.onDone});
  final String text;
  final VoidCallback onDone;

  @override
  State<WicketBand> createState() => _WicketBandState();
}

class _WicketBandState extends State<WicketBand> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed && _hold == null) _run();
  }

  Future<void> _run() async {
    final m = Motion.of(context);
    _c.duration = m.d(Motion.wicketBandIn);
    await _c.forward(from: 0).orCancel.catchError((_) {});
    if (!mounted) return;
    _hold = Timer(Motion.wicketBandHold, () async {
      if (!mounted) return;
      _c.duration = m.d(Motion.wicketBandOut);
      await _c.reverse().orCancel.catchError((_) {});
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _c, curve: Motion.standard),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.sm),
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('match_detail_wicket_band'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm + 2),
            decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(Radii.chip)),
            child: Text(widget.text, style: AppFont.style(size: 15, weight: FontWeight.w700, color: p.surface, height: 1.3)),
          ),
        ),
      ),
    );
  }
}
