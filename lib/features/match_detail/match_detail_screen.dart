import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../ads/ads.dart';
import '../review/review.dart';
import 'logic/commentary_controller.dart';
import 'logic/live_poller.dart';
import 'logic/match_detail_logic.dart';
import 'tabs/commentary_tab.dart';
import 'tabs/live_tab.dart';
import 'tabs/playing_xi_tab.dart';
import 'tabs/scorecard_tab.dart';
import 'tabs/stats_tab.dart';
import 'widgets/match_detail_shimmer.dart';
import 'widgets/match_header.dart';

enum MatchTab {
  live('Live'),
  scorecard('Scorecard'),
  commentary('Commentary'),
  stats('Stats'),
  playingXI('Playing XI');

  const MatchTab(this.label);
  final String label;
}

/// Ported from RN `src/screens/MatchDetailScreen.tsx`.
///
/// Data: GET /match/:id (+ silent 15s poll while live), /match/:id/live
/// (while live), /match/:id/scorecard (Scorecard tab, finished matches,
/// 10s poll while live on the Scorecard tab), /match/:id/commentary
/// (Commentary tab, paged), /players/:key/info (Player of the Match).
///
/// Polling only runs while the match is live AND the screen is visible (app
/// in foreground, route not covered, tab branch active); polls never overlap
/// and responses that didn't change anything don't rebuild (fingerprints).
class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    this.matchService,
    this.playerService,
    this.livePollInterval = const Duration(seconds: 15),
    this.scorecardPollInterval = const Duration(seconds: 10),
    this.commentaryPollInterval = const Duration(seconds: 20),
  });

  /// sb_match_key
  final String matchId;
  final MatchService? matchService;
  final PlayerService? playerService;
  final Duration livePollInterval, scorecardPollInterval, commentaryPollInterval;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  MatchService get _matches => widget.matchService ?? MatchService.instance;
  PlayerService get _players => widget.playerService ?? PlayerService.instance;

  final _scroll = ScrollController();
  final _headerKey = GlobalKey();
  final _visibility = ScreenVisibility();
  late final Poller _livePoller;
  late final Poller _scorecardPoller;
  CommentaryController? _commentary;

  MatchTab _tab = MatchTab.live;
  final Set<MatchTab> _visited = {MatchTab.live};
  double _restoreMinExtent = 0;

  // match detail
  MatchDetailVM? _match;
  bool _loading = true;
  String? _error;
  Future<void>? _detailReq;
  int _gen = 0; // bumps when matchId changes: drops stale responses

  // live
  LiveVM? _live;
  bool _loadingLive = false;
  bool _liveRequested = false;
  Future<void>? _liveReq;
  List<BatterRow> _lastBattingPair = const [];

  // scorecard
  JsonMap? _scorecard;
  String _scorecardFp = '';
  List<BatterRow>? _scBatters;
  List<BowlerRow>? _scBowlers;
  bool _loadingScorecard = false;
  bool _scorecardRequested = false;
  Future<void>? _scorecardReq;

  // player of the match
  JsonMap? _momInfo;
  bool _momLoading = false;
  String _momToken = '';
  int _momGen = 0;

  bool _navBusy = false;
  bool _reviewLogged = false;

  // Rewarded unlocks (RN useRewardedAd). Gates only show when the placement is
  // enabled and the ads SDK is ready.
  bool _scorecardUnlocked = false;
  bool _playingXIUnlocked = false;
  late final RewardedAdController _rewardScoreboard = RewardedAdController(
    'match_detail_scoreboard',
    onReward: () {
      if (mounted) setState(() => _scorecardUnlocked = true);
    },
  );
  late final RewardedAdController _rewardPlayingXI = RewardedAdController(
    'match_detail_playing_xi',
    onReward: () {
      if (mounted) setState(() => _playingXIUnlocked = true);
    },
  );

  @override
  void initState() {
    super.initState();
    _livePoller = Poller(
      interval: widget.livePollInterval,
      visibility: _visibility,
      task: () => Future.wait([_fetchDetail(showLoading: false), _fetchLive(silent: true)]),
    );
    _scorecardPoller = Poller(
      interval: widget.scorecardPollInterval,
      visibility: _visibility,
      task: () => _fetchScorecard(silent: true),
    );
    if (widget.matchId.trim().isNotEmpty) _fetchDetail(showLoading: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibility.bindTickerMode(TickerMode.getValuesNotifier(context));
  }

  @override
  void didUpdateWidget(MatchDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.matchId != widget.matchId) {
      // New match: drop stale data so we never flash another fixture's scorecard/live overlay.
      _gen++;
      _livePoller.setEnabled(false);
      _scorecardPoller.setEnabled(false);
      _commentary?.dispose();
      _commentary = null;
      _detailReq = _liveReq = _scorecardReq = null;
      _match = null;
      _live = null;
      _liveRequested = false;
      _lastBattingPair = const [];
      _scorecard = null;
      _scorecardFp = '';
      _scBatters = _scBowlers = null;
      _scorecardRequested = false;
      _momInfo = null;
      _momLoading = false;
      _momToken = '';
      _reviewLogged = false;
      _restoreMinExtent = 0;
      _tab = MatchTab.live;
      _visited
        ..clear()
        ..add(MatchTab.live);
      if (widget.matchId.trim().isNotEmpty) _fetchDetail(showLoading: true);
    }
  }

  @override
  void dispose() {
    _gen++;
    _livePoller.dispose();
    _scorecardPoller.dispose();
    _commentary?.dispose();
    _rewardScoreboard.dispose();
    _rewardPlayingXI.dispose();
    _visibility.dispose();
    _scroll.dispose();
    AdsManager.instance.recordDetailExit();
    super.dispose();
  }

  // ───────────────────────────── data ─────────────────────────────

  Future<void> _fetchDetail({required bool showLoading}) {
    if (_detailReq != null) return _detailReq!;
    final req = _doFetchDetail(showLoading);
    _detailReq = req;
    return req.whenComplete(() {
      if (identical(_detailReq, req)) _detailReq = null;
    });
  }

  Future<void> _doFetchDetail(bool showLoading) async {
    final gen = _gen;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _matches.getMatchById(widget.matchId);
      if (!mounted || gen != _gen) return;
      if (res.data is! Map || res.dataMap.isEmpty) throw const ApiException(-1, 'Failed to load match details');
      final next = MatchDetailVM.fromJson(res.dataMap);
      final prev = _match;
      if (!showLoading && prev != null && prev.fingerprint == next.fingerprint) return;
      setState(() {
        _match = next;
        _error = null;
      });
      _onMatchChanged(prev, next);
    } catch (e) {
      if (!mounted || gen != _gen) return;
      // A failed background poll keeps the data on screen (RN replaced the
      // whole screen with the error view).
      if (showLoading || _match == null) setState(() => _error = friendlyError(e));
    } finally {
      if (showLoading && mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  void _onMatchChanged(MatchDetailVM? prev, MatchDetailVM next) {
    // RN: opening a match counts as a meaningful action for the review prompt (once per match).
    if (!_reviewLogged) {
      _reviewLogged = true;
      final review = ReviewScope.read(context);
      if (review != null) {
        unawaited(review.recordMeaningfulAction());
        unawaited(review.requestReviewIfAppropriate());
      }
    }
    // Live data + 15s poll while live (stops as soon as the match isn't).
    if (next.isLive && !_liveRequested) {
      _liveRequested = true;
      _fetchLive(silent: false);
    }
    _livePoller.setEnabled(next.isLive);
    _syncTabPollers();

    // Scorecard is prefetched for finished matches (Live tab shows its batting/bowling).
    if (next.isMatchWon && !(prev?.isMatchWon ?? false)) {
      _fetchScorecard(silent: _tab != MatchTab.scorecard || _scorecard != null);
    }

    // Player of the Match — completed fixtures only.
    final token = next.momEligible ? '${next.id}|${next.status}|${next.momKey}' : '';
    if (token != _momToken) {
      _momToken = token;
      _loadMom(next);
    }
  }

  Future<void> _fetchLive({required bool silent}) {
    if (_match?.isLive != true) return Future.value();
    if (_liveReq != null) return _liveReq!;
    final req = _doFetchLive(silent);
    _liveReq = req;
    return req.whenComplete(() {
      if (identical(_liveReq, req)) _liveReq = null;
    });
  }

  Future<void> _doFetchLive(bool silent) async {
    final gen = _gen;
    if (!silent) setState(() => _loadingLive = true);
    try {
      final res = await _matches.getMatchLive(widget.matchId);
      if (!mounted || gen != _gen) return;
      final next = LiveVM.fromJson(res.dataMap);
      if (_live != null && _live!.fingerprint == next.fingerprint) return;
      setState(() {
        _live = next;
        // While a wicket updates, live API may omit both batters for one tick — keep last pair.
        if (next.battingPair.isNotEmpty) _lastBattingPair = next.battingPair;
      });
    } catch (_) {
      // silent: keep last live data
    } finally {
      if (!silent && mounted && gen == _gen) setState(() => _loadingLive = false);
    }
  }

  Future<void> _fetchScorecard({required bool silent}) {
    if (_scorecardReq != null) return _scorecardReq!;
    _scorecardRequested = true;
    final req = _doFetchScorecard(silent);
    _scorecardReq = req;
    return req.whenComplete(() {
      if (identical(_scorecardReq, req)) _scorecardReq = null;
    });
  }

  Future<void> _doFetchScorecard(bool silent) async {
    final gen = _gen;
    if (!silent) setState(() => _loadingScorecard = true);
    try {
      final res = await _matches.getMatchScorecard(widget.matchId);
      if (!mounted || gen != _gen) return;
      final data = res.dataMap;
      final fp = scorecardPollFingerprint(data);
      // Keep the previous object when nothing changed so the (large) scorecard subtree isn't rebuilt.
      if (_scorecard != null && fp == _scorecardFp) return;
      final last = lastScorecardInning(data);
      setState(() {
        _scorecard = data;
        _scorecardFp = fp;
        _scBatters = last?['batting'] is List ? scorecardBatters(last) : null;
        _scBowlers = last?['bowling'] is List ? scorecardBowlers(last) : null;
      });
    } catch (_) {
      // RN logs only; the scorecard tab shows its own empty state.
    } finally {
      if (!silent && mounted && gen == _gen) setState(() => _loadingScorecard = false);
    }
  }

  Future<void> _loadMom(MatchDetailVM m) async {
    final gen = ++_momGen;
    if (!m.momEligible) {
      setState(() {
        _momInfo = null;
        _momLoading = false;
      });
      return;
    }
    setState(() => _momLoading = true);
    try {
      final res = await _players.getPlayerInfo(m.momKey);
      if (!mounted || gen != _momGen) return;
      final info = res.dataMap;
      setState(() => _momInfo = info.isEmpty ? null : info);
    } catch (_) {
      if (!mounted || gen != _momGen) return;
      setState(() => _momInfo = null);
    } finally {
      if (mounted && gen == _momGen) setState(() => _momLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    final m = _match;
    await Future.wait([
      _fetchDetail(showLoading: false),
      if (m?.isLive ?? false) _fetchLive(silent: true),
      if (_tab == MatchTab.scorecard || (m?.isMatchWon ?? false)) _fetchScorecard(silent: true),
    ]);
  }

  CommentaryController _ensureCommentary() => _commentary ??= CommentaryController(
        matchId: widget.matchId,
        service: _matches,
        visibility: _visibility,
        pollInterval: widget.commentaryPollInterval,
      );

  void _syncTabPollers() {
    final live = _match?.isLive ?? false;
    final onScorecard = _tab == MatchTab.scorecard;
    // Refetch scorecard every 10s when live and on the scorecard tab; an
    // immediate refresh on (re)entering the tab when we already have data.
    final wasOn = _scorecardPoller.enabled;
    final on = live && onScorecard;
    _scorecardPoller.setEnabled(on, runNow: on && !wasOn && _scorecard != null);
    _commentary?.setPolling(live && _tab == MatchTab.commentary);
  }

  // ───────────────────────────── tabs ─────────────────────────────

  void _selectTab(MatchTab tab) {
    if (tab == _tab) return;
    // Sticky tab bar + a shorter tab body would clamp the scroll offset (RN:
    // jump to top). Keep the header/tab bar where they are: if the user had
    // scrolled past the header, the new tab starts right under the pinned tab
    // bar; the min-extent filler keeps that offset reachable.
    double? target;
    if (_scroll.hasClients) {
      final p = _scroll.position;
      final headerH = (_headerKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
      target = math.min(p.pixels, headerH);
      _restoreMinExtent = target + p.viewportDimension;
    }
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    if (target != null) {
      final t = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final p = _scroll.position;
        final y = t.clamp(p.minScrollExtent, p.maxScrollExtent);
        if ((p.pixels - y).abs() > 0.5) _scroll.jumpTo(y);
      });
    }
    if (tab == MatchTab.scorecard && !_scorecardRequested) _fetchScorecard(silent: false);
    if (tab == MatchTab.commentary) _ensureCommentary().ensureLoaded();
    _syncTabPollers();
  }

  // ───────────────────────────── navigation ─────────────────────────────

  Future<void> _guardedNav(Future<void> Function() go) async {
    if (_navBusy) return;
    _navBusy = true;
    try {
      await go();
    } finally {
      _navBusy = false;
    }
  }

  void _goBack() {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
    } else {
      Navigator.maybePop(context);
    }
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.matchId.trim().isEmpty) {
      return _ErrorView(message: 'Match ID is required', onBack: _goBack);
    }
    final m = _match;
    if (_loading && m == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            _BackHeader(onBack: _goBack),
            const Expanded(child: MatchDetailShimmer()),
          ]),
        ),
      );
    }
    if (_error != null || m == null) {
      return _ErrorView(
        message: _error ?? 'Failed to load match details',
        onRetry: () => _fetchDetail(showLoading: true),
        onBack: _goBack,
      );
    }

    final live = _live;
    final battingTeam = battingTeamKey(live: live, detailInningsOrder: m.inningsOrder);
    final displayPair =
        (live?.battingPair.isNotEmpty ?? false) ? live!.battingPair : (m.isLive && !m.isMatchWon ? _lastBattingPair : const <BatterRow>[]);
    final bottomPad = MediaQuery.paddingOf(context).bottom + kFixedBottomReserve + 16;

    Widget keepAlive(MatchTab t, Widget child) {
      if (!_visited.contains(t)) return const SliverToBoxAdapter(child: SizedBox.shrink());
      final off = _tab != t;
      return SliverOffstage(
        offstage: off,
        sliver: SliverToBoxAdapter(child: TickerMode(enabled: !off, child: child)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          key: const ValueKey('match_detail_refresh'),
          color: AppColors.pitch,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            key: const ValueKey('match_detail_scroll'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Scrolls away: back bar, top banner, match header, native ad.
              SliverToBoxAdapter(
                child: Column(key: _headerKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _BackHeader(onBack: _goBack),
                  const ScreenBannerSlots(screen: 'match_detail', onlyPosition: 'top'),
                  MatchHeader(
                    match: m,
                    team1Score: headerScoreText(live: live?.team1, apiScore: m.t1.score),
                    team2Score: headerScoreText(live: live?.team2, apiScore: m.t2.score),
                    battingTeam: battingTeam,
                    momLoading: _momLoading,
                    momInfo: _momInfo,
                    onSeriesTap: m.seriesKey == null
                        ? null
                        : () => _guardedNav(() => AppNav.seriesDetail<void>(context, m.seriesKey!, seriesName: m.seriesName)),
                    onMomTap: m.momKey.isEmpty
                        ? null
                        : () => _guardedNav(() => AppNav.player<void>(context, m.momKey, player: _momInfo)),
                  ),
                  const ListNativeAd(placement: 'match_detail'),
                ]),
              ),
              // Sticky tab bar
              SliverPersistentHeader(pinned: true, delegate: _TabBarDelegate(active: _tab, onSelect: _selectTab)),
              SliverPadding(
                padding: const EdgeInsets.all(Spacing.lg),
                sliver: SliverMainAxisGroup(slivers: [
                  if (_tab == MatchTab.live)
                    SliverToBoxAdapter(
                      child: MatchLiveTab(
                        match: m,
                        live: live,
                        displayBattingPair: displayPair,
                        scorecardBatters: _scBatters,
                        scorecardBowlers: _scBowlers,
                        loadingLive: _loadingLive,
                        loadingScorecard: _loadingScorecard,
                      ),
                    ),
                  keepAlive(
                    MatchTab.scorecard,
                    _RewardGated(
                      controller: _rewardScoreboard,
                      unlocked: _scorecardUnlocked,
                      gate: const _GateCopy(
                        key: 'scorecard',
                        icon: Icons.lock_outline,
                        title: 'Unlock Full Scoreboard',
                        subtext: 'Watch one short ad to access full innings details, stats and fall of wickets.',
                        chips: [(Icons.timer_outlined, '~10 sec'), (Icons.verified_user_outlined, 'Secure unlock')],
                      ),
                      child: MatchScorecardTab(scorecard: _scorecard, loading: _loadingScorecard),
                    ),
                  ),
                  if (_tab == MatchTab.commentary && _commentary != null) MatchCommentaryTabSliver(controller: _commentary!),
                  keepAlive(MatchTab.stats, MatchStatsTab(matchId: widget.matchId, isLive: m.isLive)),
                  keepAlive(
                    MatchTab.playingXI,
                    _RewardGated(
                      controller: _rewardPlayingXI,
                      unlocked: _playingXIUnlocked,
                      gate: const _GateCopy(
                        key: 'playing_xi',
                        icon: Icons.people_outline,
                        title: 'Unlock Playing XI',
                        subtext: 'Watch one short ad to see confirmed line-ups and squad details.',
                        chips: [(Icons.timer_outlined, '~10 sec'), (Icons.flash_on_outlined, 'Instant access')],
                      ),
                      child: MatchPlayingXITab(matchId: widget.matchId, isLive: m.isLive),
                    ),
                  ),
                ]),
              ),
              // Min-height filler so switching to a shorter tab keeps the scroll offset.
              SliverLayoutBuilder(builder: (context, constraints) {
                final h = math.max(0.0, _restoreMinExtent - constraints.precedingScrollExtent);
                return SliverToBoxAdapter(child: SizedBox(height: h));
              }),
              const SliverToBoxAdapter(child: ScreenBannerSlots(screen: 'match_detail', onlyPosition: 'bottom')),
              SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── pieces ─────────────────────────────

class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md, horizontal: Spacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
          boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'Back',
            child: InkResponse(
              key: const ValueKey('match_detail_back'),
              onTap: onBack,
              radius: 24,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(Icons.chevron_left, size: 22, color: AppColors.text),
              ),
            ),
          ),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry, required this.onBack});
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onBack;

  ButtonStyle get _style => FilledButton.styleFrom(
        backgroundColor: AppColors.pitch,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(message,
                    key: const ValueKey('match_detail_error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: AppColors.error)),
                const SizedBox(height: Spacing.md),
                if (onRetry != null) ...[
                  FilledButton(key: const ValueKey('match_detail_retry'), onPressed: onRetry, style: _style, child: const Text('Retry')),
                  const SizedBox(height: Spacing.sm),
                ],
                FilledButton(key: const ValueKey('match_detail_go_back'), onPressed: onBack, style: _style, child: const Text('Go Back')),
              ]),
            ),
          ),
        ),
      );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({required this.active, required this.onSelect});
  final MatchTab active;
  final ValueChanged<MatchTab> onSelect;

  static const double _h = 46;
  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.active != active || old.onSelect != onSelect;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _h,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final t in MatchTab.values)
                InkWell(
                  key: ValueKey('match_detail_tab_${t.name}'),
                  onTap: () => onSelect(t),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: t == active ? AppColors.pitch : Colors.transparent, width: 3)),
                    ),
                    child: Text(
                      t.label.toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.2,
                        fontWeight: t == active ? FontWeight.w800 : FontWeight.w600,
                        color: t == active ? AppColors.pitch : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GateCopy {
  const _GateCopy({required this.key, required this.icon, required this.title, required this.subtext, required this.chips});
  final String key;
  final IconData icon;
  final String title, subtext;
  final List<(IconData, String)> chips;
}

/// RN reward gate card ("Unlock Full Scoreboard" / "Unlock Playing XI"):
/// shown instead of [child] while the rewarded placement is enabled and not
/// yet unlocked. The gated child is not built (so it doesn't fetch) until unlocked.
class _RewardGated extends StatelessWidget {
  const _RewardGated({required this.controller, required this.unlocked, required this.gate, required this.child});
  final RewardedAdController controller;
  final bool unlocked;
  final _GateCopy gate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (unlocked) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, AdsManager.instance.adsReady]),
      builder: (context, _) {
        if (!controller.enabled) return child;
        final loading = controller.isLoading;
        return Padding(
          key: ValueKey('match_detail_reward_gate_${gate.key}'),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Spacing.xxl),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.symmetric(vertical: Spacing.xl, horizontal: 18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: AppColors.borderNeutral),
                boxShadow: const [BoxShadow(color: Color(0x1A0860C4), blurRadius: 16, offset: Offset(0, 10))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 58,
                  height: 58,
                  margin: const EdgeInsets.only(bottom: Spacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0x140B5CD4),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x350B5CD4)),
                  ),
                  child: Icon(gate.icon, size: 26, color: AppColors.pitch),
                ),
                Text(gate.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.pitchDark, letterSpacing: 0.2)),
                const SizedBox(height: Spacing.sm),
                Text(gate.subtext,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 19 / 13)),
                const SizedBox(height: 14),
                Wrap(alignment: WrapAlignment.center, spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
                  for (final c in gate.chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(Radii.full),
                        border: Border.all(color: AppColors.borderNeutral),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(c.$1, size: 12, color: AppColors.pitch),
                        const SizedBox(width: Spacing.xs),
                        Text(c.$2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ]),
                    ),
                ]),
                const SizedBox(height: Spacing.lg),
                Opacity(
                  opacity: loading ? 0.6 : 1,
                  child: FilledButton.icon(
                    key: ValueKey('match_detail_reward_gate_${gate.key}_button'),
                    onPressed: loading ? null : controller.show,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.pitch,
                      disabledBackgroundColor: AppColors.pitch,
                      disabledForegroundColor: AppColors.white,
                      minimumSize: const Size(220, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: Spacing.md),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: Text(loading ? 'Loading...' : controller.label,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.15)),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
