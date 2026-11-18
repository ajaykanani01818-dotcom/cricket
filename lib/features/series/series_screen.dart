import 'package:flutter/material.dart';

import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import 'series_controllers.dart';
import 'series_models.dart';
import 'series_shimmers.dart';

/// Ported from RN `SeriesScreen.tsx`: Current / Upcoming / Archive swipeable
/// tabs of series cards. Each tab loads lazily the first time it is shown,
/// then pages in more series on scroll (infinite scroll, stops at last page).
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

const _tabItems = [
  SectionTabItem('ONGOING', 'Current'),
  SectionTabItem('UPCOMING', 'Upcoming'),
  SectionTabItem('COMPLETED', 'Archive'),
];

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
          .animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic)
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
      color: AppColors.bg,
      child: Column(children: [
        const ScreenTitle(title: 'Series'),
        const ScreenBannerSlots(screen: 'series', onlyPosition: 'top'),
        SectionTabs(tabs: _tabItems, activeKey: _tabItems[_index].key, onSelect: _onTabTap),
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
            ),
          ),
        ),
        const FixedBottomBanner(screen: 'series'),
      ]),
    );
  }
}

class _SeriesTabPage extends StatefulWidget {
  const _SeriesTabPage({super.key, required this.tabKey, required this.controller, required this.onSeriesPress});
  final String tabKey;
  final SeriesTabController controller;
  final ValueChanged<SeriesItem> onSeriesPress;

  @override
  State<_SeriesTabPage> createState() => _SeriesTabPageState();
}

class _SeriesTabPageState extends State<_SeriesTabPage> with AutomaticKeepAliveClientMixin {
  SeriesTabController get c => widget.controller;
  int _checkedLength = -1;

  @override
  bool get wantKeepAlive => true;

  bool _onScroll(ScrollNotification n) {
    // After a failed page only the footer's Try Again retries (no retry storm while scrolling).
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600 && c.loadMoreError == null) c.loadMore();
    return false;
  }

  /// If the first page does not fill the viewport there is no scroll to trigger
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(c.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom + Spacing.lg;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.showShimmer) return SeriesShimmer(bottomPadding: bottomPad);
        if (c.error != null && c.items.isEmpty) {
          return _SeriesErrorCard(message: c.error!, onRetry: () => c.load(force: true));
        }
        if (c.items.isEmpty) {
          return RefreshIndicator(
            color: AppColors.pitch,
            onRefresh: _refresh,
            child: ListView(
              key: ValueKey('series_empty_${widget.tabKey}'),
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(Spacing.lg, 40 + 60, Spacing.lg, 0),
                  child: Text('No series in this section',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ),
              ],
            ),
          );
        }
        // Rows: series cards with a native ad every N cards (RN listData).
        final items = c.items;
        final adCount = (items.length - 1) ~/ kSeriesNativeAdInterval;
        final rowCount = items.length + adCount;
        final footer = c.loadingMore || c.loadMoreError != null;
        return RefreshIndicator(
          color: AppColors.pitch,
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ListView.builder(
              key: ValueKey('series_list_${widget.tabKey}'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(Spacing.lg, 14, Spacing.lg, bottomPad),
              itemCount: rowCount + (footer ? 1 : 0),
              itemBuilder: (context, row) {
                if (row == 0) _scheduleFillCheck(context);
                if (row >= rowCount) return _footer();
                // Row r maps to item i where every (interval+1)th row after the first group is an ad.
                final group = kSeriesNativeAdInterval + 1;
                if (row >= kSeriesNativeAdInterval && (row - kSeriesNativeAdInterval) % group == 0) {
                  return Padding(
                    key: ValueKey('series_ad_${widget.tabKey}_$row'),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: const ListNativeAd(placement: 'series_list'),
                  );
                }
                final adsBefore = row < kSeriesNativeAdInterval ? 0 : (row - kSeriesNativeAdInterval) ~/ group + 1;
                final item = items[row - adsBefore];
                return Padding(
                  key: ValueKey('series_row_${item.id}'),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SeriesCard(item: item, onTap: () => widget.onSeriesPress(item)),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _footer() {
    if (c.loadingMore) {
      return const Padding(
        key: ValueKey('series_load_more_spinner'),
        padding: EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Column(children: [
        Text(c.loadMoreError ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.error)),
        TextButton(
          key: const ValueKey('series_load_more_retry'),
          onPressed: c.loadMore,
          child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.pitch)),
        ),
      ]),
    );
  }
}

class _SeriesErrorCard extends StatelessWidget {
  const _SeriesErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 40, Spacing.lg, 0),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: Spacing.xxl),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Column(children: [
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.error)),
              const SizedBox(height: 14),
              Pressable(
                key: const ValueKey('series_retry'),
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(Radii.md)),
                  child: const Text('Try Again',
                      style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
                ),
              ),
            ]),
          ),
        ],
      );
}

/// Ported from RN `SeriesCard`.
class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.item, required this.onTap});
  final SeriesItem item;
  final VoidCallback onTap;

  static const _statusLabel = {
    SeriesStatusKey.ongoing: 'LIVE',
    SeriesStatusKey.upcoming: 'UPCOMING',
    SeriesStatusKey.completed: 'COMPLETED',
  };
  static const _statusColor = {
    SeriesStatusKey.ongoing: AppColors.live,
    SeriesStatusKey.upcoming: AppColors.textSecondary,
    SeriesStatusKey.completed: AppColors.win,
  };

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final isLive = item.isLive;
    return Semantics(
      button: true,
      label: item.name,
      child: Pressable(
        key: ValueKey('series_card_${item.id}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
          decoration: BoxDecoration(
            color: isLive ? AppColors.redTint : AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (item.format.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(Radii.full)),
                  child: Text(item.format,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.graphite, letterSpacing: 0.3)),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              if (status != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLive ? AppColors.pitch : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isLive) ...[
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
                      const SizedBox(width: Spacing.xs),
                    ],
                    Text(_statusLabel[status]!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isLive ? AppColors.white : _statusColor[status],
                        )),
                  ]),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: Text(
                  item.dateRange,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.1),
                ),
              ),
            ]),
            const SizedBox(height: Spacing.sm),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text, height: 22 / 16, letterSpacing: -0.2),
            ),
          ]),
        ),
      ),
    );
  }
}
