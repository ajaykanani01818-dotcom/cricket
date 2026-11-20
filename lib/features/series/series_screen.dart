import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../matches/feature_states.dart';
import 'series_controllers.dart';
import 'series_models.dart';
import 'series_shimmers.dart';

/// Series list (Discover → Series): Ongoing / Upcoming / Completed pages,
/// grouped by year, flat rows. Each page loads the first time it is shown,
/// then pages in more series on scroll (stops at the last page).
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

const _tabItems = [SectionTabItem('ONGOING', 'Ongoing'), SectionTabItem('UPCOMING', 'Upcoming'), SectionTabItem('COMPLETED', 'Completed')];

/// Max content width on tablets and desktop.
const kSeriesMaxWidth = 720.0;

class _SeriesScreenState extends State<SeriesScreen> {
  final _pageController = PageController();
  late final List<SeriesTabController> _controllers = [for (final t in _tabItems) SeriesTabController(t.key)];
  int _index = 0;
  int? _animatingTo;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _controllers[0].load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _controllers[i].load();
  }

  void _onTabTap(String key) {
    final i = _tabItems.indexWhere((t) => t.key == key);
    if (i < 0 || i == _index) return;
    _select(i);
    if (_pageController.hasClients) {
      _animatingTo = i;
      _pageController
          .animateToPage(i, duration: Motion.of(context).d(Motion.tabSwitch), curve: Motion.standard)
          .whenComplete(() => _animatingTo = null);
    }
  }

  void _onPageChanged(int i) {
    // Skip intermediate pages while animating to a tapped tab (don't load them).
    if (_animatingTo != null && i != _animatingTo) return;
    _select(i);
  }

  Future<void> _openSeries(SeriesItem item) async {
    if (_navigating || item.navId.isEmpty) return;
    _navigating = true;
    try {
      await AppNav.seriesDetail(context, item.navId, seriesName: item.name);
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.canvas,
      child: Column(
        children: [
          const ScreenTitle(title: 'Series'),
          const ScreenBannerSlots(screen: 'series', onlyPosition: 'top'),
          MaxWidthBand(
            child: SectionTabs(tabs: _tabItems, activeKey: _tabItems[_index].key, onSelect: _onTabTap),
          ),
          Expanded(
            child: PageView.builder(
              key: const ValueKey('series_pager'),
              controller: _pageController,
              itemCount: _tabItems.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) => _SeriesTabPage(
                key: ValueKey('series_page_${_tabItems[i].key}'),
                tabKey: _tabItems[i].key,
                controller: _controllers[i],
                onSeriesPress: _openSeries,
                onShowTab: _onTabTap,
              ),
            ),
          ),
          const FixedBottomBanner(screen: 'series'),
        ],
      ),
    );
  }
}

sealed class _Row {
  const _Row();
}

class _YearRow extends _Row {
  const _YearRow(this.label);
  final String label;
}

class _ItemRow extends _Row {
  const _ItemRow(this.item);
  final SeriesItem item;
}

class _AdRow extends _Row {
  const _AdRow(this.n);
  final int n;
}

/// Year headers whenever the year changes, a native ad slot every
/// [kSeriesNativeAdInterval] series (collapses to nothing without ads).
List<_Row> _buildRows(List<SeriesItem> items) {
  final rows = <_Row>[];
  Object? year = const Object();
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it.year != year) {
      year = it.year;
      rows.add(_YearRow(it.year?.toString() ?? 'Dates to be announced'));
    }
    if (i > 0 && i % kSeriesNativeAdInterval == 0) rows.add(_AdRow(i));
    rows.add(_ItemRow(it));
  }
  return rows;
}

class _SeriesTabPage extends StatefulWidget {
  const _SeriesTabPage({super.key, required this.tabKey, required this.controller, required this.onSeriesPress, required this.onShowTab});
  final String tabKey;
  final SeriesTabController controller;
  final ValueChanged<SeriesItem> onSeriesPress;
  final ValueChanged<String> onShowTab;

  @override
  State<_SeriesTabPage> createState() => _SeriesTabPageState();
}

class _SeriesTabPageState extends State<_SeriesTabPage> with AutomaticKeepAliveClientMixin {
  SeriesTabController get c => widget.controller;
  int _checkedLength = -1;
  List<SeriesItem>? _rowsFor;
  List<_Row> _rows = const [];

  @override
  bool get wantKeepAlive => true;

