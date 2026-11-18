import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../common/inline_states.dart';
import '../common/live_match_card.dart';
import '../common/series_resolver.dart';
import '../common/snap_physics.dart';
import '../common/tap_guard.dart';
import '../common/upcoming_match_card.dart';
import '../common/visible_poller.dart';
import 'home_controller.dart';
import 'home_models.dart';
import 'home_widgets.dart';

/// Tab indexes in the shell (Live, Matches, Series, Ranking, Players, Settings).
const _matchesTab = 1, _seriesTab = 2, _rankingTab = 3;

/// RN TAB_BAR_HEIGHT + FIXED_BOTTOM_RESERVE + 12 → here: shell inset + banner reserve.
const _fixedBottomReserve = 60.0;

const _liveItemWidth = liveCardWidth + liveCardMargin;

/// Ported from RN `HomeScreen` ("Live" tab): live (recent) matches carousel,
/// upcoming matches, top players, upcoming series.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Live polling interval (RN: 30s). Overridable in tests.
  static Duration pollInterval = const Duration(seconds: 30);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _c = HomeController()..start();
  late final VisiblePoller _poller = VisiblePoller(interval: HomeScreen.pollInterval, onTick: _c.poll)..start();
  final _carousel = ScrollController();
  final _carouselIndex = ValueNotifier<int>(0);
  final _guard = TapGuard();
  PlayerCategory _category = PlayerCategory.batters;

  @override
  void initState() {
    super.initState();
    _carousel.addListener(_onCarouselScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setScreenVisible(isScreenVisible(context));
  }

  @override
  void dispose() {
    _guard.dispose();
    _poller.dispose();
    _carousel.dispose();
    _carouselIndex.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onCarouselScroll() {
    final count = _c.liveMatches.length;
    if (count == 0 || !_carousel.hasClients) return;
    final i = (_carousel.offset / _liveItemWidth).round().clamp(0, count - 1);
    if (_carouselIndex.value != i) _carouselIndex.value = i;
  }

  // ── navigation ──
  void _openMatch(MatchSummary m) {
    if (m.id.isEmpty) return;
    _guard.run(() {
      AppNav.match(context, m.id);
    });
  }

  void _goTab(int index) => StatefulNavigationShell.maybeOf(context)?.goBranch(index, initialLocation: true);

  void _openPlayer(TopPlayer p) {
    if (p.playerKey.isEmpty) return;
    _guard.run(() {
      AppNav.player(context, p.playerKey);
    });
  }

  /// Push SeriesDetail onto the Home stack (Back returns here) — RN
  /// `openSeriesDetailFromHome`.
  void _openSeries(UpcomingSeriesItem item) => _guard.run(() async {
        // sb_series_key is what the Series tab itself navigates with; the
        // RN catalog lookup + probe is only needed when it's missing.
        final id = item.sbSeriesKey ??
            await resolveSeriesId(
              MatchService.instance,
              candidates: item.idCandidates,
              name: item.name,
              altName: item.firstMatchSeriesName,
            );
        if (!mounted) return;
        if (id == null) {
          _goTab(_seriesTab);
        } else {
          AppNav.seriesDetail(context, id, seriesName: item.name);
        }
      });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom + _fixedBottomReserve + 12;
    return Material(
      color: AppColors.bg,
      child: Stack(children: [
        Column(children: [
          const ScreenTitle(title: 'CrickBex'),
          Expanded(
            // Only the loading flag rebuilds this level; each section below
            // listens to its own data so a refresh rebuilds just that section.
            child: ValueListenableBuilder<bool>(
              valueListenable: _c.loadingListenable,
              builder: (context, loading, _) {
                if (loading) return HomeShimmer(bottomPadding: bottomPad);
                return Column(children: [
                  const ScreenBannerSlots(screen: 'home', onlyPosition: 'top', fullBleed: true),
                  Expanded(child: _content(bottomPad)),
                ]);
              },
            ),
          ),
        ]),
        Positioned(left: 0, right: 0, bottom: MediaQuery.paddingOf(context).bottom, child: const FixedBottomBanner(screen: 'home')),
      ]),
    );
  }

  Widget _section(List<Widget> children) =>
      Padding(padding: const EdgeInsets.only(bottom: 28), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));

  Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: Spacing.lg), child: child);

  Widget _content(double bottomPad) {
    return RefreshIndicator(
      key: const ValueKey('home_refresh'),
      color: AppColors.pitch,
      onRefresh: () => _c.fetchLive(manual: true),
      child: ListView(
        key: const ValueKey('home_scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: Spacing.lg, bottom: bottomPad),
        children: [
          // ════════════ 1. LIVE MATCHES ════════════
          _section([
            SectionHeader(overline: 'Now playing', title: 'Live Matches', onActionPress: () => _goTab(_matchesTab), showLiveDot: true),
            ListenableBuilder(listenable: _c, builder: (_, _) => _liveSection()),
          ]),
          // ════════════ 2. UPCOMING MATCHES ════════════
          _section([
            SectionHeader(
                overline: 'Schedule', title: 'Upcoming Matches', onActionPress: () => _goTab(_matchesTab), actionLabel: 'Full schedule'),
            ListenableBuilder(listenable: _c.upcoming, builder: (_, _) => _upcomingSection()),
          ]),
          // ════════════ 3. TOP PLAYERS ════════════
          _section([
            SectionHeader(overline: 'Rankings', title: 'Top Players', onActionPress: () => _goTab(_rankingTab)),
            ListenableBuilder(listenable: Listenable.merge([_c, _c.rankings]), builder: (_, _) => _topPlayersSection()),
          ]),
          // Inline native ad — no vertical margin of its own (blank band when no ad).
          _pad(const ListNativeAd(placement: 'home_feed')),
          // ════════════ 4. UPCOMING SERIES ════════════
          _section([
            SectionHeader(overline: 'Tournaments', title: 'Upcoming Series', onActionPress: () => _goTab(_seriesTab)),
            ListenableBuilder(listenable: _c.upcomingSeries, builder: (_, _) => _seriesSection()),
          ]),
        ],
      ),
    );
  }

  Widget _liveSection() {
    if (_c.error != null) {
      return _pad(InlineMessageCard(
        key: const ValueKey('home_live_error'),
        text: _c.error!,
        actionLabel: 'Try Again',
        actionKey: const ValueKey('home_live_retry'),
        onAction: () => _c.fetchLive(showLoading: true),
      ));
    }
    final list = _c.liveMatches;
    if (list.isEmpty) return _pad(const InlineMessageCard(key: ValueKey('home_live_empty'), text: 'No live matches right now'));
    return Column(children: [
      SizedBox(
        height: liveCardHeight + 6 + 18,
        child: ListView.builder(
          key: const ValueKey('home_live_carousel'),
          controller: _carousel,
          scrollDirection: Axis.horizontal,
          physics: const SnapScrollPhysics(itemExtent: _liveItemWidth),
          padding: const EdgeInsets.fromLTRB(Spacing.lg - liveCardMargin / 2, 6, Spacing.lg - liveCardMargin / 2, 18),
          itemExtent: _liveItemWidth,
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            return Align(
              alignment: Alignment.topLeft,
              child: LiveMatchCard(key: ValueKey('home_live_card_${m.id}'), match: m, onTap: () => _openMatch(m)),
            );
          },
        ),
      ),
      if (list.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: ValueListenableBuilder<int>(
            valueListenable: _carouselIndex,
            builder: (context, active, _) => Row(
              key: const ValueKey('home_live_dots'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < list.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == active ? AppColors.pitch : AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _upcomingSection() {
    final l = _c.upcoming;
    final err = _c.sectionError(l, 'Failed to fetch upcoming matches');
    if (l.loading || (!l.hasData && err == null)) return const InlineLoader();
    if (err != null) {
      return _pad(InlineMessageCard(
          key: const ValueKey('home_upcoming_error'),
          text: err,
          actionLabel: 'Try Again',
          actionKey: const ValueKey('home_upcoming_retry'),
          onAction: l.load));
    }
    final list = l.data ?? const <MatchSummary>[];
    if (list.isEmpty) return _pad(const InlineMessageCard(key: ValueKey('home_upcoming_empty'), text: 'No upcoming matches scheduled'));
    return _pad(Column(children: [
      for (final m in list.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: UpcomingMatchCard(key: ValueKey('home_upcoming_card_${m.id}'), match: m, onTap: () => _openMatch(m)),
        ),
    ]));
  }

  Widget _topPlayersSection() {
    final l = _c.rankings;
    const categories = [
      (PlayerCategory.batters, 'Batters'),
      (PlayerCategory.bowlers, 'Bowlers'),
      (PlayerCategory.allRounders, 'All-Rounders'),
    ];
    final formatLabel = homeFormatOptions.firstWhere((o) => o.$1 == _c.matchType, orElse: () => homeFormatOptions.first).$2;

    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, 14),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final (key, label) in categories)
          CategoryPill(
            key: ValueKey('home_category_${key.name}'),
            label: label,
            active: _category == key,
            onTap: () => setState(() => _category = key),
          ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          key: const ValueKey('home_format_dropdown'),
          tooltip: 'Format',
          initialValue: _c.matchType,
          onSelected: _c.setMatchType,
          position: PopupMenuPosition.under,
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: const BorderSide(color: AppColors.border)),
          itemBuilder: (context) => [
            for (final (k, label) in homeFormatOptions)
              PopupMenuItem<String>(
                key: ValueKey('home_format_$k'),
                value: k,
                child: Row(children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: k == _c.matchType ? FontWeight.w700 : FontWeight.w500,
                            color: k == _c.matchType ? AppColors.pitch : AppColors.text)),
                  ),
                  if (k == _c.matchType) const Icon(Icons.check, size: 16, color: AppColors.pitch),
                ]),
              ),
          ],
          child: Container(
            constraints: const BoxConstraints(minWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(Radii.full),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.textSecondary),
            ]),
          ),
        ),
      ]),
    );

    Widget body;
    final err = _c.sectionError(l, 'Failed to fetch player rankings');
    final players = l.data?.of(_category) ?? const <TopPlayer>[];
    if (l.loading || (!l.hasData && err == null)) {
      body = const InlineLoader();
    } else if (err != null) {
      body = _pad(InlineMessageCard(
          key: const ValueKey('home_rankings_error'),
          text: err,
          actionLabel: 'Try Again',
          actionKey: const ValueKey('home_rankings_retry'),
          onAction: l.load));
    } else if (players.isEmpty) {
      body = _pad(const InlineMessageCard(key: ValueKey('home_rankings_empty'), text: 'No rankings available'));
    } else {
      // Vertical padding is shadow headroom (cards cast a shadow below themselves).
      body = SingleChildScrollView(
        key: const ValueKey('home_top_players'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, Spacing.md),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final p in players)
              Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: TopPlayerCard(
                  key: ValueKey('home_player_${p.playerKey.isEmpty ? p.name : p.playerKey}'),
                  player: p,
                  onTap: p.playerKey.isEmpty ? null : () => _openPlayer(p),
                ),
              ),
          ]),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [filters, body]);
  }

  Widget _seriesSection() {
    final l = _c.upcomingSeries;
    final err = _c.sectionError(l, 'Failed to fetch upcoming series');
    if (l.loading || (!l.hasData && err == null)) return const InlineLoader();
    if (err != null) {
      return _pad(InlineMessageCard(
          key: const ValueKey('home_series_error'),
          text: err,
          actionLabel: 'Try Again',
          actionKey: const ValueKey('home_series_retry'),
          onAction: l.load));
    }
    final list = l.data ?? const <UpcomingSeriesItem>[];
    if (list.isEmpty) return _pad(const InlineMessageCard(key: ValueKey('home_series_empty'), text: 'No upcoming series'));
    return _pad(Column(children: [
      for (final s in list.take(4))
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: SeriesRowCard(key: ValueKey('home_series_${s.id}'), item: s, onTap: () => _openSeries(s)),
        ),
    ]));
  }
}
