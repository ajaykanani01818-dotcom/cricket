import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/net_image.dart';
import '../ads/ads.dart';
import '../matches/feature_states.dart';
import '../matches/match_row.dart';
import '../matches/matches_tab_panel.dart' show SeriesHeaderDelegate;
import 'series_models.dart';

/// Series hub tabs: Fixtures, Points table, Squads, Stats. All lazy
/// (builder lists / slivers) and fed with parsed models.

typedef PlayerTap = void Function(String? key, JsonMap json);

/// Max content width of a tab on tablets and desktop.
const kSeriesTabMaxWidth = 760.0;

double _side(double width) => width > kSeriesTabMaxWidth ? (width - kSeriesTabMaxWidth) / 2 : 0;

bool _isAdSlot(int index) => index > 0 && index % kSeriesNativeAdInterval == 0;

Widget _nativeAd(String key) => KeyedSubtree(
  key: ValueKey(key),
  child: const ListNativeAd(placement: 'series_detail'),
);

/// Scrollable message (keeps pull-to-refresh working on empty tabs).
class _MessagePage extends StatelessWidget {
  const _MessagePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(physics: const AlwaysScrollableScrollPhysics(), children: [child]);
}

// ───────────────────────── Fixtures ─────────────────────────

class FixturesList extends StatelessWidget {
  const FixturesList({super.key, required this.data, required this.onMatch, required this.onRefresh});
  final Object? data;
  final ValueChanged<String> onMatch;
  final VoidCallback onRefresh;

  static String _rowKey(MatchSummary m, int i) => J.text(m.raw['_id']) ?? (m.id.isNotEmpty ? m.id : 'fixture-$i');

