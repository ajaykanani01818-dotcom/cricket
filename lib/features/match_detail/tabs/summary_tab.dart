import 'package:flutter/material.dart';

import '../../../core/api/json.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../logic/match_detail_logic.dart';
import '../logic/match_state.dart';
import '../widgets/md_ui.dart';
import 'tab_scorecard_parse.dart';

/// Summary tab (research §3.3, PRD §8.4): players at the crease, partnership
/// and last wicket, recent overs and the latest deliveries while in play;
/// the result summary once completed. Anything the provider did not send is
/// hidden, never inferred (PRD §8.2).
class MatchSummaryTab extends StatelessWidget {
  const MatchSummaryTab({
    super.key,
    required this.match,
    required this.situation,
    required this.live,
    required this.batters,
    required this.overs,
    required this.scorecard,
    required this.loadingLive,
    this.momInfo,
    this.momLoading = false,
    this.onMomTap,
    this.onSeeCommentary,
    this.onSeeInfo,
  });

  final MatchDetailVM match;
  final MatchSituation situation;
  final LiveVM? live;

  /// Live pair, or the last non-empty pair while a poll briefly drops both.
  final List<BatterRow> batters;
  final List<OverView> overs;
  final ScorecardView? scorecard;
  final bool loadingLive;
  final JsonMap? momInfo;
  final bool momLoading;
  final VoidCallback? onMomTap;
  final VoidCallback? onSeeCommentary;
  final VoidCallback? onSeeInfo;

