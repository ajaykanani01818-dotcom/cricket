import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../logic/match_detail_logic.dart';
import '../widgets/match_detail_common.dart';
import 'match_section_title.dart';

/// Ported from RN LiveTabContent (MatchDetailScreen.tsx) / MatchLiveTab.tsx.
/// All inputs are pre-parsed view-models, so build is cheap; the parent only
/// rebuilds it when a poll actually changed something (fingerprints).
class MatchLiveTab extends StatefulWidget {
  const MatchLiveTab({
    super.key,
    required this.match,
    required this.live,
    required this.displayBattingPair,
    required this.scorecardBatters,
    required this.scorecardBowlers,
    required this.loadingLive,
    required this.loadingScorecard,
  });

  final MatchDetailVM match;
  final LiveVM? live;

  /// Live pair, or (live & not won) the last non-empty pair while the API
  /// briefly omits both batters after a wicket.
  final List<BatterRow> displayBattingPair;

  /// null = scorecard has no last-innings batting/bowling list.
  final List<BatterRow>? scorecardBatters;
  final List<BowlerRow>? scorecardBowlers;
  final bool loadingLive, loadingScorecard;

  @override
  State<MatchLiveTab> createState() => _MatchLiveTabState();
}

class _MatchLiveTabState extends State<MatchLiveTab> {
  bool _recentOversOpen = false;

  @override
  void didUpdateWidget(MatchLiveTab old) {
    super.didUpdateWidget(old);
    if (old.match.id != widget.match.id) _recentOversOpen = false;
  }

  static const _batCols = ['R', 'B', '4s', '6s', 'SR'];
  static const _bowlCols = ['O', 'M', 'R', 'W', 'Econ.'];

