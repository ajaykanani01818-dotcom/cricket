import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../logic/commentary_controller.dart';
import '../logic/match_detail_logic.dart';
import '../widgets/match_detail_common.dart';

/// Ported from RN CommentaryTabContent (MatchDetailScreen.tsx) /
/// MatchCommentaryTab.tsx. Returns a SLIVER: commentary can be hundreds of
/// rows, so items are built lazily by the outer CustomScrollView.
/// State lives in [CommentaryController] (owned by the screen) so switching
/// tabs keeps loaded pages and doesn't refetch.
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
          return const SliverToBoxAdapter(
            child: Padding(
              key: ValueKey('match_detail_commentary_loading'),
              padding: EdgeInsets.all(40),
              child: Column(children: [
                CircularProgressIndicator(color: AppColors.pitch),
                SizedBox(height: Spacing.md),
                Text('Loading commentary...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ]),
            ),
          );
        }
        if (c.error != null && !c.hasData) {
          return SliverToBoxAdapter(
            child: Padding(
              key: const ValueKey('match_detail_commentary_error'),
              padding: const EdgeInsets.all(Spacing.xl),
              child: Column(children: [
                Text(c.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.error)),
                const SizedBox(height: Spacing.md),
                TextButton(
                  key: const ValueKey('match_detail_commentary_retry'),
                  onPressed: c.retry,
                  child: const Text('Retry'),
                ),
              ]),
            ),
          );
        }
        if (!c.hasData) {
          return const SliverToBoxAdapter(
            child: Padding(
              key: ValueKey('match_detail_commentary_empty'),
              padding: EdgeInsets.all(40),
              child: Text('Commentary not available',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ),
          );
        }

        final items = c.visible;
        return SliverMainAxisGroup(slivers: [
          SliverToBoxAdapter(child: _Filters(controller: c)),
          if (c.filtered.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                key: ValueKey('match_detail_commentary_no_match'),
                padding: EdgeInsets.all(40),
                child: Text('No commentary matches the selected filters',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
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
                      : FilledButton(
                          key: const ValueKey('match_detail_commentary_load_more'),
                          onPressed: c.loadMore,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.pitch,
                            padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl, vertical: Spacing.md),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Load more', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                ),
              ),
            ),
          if (c.error != null && c.hasData)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Text(c.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.error)),
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

  Widget _chip(String key, String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: Spacing.sm),
        child: Material(
          color: active ? AppColors.pitch : AppColors.cardAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.xs),
            side: BorderSide(color: active ? AppColors.pitch : AppColors.borderSubtle),
          ),
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
              child: Text(label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? AppColors.white : AppColors.text)),
            ),
          ),
        ),
      );

  Widget _group(String label, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: Spacing.sm),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (c.teams.isNotEmpty)
          _group('Team:', [
            _chip('match_detail_commentary_team_all', 'All', c.team == 'all', () => c.setTeam('all')),
            for (final t in c.teams)
              _chip('match_detail_commentary_team_$t', commentaryTeamName(t, c.firstPage), c.team == t, () => c.setTeam(t)),
          ]),
        _group('Event:', [
          for (final f in CommentaryFilter.values)
            _chip('match_detail_commentary_filter_${f.name}', commentaryFilterLabel(f), c.filter == f, () => c.setFilter(f)),
        ]),
      ]),
    );
  }
}

/// One commentary row (ball chip, over + time pills, rich text, runs).
class CommentaryItem extends StatelessWidget {
  const CommentaryItem({super.key, required this.ball});
  final CommentaryBall ball;

  @override
  Widget build(BuildContext context) {
    final runs = ball.runs;
    final time = commentaryTime(ball.timestamp);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BallCircle(value: ball.value, size: 32, fontSize: 12),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                  decoration: BoxDecoration(color: const Color(0x40F59E0B), borderRadius: BorderRadius.circular(6)),
                  child: Text(ball.overLabel,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.goldDark)),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(width: Spacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(Radii.xs)),
                    child: Text(time, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                ],
              ]),
            ),
            CommentaryRichParagraph(runs: ball.textRuns),
            const SizedBox(height: Spacing.xs),
            Text('$runs run${runs != 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      ]),
    );
  }
}