  bool _onScroll(ScrollNotification n) {
    // After a failed page only the footer's Try again retries.
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600 && c.loadMoreError == null) c.loadMore();
    return false;
  }

  /// A first page that does not fill the viewport has no scroll to trigger
  /// load-more, so check once after layout per list length.
  void _scheduleFillCheck(BuildContext listContext) {
    if (_checkedLength == c.items.length) return;
    _checkedLength = c.items.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pos = Scrollable.maybeOf(listContext)?.position;
      if (pos != null && pos.hasContentDimensions && pos.extentAfter < 600) c.loadMore();
    });
  }

  Future<void> _refresh() async {
    await c.refresh();
    if (!mounted) return;
    if (c.error != null && c.items.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text("Series didn't refresh. ${c.error!}")));
    }
  }

  Widget _empty() {
    final (String, String, String, VoidCallback) copy = switch (widget.tabKey) {
      'ONGOING' => (
        'No series in progress right now',
        'See which series start next in Upcoming.',
        'See upcoming',
        () => widget.onShowTab('UPCOMING'),
      ),
      'UPCOMING' => (
        'No upcoming series listed',
        'New series show up here once they are announced. Pull down to check again.',
        'Refresh',
        _refresh,
      ),
      _ => ('No completed series yet', 'Finished series show up here. Pull down to check again.', 'Refresh', _refresh),
    };
    final (title, body, action, onAction) = copy;
    return StateMessage(
      icon: Icons.emoji_events_outlined,
      title: title,
      body: body,
      actionLabel: action,
      actionKey: ValueKey('series_empty_action_${widget.tabKey}'),
      onAction: onAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.palette;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.showShimmer) return const SeriesShimmer();
        if (c.error != null && c.items.isEmpty) {
          return ListView(
            children: [
              ErrorMessage(
                title: "Series didn't load",
                reason: c.error!,
                onRetry: () => c.load(force: true),
                retryKey: const ValueKey('series_retry'),
              ),
            ],
          );
        }
        if (c.items.isEmpty) {
          return RefreshIndicator(
            color: p.brandText,
            onRefresh: _refresh,
            child: ListView(
              key: ValueKey('series_empty_${widget.tabKey}'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_empty()],
            ),
          );
        }
        if (!identical(_rowsFor, c.items)) {
          _rowsFor = c.items;
          _rows = _buildRows(c.items);
        }
        final rows = _rows;
        final footer = c.loadingMore || c.loadMoreError != null;
        return LayoutBuilder(
          builder: (context, box) {
            final side = box.maxWidth > kSeriesMaxWidth ? (box.maxWidth - kSeriesMaxWidth) / 2 : 0.0;
            return RefreshIndicator(
              color: p.brandText,
              onRefresh: _refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView.builder(
                  key: ValueKey('series_list_${widget.tabKey}'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(side, 0, side, Spacing.lg),
                  itemCount: rows.length + (footer ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == 0) _scheduleFillCheck(context);
                    if (i >= rows.length) return _footer();
                    return switch (rows[i]) {
                      _YearRow(:final label) => _YearHeader(label: label),
                      _AdRow(:final n) => KeyedSubtree(
                        key: ValueKey('series_ad_${widget.tabKey}_$n'),
                        child: const ListNativeAd(placement: 'series_list'),
                      ),
                      _ItemRow(:final item) => KeyedSubtree(
                        key: ValueKey('series_row_${item.id}'),
                        child: SeriesCard(item: item, onTap: () => widget.onSeriesPress(item)),
                      ),
                    };
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _footer() {
    if (c.loadingMore) {
      return Padding(
        key: const ValueKey('series_load_more_spinner'),
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: context.palette.brandText)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md, horizontal: Spacing.lg),
      child: Column(
        children: [
          Text(
            "More series didn't load. ${c.loadMoreError ?? ''}",
            textAlign: TextAlign.center,
            style: AppText.meta.copyWith(color: context.palette.negative),
          ),
          TextButton(key: const ValueKey('series_load_more_retry'), onPressed: c.loadMore, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
      child: Text(
        label,
        style: AppFont.style(size: 14, weight: FontWeight.w700, color: context.palette.inkMuted, tabularFigures: true),
      ),
    ),
  );
}

/// One series: name, date range, format and the provider's popular flag.
class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.item, required this.onTap});
  final SeriesItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = item.name.isEmpty ? 'Unnamed series' : item.name;
    final meta = <Widget>[
      if (item.dateRange.isNotEmpty) Text(item.dateRange, style: AppText.meta.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      if (item.format.isNotEmpty) FormatChip(item.format),
      if (item.isPopular)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: p.brandText),
            const SizedBox(width: 2),
            Text('Popular', style: AppText.small.copyWith(color: p.brandText)),
          ],
        ),
    ];
    final label = [
      name,
      if (item.dateRange.isNotEmpty) item.dateRange,
      if (item.format.isNotEmpty) item.format,
      if (item.isPopular) 'popular',
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        child: InkWell(
          key: ValueKey('series_card_${item.id}'),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppFont.withWeight(AppText.name, FontWeight.w700)),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xs),
                        Wrap(spacing: Spacing.sm, runSpacing: Spacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Icon(Icons.chevron_right, color: p.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