  @override
  Widget build(BuildContext context) {
    final f = data is SeriesFixturesData ? data as SeriesFixturesData : const SeriesFixturesData([]);
    if (f.matches.isEmpty) {
      return _MessagePage(
        key: const ValueKey('series_fixtures_empty'),
        child: StateMessage(
          icon: Icons.event_outlined,
          title: 'No fixtures published yet',
          body: 'Matches appear here once the schedule is announced. Pull down to check again.',
          actionLabel: 'Refresh',
          actionKey: const ValueKey('series_fixtures_refresh'),
          onAction: onRefresh,
        ),
      );
    }
    final sections = [
      ('live', 'Live now', f.live),
      ('upcoming', 'Upcoming', f.upcoming),
      ('results', 'Results', f.results),
    ].where((s) => s.$3.isNotEmpty).toList();
    final scaler = MediaQuery.textScalerOf(context);
    final offsets = <int>[];
    var total = 0;
    for (final s in sections) {
      offsets.add(total);
      total += s.$3.length;
    }
    Widget row(MatchSummary m, int i) {
      final rowKey = _rowKey(m, i);
      final r = MatchRow(
        key: ValueKey('series_fixture_$rowKey'),
        data: MatchRowData.fromSummary(m),
        onTap: m.id.isEmpty ? null : () => onMatch(m.id),
      );
      return _isAdSlot(i)
          ? Column(key: ValueKey('series_fixture_row_$rowKey'), children: [_nativeAd('series_fixture_ad_$i'), r])
          : KeyedSubtree(key: ValueKey('series_fixture_row_$rowKey'), child: r);
    }

    return LayoutBuilder(
      builder: (context, box) {
        final side = _side(box.maxWidth);
        return CustomScrollView(
          key: const ValueKey('series_fixtures_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, Spacing.lg),
              sliver: SliverMainAxisGroup(
                slivers: [
                  for (var si = 0; si < sections.length; si++)
                    SliverMainAxisGroup(
                      key: ValueKey('series_fixtures_${sections[si].$1}'),
                      slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: SeriesHeaderDelegate(title: sections[si].$2, count: sections[si].$3.length, scaler: scaler),
                        ),
                        SliverList.builder(
                          itemCount: sections[si].$3.length,
                          itemBuilder: (_, i) => row(sections[si].$3[i], offsets[si] + i),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Points table ─────────────────────────

class PointsTableList extends StatefulWidget {
  const PointsTableList({super.key, required this.data, required this.onShowFixtures});
  final Object? data;
  final VoidCallback onShowFixtures;

  @override
  State<PointsTableList> createState() => _PointsTableListState();
}

class _PointsTableListState extends State<PointsTableList> {
  /// `group/teamKey` of the team whose results are open.
  String? _open;

  @override
  Widget build(BuildContext context) {
    final groups = widget.data is List<PointsGroup> ? widget.data as List<PointsGroup> : const <PointsGroup>[];
    if (groups.isEmpty) {
      return _MessagePage(
        key: const ValueKey('series_points_empty'),
        child: StateMessage(
          icon: Icons.table_rows_outlined,
          title: 'No points table for this series',
          body: 'Standings appear here when they are published. Bilateral series usually have none.',
          actionLabel: 'See fixtures',
          actionKey: const ValueKey('series_points_see_fixtures'),
          onAction: widget.onShowFixtures,
        ),
      );
    }
    final hasMarkers = groups.any((g) => g.rows.any((r) => r.marker != null));
    return LayoutBuilder(
      builder: (context, box) {
        final side = _side(box.maxWidth);
        return ListView.builder(
          key: const ValueKey('series_points_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, 0, side, Spacing.lg),
          itemCount: groups.length + 1,
          itemBuilder: (context, i) {
            if (i == groups.length) return _Footnote(hasMarkers: hasMarkers);
            final g = groups[i];
            return Column(
              key: ValueKey('series_points_group_$i'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isAdSlot(i)) _nativeAd('series_points_ad_$i'),
                PointsTable(
                  group: g,
                  showTitle: groups.length > 1 || (g.name.isNotEmpty && g.name.toLowerCase() != 'group'),
                  openKey: _open?.startsWith('$i/') == true ? _open!.substring('$i/'.length) : null,
                  onToggle: (key) => setState(() => _open = _open == '$i/$key' ? null : '$i/$key'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.hasMarkers});
  final bool hasMarkers;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
    child: Text(
      [
        'Standings as published by the data provider. Tap a team to see its results.',
        if (hasMarkers) 'Q qualified, E eliminated.',
      ].join(' '),
      style: AppText.meta,
    ),
  );
}

/// One standings group: P W L T NR Pts NRR (+ form), tabular figures,
/// scrolls horizontally when the screen is narrower than the table.
class PointsTable extends StatelessWidget {
  const PointsTable({super.key, required this.group, required this.showTitle, required this.openKey, required this.onToggle});
  final PointsGroup group;
  final bool showTitle;
  final String? openKey;
  final ValueChanged<String> onToggle;

  static const _cols = ['P', 'W', 'L', 'T', 'NR', 'Pts'];
  static const _colNames = ['Played', 'Won', 'Lost', 'Tied', 'No result', 'Points'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final k = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.2);
    final wPos = 30 * k, wTeam = 92 * k, wNum = 34 * k, wNrr = 64 * k, wForm = (18 * k + 5) * 5 + 16;
    final hasForm = group.rows.any((r) => r.form.isNotEmpty);
    final tableWidth = Spacing.lg * 2 + wPos + wTeam + wNum * _cols.length + wNrr + (hasForm ? wForm : 0);

    final head = AppFont.style(size: 12, weight: FontWeight.w700, color: p.inkMuted, tabularFigures: true, height: 1.25);
    final cell = AppFont.style(size: 14, weight: FontWeight.w500, color: p.ink, tabularFigures: true, height: 1.25);
    final bold = AppFont.withWeight(cell, FontWeight.w800);

    Widget num(String v, double w, {TextStyle? style, TextAlign align = TextAlign.center}) => SizedBox(
      width: w,
      child: Text(v, textAlign: align, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style ?? cell),
    );

    final header = Container(
      color: p.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
      child: Row(
        children: [
          num('#', wPos, style: head, align: TextAlign.left),
          SizedBox(
            width: wTeam,
            child: Text('Team', maxLines: 1, style: head),
          ),
          for (var c = 0; c < _cols.length; c++)
            Semantics(
              label: _colNames[c],
              excludeSemantics: true,
              child: num(_cols[c], wNum, style: head),
            ),
          Semantics(
            label: 'Net run rate',
            excludeSemantics: true,
            child: num('NRR', wNrr, style: head, align: TextAlign.right),
          ),
          if (hasForm)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SizedBox(
                width: wForm - 16,
                child: Text('Form', style: head),
              ),
            ),
        ],
      ),
    );

    Widget row(PointsRow r) {
      final open = openKey == r.key && r.key.isNotEmpty;
      final label =
          '${r.position}, ${r.shortName}${r.marker == 'Q'
              ? ', qualified'
              : r.marker == 'E'
              ? ', eliminated'
              : ''}, '
          'played ${r.matches}, won ${r.won}, lost ${r.lost}, tied ${r.tied}, no result ${r.noResult}, '
          '${r.points} points, net run rate ${r.nrr}${r.form.isEmpty ? '' : ', last results ${r.form.join(' ')}'}';
      return Semantics(
        button: r.results.isNotEmpty,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('series_points_row_${r.shortName}'),
          onTap: r.results.isEmpty || r.key.isEmpty ? null : () => onToggle(r.key),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 6),
            decoration: BoxDecoration(
              color: open ? p.brandTint : p.surface,
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                num(
                  '${r.position}',
                  wPos,
                  style: AppFont.withWeight(cell, FontWeight.w600).copyWith(color: p.inkMuted),
                  align: TextAlign.left,
                ),
                SizedBox(
                  width: wTeam,
                  child: Row(
                    children: [
                      TeamLogo(url: r.logo, name: r.shortName, size: 22),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          r.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.withWeight(cell, FontWeight.w700),
                        ),
                      ),
                      if (r.marker != null) ...[const SizedBox(width: 4), _Marker(r.marker!)],
                    ],
                  ),
                ),
                num(r.matches, wNum),
                num(r.won, wNum),
                num(r.lost, wNum),
                num(r.tied, wNum),
                num(r.noResult, wNum),
                num(r.points, wNum, style: bold),
                num(r.nrr, wNrr, align: TextAlign.right),
                if (hasForm)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: SizedBox(
                      width: wForm - 16,
                      child: Row(children: [for (final o in r.form) _FormBox(o, size: 18 * k)]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final openRow = openKey == null ? null : group.rows.where((r) => r.key == openKey).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
            child: Text(group.name.isEmpty ? 'Standings' : group.name, style: AppText.sectionTitle),
          )
        else
          const SizedBox(height: Spacing.md),
        LayoutBuilder(
          builder: (context, box) {
            final w = tableWidth > box.maxWidth ? tableWidth : box.maxWidth;
            return SingleChildScrollView(
              key: ValueKey('series_points_scroll_${group.name}'),
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: w,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, for (final r in group.rows) row(r)]),
              ),
            );
          },
        ),
        if (openRow != null) _TeamResults(row: openRow, onClose: () => onToggle(openRow.key)),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        border: Border.all(color: p.ink),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        text,
        style: AppFont.style(size: 11, weight: FontWeight.w800, color: p.ink, height: 1.2),
      ),
    );
  }
}

/// W / L letter in a small square: the letter is the cue, colour reinforces it.
class _FormBox extends StatelessWidget {
  const _FormBox(this.outcome, {required this.size});
  final String outcome;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final win = outcome == 'W';
    return Container(
      width: size + 2,
      height: size + 2,
      margin: const EdgeInsets.only(right: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: win ? p.positiveTint : p.negativeTint, borderRadius: BorderRadius.circular(Radii.xs)),
      child: Text(
        outcome,
        style: AppFont.style(size: 11, weight: FontWeight.w800, color: win ? p.positive : p.negative, height: 1),
      ),
    );
  }
}

/// The tapped team's results (provider `teamMatches`): opponent, W/L, margin.
class _TeamResults extends StatelessWidget {
  const _TeamResults({required this.row, required this.onClose});
  final PointsRow row;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: ValueKey('series_points_results_${row.key}'),
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.sm, Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('${row.shortName} matches', style: AppFont.withWeight(AppText.name, FontWeight.w700))),
              TextButton(key: const ValueKey('series_points_results_close'), onPressed: onClose, child: const Text('Close')),
            ],
          ),
          for (final r in row.results)
            Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.hairline)),
              ),
              child: Row(
                children: [
                  if (r.outcome != null)
                    _FormBox(r.outcome!, size: 18)
                  else
                    SizedBox(width: 23, child: Text(kNotAvailable, style: AppText.meta)),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      [
                        'v ${r.opponent}',
                        if (r.outcome == null)
                          'yet to play'
                        else if (r.margin != null)
                          r.outcome == 'W' ? 'won by ${r.margin}' : 'lost by ${r.margin}',
                      ].join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.reading.copyWith(fontSize: 14),
                    ),
                  ),
                  if (r.date != null) ...[
                    const SizedBox(width: Spacing.sm),
                    Text(DateFormat('d MMM', 'en_US').format(r.date!), style: AppText.meta),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Stats ─────────────────────────

class StatsList extends StatefulWidget {
  const StatsList({super.key, required this.data, required this.onPlayer, required this.onShowFixtures});
  final Object? data;
  final PlayerTap onPlayer;
  final VoidCallback onShowFixtures;

  @override
  State<StatsList> createState() => _StatsListState();
}

class _StatsListState extends State<StatsList> {
  int _format = 0;
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stats = widget.data is SeriesStatsData ? widget.data as SeriesStatsData : const SeriesStatsData(hasData: false);
    if (stats.comingSoon || !stats.hasData || stats.formats.isEmpty) {
      final soon = stats.comingSoon || !stats.hasData;
      return _MessagePage(
        child: KeyedSubtree(
          key: ValueKey(soon ? 'series_stats_coming_soon' : 'series_stats_empty'),
          child: StateMessage(
            icon: Icons.leaderboard_outlined,
            title: soon ? "Stats aren't published for this series yet" : 'No stats for this series yet',
            body: soon
                ? 'Leaderboards appear here once they are published, usually after the first few matches.'
                : 'Leaderboards fill in as matches are played.',
            actionLabel: 'See fixtures',
            actionKey: const ValueKey('series_stats_see_fixtures'),
            onAction: widget.onShowFixtures,
          ),
        ),
      );
    }
    final fi = _format.clamp(0, stats.formats.length - 1);
    final fmt = stats.formats[fi];
    final rows = <Widget>[
      if (stats.formats.length > 1)
        SingleChildScrollView(
          key: const ValueKey('series_stats_formats'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
          child: Row(
            children: [
              for (var i = 0; i < stats.formats.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    key: ValueKey('series_stats_format_${stats.formats[i].format}'),
                    label: Text(stats.formats[i].format),
                    selected: i == fi,
                    showCheckmark: false,
                    selectedColor: p.brandTint,
                    side: BorderSide(color: i == fi ? p.brand : p.hairline),
                    onSelected: (_) => setState(() => _format = i),
                  ),
                ),
            ],
          ),
        ),
      for (var c = 0; c < fmt.categories.length; c++) ...[
        if (_isAdSlot(c)) _nativeAd('series_stats_ad_$c'),
        _LeaderBlock(
          key: ValueKey('series_stats_card_${fmt.format}_${fmt.categories[c].key}'),
          category: fmt.categories[c],
          expanded: _expanded.contains('${fmt.format}/${fmt.categories[c].key}'),
          onToggle: () => setState(() {
            final k = '${fmt.format}/${fmt.categories[c].key}';
            if (!_expanded.remove(k)) _expanded.add(k);
          }),
          onPlayer: widget.onPlayer,
        ),
      ],
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final side = _side(box.maxWidth);
        return ListView.builder(
          key: const ValueKey('series_stats_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, 0, side, Spacing.lg),
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i],
        );
      },
    );
  }
}

/// One leaderboard: title, top 3 (or all 10 when expanded).
class _LeaderBlock extends StatelessWidget {
  const _LeaderBlock({super.key, required this.category, required this.expanded, required this.onToggle, required this.onPlayer});
  final StatCategory category;
  final bool expanded;
  final VoidCallback onToggle;
  final PlayerTap onPlayer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = category.entries;
    final shown = expanded ? all : all.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.sm),
          child: Semantics(header: true, child: Text(category.title, style: AppText.sectionTitle)),
        ),
        for (final e in shown) _LeaderRow(entry: e, category: category, onPlayer: onPlayer),
        if (all.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: Spacing.xs),
              child: TextButton(
                key: ValueKey('series_stats_more_${category.key}'),
                onPressed: onToggle,
                style: TextButton.styleFrom(foregroundColor: p.brandText),
                child: Text(expanded ? 'Show top 3' : 'Show all ${all.length}'),
              ),
            ),
          ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry, required this.category, required this.onPlayer});
  final StatEntry entry;
  final StatCategory category;
  final PlayerTap onPlayer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = entry.rank == 1;
    final tappable = entry.playerKey != null;
    final team = entry.team.isNotEmpty ? entry.team : null;
    return Semantics(
      button: tappable,
      label: 'Rank ${entry.rank}, ${entry.name}${team == null ? '' : ', $team'}, ${entry.value} ${category.unit}',
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        child: InkWell(
          key: ValueKey('series_stat_${category.key}_${entry.rank}_${entry.playerKey ?? ''}'),
          onTap: tappable ? () => onPlayer(entry.playerKey, entry.toPlayerJson()) : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${entry.rank}',
                    style: AppFont.style(
                      size: first ? 20 : 15,
                      weight: FontWeight.w800,
                      width: AppFont.scoreWidth,
                      tabularFigures: true,
                      color: first ? p.ink : p.inkMuted,
                    ),
                  ),
                ),
                NetImage(url: entry.logo, size: 34, fallbackLetter: entry.name, fit: BoxFit.cover),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.name),
                      if (team != null) Text(team, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.value, style: AppText.scoreRow),
                    if (category.unit.isNotEmpty) Text(category.unit, style: AppText.small),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Squads ─────────────────────────

