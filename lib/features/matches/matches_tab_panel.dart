import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/skeletons.dart';
import '../ads/ads.dart';
import '../common/match_time.dart';
import 'feature_states.dart';
import 'match_filters.dart';
import 'match_row.dart';
import 'matches_controller.dart';

/// RN adsConfig default `matches_list.interval`. ListNativeAd collapses to
/// zero height when ads are off, so the slot never leaves a gap.
const matchesNativeAdInterval = 3;

/// Max content width of the list on tablets and desktop.
const kMatchesMaxWidth = 720.0;

/// One row inside a series section: a match or an inline ad slot.
sealed class MatchListItem {
  const MatchListItem(this.key);
  final String key;
}

class MatchItem extends MatchListItem {
  const MatchItem(super.key, this.match, this.index);
  final MatchSummary match;
  final int index;
}

class NativeAdItem extends MatchListItem {
  const NativeAdItem(super.key);
}

/// A series section with a sticky header.
class MatchSection {
  MatchSection(this.key, this.title, this.items);
  final String key;
  final String title;
  final List<MatchListItem> items;
  int get matchCount => items.whereType<MatchItem>().length;
}

/// Groups [list] by series (see [groupBySeries]) and interleaves a native ad
/// slot every [nativeInterval] matches (counted across the whole list).
List<MatchSection> buildMatchSections(
  MatchesTab tab,
  List<MatchSummary> list, {
  bool showNativeSlots = true,
  int nativeInterval = matchesNativeAdInterval,
}) {
  final out = <MatchSection>[];
  var idx = 0;
  for (final g in groupBySeries(list)) {
    final items = <MatchListItem>[];
    for (final m in g.matches) {
      if (showNativeSlots && nativeInterval > 0 && idx > 0 && idx % nativeInterval == 0) {
        items.add(NativeAdItem('native-${tab.name}-$idx'));
      }
      items.add(MatchItem('match-${tab.name}-${m.id.isEmpty ? 'i$idx' : m.id}-$idx', m, idx));
      idx++;
    }
    out.add(MatchSection('header-${tab.name}-${g.key}', g.title, items));
  }
  return out;
}

/// One page of the Matches pager (Live, Upcoming or Results).
class MatchesTabPanel extends StatefulWidget {
  const MatchesTabPanel({super.key, required this.tab, required this.controller, required this.onMatchTap, this.onShowTab});
  final MatchesTab tab;
  final MatchesController controller;
  final ValueChanged<MatchSummary> onMatchTap;

  /// Empty Live → "See upcoming".
  final ValueChanged<MatchesTab>? onShowTab;

  @override
  State<MatchesTabPanel> createState() => _MatchesTabPanelState();
}

