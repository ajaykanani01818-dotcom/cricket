import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/shimmer_box.dart';
import '../ads/ads.dart';
import '../common/inline_states.dart';
import '../common/live_match_card.dart';
import '../common/upcoming_match_card.dart';
import 'matches_controller.dart';

/// RN adsConfig default `matches_list.interval`. The Flutter ads interface
/// doesn't expose placement config; ListNativeAd itself decides whether to
/// render (it collapses to nothing when ads are off / no-ads is active).
const matchesNativeAdInterval = 3;

/// One row of the flat list: series header band, match card or inline ad.
sealed class MatchListItem {
  const MatchListItem(this.key);
  final String key;
}

class SeriesHeaderItem extends MatchListItem {
  const SeriesHeaderItem(super.key, this.seriesName);
  final String seriesName;
}

class MatchItem extends MatchListItem {
  const MatchItem(super.key, this.match, this.index);
  final MatchSummary match;
  final int index;
}

class NativeAdItem extends MatchListItem {
  const NativeAdItem(super.key);
}

/// RN `buildListData`: group consecutive matches by series (preserving order)
/// and interleave a native ad slot every [nativeInterval] matches.
List<MatchListItem> buildMatchListData(MatchesTab tab, List<MatchSummary> list,
    {bool showNativeSlots = true, int nativeInterval = matchesNativeAdInterval}) {
  final items = <MatchListItem>[];
  String? current;
  var idx = 0;
  for (final m in list) {
    final series = m.series.trim().isEmpty ? 'Other matches' : m.series.trim();
    if (series != current) {
      current = series;
      items.add(SeriesHeaderItem('header-${tab.name}-$series-$idx', series));
    }
    if (showNativeSlots && nativeInterval > 0 && idx > 0 && idx % nativeInterval == 0) {
      items.add(NativeAdItem('native-${tab.name}-$idx'));
    }
    items.add(MatchItem('match-${tab.name}-${m.id.isEmpty ? 'i$idx' : m.id}-$idx', m, idx));
    idx++;
  }
  return items;
}

/// Ported from RN `MatchesTabPanel` (one page of the Matches pager).
class MatchesTabPanel extends StatefulWidget {
  const MatchesTabPanel({super.key, required this.tab, required this.controller, required this.onMatchTap, this.bottomPadding = 0});
  final MatchesTab tab;
  final MatchesController controller;
  final ValueChanged<MatchSummary> onMatchTap;
  final double bottomPadding;

  @override
  State<MatchesTabPanel> createState() => _MatchesTabPanelState();
}