/// Team squads, one open at a time. Flattened into one lazy list (team
/// header rows + the open team's player rows).
class SquadsList extends StatefulWidget {
  const SquadsList({super.key, required this.data, required this.onPlayer});
  final Object? data;
  final PlayerTap onPlayer;

  @override
  State<SquadsList> createState() => _SquadsListState();
}

class _SquadsListState extends State<SquadsList> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final teams = widget.data is List<SquadTeam> ? widget.data as List<SquadTeam> : const <SquadTeam>[];
    if (teams.isEmpty) {
      return const _MessagePage(
        key: ValueKey('series_squads_empty'),
        child: StateMessage(
          icon: Icons.groups_outlined,
          title: "Squads aren't announced yet",
          body: 'Team squads appear here once they are named. Pull down to check again.',
        ),
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < teams.length; i++) {
      final t = teams[i];
      final open = _expanded == t.key;
      if (_isAdSlot(i)) rows.add(_nativeAd('series_squad_ad_$i'));
      rows.add(_teamHeader(t, open));
      if (open) {
        for (var p = 0; p < t.players.length; p++) {
          rows.add(_playerRow(t, p));
        }
      }
    }
    return LayoutBuilder(
      builder: (context, box) {
        final side = _side(box.maxWidth);
        return ListView.builder(
          key: const ValueKey('series_squads_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, Spacing.md, side, Spacing.lg),
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i],
        );
      },
    );
  }

  Widget _teamHeader(SquadTeam team, bool open) {
    final p = context.palette;
    final count = team.players.length;
    return Semantics(
      button: true,
      expanded: open,
      label: '${team.name}, $count ${count == 1 ? 'player' : 'players'}',
      excludeSemantics: true,
      child: Material(
        color: open ? p.surfaceAlt : p.surface,
        child: InkWell(
          key: ValueKey('series_squad_team_${team.key}'),
          onTap: () => setState(() => _expanded = open ? null : team.key),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                TeamLogo(url: team.logo, name: team.name, size: 32),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        team.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.withWeight(AppText.name, FontWeight.w700),
                      ),
                      Text('$count ${count == 1 ? 'player' : 'players'}', style: AppText.meta),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: p.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerRow(SquadTeam team, int i) {
    final p = context.palette;
    final player = team.players[i];
    final tags = {'C': 'captain', 'WK': 'wicketkeeper', 'XI': 'in the playing XI'};
    return Semantics(
      button: player.key != null,
      label: [player.name, if (player.role.isNotEmpty) player.role, for (final t in player.tags) tags[t] ?? t].join(', '),
      excludeSemantics: true,
      child: Material(
        key: ValueKey('series_squad_player_${team.key}_$i'),
        color: p.surface,
        child: InkWell(
          onTap: player.key == null ? null : () => widget.onPlayer(player.key, player.toPlayerJson()),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(Spacing.xxl, Spacing.sm, Spacing.lg, Spacing.sm),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline)),
            ),
            child: Row(
              children: [
                NetImage(url: player.logo, size: 30, fallbackLetter: player.name, fit: BoxFit.cover),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(player.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.name),
                      if (player.role.isNotEmpty) Text(player.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta),
                    ],
                  ),
                ),
                for (final t in player.tags)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: p.hairline),
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Text(
                      t,
                      style: AppFont.style(size: 12, weight: FontWeight.w700, color: p.ink, height: 1.2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
