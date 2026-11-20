import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../logic/commentary_controller.dart';
import '../logic/match_detail_logic.dart';
import '../widgets/md_ui.dart';

/// Commentary tab (research §3.5): reverse-chronological feed, ball rows
/// with the over.ball label and bead, quiet info notes, over-end cards and
/// key-moment filters. Returns a SLIVER so long feeds build lazily.
/// State lives in [CommentaryController] (owned by the screen).
class MatchCommentaryTabSliver extends StatelessWidget {
  const MatchCommentaryTabSliver({super.key, required this.controller});
  final CommentaryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.loading || !c.started) {
          return const SliverToBoxAdapter(child: _CommentarySkeleton(key: ValueKey('match_detail_commentary_loading')));
        }
        if (c.error != null && !c.hasData) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
              child: ErrorRetry(
                key: const ValueKey('match_detail_commentary_error'),
                title: "Commentary didn't load",
                message: c.error!,
                onRetry: c.retry,
              ),
            ),
          );
        }
        if (!c.hasData) {
          return const SliverToBoxAdapter(
            child: Padding(
              key: ValueKey('match_detail_commentary_empty'),
              padding: EdgeInsets.symmetric(vertical: Spacing.xl),
              child: EmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'Commentary not available',
                subtitle: 'The data provider has not sent ball-by-ball commentary for this match.',
              ),
            ),
          );
        }

        final items = c.visible;
        return SliverMainAxisGroup(slivers: [
          SliverToBoxAdapter(child: _Filters(controller: c)),
          if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                key: const ValueKey('match_detail_commentary_no_match'),
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Text(
                  c.filter == CommentaryFilter.wickets
                      ? 'No wickets in the loaded commentary yet.'
                      : c.filter == CommentaryFilter.boundaries
                          ? 'No fours or sixes in the loaded commentary yet.'
                          : 'Nothing matches this filter.',
                  style: AppText.reading.copyWith(color: context.palette.inkMuted),
                ),
              ),
            )
          else
            SliverList.builder(
              key: const ValueKey('match_detail_commentary_list'),
              itemCount: items.length,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final i = items.indexWhere((b) => 'cm_${b.key}' == key.value);
                return i < 0 ? null : i;
              },
              itemBuilder: (_, i) => CommentaryItem(key: ValueKey('cm_${items[i].key}'), ball: items[i]),
            ),
          if (c.hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Center(
                  child: c.loadingMore
                      ? const SizedBox(
                          key: ValueKey('match_detail_commentary_loading_more'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton(
                          key: const ValueKey('match_detail_commentary_load_more'),
                          onPressed: c.loadMore,
                          child: const Text('Load earlier commentary'),
                        ),
                ),
              ),
            ),
          if (c.error != null && c.hasData)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Text(c.error!, style: AppText.meta.copyWith(color: context.palette.negative)),
              ),
            ),
        ]);
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});
  final CommentaryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = context.palette;
    Widget chip(String key, String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: Spacing.sm),
          child: ChoiceChip(
            key: ValueKey(key),
            label: Text(label),
            selected: active,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            selectedColor: p.brandTint,
            backgroundColor: p.surface,
            side: BorderSide(color: active ? p.brand : p.hairline),
            labelStyle: AppFont.style(size: 13, weight: FontWeight.w700, color: p.ink),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in CommentaryFilter.values)
              chip('match_detail_commentary_filter_${f.name}', commentaryFilterLabel(f), c.filter == f, () => c.setFilter(f)),
          ]),
        ),
        if (c.teams.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('match_detail_commentary_team_all', 'All innings', c.team == 'all', () => c.setTeam('all')),
              for (final t in c.teams)
                chip('match_detail_commentary_team_$t', inningsChipLabel(t, c.firstPage), c.team == t, () => c.setTeam(t)),
            ]),
          ),
      ]),
    );
  }
}

/// "RSA 1st innings" from "t1_1".
String inningsChipLabel(String inningsIndex, CommentaryPage? page) {
  final name = commentaryTeamName(inningsIndex, page);
  final n = int.tryParse(inningsIndex.split('_').last);
  if (n == null) return name;
  final ord = switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };
  return '$name $ord innings';
}

/// One feed row: info note, or ball row (+ over-end card above the over's
/// last ball, since the feed is newest first).
class CommentaryItem extends StatelessWidget {
  const CommentaryItem({super.key, required this.ball});
  final CommentaryBall ball;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (ball.type == 'info') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
        padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.xs, 0, Spacing.xs),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: p.hairline, width: 3))),
        child: CommentaryRichParagraph(runs: ball.textRuns, style: AppText.meta.copyWith(color: p.inkMuted, height: 1.45)),
      );
    }
    final oe = ball.overEnd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (oe != null) _OverEndCard(summary: oe),
      Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 48,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ball.overLabel, style: AppText.figures.copyWith(color: p.ink)),
              const SizedBox(height: Spacing.xs),
              BallBead(ball.value, size: 28),
            ]),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(child: CommentaryRichParagraph(runs: ball.textRuns)),
        ]),
      ),
    ]);
  }
}

class _OverEndCard extends StatelessWidget {
  const _OverEndCard({required this.summary});
  final OverEndSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = summary;
    final title = StringBuffer('End of over ${s.overNumber}');
    if (s.runs != null) title.write(': ${s.runs == 1 ? '1 run' : '${s.runs} runs'}');
    final lines = <String>[
      if (s.totalScore != null) '${s.battingTeam != null ? '${s.battingTeam} ' : ''}${s.totalScore}',
      ?s.bowlerLine,
      if (s.batterLines.isNotEmpty) s.batterLines.join(', '),
    ];
    return Container(
      key: ValueKey('match_detail_over_end_${s.overNumber}'),
      margin: const EdgeInsets.only(top: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toString(), style: AppFont.style(size: 14, weight: FontWeight.w700, color: p.ink, height: 1.3)),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(l, style: AppText.meta.copyWith(color: p.inkMuted)),
          ),
      ]),
    );
  }
}

class _CommentarySkeleton extends StatelessWidget {
  const _CommentarySkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading commentary',
        child: ShimmerGroup(
          child: Padding(
            padding: const EdgeInsets.only(top: Spacing.lg),
            child: Column(children: [
              for (var i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: Spacing.lg),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ShimmerBox(width: 40, height: 40, radius: 20),
                    SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ShimmerBox(height: 14, radius: 4),
                        SizedBox(height: 6),
                        FractionallySizedBox(widthFactor: 0.6, child: ShimmerBox(height: 14, radius: 4)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      );
}
