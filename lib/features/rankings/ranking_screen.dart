import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../players/widgets/gradient_card.dart';
import 'ranking_models.dart';
import 'widgets/ranking_widgets.dart';

/// Ported from RN `src/screens/RankingScreen.tsx`.
///
/// Teams / Players × Test / ODI / T20 × Men / Women (× Batters / Bowlers /
/// All-Rounders). Results are cached per combination for the screen's life.
/// Rapid toggling: the selection is applied immediately, the request fires
/// after the 120ms fade-out (only the last selection is fetched), identical
/// in-flight requests are shared, and responses for an older selection are
/// ignored (generation counter).
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  static const _fadeOut = Duration(milliseconds: 120);
  static const _fadeIn = Duration(milliseconds: 180);

  RankMode _mode = RankMode.teams;
  String _format = 'TEST';
  String _gender = 'MALE';
  String _category = 'batters';

  final Map<String, List<RankingRowItem>> _cache = {};
  final Map<String, Future<List<RankingRowItem>>> _inFlight = {};

  /// Data currently shown + whether it is a team list (rows not tappable).
  List<RankingRowItem> _list = const [];
  bool _listIsTeam = true;

  /// Derived once per data/search change (not in build).
  List<RankingRowItem> _podium = const [];
  List<RankingRowItem> _rows = const [];
  int _filteredCount = 0;

  bool _loading = true;
  bool _initialLoadDone = false;
  String? _error;
  bool _visible = true;
  int _gen = 0;
  Timer? _switchTimer;
  bool _navigating = false;

  final _search = TextEditingController();
  String _query = '';

  String get _cacheKey => _mode == RankMode.teams ? 'teams-$_format-$_gender' : 'players-$_format-$_gender-$_category';

  bool get _searching => _mode == RankMode.players && _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _switchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _derive() {
    final filtered = _mode == RankMode.players ? filterRankings(_list, _query) : _list;
    final split = splitForDisplay(filtered, searching: _searching);
    _filteredCount = filtered.length;
    _podium = split.podium;
    _rows = split.rows;
  }

  void _show(List<RankingRowItem> items, bool isTeam) {
    _list = items;
    _listIsTeam = isTeam;
    _derive();
  }

  Future<List<RankingRowItem>> _fetch(RankMode mode, String format, String gender, String category) async {
    final svc = RankingService.instance;
    if (mode == RankMode.teams) {
      final res = await svc.getTeamRankings(gender: gender, matchType: format);
      return parseTeamRankings(res.data);
    }
    final res = await svc.getPlayerRankings(gender: gender, matchType: format, type: categoryToApiType(category));
    return parsePlayerRankings(res.data);
  }

  /// [force] bypasses the in-memory cache (pull-to-refresh / retry).
  /// [silent] keeps the current list on screen while loading.
  Future<void> _load({bool force = false, bool silent = false}) async {
    final key = _cacheKey;
    final isTeam = _mode == RankMode.teams;
    final gen = ++_gen;
    final cached = _cache[key];
    if (!force && cached != null) {
      setState(() {
        _show(cached, isTeam);
        _error = null;
        _loading = false;
        _initialLoadDone = true;
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        // Network fetch: fade the shimmer in instead of a blank area.
        _visible = true;
      });
    }
    try {
      // Share an identical in-flight request instead of stacking a new one.
      // (Block body: returning the removed future would make whenComplete
      // wait on itself.)
      final future = _inFlight[key] ??= _fetch(_mode, _format, _gender, _category).whenComplete(() {
        _inFlight.remove(key);
      });
      final items = await future;
      _cache[key] = items;
      if (!mounted || gen != _gen) return;
      setState(() {
        _show(items, isTeam);
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      if (silent && _list.isNotEmpty && _listIsTeam == isTeam) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      } else {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _initialLoadDone = true;
        });
      }
    }
  }

  /// RN: fade out (120ms) → load → fade in (180ms) on every selector change.
  void _changeSelection(VoidCallback apply) {
    setState(() {
      apply();
      _visible = false;
    });
    // Invalidate any in-flight response for the previous selection now.
    _gen++;
    _switchTimer?.cancel();
    _switchTimer = Timer(_fadeOut, () {
      if (!mounted) return;
      final gen = _gen + 1; // generation _load is about to take
      _load().whenComplete(() {
        if (mounted && _gen == gen) setState(() => _visible = true);
      });
    });
  }

  void _onSearch(String v) => setState(() {
        _query = v;
        _derive();
      });

  Future<void> _onPlayerPress(RankingRowItem item) async {
    final key = item.playerKey;
    if (_listIsTeam || key == null || _navigating) return;
    _navigating = true;
    try {
      await AppNav.player<void>(context, key, player: item.toInitialPlayer());
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: Column(children: [
        const ScreenTitle(title: 'Rankings'),
        const ScreenBannerSlots(screen: 'ranking', onlyPosition: 'top'),
        if (_loading && !_initialLoadDone)
          const Expanded(child: RankingShimmer())
        else ...[
          _controls(),
          Expanded(
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _visible ? _fadeIn : _fadeOut,
              child: _content(),
            ),
          ),
        ],
        const FixedBottomBanner(screen: 'ranking'),
      ]),
    );
  }

  Widget _controls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 14),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(children: [
        SegmentedControl<String>(
          key: const ValueKey('rankings_mode'),
          options: const [SegmentOption('teams', 'Teams'), SegmentOption('players', 'Players')],
          value: _mode.name,
          onChanged: (v) {
            final m = RankMode.values.byName(v);
            if (m != _mode) _changeSelection(() => _mode = m);
          },
        ),
        const SizedBox(height: Spacing.sm),
        SegmentedControl<String>(
          key: const ValueKey('rankings_format'),
          compact: true,
          options: [for (final o in kFormatOptions) SegmentOption(o.$1, o.$2)],
          value: _format,
          onChanged: (v) {
            if (v != _format) _changeSelection(() => _format = v);
          },
        ),
        const SizedBox(height: Spacing.sm),
        SegmentedControl<String>(
          key: const ValueKey('rankings_gender'),
          compact: true,
          options: [for (final o in kGenderOptions) SegmentOption(o.$1, o.$2)],
          value: _gender,
          onChanged: (v) {
            if (v != _gender) _changeSelection(() => _gender = v);
          },
        ),
        if (_mode == RankMode.players) ...[
          const SizedBox(height: Spacing.sm),
          SegmentedControl<String>(
            key: const ValueKey('rankings_category'),
            compact: true,
            options: [for (final o in kCategoryOptions) SegmentOption(o.$1, o.$2)],
            value: _category,
            onChanged: (v) {
              if (v != _category) _changeSelection(() => _category = v);
            },
          ),
          const SizedBox(height: Spacing.sm + Spacing.xs),
          _searchBox(),
        ],
      ]),
    );
  }

  Widget _searchBox() => Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Row(children: [
          const Icon(Icons.search, size: 16, color: AppColors.textMuted),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: TextField(
              key: const ValueKey('rankings_search'),
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14, color: AppColors.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                hintText: 'Search player…',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            InkResponse(
              key: const ValueKey('rankings_search_clear'),
              radius: 16,
              onTap: () {
                _search.clear();
                _onSearch('');
              },
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.cancel, size: 16, color: AppColors.textMuted)),
            ),
        ]),
      );

  Widget _messageCard({required Widget child}) => ListView(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.xxl, Spacing.lg, bottomReserve(context)),
        children: [
          GradientCard(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: Spacing.xxl),
            child: child,
          ),
        ],
      );

  Widget _content() {
    if (_loading) return const RankingShimmer(showControls: false);
    if (_error != null) {
      return _messageCard(
        child: Column(children: [
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.error)),
          const SizedBox(height: 14),
          TryAgainButton(key: const ValueKey('rankings_retry'), onPressed: () => _load(force: true)),
        ]),
      );
    }
    if (_filteredCount == 0) {
      final q = _searching ? _query.trim() : '';
      return RefreshIndicator(
        color: AppColors.pitch,
        onRefresh: () => _load(force: true, silent: true),
        child: _messageCard(
          child: Text(
            q.isNotEmpty ? 'No matches for "$q"' : 'No rankings available',
            key: const ValueKey('rankings_empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final label = _searching
        ? '$_filteredCount result${_filteredCount == 1 ? '' : 's'}'
        : 'Ranks 4–${_filteredCount < 100 ? _filteredCount : 100}';
    final isTeam = _listIsTeam;
    return RefreshIndicator(
      color: AppColors.pitch,
      onRefresh: () => _load(force: true, silent: true),
      child: ListView.builder(
        key: const ValueKey('rankings_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: Spacing.lg, bottom: bottomReserve(context)),
        itemCount: _rows.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(children: [
              if (_podium.isNotEmpty) RankingPodium(items: _podium, onItemPress: isTeam ? null : _onPlayerPress),
              RankingSectionLabel(text: label),
            ]);
          }
          final item = _rows[i - 1];
          return RankingListRow(
            key: ValueKey('ranking_row_${item.id}'),
            item: item,
            isTeam: isTeam,
            onPress: () => _onPlayerPress(item),
          );
        },
      ),
    );
  }
}
