import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/motion/motion.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/seam_strip.dart';
import '../ads/ads.dart';
import '../review/review.dart';
import 'logic/commentary_controller.dart';
import 'logic/live_poller.dart';
import 'logic/match_detail_logic.dart';
import 'logic/match_state.dart';
import 'tabs/commentary_tab.dart';
import 'tabs/info_tab.dart';
import 'tabs/playing_xi_tab.dart';
import 'tabs/scorecard_tab.dart';
import 'tabs/stats_tab.dart';
import 'tabs/summary_tab.dart';
import 'tabs/tab_scorecard_parse.dart';
import 'widgets/match_detail_shimmer.dart';
import 'widgets/match_header.dart';
import 'widgets/over_strip.dart';

/// Match Centre tabs, in a fixed order that never changes (research §1).
enum MatchTab {
  summary('Summary'),
  commentary('Commentary'),
  scorecard('Scorecard'),
  stats('Stats'),
  info('Info');

  const MatchTab(this.label);
  final String label;
}

/// Max width of the Match Centre column on tablets and desktop.
const double kMatchCentreMaxWidth = 840;

/// The Match Centre (research §3, PRD §8).
///
/// Data: GET /match/:id (+ live poll), /match/:id/live (in play),
/// /match/:id/scorecard (header innings + target, Scorecard tab),
/// /match/:id/commentary (paged), stats + line-ups lazily in their tabs,
/// /players/:key/info (player of the match).
///
/// Polling: detail + live every 10 s while the match is in play (live or a
/// break), only while the screen is visible (foreground, route not covered,
/// tab branch active); polls never overlap and unchanged responses don't
/// rebuild (fingerprints). Motion answers only genuinely new data: the
/// digit roll and the wicket band fire for exactly one new delivery; a
/// catch-up (several balls in one poll) shows the final state.
class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    this.matchService,
    this.playerService,
    this.livePollInterval = const Duration(seconds: 10),
    this.scorecardPollInterval = const Duration(seconds: 10),
    this.commentaryPollInterval = const Duration(seconds: 10),
    this.backgroundScorecardInterval = const Duration(seconds: 60),
    this.upcomingPollInterval = const Duration(seconds: 60),
  });

  /// sb_match_key
  final String matchId;
  final MatchService? matchService;
  final PlayerService? playerService;
  final Duration livePollInterval, scorecardPollInterval, commentaryPollInterval;

  /// Scorecard refresh for the header while in play and off the Scorecard tab.
  final Duration backgroundScorecardInterval;

  /// Detail refresh before the start (status flips to live).
  final Duration upcomingPollInterval;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  MatchService get _matches => widget.matchService ?? MatchService.instance;
  PlayerService get _players => widget.playerService ?? PlayerService.instance;

  final _scroll = ScrollController();
  final _visibility = ScreenVisibility();
  final _headerH = ValueNotifier<double>(0);
  late final Poller _livePoller;
  late final Poller _scorecardPoller;
  late final Poller _scorecardBgPoller;
  late final Poller _upcomingPoller;
  CommentaryController? _commentary;

  MatchTab _tab = MatchTab.summary;
  final Set<MatchTab> _visited = {MatchTab.summary};
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
  ScorecardView? _scView;
  String _scorecardFp = '';
  bool _loadingScorecard = false;
  bool _scorecardRequested = false;
  Future<void>? _scorecardReq;

  // player of the match
  JsonMap? _momInfo;
  bool _momLoading = false;
  String _momToken = '';
  int _momGen = 0;

  // feedback motion (only for genuinely new data)
  bool _animateScore = false;
  String? _bandText;
  int _bandId = 0;

  bool _navBusy = false;
  bool _reviewLogged = false;

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

  // derived (memoised on input identity)
  Object? _derivedFor;
  List<InningsScore> _innings = const [];
  MatchSituation? _situation;
  List<OverView> _overs = const [];

  @override
  void initState() {
    super.initState();
    _livePoller = Poller(
      interval: widget.livePollInterval,
      visibility: _visibility,
      task: () => Future.wait([_fetchDetail(showLoading: false), _fetchLive(silent: true)]),
    );
    _scorecardPoller = Poller(interval: widget.scorecardPollInterval, visibility: _visibility, task: () => _fetchScorecard(silent: true));
    _scorecardBgPoller =
        Poller(interval: widget.backgroundScorecardInterval, visibility: _visibility, task: () => _fetchScorecard(silent: true));
    _upcomingPoller = Poller(interval: widget.upcomingPollInterval, visibility: _visibility, task: () => _fetchDetail(showLoading: false));
    _scroll.addListener(_onScroll);
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
      _gen++;
      for (final p in [_livePoller, _scorecardPoller, _scorecardBgPoller, _upcomingPoller]) {
        p.setEnabled(false);
      }
      _commentary?.dispose();
      _commentary = null;
      _detailReq = _liveReq = _scorecardReq = null;
      _match = null;
      _live = null;
      _liveRequested = false;
      _lastBattingPair = const [];
      _scorecard = null;
      _scView = null;
      _scorecardFp = '';
      _scorecardRequested = false;
      _momInfo = null;
      _momLoading = false;
      _momToken = '';
      _reviewLogged = false;
      _restoreMinExtent = 0;
      _derivedFor = null;
      _bandText = null;
      _animateScore = false;
      _headerH.value = 0;
      _tab = MatchTab.summary;
      _visited
        ..clear()
        ..add(MatchTab.summary);
      if (widget.matchId.trim().isNotEmpty) _fetchDetail(showLoading: true);
    }
  }

  @override
  void dispose() {
    _gen++;
    _livePoller.dispose();
    _scorecardPoller.dispose();
    _scorecardBgPoller.dispose();
    _upcomingPoller.dispose();
    _commentary?.dispose();
    _rewardScoreboard.dispose();
    _rewardPlayingXI.dispose();
    _visibility.dispose();
    _scroll.dispose();
    _headerH.dispose();
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
      if (res.data is! Map || res.dataMap.isEmpty) throw const ApiException(-1, 'Match details are not available');
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
      // A failed background poll keeps the data on screen.
      if (showLoading || _match == null) setState(() => _error = friendlyError(e));
    } finally {
      if (showLoading && mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  void _onMatchChanged(MatchDetailVM? prev, MatchDetailVM next) {
    if (!_reviewLogged) {
      _reviewLogged = true;
      final review = ReviewScope.read(context);
      if (review != null) {
        unawaited(review.recordMeaningfulAction());
        // A finished match is the positive moment (review rules in README).
        unawaited(review.requestReviewIfAppropriate(
          positiveMoment: next.matchStatus.phase == MatchPhase.completed,
        ));
      }
    }
    final phase = next.matchStatus.phase;
    final inPlay = next.matchStatus.inPlay;
    if (inPlay && !_liveRequested) {
      _liveRequested = true;
      _fetchLive(silent: false);
    }
    _livePoller.setEnabled(inPlay);
    _scorecardBgPoller.setEnabled(inPlay);
    _upcomingPoller.setEnabled(phase == MatchPhase.upcoming);
    _syncTabPollers();

    // Scorecard feeds the header (Test innings, provider target) and the
    // completed summary; not requested before the start.
    final wantsScorecard = phase != MatchPhase.upcoming && phase != MatchPhase.abandoned;
    final phaseChanged = prev != null && prev.matchStatus.phase != phase;
    if (wantsScorecard && (!_scorecardRequested || (phaseChanged && phase == MatchPhase.completed))) {
      _fetchScorecard(silent: _tab != MatchTab.scorecard || _scorecard != null);
    }

    final token = next.momEligible ? '${next.id}|${next.status}|${next.momKey}' : '';
    if (token != _momToken) {
      _momToken = token;
      _loadMom(next);
    }
  }

  Future<void> _fetchLive({required bool silent}) {
    if (_match?.matchStatus.inPlay != true) return Future.value();
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
      final change = _classifyNewBalls(next);
      setState(() {
        _live = next;
        if (next.battingPair.isNotEmpty) _lastBattingPair = next.battingPair;
        _animateScore = change.$1 == SeamChange.oneNew;
        if (change.$1 == SeamChange.oneNew && change.$2 != null && Ball.parse(change.$2).kind == BallKind.wicket) {
          _bandText = _wicketText(next);
          _bandId++;
        }
      });
      // The roll flag applies to this frame only.
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateScore = false);
    } catch (_) {
      // silent: keep last live data
    } finally {
      if (!silent && mounted && gen == _gen) setState(() => _loadingLive = false);
    }
  }

  /// How the live update relates to what is on screen. The first live
  /// payload is never "new" (no motion on first render or from cache).
  (SeamChange, String?) _classifyNewBalls(LiveVM next) {
    final prevLive = _live;
    final m = _match;
    if (prevLive == null || m == null) return (SeamChange.none, null);
    final before = buildOverViews(match: m, live: prevLive, maxPrevious: 0);
    final after = buildOverViews(match: m, live: next, maxPrevious: 0);
    if (before.isEmpty || after.isEmpty) return (SeamChange.none, null);
    final a = before.first, b = after.first;
    if (a.key == b.key) {
      final d = diffBalls([for (final l in a.labels) Ball.parse(l)], [for (final l in b.labels) Ball.parse(l)]);
      return (d.change, d.change == SeamChange.oneNew ? b.labels.last : null);
    }
    // First ball of the next over after a complete over.
    if (b.labels.length == 1 && a.overNumber != null && b.overNumber == a.overNumber! + 1 && !a.inProgress) {
      return (SeamChange.oneNew, b.labels.single);
    }
    return (SeamChange.catchUp, null);
  }

  static String _wicketText(LiveVM live) {
    final lw = J.map(live.score?['lastWicket']);
    final name = J.text(lw['name']);
    if (name == null) return 'Wicket';
    final run = J.text(lw['run']);
    final ball = J.text(lw['ball']);
    final info = J.text(lw['info']);
    final b = StringBuffer('Wicket: $name');
    if (run != null) b.write(ball != null ? ' $run ($ball)' : ' $run');
    if (info != null) b.write(', $info');
    return b.toString();
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
      if (_scorecard != null && fp == _scorecardFp) return;
      setState(() {
        _scorecard = data;
        _scorecardFp = fp;
        _scView = parseScorecard(data);
      });
    } catch (_) {
      // The Scorecard tab shows its own empty state.
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
      if (m?.matchStatus.inPlay ?? false) _fetchLive(silent: true),
      if (_tab == MatchTab.scorecard || (m?.isMatchWon ?? false) || _scorecard != null) _fetchScorecard(silent: true),
    ]);
  }

  CommentaryController _ensureCommentary() => _commentary ??= CommentaryController(
        matchId: widget.matchId,
        service: _matches,
        visibility: _visibility,
        pollInterval: widget.commentaryPollInterval,
      );

  void _syncTabPollers() {
    final inPlay = _match?.matchStatus.inPlay ?? false;
    final onScorecard = _tab == MatchTab.scorecard;
    final wasOn = _scorecardPoller.enabled;
    final on = inPlay && onScorecard;
    _scorecardPoller.setEnabled(on, runNow: on && !wasOn && _scorecard != null);
    _commentary?.setPolling(inPlay && _tab == MatchTab.commentary);
  }

  // ───────────────────────────── scroll ─────────────────────────────

  double get _collapseRange => math.max(0, _headerH.value - CollapsedScoreBar.height);

  void _onScroll() {
    final c = _commentary;
    if (c == null || _tab != MatchTab.commentary || !_scroll.hasClients) return;
    final pos = _scroll.position;
    // Reading further down the feed → hold new balls behind the pill.
    c.setHold(pos.pixels > _collapseRange + 160);
    // Infinite scroll at 80 % of the loaded feed.
    if (c.hasMore && !c.loadingMore && pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent * 0.8) {
      c.loadMore();
    }
  }

  void _showPendingBalls() {
    _commentary?.showPending();
    if (_scroll.hasClients) {
      final target = math.min(_collapseRange, _scroll.position.maxScrollExtent);
      if (Motion.reducedOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: Motion.tabSwitch, curve: Motion.standard);
      }
    }
  }

  // ───────────────────────────── tabs ─────────────────────────────

  void _selectTab(MatchTab tab) {
    if (tab == _tab) return;
    // Keep the header where it is: if the user had collapsed it, the new
    // tab starts right under the pinned bar (the min-extent filler keeps
    // that offset reachable for a shorter tab).
    double? target;
    if (_scroll.hasClients) {
      final p = _scroll.position;
      target = math.min(p.pixels, _collapseRange);
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
    if (tab == MatchTab.scorecard && (!_scorecardRequested || _scorecard == null) && _scorecardReq == null) {
      _fetchScorecard(silent: false);
    }
    if (tab == MatchTab.commentary) _ensureCommentary().ensureLoaded();
    if (tab != MatchTab.commentary) _commentary?.setHold(false);
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

  VoidCallback? _seriesTap(MatchDetailVM m) => m.seriesKey == null
      ? null
      : () => _guardedNav(() => AppNav.seriesDetail<void>(context, m.seriesKey!, seriesName: m.seriesName));

  // ───────────────────────────── derive ─────────────────────────────

  void _derive(MatchDetailVM m) {
    final key = (m, _live, _scView);
    if (_derivedFor is (MatchDetailVM, LiveVM?, ScorecardView?)) {
      final k = _derivedFor! as (MatchDetailVM, LiveVM?, ScorecardView?);
      if (identical(k.$1, m) && identical(k.$2, _live) && identical(k.$3, _scView) && _situation != null) return;
    }
    _derivedFor = key;
    _innings = buildInnings(match: m, live: _live, scorecard: _scView, scorecardOrder: _scView?.inningsOrder ?? const []);
    _situation = deriveSituation(
      match: m,
      status: m.matchStatus,
      innings: _innings,
      providerTarget: _scView?.targetRuns,
      scorecardMaxOvers: _scView?.maxOvers,
      teamLabel: (s) {
        final t = s == TeamSide.team1 ? m.t1 : m.t2;
        return t.name.length <= 16 ? t.name : t.code;
      },
    );
    _overs = m.matchStatus.inPlay ? buildOverViews(match: m, live: _live) : const [];
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (widget.matchId.trim().isEmpty) {
      return _ErrorView(message: 'Match ID is required', onBack: _goBack);
    }
    final m = _match;
    if (_loading && m == null) {
      return Scaffold(
        backgroundColor: p.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            _TopBar(onBack: _goBack, title: null),
            const Expanded(child: MatchDetailShimmer()),
          ]),
        ),
      );
    }
    if (_error != null || m == null) {
      return _ErrorView(
        message: _error ?? 'Match details are not available',
        onRetry: () => _fetchDetail(showLoading: true),
        onBack: _goBack,
      );
    }

    _derive(m);

    // Summary only exists for a completed match (before that it is empty:
    // the live view is on Commentary / Scorecard). If the open tab is Summary
    // and the match is not completed, land on Commentary instead.
    final showSummary = m.isMatchWon;
    final tabs = [for (final t in MatchTab.values) if (t != MatchTab.summary || showSummary) t];
    if (!showSummary && _tab == MatchTab.summary) {
      // Not started: there is no commentary yet, so open on Info (venue,
      // toss, squads). In play: Commentary.
      final land = m.matchStatus.phase == MatchPhase.upcoming ? MatchTab.info : MatchTab.commentary;
      _tab = land;
      _visited.add(land);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (land == MatchTab.commentary) _ensureCommentary().ensureLoaded();
        _syncTabPollers();
        // The commentary sliver is only built once its controller exists.
        setState(() {});
      });
    }

    final situation = _situation!;
    final phase = situation.status.phase;
    final inPlay = situation.status.inPlay;
    final displayPair = (_live?.battingPair.isNotEmpty ?? false)
        ? _live!.battingPair
        : (inPlay ? _lastBattingPair : const <BatterRow>[]);

    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(0.0, (width - kMatchCentreMaxWidth) / 2);

    final header = MatchCentreHeader(
      matchId: widget.matchId,
      match: m,
      situation: situation,
      note: phase == MatchPhase.interrupted ? latestInfoNote(_live) : null,
      animateScore: _animateScore,
      strip: _overs.isEmpty ? null : OverStrip(overs: _overs),
      band: _bandText == null
          ? null
          : WicketBand(
              key: ValueKey('band_$_bandId'),
              text: _bandText!,
              onDone: () {
                if (mounted) setState(() => _bandText = null);
              },
            ),
    );
    final collapsed = CollapsedScoreBar(
      match: m,
      situation: situation,
      lastBall: _overs.isEmpty || _overs.first.labels.isEmpty ? null : _overs.first.labels.last,
    );

    Widget keepAlive(MatchTab t, Widget child) {
      if (!_visited.contains(t)) return const SliverToBoxAdapter(child: SizedBox.shrink());
      final off = _tab != t;
      return SliverOffstage(
        offstage: off,
        sliver: SliverToBoxAdapter(child: TickerMode(enabled: !off, child: child)),
      );
    }

    final lineups = _RewardGated(
      controller: _rewardPlayingXI,
      unlocked: _playingXIUnlocked,
      gate: const _GateCopy(
        key: 'playing_xi',
        icon: Icons.people_outline,
        title: 'Unlock the line-ups',
        subtext: 'Watch one short ad to see the confirmed playing XI and bench.',
      ),
      child: MatchPlayingXITab(
        matchId: widget.matchId,
        isLive: inPlay,
        service: _matches,
        onPlayerTap: (key) => _guardedNav(() => AppNav.player<void>(context, key)),
      ),
    );

    final scrollView = CustomScrollView(
      key: const ValueKey('match_detail_scroll'),
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: ScreenBannerSlots(screen: 'match_detail', onlyPosition: 'top')),
        ValueListenableBuilder<double>(
          valueListenable: _headerH,
          builder: (context, h, _) => SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              header: header,
              collapsed: collapsed,
              tabs: _TabBar(tabs: tabs, active: _tab, onSelect: _selectTab),
              headerHeight: h,
              side: side,
              canvas: p.canvas,
              onMeasured: (v) {
                if ((v - _headerH.value).abs() > 0.5) _headerH.value = v;
              },
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side + Spacing.lg),
          sliver: SliverMainAxisGroup(slivers: [
            if (_tab == MatchTab.summary)
              SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  MatchSummaryTab(
                    match: m,
                    situation: situation,
                    live: _live,
                    batters: displayPair,
                    overs: _overs,
                    scorecard: _scView,
                    loadingLive: _loadingLive,
                    momInfo: _momInfo,
                    momLoading: _momLoading,
                    onMomTap: m.momKey.isEmpty ? null : () => _guardedNav(() => AppNav.player<void>(context, m.momKey, player: _momInfo)),
                    onSeeCommentary: () => _selectTab(MatchTab.commentary),
                    onSeeInfo: () => _selectTab(MatchTab.info),
                  ),
                  const ListNativeAd(placement: 'match_detail'),
                ]),
              ),
            if (_tab == MatchTab.commentary && _commentary != null) MatchCommentaryTabSliver(controller: _commentary!),
            keepAlive(
              MatchTab.scorecard,
              _RewardGated(
                controller: _rewardScoreboard,
                unlocked: _scorecardUnlocked,
                gate: const _GateCopy(
                  key: 'scorecard',
                  icon: Icons.lock_outline,
                  title: 'Unlock the full scorecard',
                  subtext: 'Watch one short ad to see every innings, bowling figures and the fall of wickets.',
                ),
                child: MatchScorecardTab(scorecard: _scorecard, loading: _loadingScorecard),
              ),
            ),
            keepAlive(MatchTab.stats, MatchStatsTab(matchId: widget.matchId, isLive: inPlay, service: _matches, scorecard: _scView)),
            keepAlive(
              MatchTab.info,
              MatchInfoTab(match: m, situation: situation, lineups: lineups, onSeriesTap: _seriesTap(m)),
            ),
          ]),
        ),
        // Min-height filler so switching to a shorter tab keeps the scroll offset.
        SliverLayoutBuilder(builder: (context, constraints) {
          final h = math.max(0.0, _restoreMinExtent - constraints.precedingScrollExtent);
          return SliverToBoxAdapter(child: SizedBox(height: h));
        }),
        const SliverToBoxAdapter(child: ScreenBannerSlots(screen: 'match_detail', onlyPosition: 'bottom')),
        const SliverToBoxAdapter(child: SizedBox(height: Spacing.xl)),
      ],
    );

    final c = _commentary;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _TopBar(
            onBack: _goBack,
            title: m.seriesName.isEmpty ? null : m.seriesName,
            onTitleTap: _seriesTap(m),
            side: side,
          ),
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Positioned.fill(
                child: RefreshIndicator(
                  key: const ValueKey('match_detail_refresh'),
                  color: p.brandText,
                  backgroundColor: p.surface,
                  onRefresh: _onRefresh,
                  child: scrollView,
                ),
              ),
              if (_tab == MatchTab.commentary && c != null)
                ListenableBuilder(
                  listenable: c,
                  builder: (context, _) {
                    if (c.pendingCount <= 0) return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
                    return Positioned(
                      top: CollapsedScoreBar.height + _TabBar.height + Spacing.sm,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Material(
                          color: p.ink,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            key: const ValueKey('match_detail_commentary_new_pill'),
                            customBorder: const StadiumBorder(),
                            onTap: _showPendingBalls,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm + 2),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.arrow_upward, size: 16, color: p.surface),
                                const SizedBox(width: Spacing.xs + 2),
                                Text(
                                  c.pendingCount == 1 ? '1 new ball' : '${c.pendingCount} new balls',
                                  style: AppFont.style(size: 14, weight: FontWeight.w700, color: p.surface),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────────── pieces ─────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.title, this.onTitleTap, this.side = 0});
  final VoidCallback onBack;
  final String? title;
  final VoidCallback? onTitleTap;
  final double side;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = title;
    return Container(
      height: 56,
      color: p.canvas,
      padding: EdgeInsets.symmetric(horizontal: side + Spacing.xs),
      child: Row(children: [
        IconButton(
          key: const ValueKey('match_detail_back'),
          tooltip: 'Back',
          onPressed: onBack,
          icon: Icon(Icons.arrow_back, color: p.ink),
        ),
        if (t != null)
          Expanded(
            child: onTitleTap == null
                ? Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.name.copyWith(color: p.ink))
                : Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      key: const ValueKey('match_detail_series_link'),
                      onTap: onTitleTap,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                              child: Text(
                                t,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.name.copyWith(color: p.brandText),
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: p.brandText),
                          ]),
                        ),
                      ),
                    ),
                  ),
          ),
      ]),
    );
  }
}