class _MatchesTabPanelState extends State<MatchesTabPanel> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  List<MatchSummary>? _builtFor;
  MatchFilters? _builtFilters;
  List<MatchSummary> _visible = const [];
  List<MatchSection> _sections = const [];

  @override
  bool get wantKeepAlive => true;

  MatchesController get _c => widget.controller;
  bool get _isCompleted => widget.tab == MatchesTab.completed;
  bool get _applyDay => widget.tab != MatchesTab.live;

  /// Filters that hide loaded rows (auto paging is off while they apply, so
  /// a filter change never sends a request).
  bool get _filtering => _c.filters.hasContentFilter || (_applyDay && _c.filters.day != null);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// RN onEndReachedThreshold 0.4 (fraction of the viewport).
  void _maybeLoadMore(ScrollMetrics m) {
    // After a failed page only the footer retries (no retry loop), and while
    // filters apply paging is explicit ("Load more results").
    if (!_isCompleted || _c.loadMoreError != null || _filtering) return;
    if (m.extentAfter < m.viewportDimension * 0.4) _c.loadMoreCompleted();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(listenable: _c, builder: (context, _) => _body(context));
  }

  VoidCallback get _retry => switch (widget.tab) {
    MatchesTab.upcoming => _c.fetchUpcoming,
    MatchesTab.live => _c.fetchLive,
    MatchesTab.completed => _c.fetchCompleted,
  };

  Widget _refreshable(Widget child) => RefreshIndicator(
    key: ValueKey('matches_refresh_${widget.tab.name}'),
    color: context.palette.brandText,
    onRefresh: _c.refresh,
    child: child,
  );

  Widget _messageList(Widget message, {bool withFooter = false}) => _refreshable(
    ListView(
      key: PageStorageKey('matches_message_${widget.tab.name}'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [message, if (withFooter) _footer()],
    ),
  );

  Widget _body(BuildContext context) {
    final d = _c[widget.tab];
    final tab = widget.tab.name;

    if (d.loading && d.matches.isEmpty && d.error == null) return const MatchesShimmer();

    if (d.error != null && d.matches.isEmpty) {
      return _messageList(
        KeyedSubtree(
          key: ValueKey('matches_error_$tab'),
          child: ErrorMessage(
            title: switch (widget.tab) {
              MatchesTab.live => "Live matches didn't load",
              MatchesTab.upcoming => "Upcoming matches didn't load",
              MatchesTab.completed => "Results didn't load",
            },
            reason: d.error!,
            onRetry: _retry,
            retryKey: ValueKey('matches_retry_$tab'),
          ),
        ),
      );
    }

    if (d.matches.isEmpty) return _messageList(_emptyMessage());

    if (!identical(_builtFor, d.matches) || _builtFilters != _c.filters) {
      _builtFor = d.matches;
      _builtFilters = _c.filters;
      _visible = _c.filters.apply(d.matches, applyDay: _applyDay);
      _sections = buildMatchSections(widget.tab, _visible);
    }

    if (_visible.isEmpty) return _messageList(_filteredEmpty(), withFooter: _isCompleted);

    if (_isCompleted && !_filtering) {
      // A first page that does not fill the viewport has no scroll to fire
      // paging; check once after layout (the controller ignores duplicates).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _maybeLoadMore(_scroll.position);
      });
    }

    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth > kMatchesMaxWidth ? (box.maxWidth - kMatchesMaxWidth) / 2 : 0.0;
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical) _maybeLoadMore(n.metrics);
            return false;
          },
          child: _refreshable(
            CustomScrollView(
              key: PageStorageKey('matches_list_$tab'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, Spacing.lg),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      for (final s in _sections) _section(context, s),
                      if (_isCompleted) SliverToBoxAdapter(child: _footer()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(BuildContext context, MatchSection s) {
    final scaler = MediaQuery.textScalerOf(context);
    return SliverMainAxisGroup(
      key: ValueKey(s.key),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: SeriesHeaderDelegate(title: s.title, count: s.matchCount, scaler: scaler),
        ),
        SliverList.builder(
          itemCount: s.items.length,
          itemBuilder: (context, i) {
            final it = s.items[i];
            return switch (it) {
              NativeAdItem() => KeyedSubtree(
                key: ValueKey(it.key),
                child: const ListNativeAd(placement: 'matches_list'),
              ),
              MatchItem(:final match) => MatchRow(
                key: ValueKey(it.key),
                data: MatchRowData.fromSummary(match),
                onTap: match.id.isEmpty ? null : () => widget.onMatchTap(match),
              ),
            };
          },
        ),
      ],
    );
  }

  Widget _emptyMessage() {
    final tab = widget.tab.name;
    return KeyedSubtree(
      key: ValueKey('matches_empty_$tab'),
      child: switch (widget.tab) {
        MatchesTab.live => StateMessage(
          icon: Icons.sensors_off_outlined,
          title: 'No live matches right now',
          body: 'See what starts next in Upcoming.',
          actionLabel: 'See upcoming',
          actionKey: const ValueKey('matches_empty_action_live'),
          onAction: widget.onShowTab == null ? null : () => widget.onShowTab!(MatchesTab.upcoming),
        ),
        MatchesTab.upcoming => StateMessage(
          icon: Icons.event_outlined,
          title: 'No upcoming matches listed',
          body: 'New fixtures show up here once they are scheduled. Pull down to check again.',
          actionLabel: 'Refresh',
          actionKey: const ValueKey('matches_empty_action_upcoming'),
          onAction: _c.refresh,
        ),
        MatchesTab.completed => StateMessage(
          icon: Icons.emoji_events_outlined,
          title: 'No results yet',
          body: 'Finished matches show up here. Pull down to check again.',
          actionLabel: 'Refresh',
          actionKey: const ValueKey('matches_empty_action_completed'),
          onAction: _c.refresh,
        ),
      },
    );
  }

  Widget _filteredEmpty() {
    final f = _c.filters;
    final what = [if (f.women) "women's", if (f.format != FormatFilter.all) f.format.label].join(' ');
    final noun = switch (widget.tab) {
      MatchesTab.live => 'live matches',
      MatchesTab.upcoming => 'upcoming matches',
      MatchesTab.completed => 'results',
    };
    final when = _applyDay && f.day != null ? ' ${_dayPhrase(f.day!)}' : '';
    final more = _isCompleted && _c.completedHasMore;
    return KeyedSubtree(
      key: ValueKey('matches_filtered_empty_${widget.tab.name}'),
      child: StateMessage(
        icon: Icons.filter_alt_off_outlined,
        title: 'No ${what.isEmpty ? '' : '$what '}$noun$when',
        body: more
            ? 'Filters apply to the results loaded so far. Load more results below or clear the filters.'
            : 'Try another date or format, or clear the filters.',
        actionLabel: 'Clear filters',
        actionKey: const ValueKey('matches_clear_filters'),
        onAction: () => _c.setFilters(const MatchFilters()),
      ),
    );
  }

  String _dayPhrase(DateTime day) {
    final l = dayLabel(day, MinuteClock.now());
    return switch (l) {
      'Today' => 'today',
      'Yesterday' => 'yesterday',
      'Tomorrow' => 'tomorrow',
      _ => 'on $l',
    };
  }

  Widget _footer() {
    final p = context.palette;
    final Widget child;
    if (_c.completedLoadingMore) {
      child = Row(
        key: const ValueKey('matches_loading_more'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.brandText)),
          const SizedBox(width: Spacing.sm),
          Flexible(child: Text('Loading more results', style: AppText.meta)),
        ],
      );
    } else if (_c.loadMoreError != null) {
      child = Column(
        key: const ValueKey('matches_load_more_error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "More results didn't load. ${_c.loadMoreError!}",
            textAlign: TextAlign.center,
            style: AppText.meta.copyWith(color: p.negative),
          ),
          TextButton(key: const ValueKey('matches_load_more_retry'), onPressed: _c.loadMoreCompleted, child: const Text('Try again')),
        ],
      );
    } else if (_c.completedHasMore && _filtering && _c[MatchesTab.completed].matches.isNotEmpty) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Filters apply to the ${_c[MatchesTab.completed].matches.length} results loaded so far.',
            textAlign: TextAlign.center,
            style: AppText.meta,
          ),
          TextButton(
            key: const ValueKey('matches_load_more_button'),
            onPressed: _c.loadMoreCompleted,
            child: const Text('Load more results'),
          ),
        ],
      );
    } else if (!_c.completedHasMore && _c[MatchesTab.completed].matches.isNotEmpty) {
      child = Text("That's every result we have", key: const ValueKey('matches_no_more'), style: AppText.meta);
    } else {
      child = const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('matches_footer'),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: Spacing.lg),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Sticky series header: series name and match count on the canvas band.
