import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/skeletons.dart';
import '../common/match_row.dart';
import '../common/tap_guard.dart';
import 'recent_searches.dart';
import 'search_index.dart';

/// Full-screen local search (PRD §11, research §8): teams, players, series,
/// match names and venues across what is loaded or fetched on open. No
/// search endpoint exists, so results never include anything the provider
/// has not sent; an empty result says so.
///
/// Typing is debounced ([debounce]); the trending-players endpoint is
/// queried with the text for players. Recent searches are stored on the
/// device with a Clear action.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.index});

  /// Defaults to [SearchIndex.instance].
  final SearchIndex? index;

  static Duration debounce = const Duration(milliseconds: 300);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  SearchIndex get _index => widget.index ?? SearchIndex.instance;
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _tap = TapGuard();
  Timer? _debounce;

  List<String> _recent = const [];
  String _query = '';
  SearchResults _results = const SearchResults();
  bool _warming = true;
  bool _playersLoading = false;
  Object? _playersError;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    RecentSearches.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
    _warm();
  }

  Future<void> _warm({bool force = false}) async {
    setState(() => _warming = true);
    await _index.warmUp(force: force);
    if (!mounted) return;
    setState(() {
      _warming = false;
      if (_query.isNotEmpty) _results = _index.search(_query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    _tap.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      _gen++;
      setState(() {
        _query = '';
        _results = const SearchResults();
        _playersLoading = false;
        _playersError = null;
      });
      return;
    }
    _debounce = Timer(SearchScreen.debounce, () => _run(q));
  }

  Future<void> _run(String q) async {
    final gen = ++_gen;
    setState(() {
      _query = q;
      _results = _index.search(q);
      _playersLoading = q.length >= 2;
      _playersError = null;
    });
    if (q.length < 2) return;
    try {
      await _index.searchPlayers(q);
      if (!mounted || gen != _gen) return;
      setState(() {
        _results = _index.search(q);
        _playersLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _playersLoading = false;
        _playersError = e;
      });
    }
  }

  void _useRecent(String q) {
    _text.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _debounce?.cancel();
    _run(q);
  }

  Future<void> _remember() async {
    final q = _query.isNotEmpty ? _query : _text.text.trim();
    if (q.isEmpty) return;
    final next = await RecentSearches.add(q);
    if (mounted) setState(() => _recent = next);
  }

  Future<void> _clearRecent() async {
    await RecentSearches.clear();
    if (mounted) setState(() => _recent = const []);
  }

  void _open(Future<void> Function() go) => _tap.run(() async {
    await _remember();
    if (mounted) await go();
  });

  void _openMatch(MatchSummary m) =>
      _open(() => AppNav.match<void>(context, m.id));
  void _openSeries(SeriesHit s) =>
      _open(() => AppNav.seriesDetail<void>(context, s.id, seriesName: s.name));
  void _openPlayer(PlayerHit p) =>
      _open(() => AppNav.player<void>(context, p.key, player: p.raw));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.canvas,
      child: Column(
        children: [
          _bar(context),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final p = context.palette;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Material(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.hairline)),
          ),
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  key: const ValueKey('search_back'),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: p.ink),
                )
              else
                const SizedBox(width: Spacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('search_field'),
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) {
                    _debounce?.cancel();
                    if (v.trim().isNotEmpty) _run(v.trim());
                    _remember();
                  },
                  style: AppText.reading,
                  cursorColor: p.brandText,
                  decoration: InputDecoration(
                    hintText: 'Teams, players, series or venues',
                    hintStyle: AppText.reading.copyWith(color: p.inkMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, v, _) => v.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('search_clear_query'),
                        tooltip: 'Clear text',
                        onPressed: () {
                          _text.clear();
                          _onChanged('');
                          _focus.requestFocus();
                        },
                        icon: Icon(Icons.close, color: p.ink),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centered(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );

  Widget _body(BuildContext context) {
    if (_query.isEmpty) return _idle(context);
    final r = _results;
    if (!r.isEmpty) return _list(context, r);
    if (_warming || _playersLoading) {
      return const SingleChildScrollView(
        key: ValueKey('search_loading'),
        physics: NeverScrollableScrollPhysics(),
        child: SkeletonList(cards: 0, rows: 4),
      );
    }
    final failed = _index.warmError != null && _index.size == 0;
    if (failed) {
      return SingleChildScrollView(
        child: _centered(
          ErrorRetry(
            key: const ValueKey('search_error'),
            title: "Search couldn't load",
            message: friendlyError(_index.warmError!),
            onRetry: () => _warm(force: true),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: _centered(
        EmptyState(
          key: const ValueKey('search_empty'),
          icon: Icons.search_off,
          title: 'Nothing found for "$_query"',
          subtitle:
              'Search covers live, upcoming and recent matches, the series '
              'list and trending players.',
          hint: _playersError != null
              ? 'Player search is not reachable right now.'
              : 'Check the spelling, or browse players by country.',
          actionLabel: 'Browse players',
          onAction: () => AppNav.discover(context, DiscoverSection.players),
        ),
      ),
    );
  }

  Widget _idle(BuildContext context) {
    final p = context.palette;
    if (_recent.isEmpty) {
      return SingleChildScrollView(
        child: _centered(
          const EmptyState(
            key: ValueKey('search_idle'),
            icon: Icons.search,
            title: 'Find a match, series or player',
            subtitle:
                'Type a team (India, IND), a player, a series or a venue.',
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('search_recent'),
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        _centered(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.sm,
              Spacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Recent searches', style: AppText.sectionTitle),
                ),
                TextButton(
                  key: const ValueKey('search_recent_clear'),
                  onPressed: _clearRecent,
                  child: Text(
                    'Clear',
                    style: AppFont.style(
                      size: 14,
                      weight: FontWeight.w700,
                      color: p.brandText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < _recent.length; i++)
          _centered(
            ListTile(
              key: ValueKey('search_recent_$i'),
              leading: Icon(Icons.history, color: p.inkMuted),
              title: Text(
                _recent[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.name,
              ),
              trailing: Icon(Icons.north_west, size: 18, color: p.inkMuted),
              onTap: () => _useRecent(_recent[i]),
            ),
          ),
      ],
    );
  }

  Widget _header(String title, {bool loading = false}) => _centered(
    Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppText.sectionTitle),
            ),
          ),
          if (loading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.palette.brandText,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _list(BuildContext context, SearchResults r) {
    final p = context.palette;
    final items = <Widget>[
      if (r.matches.isNotEmpty) ...[
        _header('Matches'),
        _centered(
          MatchRowGroup(
            children: [
              for (final m in r.matches)
                MatchRow(
                  key: ValueKey('search_match_${m.id}'),
                  match: m,
                  onTap: () => _openMatch(m),
                ),
            ],
          ),
        ),
      ],
      if (r.series.isNotEmpty) ...[
        _header('Series'),
        _centered(
          MatchRowGroup(
            children: [
              for (final s in r.series)
                ListTile(
                  key: ValueKey('search_series_${s.id}'),
                  leading: Icon(Icons.emoji_events_outlined, color: p.inkMuted),
                  title: Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.name,
                  ),
                  subtitle: _seriesSub(s) == null
                      ? null
                      : Text(
                          _seriesSub(s)!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small.copyWith(color: p.inkMuted),
                        ),
                  onTap: () => _openSeries(s),
                ),
            ],
          ),
        ),
      ],
      if (r.players.isNotEmpty || _playersLoading) ...[
        _header('Players', loading: _playersLoading),
        if (r.players.isNotEmpty)
          _centered(
            MatchRowGroup(
              children: [
                for (final pl in r.players)
                  ListTile(
                    key: ValueKey('search_player_${pl.key}'),
                    leading: NetImage(
                      url: pl.logo,
                      size: 36,
                      fit: BoxFit.cover,
                      fallbackLetter: pl.name,
                    ),
                    title: Text(
                      pl.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.name,
                    ),
                    subtitle: pl.country == null
                        ? null
                        : Text(
                            pl.country!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.small.copyWith(color: p.inkMuted),
                          ),
                    onTap: () => _openPlayer(pl),
                  ),
              ],
            ),
          ),
      ],
    ];
    return ListView(
      key: const ValueKey('search_results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: items,
    );
  }

  String? _seriesSub(SeriesHit s) {
    final parts = [?s.status, ?s.dates];
    return parts.isEmpty ? null : parts.join(', ');
  }
}