  @override
  Widget build(BuildContext context) {
    final phase = situation.status.phase;
    final children = <Widget>[];
    switch (phase) {
      case MatchPhase.live:
      case MatchPhase.interrupted:
        children.addAll(_inPlay(context));
        // Live but the provider has no ball-by-ball detail yet (e.g. first
        // ball not bowled): never leave the tab blank (PRD §16.3).
        if (children.isEmpty) {
          children.add(_message(
            context,
            'Batting, bowling and the over strip appear here as soon as ball-by-ball data arrives for this match.',
            actionLabel: 'See match info',
            onAction: onSeeInfo,
          ));
        }
      case MatchPhase.completed:
        children.addAll(_completed(context));
        if (children.isEmpty) {
          children.add(_message(
            context,
            'A summary is not available for this match. The scorecard may have more detail.',
            actionLabel: 'See match info',
            onAction: onSeeInfo,
          ));
        }
      case MatchPhase.upcoming:
        children.add(_message(
          context,
          'Live scores, the over strip and ball-by-ball commentary appear here once play starts.',
          actionLabel: 'See match info',
          onAction: onSeeInfo,
        ));
      case MatchPhase.abandoned:
        children.add(_message(context, '${situation.status.label}. No scores to show for this match.',
            actionLabel: 'See match info', onAction: onSeeInfo));
      case MatchPhase.unknown:
        children.addAll(_inPlay(context));
        if (children.isEmpty) children.add(_message(context, 'Match status is not available yet.'));
    }
    return Column(
      key: const ValueKey('match_detail_summary_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _message(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction}) {
    final p = context.palette;
    return Padding(
      key: const ValueKey('match_detail_summary_message'),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: AppText.reading.copyWith(color: p.inkMuted)),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: Spacing.md),
          OutlinedButton(key: const ValueKey('match_detail_summary_action'), onPressed: onAction, child: Text(actionLabel)),
        ],
      ]),
    );
  }

  // ── in play ────────────────────────────────────────────────────────────────

  List<Widget> _inPlay(BuildContext context) {
    final p = context.palette;
    final out = <Widget>[];
    final score = live?.score;
    final bowler = live?.bowler;

    if (batters.isNotEmpty || bowler != null) {
      out.add(const MdSectionTitle('At the crease', padding: EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.sm)));
      if (batters.isNotEmpty) {
        out.add(NumTable(
          key: const ValueKey('match_detail_batting'),
          nameHeader: 'Batter',
          columns: const ['R', 'B', '4s', '6s', 'SR'],
          rows: [
            for (final b in batters)
              () {
                final onStrike = b.key.startsWith('striker-');
                return NumRow(
                  key: ValueKey('bat_${b.key}'),
                  name: b.name,
                  leading: onStrike ? Icon(Icons.sports_cricket, size: 15, color: p.ink) : null,
                  tags: [if (onStrike) const MdTag('on strike', strong: true)],
                  values: [b.runs, b.balls, b.fours, b.sixes, b.strikeRate],
                  strongValue: 0,
                  semanticsLabel:
                      '${b.name}${onStrike ? ', on strike' : ''}: ${b.runs} runs from ${b.balls} balls, ${b.fours} fours, ${b.sixes} sixes, strike rate ${b.strikeRate}',
                );
              }(),
          ],
        ));
      }
      if (bowler != null) {
        out.add(const SizedBox(height: Spacing.md));
        out.add(NumTable(
          key: const ValueKey('match_detail_bowling'),
          nameHeader: 'Bowler',
          columns: const ['O', 'M', 'R', 'W', 'Econ'],
          rows: [
            NumRow(
              key: ValueKey('bowl_${bowler.key}'),
              name: bowler.name,
              values: [bowler.overs, bowler.maidens, bowler.runs, bowler.wickets, bowler.economy],
              strongValue: 3,
              semanticsLabel:
                  '${bowler.name}: ${bowler.overs} overs, ${bowler.maidens} maidens, ${bowler.runs} runs, ${bowler.wickets} wickets, economy ${bowler.economy}',
            ),
          ],
        ));
      }
    } else if (loadingLive) {
      out.add(const Padding(
        key: ValueKey('match_detail_live_loading'),
        padding: EdgeInsets.all(Spacing.xl),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ));
    }

    final pRuns = J.text(J.at(score, 'partnerShip.run'));
    final pBalls = J.text(J.at(score, 'partnerShip.ball'));
    final lw = J.map(score?['lastWicket']);
    final lwName = J.text(lw['name']);
    final facts = <Widget>[
      if (pRuns != null)
        MdKeyValue(
          valueKey: const ValueKey('match_detail_partnership'),
          label: 'Partnership',
          value: pBalls != null ? '$pRuns ($pBalls)' : pRuns,
        ),
      if (lwName != null)
        MdKeyValue(
          valueKey: const ValueKey('match_detail_last_wicket'),
          label: 'Last wicket',
          value: _lastWicketLine(lw),
        ),
    ];
    if (facts.isNotEmpty) {
      out.add(const SizedBox(height: Spacing.sm));
      out.addAll(facts);
    }

    final previous = overs.skip(1).toList(); // index 0 is in the header strip
    if (previous.isNotEmpty) {
      out.add(const MdSectionTitle('Recent overs'));
      out.add(Column(
        key: const ValueKey('match_detail_recent_overs'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final o in previous) _RecentOver(key: ValueKey('ro_${o.key}'), over: o)],
      ));
    }

    final latest = (live?.commentaryBalls ?? const <CommentaryBall>[]).take(4).toList();
    if (latest.isNotEmpty) {
      out.add(MdSectionTitle(
        'Latest',
        trailing: onSeeCommentary == null
            ? null
            : TextButton(
                key: const ValueKey('match_detail_see_commentary'),
                onPressed: onSeeCommentary,
                child: const Text('All commentary'),
              ),
      ));
      out.add(Column(
        key: const ValueKey('match_detail_live_commentary'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in latest)
            Padding(
              key: ValueKey('lc_${b.key}'),
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 44,
                  child: Text(b.overLabel, style: AppText.figures.copyWith(color: p.inkMuted)),
                ),
                BallBead(b.value, size: 26),
                const SizedBox(width: Spacing.md),
                Expanded(child: CommentaryRichParagraph(runs: b.textRuns)),
              ]),
            ),
        ],
      ));
    }
    return out;
  }

  static String _lastWicketLine(JsonMap lw) {
    final name = J.str(lw['name']);
    final run = J.text(lw['run']);
    final ball = J.text(lw['ball']);
    final info = J.text(lw['info']);
    final at = J.text(lw['score']);
    final over = J.text(lw['over']);
    final b = StringBuffer(name);
    if (run != null) b.write(ball != null ? ' $run ($ball)' : ' $run');
    if (info != null) b.write(', $info');
    if (at != null) b.write(' at $at');
    if (over != null) b.write(' in over $over');
    return b.toString();
  }

  // ── completed ──────────────────────────────────────────────────────────────

  List<Widget> _completed(BuildContext context) {
    final out = <Widget>[];
    if (match.momEligible && (momLoading || momInfo != null)) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: Spacing.lg),
        child: _MomCard(info: momInfo, loading: momLoading, onTap: onMomTap),
      ));
    }
    final sc = scorecard;
    if (sc != null && sc.hasInnings) {
      for (var i = 0; i < sc.innings.length; i++) {
        out.add(_InningsDigest(key: ValueKey('match_detail_digest_$i'), inning: sc.innings[i], index: i));
      }
    } else {
      out.add(_message(context, 'A detailed scorecard is not available for this match.'));
    }
    return out;
  }
}