class SeriesHeaderDelegate extends SliverPersistentHeaderDelegate {
  SeriesHeaderDelegate({required this.title, required this.count, required this.scaler});
  final String title;
  final int count;
  final TextScaler scaler;

  double get _extent => scaler.scale(14) * 1.3 + 22;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final p = context.palette;
    return Semantics(
      header: true,
      label: '$title, $count ${count == 1 ? 'match' : 'matches'}',
      excludeSemantics: true,
      child: Container(
        height: _extent,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        decoration: BoxDecoration(
          color: p.canvas,
          border: Border(bottom: BorderSide(color: p.hairline)),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.style(size: 14, weight: FontWeight.w700, color: p.ink, height: 1.3),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              '$count',
              style: AppFont.style(size: 13, weight: FontWeight.w600, color: p.inkMuted, tabularFigures: true, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(SeriesHeaderDelegate old) => old.title != title || old.count != count || old.scaler != scaler;
}

/// First-load skeleton: header bands and flat rows (mirrors the list).
class MatchesShimmer extends StatelessWidget {
  const MatchesShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget band() => Container(height: 36, color: p.canvas);
    return ListView(
      key: const ValueKey('matches_shimmer'),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var s = 0; s < 2; s++) ...[band(), for (var i = 0; i < 3; i++) ColoredBox(color: p.surface, child: const SkeletonMatchRow())],
      ],
    );
  }
}
