import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tabs.dart';
import '../ads/ads.dart';
import 'series_controllers.dart';
import 'series_detail_views.dart';
import 'series_shimmers.dart';

/// Ported from RN `SeriesDetailScreen.tsx`: gradient hero with the series
/// name, then swipeable Results / Points / Stats / Squads pages. Each page
/// loads lazily the first time it is shown and is cached afterwards.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.seriesId, this.seriesName});
  final String seriesId;
  final String? seriesName;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

const _views = SeriesView.values; // fixtures, points, stats, squads

String _viewKey(SeriesView v) => v.name;

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late final SeriesDetailController _c = SeriesDetailController(seriesId: widget.seriesId, seriesName: widget.seriesName);
  final _pageController = PageController();
  SeriesView _view = SeriesView.fixtures;
  int? _animatingTo;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _c.load(SeriesView.fixtures);
  }

  @override
  void didUpdateWidget(SeriesDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.seriesId != widget.seriesId) {
      _c.resetFor(widget.seriesId, widget.seriesName);
      _view = SeriesView.fixtures;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      _c.load(SeriesView.fixtures);
    }
  }

  @override
  void dispose() {
    AdsManager.instance.recordDetailExit();
    _pageController.dispose();
    _c.dispose();
    super.dispose();
  }

  void _select(SeriesView v) {
    if (v == _view) return;
    setState(() => _view = v);
    _c.load(v);
  }

  void _onTabTap(String key) {
    final i = _views.indexWhere((v) => _viewKey(v) == key);
    if (i < 0 || _views[i] == _view) return;
    _select(_views[i]);
    if (_pageController.hasClients) {
      _animatingTo = i;
      _pageController
          .animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic)
          .whenComplete(() => _animatingTo = null);
    }
  }

  void _onPageChanged(int i) {
    if (_animatingTo != null && i != _animatingTo) return;
    _select(_views[i]);
  }

  /// Pop within the stack; if this screen is the only route, open the series list.
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/series');
    }
  }

  Future<void> _guarded(Future<void> Function() push) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await push();
    } finally {
      _navigating = false;
    }
  }

  void _openMatch(String id) => _guarded(() => AppNav.match(context, id));

  void _openPlayer(String? key, Map<String, dynamic> json) {
    if (key == null || key.isEmpty) return;
    _guarded(() => AppNav.player(context, key, player: json));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom + Spacing.xxl;
    return Material(
      color: AppColors.bg,
      child: Column(children: [
        _Hero(name: widget.seriesName, onBack: _goBack),
        const ScreenBannerSlots(screen: 'series_detail', onlyPosition: 'top'),
        ListenableBuilder(
          listenable: _c,
          builder: (_, _) => SectionTabs(
            tabs: [
              // RN Ionicons: list, trophy, stats-chart, people
              const SectionTabItem('fixtures', 'Results', icon: Icons.list),
              const SectionTabItem('points', 'Points', icon: Icons.emoji_events),
              const SectionTabItem('stats', 'Stats', icon: Icons.bar_chart),
              SectionTabItem('squads', _c.squadCount != null ? 'Squads (${_c.squadCount})' : 'Squads', icon: Icons.people),
            ],
            activeKey: _viewKey(_view),
            onSelect: _onTabTap,
          ),
        ),
        Expanded(
          child: PageView.builder(
            key: const ValueKey('series_detail_pager'),
            controller: _pageController,
            itemCount: _views.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) => _DetailPage(
              key: ValueKey('series_detail_page_${_viewKey(_views[i])}'),
              view: _views[i],
              controller: _c,
              bottomPadding: bottomPad,
              onMatch: _openMatch,
              onPlayer: _openPlayer,
            ),
          ),
        ),
        const FixedBottomBanner(screen: 'series_detail'),
      ]),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.onBack});
  final String? name;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = name?.trim() ?? '';
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.pitchDark, AppColors.pitch, AppColors.pitchLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              button: true,
              label: 'Go back',
              child: InkResponse(
                key: const ValueKey('series_detail_back'),
                onTap: onBack,
                radius: 24,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x2EFFFFFF),
                    border: Border.all(color: const Color(0x47FFFFFF)),
                  ),
                  child: const Icon(Icons.chevron_left, size: 22, color: AppColors.white),
                ),
              ),
            ),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm + 2),
                child: Text(title,
                    key: const ValueKey('series_detail_title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.white, height: 24 / 18)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _DetailPage extends StatefulWidget {
  const _DetailPage({
    super.key,
    required this.view,
    required this.controller,
    required this.bottomPadding,
    required this.onMatch,
    required this.onPlayer,
  });
  final SeriesView view;
  final SeriesDetailController controller;
  final double bottomPadding;
  final ValueChanged<String> onMatch;
  final void Function(String? key, Map<String, dynamic> json) onPlayer;

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.controller;
    final v = widget.view;
    final padding = EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, widget.bottomPadding);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.state(v);
        if (s.showShimmer || (!s.fetched && s.error == null)) {
          return ListView(padding: padding, physics: const NeverScrollableScrollPhysics(), children: const [SeriesDetailShimmer()]);
        }
        if (s.error != null) {
          return SeriesDetailError(message: s.error!, onRetry: () => c.load(v, force: true), padding: padding);
        }
        Future<void> refresh() => c.load(v, force: true);
        return RefreshIndicator(
          color: AppColors.pitch,
          onRefresh: refresh,
          child: switch (v) {
            SeriesView.fixtures => FixturesList(data: s.data, padding: padding, onMatch: widget.onMatch),
            SeriesView.points => PointsTableList(data: s.data, padding: padding),
            SeriesView.stats => StatsList(data: s.data, padding: padding, onPlayer: widget.onPlayer),
            SeriesView.squads => SquadsList(data: s.data, padding: padding, onPlayer: widget.onPlayer),
          },
        );
      },
    );
  }
}
