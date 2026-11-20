import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/shimmer_box.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../discover/discover_cache.dart';
import 'player_models.dart';
import 'widgets/player_widgets.dart';

/// Trending players (shared with the Discover hub preview, cached).
Future<List<CountryPlayer>> loadTrendingPlayers({bool force = false}) =>
    DiscoverCache.get(
      'players:trending',
      () async => CountryPlayer.listFrom(
        (await PlayerService.instance.getTrendingPlayers(perPage: 10)).data,
      ),
      force: force,
    );

/// Players hub: search (debounced, server + loaded lists), trending, and
/// browse by country (paginated, infinite scroll).
///
/// A generation counter drops responses that belong to a previously
/// selected country or an older search, and load-more is guarded so a page
/// is never requested twice.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  static const searchDebounce = Duration(milliseconds: 350);
  static const minQuery = 2;

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  static const perPage = 20;

  List<String> _countries = const [];
  bool _loadingCountries = true;
  String _selected = kDefaultCountry;
  final Map<String, GlobalKey> _chipKeys = {};

  List<CountryPlayer>? _trending;

  List<CountryPlayer> _players = const [];
  final Set<String> _ids = {};
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  String? _error;
  int _gen = 0;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  int _searchGen = 0;
  bool _searching = false;
  String? _searchError;
  List<CountryPlayer> _results = const [];

  bool _navigating = false;
  final _scroll = ScrollController();

  bool get _searchActive => _query.length >= PlayersScreen.minQuery;

  @override
  void initState() {
    super.initState();
    _fetchTrending();
    _fetchCountries();
    _fetchPlayers(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetchTrending({bool force = false}) async {
    try {
      final list = await loadTrendingPlayers(force: force);
      if (mounted) setState(() => _trending = list);
    } catch (_) {
      // Trending is optional: the section hides itself.
      if (mounted) setState(() => _trending = const []);
    }
  }

  Future<void> _fetchCountries({bool force = false}) async {
    if (mounted && _countries.isEmpty) setState(() => _loadingCountries = true);
    List<String> list;
    try {
      list = await DiscoverCache.get('players:countries', () async {
        final res = await PlayerService.instance.getCountries();
        return J
            .list(res.data)
            .map((e) => J.text(e))
            .whereType<String>()
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }, force: force);
    } catch (_) {
      list = const [];
    }
    if (list.isEmpty) list = const [kDefaultCountry];
    if (!mounted) return;
    setState(() {
      _countries = list;
      _loadingCountries = false;
    });
    if (!list.contains(_selected)) {
      _selectCountry(list.first);
    } else {
      _scrollChipIntoView();
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
      final res = await PlayerService.instance.getPlayersByCountry(
        country,
        page: pageNum,
        perPage: perPage,
      );
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
    if (_searchActive ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _loadMoreFailed ||
        _players.isEmpty) {
      return;
    }
    _fetchPlayers(_page + 1);
  }

  /// Keep loading while the content is shorter than the screen.
  void _checkFillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.extentAfter < pos.viewportDimension * 0.4) _loadMore();
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.metrics.extentAfter < n.metrics.viewportDimension * 0.4) {
      // Notifications can arrive during layout; never setState there.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMore();
      });
    }
    return false;
  }

  void _selectCountry(String c) {
    if (c == _selected && _players.isNotEmpty) return;
    setState(() {
      _selected = c;
      _page = 1;
      _hasMore = true;
    });
    _scrollChipIntoView();
    _fetchPlayers(1);
  }

  void _scrollChipIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[_selected]?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final ro = ctx.findRenderObject();
      if (ro == null) return;
      // Only the chip row scrolls (Scrollable.ensureVisible would also move
      // the page and hide the trending strip).
      Scrollable.maybeOf(ctx)?.position.ensureVisible(
        ro,
        alignment: 0.1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _onRefresh() => Future.wait([
    _fetchTrending(force: true),
    _fetchCountries(force: true),
    _fetchPlayers(1),
  ]);

  // ── search ──

  void _onQueryChanged(String v) {
    setState(() {}); // clear button visibility
    _debounce?.cancel();
    _debounce = Timer(PlayersScreen.searchDebounce, () => _applyQuery(v));
  }

  void _applyQuery(String v) {
    final q = v.trim();
    if (q == _query && (_results.isNotEmpty || _searching)) return;
    setState(() => _query = q);
    if (_searchActive) _runSearch(q);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    _searchGen++;
    setState(() {
      _query = '';
      _results = const [];
      _searching = false;
      _searchError = null;
    });
  }

  Future<void> _runSearch(String q) async {
    final gen = ++_searchGen;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    // Names already loaded on this screen match instantly.
    final local = [
      ...?_trending,
      ..._players,
    ].where((p) => nameMatches(p.name, q));
    try {
      final res = await PlayerService.instance.getTrendingPlayers(
        perPage: 20,
        search: q,
      );
      if (!mounted || gen != _searchGen) return;
      final seen = <String>{};
      final merged = [
        // Only keep server rows that really match (the endpoint can return
        // its trending list unfiltered).
        ...CountryPlayer.listFrom(
          res.data,
        ).where((p) => nameMatches(p.name, q)),
        ...local,
      ].where((p) => seen.add(p.playerKey.isEmpty ? p.id : p.playerKey)).toList();
      setState(() {
        _results = merged;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      final l = local.toList();
      setState(() {
        _results = l;
        _searchError = l.isEmpty ? friendlyError(e) : null;
        _searching = false;
      });
    }
  }

  Future<void> _openPlayer(CountryPlayer p) async {
    if (_navigating || p.playerKey.isEmpty) return;
    _navigating = true;
    try {
      await AppNav.player<void>(context, p.playerKey, player: p.raw);
    } finally {
      _navigating = false;
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.canvas,
      child: Column(
        children: [
          const ScreenTitle(title: 'Players'),
          const ScreenBannerSlots(screen: 'players', onlyPosition: 'top'),
          _searchBar(),
          Expanded(child: _searchActive ? _searchResults() : _browse()),
          const FixedBottomBanner(screen: 'players'),
        ],
      ),
    );
  }

  Widget _searchBar() {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.md,
      ),
      child: Capped(
        child: TextField(
          key: const ValueKey('players_search'),
          controller: _search,
          focusNode: _searchFocus,
          onChanged: _onQueryChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            _applyQuery(v);
          },
          textInputAction: TextInputAction.search,
          style: AppText.reading,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: p.surfaceAlt,
            hintText: 'Search players by name',
            hintStyle: AppText.reading.copyWith(color: p.inkMuted),
            prefixIcon: Icon(Icons.search, color: p.inkMuted, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('players_search_clear'),
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                    icon: Icon(Icons.close, color: p.inkMuted, size: 20),
                  ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: Spacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: p.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: p.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: p.ink, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchResults() {
    if (_searching && _results.isEmpty) {
      return const SingleChildScrollView(
        key: ValueKey('players_search_loading'),
        physics: NeverScrollableScrollPhysics(),
        child: Capped(child: PlayersSkeleton(count: 5)),
      );
    }
    if (_searchError != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorRetry(
            key: const ValueKey('players_search_error'),
            title: "Search didn't finish",
            message: _searchError!,
            onRetry: () => _runSearch(_query),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyState(
            key: const ValueKey('players_search_empty'),
            icon: Icons.person_search_outlined,
            title: 'No player named "$_query"',
            subtitle: 'Check the spelling, or browse players by country.',
            actionLabel: 'Browse by country',
            onAction: _clearSearch,
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('players_search_results'),
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      itemCount: _results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Capped(
            child: PageSectionTitle(
              '${_results.length} ${_results.length == 1 ? 'player' : 'players'} found',
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.lg,
                Spacing.lg,
                Spacing.sm,
              ),
            ),
          );
        }
        final p = _results[i - 1];
        return Capped(
          child: Column(
            children: [
              if (i > 1) const RowDivider(),
              PlayerRow(
                key: ValueKey('players_result_${p.id}'),
                player: p,
                showCountry: true,
                onPress: _openPlayer,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Header items before the country rows: trending, country chips.
  static const _headerCount = 2;

  Widget _browse() {
    final showRows = !_loading && _error == null && _players.isNotEmpty;
    final rowCount = showRows ? _players.length + 1 : 1; // + footer / state
    return RefreshIndicator(
      color: context.palette.brandText,
      onRefresh: _onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.builder(
          key: const ValueKey('players_list'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          itemCount: _headerCount + rowCount,
          itemBuilder: (context, i) {
            if (i == 0) return Capped(child: _trendingSection());
            if (i == 1) return Capped(child: _countryHeader());
            final r = i - _headerCount;
            if (!showRows) return Capped(child: _countryState());
            if (r == _players.length) return Capped(child: _footer());
            final p = _players[r];
            return Capped(
              child: Column(
                children: [
                  if (r > 0) const RowDivider(),
                  PlayerRow(
                    key: ValueKey('players_row_${p.id}'),
                    player: p,
                    onPress: _openPlayer,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _trendingSection() {
    final list = _trending;
    if (list != null && list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageSectionTitle(
          'Trending',
          padding: EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.lg,
            Spacing.sm,
          ),
        ),
        SingleChildScrollView(
          key: const ValueKey('players_trending'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: list == null
              ? ShimmerGroup(
                  child: Row(
                    children: [
                      for (var i = 0; i < 6; i++)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: Spacing.xs),
                          child: SizedBox(
                            width: 80,
                            child: Column(
                              children: [
                                ShimmerBox(width: 56, height: 56, radius: 28),
                                SizedBox(height: 8),
                                ShimmerBox(width: 60, height: 11, radius: 4),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in list)
                      TrendingPlayerTile(player: p, onPress: _openPlayer),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _countryHeader() {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageSectionTitle('By country'),
        SingleChildScrollView(
          key: const ValueKey('players_country_tabs'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.md,
          ),
          child: Row(
            children: [
              if (_loadingCountries)
                for (var i = 0; i < 6; i++)
                  const Padding(
                    padding: EdgeInsets.only(right: Spacing.sm),
                    child: ShimmerBox(
                      width: 76,
                      height: 36,
                      radius: Radii.chip,
                    ),
                  )
              else
                for (final c in _countries)
                  Padding(
                    key: _chipKeys.putIfAbsent(c, GlobalKey.new),
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: _CountryChip(
                      key: ValueKey('players_country_$c'),
                      label: c,
                      selected: c == _selected,
                      onTap: () => _selectCountry(c),
                    ),
                  ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: p.hairline),
      ],
    );
  }

  Widget _countryState() {
    if (_loading) {
      return const PlayersSkeleton(key: ValueKey('players_shimmer'), count: 8);
    }
    if (_error != null) {
      return ErrorRetry(
        key: const ValueKey('players_error'),
        title: "Players didn't load",
        message: _error!,
        onRetry: () => _fetchPlayers(1),
      );
    }
    return EmptyState(
      key: const ValueKey('players_empty'),
      icon: Icons.groups_outlined,
      title: 'No players listed for $_selected',
      subtitle: 'Pick another country above, or search by name.',
      actionLabel: 'Search by name',
      onAction: () => _searchFocus.requestFocus(),
    );
  }

  Widget _footer() {
    final p = context.palette;
    if (_loadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        child: Center(
          child: SizedBox(
            key: const ValueKey('players_loading_more'),
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: p.brandText,
            ),
          ),
        ),
      );
    }
    if (_loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Center(
          child: TextButton(
            key: const ValueKey('players_load_more_retry'),
            onPressed: () {
              setState(() => _loadMoreFailed = false);
              _loadMore();
            },
            child: const Text(
              "More players didn't load. Tap to try again",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Spacing.xl,
          horizontal: Spacing.lg,
        ),
        child: Center(
          child: Text(
            'That is everyone listed for $_selected',
            textAlign: TextAlign.center,
            style: AppText.meta,
          ),
        ),
      );
    }
    return const SizedBox(height: Spacing.md);
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.brandTint : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
          side: BorderSide(color: selected ? p.brand : p.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(
                label,
                maxLines: 1,
                style: AppFont.style(
                  size: 14,
                  weight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: p.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar + name, used in the Trending strip here and on the Discover hub.
class TrendingPlayerTile extends StatelessWidget {
  const TrendingPlayerTile({
    super.key,
    required this.player,
    required this.onPress,
    this.size = 56,
  });
  final CountryPlayer player;
  final ValueChanged<CountryPlayer> onPress;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: [
      player.name,
      if (player.country.isNotEmpty) player.country,
    ].join(', '),
    excludeSemantics: true,
    child: Pressable(
      key: ValueKey('players_trending_${player.id}'),
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () => onPress(player),
      child: SizedBox(
        width: size + 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs,
            vertical: Spacing.xs,
          ),
          child: Column(
            children: [
              PlayerAvatar(url: player.logo, name: player.name, size: size),
              const SizedBox(height: 6),
              Text(
                player.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppText.small.copyWith(color: context.palette.ink),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
