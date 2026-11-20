import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/brand/brand.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../common/inline_states.dart';
import '../common/live_match_card.dart';
import '../common/match_parsing.dart';
import '../common/match_row.dart';
import '../common/series_resolver.dart';
import '../common/tap_guard.dart';
import '../common/visible_poller.dart';
import 'home_controller.dart';
import 'home_models.dart';
import 'home_widgets.dart';

/// Rows shown per section before "See all".
const kHomeLiveRows = 4, kHomeUpcomingRows = 5, kHomeResultRows = 5;

/// Width from which Home lays its sections out in two columns.
const kHomeTwoColumnWidth = 1000.0;

/// Home: glance and go (research §2). Top to bottom:
/// 1. Live now: the first live match as the raised [LiveMatchCard] (Seam
///    strip of the current over, hero tags for the card → Match Centre
///    moment), the other live matches as flat rows. None live: the next
///    start counting down and a way to the schedule.
/// 2. Starting soon: upcoming matches with per-minute countdowns.
/// 3. Latest results: winner emphasised.
/// 4. Upcoming series: a quiet chip strip.
///
/// Polls every 30 s while visible and in the foreground ([VisiblePoller]);
/// pull to refresh.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Poll interval (perf budget §13: 30 s on Home). Overridable in tests.
  static Duration pollInterval = const Duration(seconds: 30);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _c = HomeController()..start();
  late final VisiblePoller _poller = VisiblePoller(
    interval: HomeScreen.pollInterval,
    onTick: _c.poll,
  )..start();
  final _guard = TapGuard();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setScreenVisible(isScreenVisible(context));
  }

  @override
  void dispose() {
    _guard.dispose();
    _poller.dispose();
    _c.dispose();
    super.dispose();
  }

  // ── navigation ──
  void _openMatch(MatchSummary m) {
    if (m.id.isEmpty) return;
    _guard.run(() => AppNav.match<void>(context, m.id));
  }

  void _openSearch() => _guard.run(() => AppNav.search<void>(context));

  /// Series detail on the Home stack; Discover → Series when the id cannot
  /// be resolved.
  void _openSeries(UpcomingSeriesItem item) => _guard.run(() async {
    final id =
        item.sbSeriesKey ??
        await resolveSeriesId(
          MatchService.instance,
          candidates: item.idCandidates,
          name: item.name,
          altName: item.firstMatchSeriesName,
        );
    if (!mounted) return;
    if (id == null) {
      AppNav.discover(context, DiscoverSection.series);
    } else {
      await AppNav.seriesDetail<void>(context, id, seriesName: item.name);
    }
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.canvas,
      child: Column(
        children: [
          ScreenTitle(
            title: Brand.appName,
            showBack: false,
            onSearch: _openSearch,
          ),
          Expanded(
            // Only the loading flag rebuilds this level; each section
            // listens to its own data.
            child: ValueListenableBuilder<bool>(
              valueListenable: _c.loadingListenable,
              builder: (context, loading, _) {
                if (loading) return const HomeShimmer();
                return Column(
                  children: [
                    const ScreenBannerSlots(
                      screen: 'home',
                      onlyPosition: 'top',
                      fullBleed: true,
                    ),
                    Expanded(child: _content()),
                  ],
                );
              },
            ),
          ),
          const FixedBottomBanner(screen: 'home'),
        ],
      ),
    );
  }

  Widget _content() {
    final p = context.palette;
    final live = ListenableBuilder(
      listenable: Listenable.merge([_c, _c.upcoming]),
      builder: (context, _) => _liveSection(),
    );
    final soon = ListenableBuilder(
      listenable: _c.upcoming,
      builder: (context, _) => _upcomingSection(),
    );
    final results = ListenableBuilder(
      listenable: _c,
      builder: (context, _) => _resultsSection(),
    );
    final series = ListenableBuilder(
      listenable: _c.upcomingSeries,
      builder: (context, _) => _seriesSection(),
    );
    const ad = Padding(
      padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: ListNativeAd(placement: 'home_feed'),
    );

    return RefreshIndicator(
      key: const ValueKey('home_refresh'),
      color: p.brandText,
      onRefresh: () => _c.fetchLive(manual: true),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= kHomeTwoColumnWidth;
          final List<Widget> children;
          if (wide) {
            Widget col(List<Widget> w) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: w,
              ),
            );
            children = [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      col([live, soon]),
                      const SizedBox(width: Spacing.lg),
                      col([results, ad, series]),
                    ],
                  ),
                ),
              ),
            ];
          } else {
            Widget narrow(Widget w) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: w,
              ),
            );
            children = [
              for (final w in [live, soon, results, ad, series]) narrow(w),
            ];
          }
          return ListView(
            key: const ValueKey('home_scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Spacing.xxl),
            children: children,
          );
        },
      ),
    );
  }

  Widget _section({
    required String title,
    String? overline,
    String? actionLabel,
    VoidCallback? onAction,
    bool liveDot = false,
    required Widget child,
    Key? key,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: Spacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          overline: overline,
          showLiveDot: liveDot,
          actionLabel: actionLabel ?? 'See all',
          onActionPress: onAction,
        ),
        child,
      ],
    ),
  );

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
    child: child,
  );

  String? _updatedLine() {
    final t = _c.lastUpdated;
    if (t == null) return null;
    return 'Updated ${DateFormat('h:mm a', 'en_US').format(t)}';
  }

  Widget _liveSection() {
    final err = _c.error;
    final list = _c.liveMatches;
    final updated = _updatedLine();
    if (err != null && list.isEmpty) {
      return _section(
        title: 'Live now',
        child: _pad(
          InlineMessageCard(
            key: const ValueKey('home_live_error'),
            text: err,
            isError: true,
            actionLabel: 'Try again',
            actionKey: const ValueKey('home_live_retry'),
            onAction: () => _c.fetchLive(showLoading: true),
          ),
        ),
      );
    }
    if (list.isEmpty) {
      final next = startingSoon(_c.upcoming.data ?? const []).firstOrNull;
      return _section(
        title: 'Live now',
        overline: updated,
        child: NoLivePanel(
          key: const ValueKey('home_live_empty'),
          next: next,
          onOpenNext: () {
            if (next != null) _openMatch(next);
          },
          onSchedule: () => AppNav.tab(context, AppTab.matches),
        ),
      );
    }
    final first = list.first;
    final over = _c.featuredOver;
    final rest = list.skip(1).take(kHomeLiveRows).toList();
    final count = list.length == 1 ? '1 match' : '${list.length} matches';
    return _section(
      title: 'Live now',
      overline: updated == null ? count : '$count. $updated',
      liveDot: list.any((m) => m.isInPlay),
      actionLabel: 'All live',
      onAction: () => AppNav.tab(context, AppTab.live),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pad(
            LiveMatchCard(
              key: ValueKey('home_live_card_${first.id}'),
              match: first,
              fullWidth: true,
              heroTags: true,
              overBalls: over?.matchId == first.id ? over!.balls : null,
              overNumber: over?.matchId == first.id ? over!.overNumber : null,
              onTap: () => _openMatch(first),
            ),
          ),
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: MatchRowGroup(
                children: [
                  for (final m in rest)
                    MatchRow(
                      key: ValueKey('home_live_row_${m.id}'),
                      match: m,
                      onTap: () => _openMatch(m),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _upcomingSection() {
    final l = _c.upcoming;
    final err = _c.sectionError(l, 'Upcoming matches did not load');
    final list = startingSoon(l.data ?? const []);
    final now = DateTime.now();
    final soon =
        list.isNotEmpty &&
        (list.first.startTime?.difference(now).inHours ?? 99) < 24;
    Widget child;
    if (!l.hasData && err == null) {
      child = const Column(
        key: ValueKey('home_upcoming_loading'),
        children: [SkeletonMatchRow(), SkeletonMatchRow()],
      );
    } else if (err != null && list.isEmpty) {
      child = _pad(
        InlineMessageCard(
          key: const ValueKey('home_upcoming_error'),
          text: err,
          isError: true,
          actionLabel: 'Try again',
          actionKey: const ValueKey('home_upcoming_retry'),
          onAction: l.load,
        ),
      );
    } else if (list.isEmpty) {
      child = _pad(
        const InlineMessageCard(
          key: ValueKey('home_upcoming_empty'),
          text: 'No upcoming matches are scheduled yet.',
        ),
      );
    } else {
      child = MatchRowGroup(
        children: [
          for (final m in list.take(kHomeUpcomingRows))
            MatchRow(
              key: ValueKey('home_upcoming_card_${m.id}'),
              match: m,
              onTap: () => _openMatch(m),
            ),
        ],
      );
    }
    return _section(
      key: const ValueKey('home_upcoming_section'),
      title: soon || list.isEmpty ? 'Starting soon' : 'Coming up',
      actionLabel: 'Schedule',
      onAction: () => AppNav.tab(context, AppTab.matches),
      child: child,
    );
  }

  Widget _resultsSection() {
    final list = _c.results;
    final err = _c.resultsError;
    Widget child;
    if (err != null && list.isEmpty) {
      child = _pad(
        InlineMessageCard(
          key: const ValueKey('home_results_error'),
          text: err,
          isError: true,
          actionLabel: 'Try again',
          actionKey: const ValueKey('home_results_retry'),
          onAction: () => _c.fetchLive(manual: true),
        ),
      );
    } else if (list.isEmpty) {
      child = _pad(
        const InlineMessageCard(
          key: ValueKey('home_results_empty'),
          text: 'No results in the last few days.',
        ),
      );
    } else {
      child = MatchRowGroup(
        children: [
          for (final m in list.take(kHomeResultRows))
            MatchRow(
              key: ValueKey('home_result_${m.id}'),
              match: m,
              onTap: () => _openMatch(m),
            ),
        ],
      );
    }
    return _section(
      key: const ValueKey('home_results_section'),
      title: 'Latest results',
      actionLabel: 'All results',
      onAction: () => AppNav.tab(context, AppTab.matches),
      child: child,
    );
  }

  /// Quiet and optional: hidden while loading, on error and when empty.
  Widget _seriesSection() {
    final list = _c.upcomingSeries.data ?? const <UpcomingSeriesItem>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final shown = list.take(8).toList();
    return _section(
      key: const ValueKey('home_series_section'),
      title: 'Upcoming series',
      actionLabel: 'All series',
      onAction: () => AppNav.discover(context, DiscoverSection.series),
      child: SizedBox(
        height: 96 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.2),
        child: ListView.separated(
          key: const ValueKey('home_series_strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
          itemBuilder: (context, i) => Align(
            alignment: Alignment.topCenter,
            child: SeriesChip(
              key: ValueKey('home_series_${shown[i].id}'),
              item: shown[i],
              onTap: () => _openSeries(shown[i]),
            ),
          ),
        ),
      ),
    );
  }
}