class _RecentOver extends StatelessWidget {
  const _RecentOver({super.key, required this.over});
  final OverView over;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm + 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Spacing.md, runSpacing: 2, children: [
          Text(over.title, style: AppFont.style(size: 14, weight: FontWeight.w700, color: p.ink, height: 1.3)),
          if (over.runs != null) Text(over.runs == 1 ? '1 run' : '${over.runs} runs', style: AppText.meta.copyWith(color: p.inkMuted)),
          if (over.bowler != null) Text(over.bowler!, style: AppText.meta.copyWith(color: p.inkMuted)),
        ]),
        const SizedBox(height: Spacing.xs + 2),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final l in over.labels) BallBead(l, size: 28)]),
      ]),
    );
  }
}

class _MomCard extends StatelessWidget {
  const _MomCard({required this.info, required this.loading, this.onTap});
  final JsonMap? info;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = J.text(info?['name']);
    final enabled = !loading && info != null && onTap != null;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card), side: BorderSide(color: p.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('match_detail_mom_card'),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(children: [
            NetImage(url: J.text(info?['logo']), size: 44, fallbackLetter: name ?? '?', background: p.surfaceAlt),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Player of the match', style: AppText.small.copyWith(color: p.inkMuted)),
                const SizedBox(height: 2),
                if (loading)
                  Text('Loading…', style: AppText.name.copyWith(color: p.inkMuted))
                else if (name != null)
                  Text(name, key: const ValueKey('match_detail_mom_name'), style: AppFont.style(size: 17, weight: FontWeight.w700, color: p.ink)),
              ]),
            ),
            if (enabled) Icon(Icons.chevron_right, color: p.inkMuted),
          ]),
        ),
      ),
    );
  }
}

/// Completed match: per innings total + top two batters and bowlers
/// (sorted from the real scorecard rows; nothing computed beyond that).
class _InningsDigest extends StatelessWidget {
  const _InningsDigest({super.key, required this.inning, required this.index});
  final ScInning inning;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    int n(String s) => int.tryParse(s) ?? -1;
    final bats = [...inning.batting]..sort((a, b) => n(b.runs).compareTo(n(a.runs)));
    final bowls = [...inning.bowling]..sort((a, b) {
        final w = n(b.wickets).compareTo(n(a.wickets));
        return w != 0 ? w : n(a.runs).compareTo(n(b.runs));
      });
    final total = inning.runs == '-' ? null : (inning.wickets == '10' || inning.wickets == '-' ? inning.runs : '${inning.runs}/${inning.wickets}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MdSectionTitle(
        '${inning.shortName ?? inning.teamName} innings',
        trailing: total == null
            ? null
            : Text('$total${inning.overs != '-' ? ' (${inning.overs})' : ''}', style: AppText.scoreRow.copyWith(color: p.ink)),
      ),
      if (bats.isNotEmpty)
        NumTable(
          nameHeader: 'Top batters',
          columns: const ['R', 'B'],
          rows: [
            for (final b in bats.take(2))
              NumRow(name: b.name, tags: [if (!b.isOut) const MdTag('not out')], values: [b.runs, b.balls], strongValue: 0),
          ],
        ),
      if (bowls.isNotEmpty) ...[
        const SizedBox(height: Spacing.sm),
        NumTable(
          nameHeader: 'Top bowlers',
          columns: const ['W', 'R', 'O'],
          rows: [for (final b in bowls.take(2)) NumRow(name: b.name, values: [b.wickets, b.runs, b.overs], strongValue: 0)],
        ),
      ],
    ]);
  }
}