class _MatchesTabPanelState extends State<MatchesTabPanel> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  List<MatchSummary>? _builtFor;
  List<MatchListItem> _items = const [];
  Map<String, int> _indexByKey = const {};

  @override
  bool get wantKeepAlive => true;

  MatchesController get _c => widget.controller;
  bool get _isCompleted => widget.tab == MatchesTab.completed;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// RN onEndReachedThreshold 0.4 (fraction of the viewport).
  void _maybeLoadMore(ScrollMetrics m) {
    // Auto-trigger only; after a failed page the footer's Try Again retries
    // (otherwise a short list + failing server would retry in a loop).
    if (!_isCompleted || _c.loadMoreError != null) return;
    if (m.extentAfter < m.viewportDimension * 0.4) _c.loadMoreCompleted();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(listenable: _c, builder: (context, _) => _body());
  }

  Widget _body() {
    final d = _c[widget.tab];
    final retry = switch (widget.tab) {
      MatchesTab.upcoming => _c.fetchUpcoming,
      MatchesTab.live => _c.fetchLive,
      MatchesTab.completed => _c.fetchCompleted,
    };

    if (d.loading && d.matches.isEmpty) return const MatchesShimmer();

    Widget scrollable(Widget child) => RefreshIndicator(
          key: ValueKey('matches_refresh_${widget.tab.name}'),
          color: AppColors.pitch,
          onRefresh: _c.refresh,
          child: child,
        );

    if (d.error != null || d.matches.isEmpty) {
      // Still pull-to-refreshable.
      return scrollable(ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xxl, Spacing.lg, 0),
        children: [
          if (d.error != null)
            InlineMessageCard(
              key: ValueKey('matches_error_${widget.tab.name}'),
              text: d.error!,
              isError: true,
              actionLabel: 'Try Again',
              actionKey: ValueKey('matches_retry_${widget.tab.name}'),
              onAction: retry,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: Spacing.xxl),
            )
          else
            InlineMessageCard(
              key: ValueKey('matches_empty_${widget.tab.name}'),
              text: widget.tab == MatchesTab.live ? 'No live matches right now' : 'No matches in this section',
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: Spacing.xxl),
            ),
        ],
      ));
    }

    if (!identical(_builtFor, d.matches)) {
      _builtFor = d.matches;
      _items = buildMatchListData(widget.tab, d.matches);
      _indexByKey = {for (var i = 0; i < _items.length; i++) _items[i].key: i};
    }
    final items = _items;
    final r = Responsive.of(context);
    final footer = _isCompleted ? 1 : 0;

    if (_isCompleted) {
      // RN FlatList fires onEndReached on layout when the first page doesn't
      // fill the viewport; mirror that (the controller ignores duplicates).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _maybeLoadMore(_scroll.position);
      });
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: r.contentMaxWidth),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical) _maybeLoadMore(n.metrics);
            return false;
          },
          child: scrollable(ListView.builder(
            key: PageStorageKey('matches_list_${widget.tab.name}'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(r.horizontalPadding, r.isSmall ? 12 : 14, r.horizontalPadding, widget.bottomPadding),
            itemCount: items.length + footer,
            findChildIndexCallback: (key) {
              final k = key is ValueKey<String> ? key.value : null;
              return k == null ? null : _indexByKey[k];
            },
            itemBuilder: (context, i) {
              if (i >= items.length) return _footer();
              final it = items[i];
              return switch (it) {
                SeriesHeaderItem(:final seriesName) => Padding(
                    key: ValueKey(it.key),
                    padding: const EdgeInsets.fromLTRB(Spacing.xs, 18, Spacing.xs, Spacing.sm),
                    child: Text(seriesName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
                  ),
                NativeAdItem() => Padding(
                    key: ValueKey(it.key),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: const ListNativeAd(placement: 'matches_list'),
                  ),
                MatchItem(:final match) => Padding(
                    key: ValueKey(it.key),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: match.isLive
                        ? LiveMatchCard(match: match, onTap: () => widget.onMatchTap(match), fullWidth: true, compact: true)
                        : UpcomingMatchCard(
                            match: match,
                            onTap: () => widget.onMatchTap(match),
                            variant: _isCompleted ? UpcomingCardVariant.completed : UpcomingCardVariant.upcoming,
                            matchesListFrame: true,
                          ),
                  ),
              };
            },
          )),
        ),
      ),
    );
  }

  Widget _footer() {
    final Widget child;
    if (_c.completedLoadingMore) {
      child = const Row(key: ValueKey('matches_loading_more'), mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pitch)),
        SizedBox(width: Spacing.sm),
        Text('Loading more…', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]);
    } else if (_c.loadMoreError != null) {
      child = Column(key: const ValueKey('matches_load_more_error'), mainAxisSize: MainAxisSize.min, children: [
        Text(_c.loadMoreError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.error)),
        TextButton(
          key: const ValueKey('matches_load_more_retry'),
          onPressed: _c.loadMoreCompleted,
          child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.pitch)),
        ),
      ]);
    } else if (!_c.completedHasMore && _c[MatchesTab.completed].matches.isNotEmpty) {
      child = const Center(
        key: ValueKey('matches_no_more'),
        child: Text('No more matches', style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 0.3)),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('matches_footer'),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Ported from RN `MatchesShimmer`: series header bands + match card placeholders.
class MatchesShimmer extends StatelessWidget {
  const MatchesShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card() => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: const Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              ShimmerBox(width: 70, height: 20, radius: 999),
              ShimmerBox(width: 90, height: 11, radius: 4),
            ]),
            SizedBox(height: 14),
            Row(children: [
              Expanded(child: Column(children: [ShimmerBox(width: 32, height: 32, radius: 16), ShimmerBox(width: 70, height: 12, radius: 4, margin: EdgeInsets.only(top: 6))])),
              SizedBox(width: 12),
              ShimmerBox(width: 20, height: 12, radius: 4),
              SizedBox(width: 12),
              Expanded(child: Column(children: [ShimmerBox(width: 32, height: 32, radius: 16), ShimmerBox(width: 70, height: 12, radius: 4, margin: EdgeInsets.only(top: 6))])),
            ]),
            SizedBox(height: 14),
            Divider(height: 0.5, thickness: 0.5, color: AppColors.border),
            SizedBox(height: 12),
            FractionallySizedBox(widthFactor: 0.7, alignment: Alignment.centerLeft, child: ShimmerBox(height: 11, radius: 4)),
          ]),
        );

    return ShimmerGroup(
      key: const ValueKey('matches_shimmer'),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        children: [
          for (var s = 0; s < 2; s++) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
              child: Align(alignment: Alignment.centerLeft, child: ShimmerBox(width: 180, height: 11, radius: 4)),
            ),
            for (var i = 0; i < 3; i++) card(),
          ],
        ],
      ),
    );
  }
}