/// The collapsing header: full header → 56 dp score bar, with the tab bar
/// pinned under it. The header is laid out at its natural height (reported
/// by [_SizeReporter]) and slides up under a clip as the page scrolls; the
/// collapsed bar fades in over its last stretch.
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.header,
    required this.collapsed,
    required this.tabs,
    required this.headerHeight,
    required this.side,
    required this.canvas,
    required this.onMeasured,
  });
  final Widget header;
  final Widget collapsed;
  final Widget tabs;
  final double headerHeight;
  final double side;
  final Color canvas;
  final ValueChanged<double> onMeasured;

  static const double _bar = CollapsedScoreBar.height;

  /// Before the first measurement: a typical header height.
  double get _h => headerHeight > 0 ? headerHeight : 260;

  @override
  double get minExtent => _bar + _TabBar.height;

  @override
  double get maxExtent => math.max(_h, _bar) + _TabBar.height;

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.header != header || old.collapsed != collapsed || old.tabs != tabs || old.headerHeight != headerHeight || old.side != side || old.canvas != canvas;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = math.max(0.0, _h - _bar);
    final regionH = math.max(_bar, _h - shrinkOffset);
    // Collapsed bar fades in over the last 48 dp of the collapse.
    final t = headerHeight <= 0 || range <= 0 ? 0.0 : ((shrinkOffset - (range - 48)) / 48).clamp(0.0, 1.0);
    return ColoredBox(
      color: canvas,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: regionH,
          child: ClipRect(
            child: Stack(fit: StackFit.expand, children: [
              IgnorePointer(
                ignoring: t > 0.5,
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: _SizeReporter(
                    onSize: onMeasured,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: header,
                    ),
                  ),
                ),
              ),
              if (t > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _bar,
                  child: Opacity(
                    opacity: t,
                    child: Padding(padding: EdgeInsets.symmetric(horizontal: side), child: collapsed),
                  ),
                ),
            ]),
          ),
        ),
        Padding(padding: EdgeInsets.symmetric(horizontal: side), child: tabs),
      ]),
    );
  }
}

