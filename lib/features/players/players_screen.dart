import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import 'player_models.dart';
import 'widgets/gradient_card.dart';
import 'widgets/player_widgets.dart';

/// Ported from RN `src/screens/PlayersScreen.tsx` (+ PlayersTableByCountry).
///
/// Country pill tabs → paginated players list (20 per page, infinite scroll).
/// A generation counter drops responses that belong to a previously selected
/// country, and load-more is guarded so a page is never requested twice.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  static const perPage = 20;
  static const _fadeOut = Duration(milliseconds: 120);
  static const _fadeIn = Duration(milliseconds: 180);

  List<String> _countries = const [];
  bool _loadingCountries = true;
  String _selected = kDefaultCountry;
  final Map<String, GlobalKey> _tabKeys = {};

  List<CountryPlayer> _players = const [];
  final Set<String> _ids = {};
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  String? _error;

  int _gen = 0;
  bool _visible = true;
  Timer? _switchTimer;
  bool _navigating = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchCountries();
    _fetchPlayers(1);
  }

  @override
  void dispose() {
    _switchTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetchCountries() async {
    if (mounted) setState(() => _loadingCountries = true);
    List<String> list;
    try {
      final res = await PlayerService.instance.getCountries();
      list = J.list(res.data).map((e) => J.text(e)).whereType<String>().toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } catch (_) {
      list = const [kDefaultCountry];
    }
    if (!mounted) return;
    setState(() {
      _countries = list;
      _loadingCountries = false;
    });
    if (list.isNotEmpty && !list.contains(_selected)) {
      _selectCountry(list.first);
    } else {
      _scrollTabIntoView();
    }
  }

  /// [pageNum] 1 replaces the list, > 1 appends.
  Future<void> _fetchPlayers(int pageNum) async {
    final append = pageNum > 1;
    final gen = append ? _gen : ++_gen;
    final country = _selected;
    setState(() {
      if (append) {
        _loadingMore = true;
        _loadMoreFailed = false;
      } else {
        _loading = true;
        _loadingMore = false;
        _error = null;
      }
    });
    try {
      final res = await PlayerService.instance.getPlayersByCountry(country, page: pageNum, perPage: perPage);
      if (!mounted || gen != _gen) return;
      final list = CountryPlayer.listFrom(res.data);
      final info = res.pageInfo;
      final more = computeHasMore(
        received: list.length,
        perPage: perPage,
        infoPage: info?.page,
        infoPerPage: info?.perPage,
        infoTotal: info?.total,
      );
      setState(() {
        if (!append) {
          _ids.clear();
          _players = const [];
        }
        // De-dupe (stable keys; the API can shift rows between pages).
        final fresh = list.where((p) => _ids.add(p.id)).toList();
        _players = [..._players, ...fresh];
        _hasMore = more;
        _page = pageNum;
        _error = null;
      });
      _checkFillViewport();
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        if (append) {
          _loadMoreFailed = true;
        } else {
          _error = friendlyError(e);
          _players = const [];
          _ids.clear();
        }
      });
    } finally {
      if (mounted && gen == _gen) {
        setState(() {
          if (append) {
            _loadingMore = false;
          } else {
            _loading = false;
          }
        });
      }
    }
  }

  void _loadMore() {
    if (_loading || _loadingMore || !_hasMore || _loadMoreFailed || _players.isEmpty) return;
    _fetchPlayers(_page + 1);
  }

  /// RN FlatList fires onEndReached when content is shorter than the screen.
  void _checkFillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.extentAfter < pos.viewportDimension * 0.4) _loadMore();
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < n.metrics.viewportDimension * 0.4) _loadMore();
    return false;
  }

  void _selectCountry(String c) {
    if (c == _selected) return;
    setState(() {
      _selected = c;
      _page = 1;
      _hasMore = true;
      _visible = false;
    });
    _gen++; // drop in-flight responses for the previous country
    _scrollTabIntoView();
    _switchTimer?.cancel();
    _switchTimer = Timer(_fadeOut, () {
      if (!mounted) return;
      final gen = _gen + 1;
      _fetchPlayers(1).whenComplete(() {
        if (mounted && gen == _gen) setState(() => _visible = true);
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _scrollTabIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[_selected]?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(ctx, alignment: 0.1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _onRefresh() => Future.wait([_fetchCountries(), _fetchPlayers(1)]);

  Future<void> _onPlayerPress(CountryPlayer p) async {
    if (_navigating || p.playerKey.isEmpty) return;
    _navigating = true;
    try {
      await AppNav.player<void>(context, p.playerKey, player: p.raw);
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = _loading && _players.isEmpty;
    final showEmpty = !_loading && _players.isEmpty;
    return Material(
      color: AppColors.bg,
      child: Column(children: [
        const ScreenTitle(title: 'Players'),
        const ScreenBannerSlots(screen: 'players', onlyPosition: 'top'),
        _countryTabs(),
        Expanded(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: _visible ? _fadeIn : _fadeOut,
            child: showLoading
                ? const PlayersShimmer()
                : showEmpty
                    ? _emptyOrError()
                    : _list(),
          ),
        ),
        const FixedBottomBanner(screen: 'players'),
      ]),
    );
  }

  Widget _countryTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: SizedBox(
        height: 34,
        child: Stack(children: [
          SingleChildScrollView(
            key: const ValueKey('players_country_tabs'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 14, right: Spacing.xxxl),
            child: Row(children: [
              if (_loadingCountries)
                for (var i = 0; i < 8; i++)
                  Container(
                    width: 72,
                    height: 32,
                    margin: const EdgeInsets.only(right: Spacing.sm),
                    decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(Radii.lg)),
                  )
              else
                for (final c in _countries) _countryTab(c),
            ]),
          ),
          // Right-edge fade hint.
          const Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x00FFFFFF), AppColors.bg])),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _countryTab(String c) {
    final active = c == _selected;
    return Padding(
      key: _tabKeys.putIfAbsent(c, GlobalKey.new),
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: Material(
        color: active ? AppColors.text : AppColors.bg,
        shape: StadiumBorder(side: BorderSide(color: active ? AppColors.text : AppColors.borderStrong)),
        child: InkWell(
          key: ValueKey('players_country_$c'),
          customBorder: const StadiumBorder(),
          onTap: () => _selectCountry(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: Spacing.lg),
            child: Text(
              c,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppColors.white : AppColors.graphite,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyOrError() => RefreshIndicator(
        color: AppColors.pitch,
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(14, 40, 14, bottomReserve(context)),
          children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: _error != null
                  ? Column(children: [
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.error)),
                      const SizedBox(height: Spacing.lg),
                      TryAgainButton(key: const ValueKey('players_retry'), onPressed: () => _fetchPlayers(1)),
                    ])
                  : const Text('No players in this country',
                      key: ValueKey('players_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );

  Widget _list() => RefreshIndicator(
        color: AppColors.pitch,
        onRefresh: _onRefresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            key: const ValueKey('players_list'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(14, 12, 14, bottomReserve(context)),
            itemCount: _players.length + 1,
            itemBuilder: (context, i) {
              if (i == _players.length) return _footer();
              final p = _players[i];
              return PlayerRow(key: ValueKey('players_row_${p.id}'), player: p, onPress: _onPlayerPress);
            },
          ),
        ),
      );

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            key: ValueKey('players_loading_more'),
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.pitch),
          ),
        ),
      );
    }
    if (_loadMoreFailed) {
      return Center(
        child: TextButton(
          key: const ValueKey('players_load_more_retry'),
          onPressed: () {
            setState(() => _loadMoreFailed = false);
            _loadMore();
          },
          child: const Text("Couldn't load more players. Tap to retry",
              style: TextStyle(fontSize: 12, color: AppColors.pitch, fontWeight: FontWeight.w600)),
        ),
      );
    }
    if (!_hasMore && _players.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No more players',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, letterSpacing: 0.3, fontWeight: FontWeight.w600)),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}