  Widget _spinner() => const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
      );

  Widget _battingTable(List<BatterRow> rows) => StatTable(children: [
        const StatTableHeader(first: 'Batter', columns: _batCols, lastWidth: 42),
        for (var i = 0; i < rows.length; i++)
          StatRow(
            key: ValueKey('bat_${rows[i].key}'),
            first: i == 0,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: Spacing.xs),
                    child: Text(
                      rows[i].displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: rows[i].notOut ? AppColors.win : AppColors.text,
                      ),
                    ),
                  ),
                ),
                StatCell(rows[i].runs),
                StatCell(rows[i].balls),
                StatCell(rows[i].fours),
                StatCell(rows[i].sixes),
                StatCell(rows[i].strikeRate, width: 42),
              ]),
              if (rows[i].outSummary != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, Spacing.sm, 2, 0),
                  child: Text(rows[i].outSummary!, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textMuted)),
                ),
            ]),
          ),
      ]);

  Widget _bowlingTable(List<BowlerRow> rows) => StatTable(children: [
        const StatTableHeader(first: 'Bowler', columns: _bowlCols, lastWidth: 44),
        for (var i = 0; i < rows.length; i++)
          StatRow(
            key: ValueKey('bowl_${rows[i].key}'),
            first: i == 0,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: Spacing.xs),
                  child: Text(rows[i].name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
              ),
              StatCell(rows[i].overs),
              StatCell(rows[i].maidens),
              StatCell(rows[i].runs),
              StatCell(rows[i].wickets),
              StatCell(rows[i].economy, width: 44),
            ]),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final live = widget.live;
    final isLive = m.isLive;
    final won = m.isMatchWon;
    final co = m.currentOver;
    final liveBowler = isLive ? live?.bowler : null;
    final recentRows = isLive ? (live?.recentOvers ?? const <RecentOverRow>[]) : const <RecentOverRow>[];
    final commentary = liveTabCommentary(live, m);
    final children = <Widget>[];

    // Current Over — only real ball rows; wickets/runs from chips, not stale API wickets
    if (isLive && co != null) {
      children.add(Container(
        key: const ValueKey('match_detail_current_over'),
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.border),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.white, Color(0xFFF7F7F8), Color(0xFFF0F0F0)],
          ),
          boxShadow: const [BoxShadow(color: Color(0x1A0860C4), blurRadius: 8, offset: Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: AppColors.gold),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MatchSectionTitle(icon: Icons.bolt, label: co.title, variant: 'currentOver'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(co.statsLine,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4)),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final b in co.balls) BallCircle(key: ValueKey('co_${b.key}'), value: b.value, bordered: true),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ));
    }

    // Batting — same section + table chrome as Scorecard
    if (won || isLive) {
      final batters = widget.scorecardBatters;
      Widget body;
      if (widget.loadingLive && live?.score == null && batters == null) {
        body = _spinner();
      } else if (isLive && widget.displayBattingPair.isNotEmpty) {
        body = _battingTable(widget.displayBattingPair);
      } else if (batters != null && batters.isNotEmpty) {
        body = _battingTable(batters);
      } else {
        body = _empty('Batter data will appear here when available');
      }
      children.add(SectionCard(
        key: const ValueKey('match_detail_batting'),
        stat: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const MatchSectionTitle(icon: Icons.sports_cricket, label: 'Batting', variant: 'stat'),
          body,
        ]),
      ));
    }

    // Bowling — same section + table chrome as Scorecard
    if ((isLive && !won && liveBowler != null) || won) {
      final bowlers = widget.scorecardBowlers;
      Widget body;
      if (won && widget.loadingScorecard && bowlers == null) {
        body = _spinner();
      } else if (isLive && liveBowler != null) {
        body = _bowlingTable([liveBowler]);
      } else if (bowlers != null && bowlers.isNotEmpty) {
        body = _bowlingTable(bowlers);
      } else {
        body = _empty('Bowler data will appear here when available');
      }
      children.add(SectionCard(
        key: const ValueKey('match_detail_bowling'),
        stat: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const MatchSectionTitle(icon: Icons.sports_baseball, label: 'Bowling', variant: 'stat'),
          body,
        ]),
      ));
    }

    // Recent overs — collapsed by default; tap header to expand
    if (isLive && recentRows.isNotEmpty) {
      children.add(SectionCard(
        key: const ValueKey('match_detail_recent_overs'),
        stat: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            key: const ValueKey('match_detail_recent_overs_toggle'),
            onTap: () => setState(() => _recentOversOpen = !_recentOversOpen),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const MatchSectionTitle(icon: Icons.list_alt, label: 'Recent overs', variant: 'stat'),
                  Text(
                    'Last ${recentRows.length} over${recentRows.length != 1 ? 's' : ''} · scroll for earlier',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.4),
                  ),
                ]),
              ),
              const SizedBox(width: Spacing.md),
              Icon(_recentOversOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: AppColors.pitch),
            ]),
          ),
          if (_recentOversOpen)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  key: const ValueKey('match_detail_recent_overs_list'),
                  shrinkWrap: true,
                  primary: false,
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  itemCount: recentRows.length,
                  itemBuilder: (_, i) => _RecentOverTable(key: ValueKey('ro_${recentRows[i].key}'), row: recentRows[i]),
                ),
              ),
            ),
        ]),
      ));
    }

    // Weather
    final w = m.weather;
    if (w != null) {
      Widget line(String icon, String text) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(icon, style: const TextStyle(fontSize: 15, height: 1.33)),
              const SizedBox(width: Spacing.sm),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.text, height: 1.43))),
            ]),
          );
      children.add(SectionCard(
        key: const ValueKey('match_detail_weather'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const MatchSectionTitle(icon: Icons.wb_cloudy_outlined, label: 'Weather'),
          line('☀️', w.condition),
          const SizedBox(height: Spacing.xs),
          line('🌡️', w.temperature),
          const SizedBox(height: Spacing.xs),
          line('💨', w.wind),
          const SizedBox(height: Spacing.xs),
          line('💧', '${w.humidity}%'),
          const SizedBox(height: Spacing.xs),
          line('🌧️', '${w.rainForecast}%'),
        ]),
      ));
    }

    // Commentary (latest 20, own capped scroll area)
    if (commentary.isNotEmpty) {
      children.add(SectionCard(
        key: const ValueKey('match_detail_live_commentary'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const MatchSectionTitle(icon: Icons.chat_bubble_outline, label: 'Commentary'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: commentary.length,
              itemBuilder: (_, i) => _LiveCommentaryItem(key: ValueKey('lc_${commentary[i].key}'), ball: commentary[i]),
            ),
          ),
        ]),
      ));
    }

    return Column(key: const ValueKey('match_detail_live_tab'), crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _RecentOverTable extends StatelessWidget {
  const _RecentOverTable({super.key, required this.row});
  final RecentOverRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StatTable(children: [
        Container(
          color: AppColors.tableHeaderBg,
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.xs),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'Over ${row.displayOverNumber}',
                      // RN used theme.text here, which is invisible on the dark header band.
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.white)),
                  if (row.bowler != null)
                    TextSpan(
                        text: '  ·  ${row.bowler}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              '${row.runs} run${row.runs != 1 ? 's' : ''} • ${row.wickets} wicket${row.wickets != 1 ? 's' : ''}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ]),
        ),
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: Spacing.md),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in row.chips) BallCircle(value: c, size: 30, fontSize: c.length > 2 ? 8 : 11),
          ]),
        ),
      ]),
    );
  }
}

class _LiveCommentaryItem extends StatelessWidget {
  const _LiveCommentaryItem({super.key, required this.ball});
  final CommentaryBall ball;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BallCircle(value: ball.value, size: 32, fontSize: 12),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CommentaryRichParagraph(runs: ball.textRuns),
              const SizedBox(height: Spacing.xs),
              if (ball.overNumber != null)
                Text('Over ${ball.overLabel}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ]),
      );
}