/// Reports its child's laid-out height after layout (only when it changes).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});
  final ValueChanged<double> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<double> onSize;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (_last != h) {
      _last = h;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) onSize(h);
      });
    }
  }
}

class _TabBar extends StatefulWidget {
  const _TabBar({required this.tabs, required this.active, required this.onSelect});
  final List<MatchTab> tabs;
  final MatchTab active;
  final ValueChanged<MatchTab> onSelect;

  static const double height = 48;

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  final _keys = {for (final t in MatchTab.values) t: GlobalKey()};
  final _hScroll = ScrollController();

  @override
  void didUpdateWidget(_TabBar old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  /// Centres the active tab in the tab row only (Scrollable.ensureVisible
  /// would also scroll the page).
  void _reveal() {
    final box = _keys[widget.active]?.currentContext?.findRenderObject();
    if (!mounted || box == null || !_hScroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final target = viewport.getOffsetToReveal(box, 0.5).offset.clamp(0.0, _hScroll.position.maxScrollExtent);
    final d = Motion.of(context).orZero(Motion.tabSwitch);
    if (d == Duration.zero) {
      _hScroll.jumpTo(target);
    } else {
      _hScroll.animateTo(target, duration: d, curve: Motion.standard);
    }
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3)),
      child: Container(
        height: _TabBar.height,
        decoration: BoxDecoration(color: p.canvas, border: Border(bottom: BorderSide(color: p.hairline))),
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final t in widget.tabs)
              Semantics(
                key: _keys[t],
                selected: t == widget.active,
                button: true,
                child: InkWell(
                  key: ValueKey('match_detail_tab_${t.name}'),
                  onTap: () => widget.onSelect(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm + 2),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            t.label,
                            maxLines: 1,
                            style: AppFont.style(
                              size: 14,
                              weight: t == widget.active ? FontWeight.w700 : FontWeight.w600,
                              color: t == widget.active ? p.ink : p.inkMuted,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        height: 3,
                        width: 28,
                        decoration: BoxDecoration(
                          color: t == widget.active ? p.brand : Colors.transparent,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry, required this.onBack});
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(children: [
          _TopBar(onBack: onBack, title: null),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sports_cricket_outlined, size: 40, color: p.inkMuted),
                    const SizedBox(height: Spacing.md),
                    Text("Match didn't load", textAlign: TextAlign.center, style: AppText.sectionTitle.copyWith(color: p.ink)),
                    const SizedBox(height: Spacing.sm),
                    Text(message,
                        key: const ValueKey('match_detail_error'),
                        textAlign: TextAlign.center,
                        style: AppText.reading.copyWith(color: p.inkMuted)),
                    const SizedBox(height: Spacing.lg),
                    if (onRetry != null) ...[
                      FilledButton(key: const ValueKey('match_detail_retry'), onPressed: onRetry, child: const Text('Try again')),
                      const SizedBox(height: Spacing.sm),
                    ],
                    TextButton(key: const ValueKey('match_detail_go_back'), onPressed: onBack, child: const Text('Go back')),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GateCopy {
  const _GateCopy({required this.key, required this.icon, required this.title, required this.subtext});
  final String key;
  final IconData icon;
  final String title, subtext;
}

/// Rewarded unlock: shown instead of [child] while the rewarded placement
/// is enabled and not yet unlocked. The gated child is not built (so it does
/// not fetch) until unlocked.
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
        final p = context.palette;
        final loading = controller.isLoading;
        return Padding(
          key: ValueKey('match_detail_reward_gate_${gate.key}'),
          padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
          child: Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: p.hairline),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(gate.icon, size: 24, color: p.ink),
              const SizedBox(height: Spacing.sm),
              Text(gate.title, style: AppText.sectionTitle.copyWith(color: p.ink)),
              const SizedBox(height: Spacing.xs),
              Text(gate.subtext, style: AppText.reading.copyWith(color: p.inkMuted)),
              const SizedBox(height: Spacing.lg),
              FilledButton.icon(
                key: ValueKey('match_detail_reward_gate_${gate.key}_button'),
                onPressed: loading ? null : controller.show,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: Text(loading ? 'Loading ad…' : controller.label),
              ),
            ]),
          ),
        );
      },
    );
  }
}
