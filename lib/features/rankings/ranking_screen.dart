import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../discover/discover_cache.dart';
import '../players/widgets/player_widgets.dart';
import 'ranking_models.dart';
import 'widgets/ranking_widgets.dart';

/// ICC rankings for one selection, cached (shared with the Discover hub).
/// `gender` and `matchType` are always sent: the API rejects calls without
/// them.
Future<List<RankingRowItem>> loadRankings(
  RankKind kind, {
  required String format,
  required String gender,
  bool force = false,
}) => DiscoverCache.get('rank:${kind.name}:$format:$gender', () async {
  final svc = RankingService.instance;
  if (kind.isTeam) {
    return parseTeamRankings(
      (await svc.getTeamRankings(gender: gender, matchType: format)).data,
    );
  }
  return parsePlayerRankings(
    (await svc.getPlayerRankings(
      gender: gender,
      matchType: format,
      type: kind.apiType!,
    )).data,
  );
}, force: force);

/// Rankings: Teams / Batting / Bowling / All-rounders × Test / ODI / T20 ×
/// Men / Women in one control block, then the top three as larger rows and
/// a dense table for ranks 4–100. No movement arrows: the API has no
/// previous rank.
///
/// Rapid toggling: the selection applies at once, the request fires after
/// [switchDelay] (only the last selection is fetched), identical in-flight
/// requests are shared and responses for an older selection are ignored.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  static const switchDelay = Duration(milliseconds: 120);

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  RankKind _kind = RankKind.teams;
  String _format = 'TEST';
  String _gender = 'MALE';

  List<RankingRowItem> _list = const [];
  bool _listIsTeam = true;
  List<RankingRowItem> _leaders = const [];
  List<RankingRowItem> _rows = const [];
  int _filteredCount = 0;

  bool _loading = true;
  String? _error;
  int _gen = 0;
  Timer? _switchTimer;
  bool _navigating = false;

  final _search = TextEditingController();
  String _query = '';

  bool get _searching => !_kind.isTeam && _query.trim().isNotEmpty;

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
    final filtered = _kind.isTeam ? _list : filterRankings(_list, _query);
    final split = splitForDisplay(filtered, searching: _searching);
    _filteredCount = filtered.length;
    _leaders = split.leaders;
    _rows = split.rows;
  }

  /// [force] bypasses the cache (pull-to-refresh / retry). [silent] keeps
  /// the current list on screen while loading.
  Future<void> _load({bool force = false, bool silent = false}) async {
    final gen = ++_gen;
    final kind = _kind;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await loadRankings(
        kind,
        format: _format,
        gender: _gender,
        force: force,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _list = items;
        _listIsTeam = kind.isTeam;
        _error = null;
        _loading = false;
        _derive();
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      if (silent && _list.isNotEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text("Rankings didn't refresh. ${friendlyError(e)}"),
          ),
        );
      } else {
        setState(() => _error = friendlyError(e));
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeSelection(VoidCallback apply) {
    setState(() {
      apply();
      _loading = true;
      _error = null;
    });
    // Invalidate any in-flight response for the previous selection now.
    _gen++;
    _switchTimer?.cancel();
    _switchTimer = Timer(RankingScreen.switchDelay, () {
      if (mounted) _load();
    });
  }

  void _onSearch(String v) => setState(() {
    _query = v;
    _derive();
  });

  void _clearSearch() {
    _search.clear();
    _onSearch('');
  }

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
      color: context.palette.canvas,
      child: Column(
        children: [
          const ScreenTitle(title: 'Rankings'),
          const ScreenBannerSlots(screen: 'ranking', onlyPosition: 'top'),
          _controls(),
          Expanded(child: _content()),
          const FixedBottomBanner(screen: 'ranking'),
        ],
      ),
    );
  }

  Widget _controls() {
    final p = context.palette;
    final ts = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      key: const ValueKey('rankings_controls'),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Capped(
        child: LayoutBuilder(
          builder: (context, c) {
            final narrowTabs = c.maxWidth < 440 * ts;
            final stack = c.maxWidth < 380 * ts;
            final format = SegmentedControl<String>(
              key: const ValueKey('rankings_format'),
              compact: true,
              options: [
                for (final o in kFormatOptions) SegmentOption(o.$1, o.$2),
              ],
              value: _format,
              onChanged: (v) {
                if (v != _format) _changeSelection(() => _format = v);
              },
            );
            final gender = SegmentedControl<String>(
              key: const ValueKey('rankings_gender'),
              compact: true,
              options: [
                for (final o in kGenderOptions) SegmentOption(o.$1, o.$2),
              ],
              value: _gender,
              onChanged: (v) {
                if (v != _gender) _changeSelection(() => _gender = v);
              },
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTabs(
                  key: const ValueKey('rankings_kind'),
                  scrollable: narrowTabs,
                  tabs: [
                    for (final k in RankKind.values)
                      SectionTabItem(k.name, k.label),
                  ],
                  activeKey: _kind.name,
                  onSelect: (v) {
                    final k = RankKind.values.byName(v);
                    if (k != _kind) _changeSelection(() => _kind = k);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.md,
                    Spacing.lg,
                    Spacing.md,
                  ),
                  child: stack
                      ? Column(
                          children: [
                            format,
                            const SizedBox(height: Spacing.sm),
                            gender,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(flex: 3, child: format),
                            const SizedBox(width: Spacing.sm),
                            Expanded(flex: 2, child: gender),
                          ],
                        ),
                ),
                if (!_kind.isTeam)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      0,
                      Spacing.lg,
                      Spacing.md,
                    ),
                    child: _searchField(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _searchField() {
    final p = context.palette;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
      borderSide: BorderSide(color: p.hairline),
    );
    return TextField(
      key: const ValueKey('rankings_search'),
      controller: _search,
      onChanged: _onSearch,
      textInputAction: TextInputAction.search,
      style: AppText.reading,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: p.surfaceAlt,
        hintText: 'Find a player in this list',
        hintStyle: AppText.reading.copyWith(color: p.inkMuted),
        prefixIcon: Icon(Icons.search, size: 20, color: p.inkMuted),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('rankings_search_clear'),
                tooltip: 'Clear search',
                onPressed: _clearSearch,
                icon: Icon(Icons.close, size: 20, color: p.inkMuted),
              ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: Spacing.md,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: p.ink, width: 1.5),
        ),
      ),
    );
  }

  Widget _centered(Widget child) => RefreshIndicator(
    color: context.palette.brandText,
    onRefresh: () => _load(force: true, silent: true),
    child: LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: child),
        ),
      ),
    ),
  );

  Widget _content() {
    if (_loading) {
      return const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Capped(child: RankingSkeleton()),
      );
    }
    if (_error != null) {
      return _centered(
        ErrorRetry(
          key: const ValueKey('rankings_error'),
          title: "Rankings didn't load",
          message: _error!,
          onRetry: () => _load(force: true),
        ),
      );
    }
    final title = selectionTitle(_kind, _format, _gender);
    if (_filteredCount == 0) {
      final q = _searching ? _query.trim() : '';
      return _centered(
        q.isNotEmpty
            ? EmptyState(
                key: const ValueKey('rankings_empty'),
                icon: Icons.person_search_outlined,
                title: 'No player named "$q" in this list',
                subtitle:
                    'Check the spelling, or clear the search to see everyone.',
                actionLabel: 'Clear search',
                onAction: _clearSearch,
              )
            : EmptyState(
                key: const ValueKey('rankings_empty'),
                icon: Icons.leaderboard_outlined,
                title: 'No $title rankings published',
                subtitle:
                    'Pick another format, or switch between men and women above.',
              ),
      );
    }

    final isTeam = _listIsTeam;
    final noun = isTeam ? 'team' : 'player';
    final label = _searching
        ? '$_filteredCount ${_filteredCount == 1 ? 'result' : 'results'}'
        : 'Ranks 4 to ${_filteredCount < 100 ? _filteredCount : 100}';
    // Items: [heading, leaders?, table header?, rows...]
    final hasLeaders = _leaders.isNotEmpty;
    final hasTable = _rows.isNotEmpty;
    final head = 1 + (hasLeaders ? 1 : 0) + (hasTable ? 1 : 0);
    return RefreshIndicator(
      color: context.palette.brandText,
      onRefresh: () => _load(force: true, silent: true),
      child: ListView.builder(
        key: const ValueKey('rankings_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Spacing.xxl),
        itemCount: head + _rows.length,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Capped(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        '$title rankings',
                        key: const ValueKey('rankings_title'),
                        style: AppText.sectionTitle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_list.length} ${_list.length == 1 ? noun : '${noun}s'} ranked by the ICC',
                      style: AppText.meta,
                    ),
                  ],
                ),
              ),
            );
          }
          if (hasLeaders && i == 1) {
            return Capped(
              child: RankingLeaders(
                items: _leaders,
                isTeam: isTeam,
                onItemPress: isTeam ? null : _onPlayerPress,
              ),
            );
          }
          if (hasTable && i == head - 1) {
            return Capped(
              child: RankingTableHeader(isTeam: isTeam, label: label),
            );
          }
          final r = i - head;
          final item = _rows[r];
          return Capped(
            child: Column(
              children: [
                if (r > 0) const RowDivider(indent: Spacing.lg),
                RankingListRow(
                  key: ValueKey('ranking_row_${item.id}'),
                  item: item,
                  isTeam: isTeam,
                  onPress: () => _onPlayerPress(item),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
