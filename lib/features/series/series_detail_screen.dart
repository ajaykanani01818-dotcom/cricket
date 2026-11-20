import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/tabs.dart';
import '../ads/ads.dart';
import '../matches/feature_states.dart';
import 'series_controllers.dart';
import 'series_detail_views.dart';
import 'series_models.dart';
import 'series_shimmers.dart';

/// Series hub: header (name, formats, match count, dates) and swipeable
/// Fixtures / Points table / Squads / Stats tabs. Each tab loads the first
/// time it is shown and is cached afterwards.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.seriesId, this.seriesName});
  final String seriesId;
  final String? seriesName;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

const _views = SeriesView.values; // fixtures, points, squads, stats

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

  void _show(SeriesView v) {
    final i = _views.indexOf(v);
    if (i < 0 || v == _view) return;
    _select(v);
    if (_pageController.hasClients) {
      _animatingTo = i;
      _pageController
          .animateToPage(i, duration: Motion.of(context).d(Motion.tabSwitch), curve: Motion.standard)
          .whenComplete(() => _animatingTo = null);
    }
  }

  void _onTabTap(String key) {
    final i = _views.indexWhere((v) => _viewKey(v) == key);
    if (i >= 0) _show(_views[i]);
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
      AppNav.discover(context, DiscoverSection.series);
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
    final narrow = MediaQuery.sizeOf(context).width < 420 || MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return Material(
      color: context.palette.canvas,
      child: Column(
        children: [
          ListenableBuilder(
            listenable: _c,
            builder: (_, _) {
              final f = _c.state(SeriesView.fixtures).data;
              return _Header(name: widget.seriesName, fixtures: f is SeriesFixturesData ? f : null, onBack: _goBack);
            },
          ),
          const ScreenBannerSlots(screen: 'series_detail', onlyPosition: 'top'),
          ListenableBuilder(
            listenable: _c,
            builder: (_, _) => MaxWidthBand(
              maxWidth: 760,
              child: SectionTabs(
                scrollable: narrow,
                tabs: [
                  const SectionTabItem('fixtures', 'Fixtures'),
                  const SectionTabItem('points', 'Points table'),
                  SectionTabItem('squads', _c.squadCount != null && _c.squadCount! > 0 ? 'Squads (${_c.squadCount})' : 'Squads'),
                  const SectionTabItem('stats', 'Stats'),
                ],
                activeKey: _viewKey(_view),
                onSelect: _onTabTap,
              ),
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
                onMatch: _openMatch,
                onPlayer: _openPlayer,
                onShowView: _show,
              ),
            ),
          ),
          const FixedBottomBanner(screen: 'series_detail'),
        ],
      ),
    );
  }
}

/// Full-bleed surface header (no gradient): back, series name, and facts
/// derived from the fixtures once they load (formats, match count, dates).
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.fixtures, required this.onBack});
  final String? name;
  final SeriesFixturesData? fixtures;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = fixtures;
    // Deep links carry no name: fall back to the fixtures' series name.
    final fromRoute = name?.trim() ?? '';
    final title = fromRoute.isNotEmpty
        ? fromRoute
        : (f?.matches.map((m) => m.series.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '') ?? '');
    final count = f?.matches.length ?? 0;
    final span = f?.dateSpan ?? '';
    final meta = <Widget>[
      for (final fmt in f?.formats ?? const <String>[]) FormatChip(fmt),
      if (count > 0) Text('$count ${count == 1 ? 'match' : 'matches'}', style: AppText.meta),
      if (span.isNotEmpty) Text(span, style: AppText.meta),
    ];
    return Material(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.hairline)),
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, Spacing.lg, Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                key: const ValueKey('series_detail_back'),
                tooltip: 'Back',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, color: p.ink),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: title.isNotEmpty
                            ? Text(
                                title,
                                key: const ValueKey('series_detail_title'),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.screenTitle,
                              )
                            : Text('Series', style: AppText.screenTitle),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: Spacing.sm),
                        Wrap(spacing: Spacing.md, runSpacing: Spacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    required this.onMatch,
    required this.onPlayer,
    required this.onShowView,
  });
  final SeriesView view;
  final SeriesDetailController controller;
  final ValueChanged<String> onMatch;
  final PlayerTap onPlayer;
  final ValueChanged<SeriesView> onShowView;

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static String _errorTitle(SeriesView v) => switch (v) {
    SeriesView.fixtures => "Fixtures didn't load",
    SeriesView.points => "Points table didn't load",
    SeriesView.squads => "Squads didn't load",
    SeriesView.stats => "Stats didn't load",
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.controller;
    final v = widget.view;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.state(v);
        if (s.showShimmer || (!s.fetched && s.error == null)) {
          return ListView(physics: const NeverScrollableScrollPhysics(), children: const [SeriesDetailShimmer()]);
        }
        if (s.error != null) {
          return ListView(
            children: [
              ErrorMessage(
                title: _errorTitle(v),
                reason: s.error!,
                onRetry: () => c.load(v, force: true),
                retryKey: const ValueKey('series_detail_retry'),
              ),
            ],
          );
        }
        Future<void> refresh() => c.load(v, force: true);
        void showFixtures() => widget.onShowView(SeriesView.fixtures);
        return RefreshIndicator(
          color: context.palette.brandText,
          onRefresh: refresh,
          child: switch (v) {
            SeriesView.fixtures => FixturesList(data: s.data, onMatch: widget.onMatch, onRefresh: refresh),
            SeriesView.points => PointsTableList(data: s.data, onShowFixtures: showFixtures),
            SeriesView.squads => SquadsList(data: s.data, onPlayer: widget.onPlayer),
            SeriesView.stats => StatsList(data: s.data, onPlayer: widget.onPlayer, onShowFixtures: showFixtures),
          },
        );
      },
    );
  }
}
