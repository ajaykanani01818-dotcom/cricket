import 'package:flutter/material.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/net_image.dart';
import '../ads/ads.dart';
import 'series_fixture_card.dart';
import 'series_models.dart';

/// Sub-views of Series Detail (RN FixturesView / PointsTableView / StatsView /
/// SquadsView). All are lazy (builder lists / slivers) and take parsed models.

typedef PlayerTap = void Function(String? key, JsonMap json);

bool _isAdSlot(int index) => index > 0 && index % kSeriesNativeAdInterval == 0;

Widget _nativeAd(String key) => KeyedSubtree(key: ValueKey(key), child: const ListNativeAd(placement: 'series_detail'));

/// Scrollable centered message (keeps pull-to-refresh working on empty pages).
class _EmptyPage extends StatelessWidget {
  const _EmptyPage({required this.text, required this.padding, this.child});
  final String text;
  final EdgeInsets padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          child ??
              Padding(
                padding: const EdgeInsets.all(Spacing.xxl),
                child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
              ),
        ],
      );
}

/// RN errorWrap + retryBtn.
class SeriesDetailError extends StatelessWidget {
  const SeriesDetailError({super.key, required this.message, required this.onRetry, required this.padding});
  final String message;
  final VoidCallback onRetry;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ListView(padding: padding, children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.error)),
            const SizedBox(height: Spacing.md),
            FilledButton(
              key: const ValueKey('series_detail_retry'),
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.pitch,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
              ),
              child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.white)),
            ),
          ]),
        ),
      ]);
}

// ───────────────────────── Fixtures ─────────────────────────

class FixturesList extends StatelessWidget {
  const FixturesList({super.key, required this.data, required this.padding, required this.onMatch});
  final Object? data;
  final EdgeInsets padding;
  final ValueChanged<String> onMatch;

  @override
  Widget build(BuildContext context) {
    final fixtures = data is List<SeriesFixture> ? data as List<SeriesFixture> : const <SeriesFixture>[];
    if (fixtures.isEmpty) return _EmptyPage(text: 'No fixtures available', padding: padding);
    return ListView.builder(
      key: const ValueKey('series_fixtures_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: fixtures.length,
      itemBuilder: (_, i) {
        final f = fixtures[i];
        return Padding(
          key: ValueKey('series_fixture_row_${f.listKey}'),
          padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.md),
          child: Column(children: [
            if (_isAdSlot(i)) ...[_nativeAd('series_fixture_ad_$i'), const SizedBox(height: Spacing.md)],
            SeriesFixtureCard(fixture: f, onOpen: () => onMatch(f.matchId)),
          ]),
        );
      },
    );
  }
}

// ───────────────────────── Points table ─────────────────────────

class PointsTableList extends StatelessWidget {
  const PointsTableList({super.key, required this.data, required this.padding});
  final Object? data;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final groups = data is List<PointsGroup> ? data as List<PointsGroup> : const <PointsGroup>[];
    if (groups.isEmpty) return _EmptyPage(text: 'No points table available', padding: padding);
    // Each group is one lazily-built item; its rows share one horizontal scroll.
    return ListView.builder(
      key: const ValueKey('series_points_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: groups.length,
      itemBuilder: (_, i) => Padding(
        key: ValueKey('series_points_group_$i'),
        padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.lg),
        child: Column(children: [
          if (_isAdSlot(i)) ...[_nativeAd('series_points_ad_$i'), const SizedBox(height: Spacing.lg)],
          _PointsCard(group: groups[i]),
        ]),
      ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.group});
  final PointsGroup group;

  static const _cell = TextStyle(fontSize: 12, color: AppColors.text);
  static const _head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.tableHeaderText);

  Widget _num(String v, {double w = 36, TextStyle style = _cell, TextAlign align = TextAlign.center}) =>
      SizedBox(width: w, child: Text(v, textAlign: align, maxLines: 1, style: style));

  @override
  Widget build(BuildContext context) {
    final headerRow = Container(
      color: AppColors.tableHeaderBg,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        const SizedBox(width: 120, child: Text('Team', style: _head)),
        for (final h in const ['P', 'W', 'L', 'T', 'NR', 'Pts']) _num(h, style: _head),
        _num('NRR', w: 52, style: _head, align: TextAlign.right),
      ]),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: AppColors.tableHeaderBg,
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.tableHeaderText)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                headerRow,
                for (var i = 0; i < group.rows.length; i++) _row(group.rows[i], i),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _row(PointsRow t, int i) => Container(
        decoration: BoxDecoration(
          color: i.isEven ? AppColors.white : AppColors.surfaceFaint,
          border: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 120,
            child: Row(children: [
              if (t.logo != null) ...[
                NetImage(url: t.logo, size: 28, radius: 0, fallbackLetter: t.shortName, background: Colors.transparent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(t.shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ]),
          ),
          _num(t.matches),
          _num(t.won, style: const TextStyle(fontSize: 12, color: AppColors.win, fontWeight: FontWeight.w600)),
          _num(t.lost, style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600)),
          _num(t.tied),
          _num(t.noResult),
          _num(t.points, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text)),
          _num(t.nrr, w: 52, align: TextAlign.right),
        ]),
      );
}

// ───────────────────────── Stats ─────────────────────────

sealed class _StatsRow {}

class _FormatHeader extends _StatsRow {
  _FormatHeader(this.format, this.first);
  final String format;
  final bool first;
}

class _CardRow extends _StatsRow {
  _CardRow(this.category, this.cardIndex, this.formatKey);
  final StatCategory category;
  final int cardIndex; // 1-based, across all formats (RN cardIndex)
  final String formatKey;
}

class StatsList extends StatelessWidget {
  const StatsList({super.key, required this.data, required this.padding, required this.onPlayer});
  final Object? data;
  final EdgeInsets padding;
  final PlayerTap onPlayer;

  @override
  Widget build(BuildContext context) {
    final stats = data is SeriesStatsData ? data as SeriesStatsData : const SeriesStatsData(hasData: false);
    if (stats.comingSoon) {
      return _EmptyPage(text: '', padding: padding, child: const _ComingSoonCard());
    }
    if (!stats.hasData) return _EmptyPage(text: 'No stats available', padding: padding);
    if (stats.formats.isEmpty) return _EmptyPage(text: 'No stats for this series yet', padding: padding);

    final rows = <_StatsRow>[];
    var cardIndex = 0;
    for (var f = 0; f < stats.formats.length; f++) {
      final fmt = stats.formats[f];
      rows.add(_FormatHeader(fmt.format, f == 0));
      for (final cat in fmt.categories) {
        rows.add(_CardRow(cat, ++cardIndex, fmt.format));
      }
    }

    return ListView.builder(
      key: const ValueKey('series_stats_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding.copyWith(bottom: padding.bottom + Spacing.lg),
      itemCount: rows.length,
      itemBuilder: (_, i) => switch (rows[i]) {
        _FormatHeader(:final format, :final first) => Padding(
            key: ValueKey('series_stats_format_$format'),
            padding: EdgeInsets.only(top: first ? 0 : Spacing.xl, bottom: Spacing.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(format.toUpperCase(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)),
              Container(height: 1, color: AppColors.border, margin: const EdgeInsets.only(top: Spacing.xs)),
            ]),
          ),
        _CardRow(:final category, :final cardIndex, :final formatKey) => Padding(
            key: ValueKey('series_stats_card_${formatKey}_${category.key}'),
            padding: const EdgeInsets.only(top: 14),
            child: Column(children: [
              if (cardIndex > 1 && (cardIndex - 1) % kSeriesNativeAdInterval == 0) ...[
                _nativeAd('series_stats_ad_$cardIndex'),
                const SizedBox(height: 14),
              ],
              _StatCard(category: category, onPlayer: onPlayer),
            ]),
          ),
      },
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('series_stats_coming_soon'),
        margin: const EdgeInsets.only(top: Spacing.md),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Container(
            width: 80,
            height: 80,
            margin: const EdgeInsets.only(bottom: Spacing.lg),
            decoration: const BoxDecoration(color: Color(0x180B5CD4), shape: BoxShape.circle),
            child: const Icon(Icons.bar_chart_outlined, size: 48, color: AppColors.pitchDark),
          ),
          const Text('Coming Soon', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.pitch)),
          const SizedBox(height: Spacing.sm),
          const Text(
            'Series stats and leaderboards for this tournament are not available yet. Check back after matches are completed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 21 / 14, fontWeight: FontWeight.w500),
          ),
        ]),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.category, required this.onPlayer});
  final StatCategory category;
  final PlayerTap onPlayer;

  @override
  Widget build(BuildContext context) {
    final entries = category.entries;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.borderNeutral),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: AppColors.tableHeaderBg,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Row(children: [
            const Icon(Icons.military_tech, size: 16, color: AppColors.gold),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(category.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            for (var i = 0; i < entries.length; i++)
              _StatRow(entry: entries[i], isLast: i == entries.length - 1, categoryKey: category.key, onPlayer: onPlayer),
          ]),
        ),
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.entry, required this.isLast, required this.categoryKey, required this.onPlayer});
  final StatEntry entry;
  final bool isLast;
  final String categoryKey;
  final PlayerTap onPlayer;

  @override
  Widget build(BuildContext context) {
    final rank = entry.rank;
    final badge = switch (rank) {
      1 => AppColors.gold,
      2 => AppColors.silver,
      3 => AppColors.bronze,
      _ => AppColors.neutralSurface,
    };
    return InkWell(
      key: ValueKey('series_stat_${categoryKey}_${rank}_${entry.playerKey ?? ''}'),
      onTap: entry.playerKey == null ? null : () => onPlayer(entry.playerKey, entry.toPlayerJson()),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
            child: Text('$rank',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: rank <= 3 ? AppColors.white : AppColors.textSecondary)),
          ),
          const SizedBox(width: 10),
          entry.logo != null
              ? NetImage(url: entry.logo, size: 36, fallbackLetter: entry.name, fit: BoxFit.cover)
              : Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0x250B5CD4), shape: BoxShape.circle),
                  child: Text(entry.name.isEmpty ? '?' : entry.name[0],
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pitch)),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 1),
              Text(entry.team,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(entry.value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)),
        ]),
      ),
    );
  }
}

// ───────────────────────── Squads ─────────────────────────

/// Accordion of team squads (one expanded at a time). Player rows are a lazy
/// SliverList so long squads never build off-screen rows.
class SquadsList extends StatefulWidget {
  const SquadsList({super.key, required this.data, required this.padding, required this.onPlayer});
  final Object? data;
  final EdgeInsets padding;
  final PlayerTap onPlayer;

  @override
  State<SquadsList> createState() => _SquadsListState();
}

class _SquadsListState extends State<SquadsList> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final teams = widget.data is List<SquadTeam> ? widget.data as List<SquadTeam> : const <SquadTeam>[];
    if (teams.isEmpty) return _EmptyPage(text: 'No squads available', padding: widget.padding);
    return CustomScrollView(
      key: const ValueKey('series_squads_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: widget.padding,
          sliver: SliverMainAxisGroup(slivers: [
            for (var i = 0; i < teams.length; i++) ..._teamSlivers(teams[i], i),
          ]),
        ),
      ],
    );
  }

  List<Widget> _teamSlivers(SquadTeam team, int i) {
    final expanded = _expanded == team.key;
    return [
      if (_isAdSlot(i))
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.only(top: Spacing.lg), child: _nativeAd('series_squad_ad_$i')),
        ),
      SliverPadding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.lg),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: AppColors.border),
          ),
          sliver: SliverPadding(
            padding: const EdgeInsets.all(10),
            sliver: SliverMainAxisGroup(slivers: [
              SliverToBoxAdapter(child: _header(team, expanded)),
              if (expanded) ...[
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.only(top: Spacing.xs),
                    padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: 10),
                    decoration: const BoxDecoration(
                      color: AppColors.tableHeaderBg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: const Row(children: [
                      Expanded(flex: 14, child: Text('Player', style: _headCell)),
                      Expanded(flex: 11, child: Text('Role', style: _headCell)),
                      SizedBox(width: 52, child: Text('Tag', textAlign: TextAlign.right, style: _headCell)),
                    ]),
                  ),
                ),
                SliverList.builder(
                  itemCount: team.players.length,
                  itemBuilder: (_, p) => _playerRow(team, p),
                ),
              ],
            ]),
          ),
        ),
      ),
    ];
  }

  static const _headCell = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText);

  Widget _header(SquadTeam team, bool expanded) => Material(
        color: AppColors.tableHeaderBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('series_squad_team_${team.key}'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _expanded = expanded ? null : team.key),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              if (team.logo != null) ...[
                NetImage(url: team.logo, size: 44, radius: 0, fallbackLetter: team.name, background: Colors.transparent),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText)),
                  const SizedBox(height: 2),
                  Text('${team.players.length} players',
                      style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF), fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 10),
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: Color(0x26FFFFFF), shape: BoxShape.circle),
                child: Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: AppColors.tableHeaderText),
              ),
            ]),
          ),
        ),
      );

  Widget _playerRow(SquadTeam team, int p) {
    final player = team.players[p];
    final bg = player.isPlaying
        ? AppColors.winTintSoft
        : p.isOdd
            ? AppColors.surfaceSubtle
            : AppColors.bg;
    final isLast = p == team.players.length - 1;
    return Material(
      key: ValueKey('series_squad_player_${team.key}_$p'),
      color: bg,
      borderRadius: isLast ? const BorderRadius.vertical(bottom: Radius.circular(10)) : null,
      child: InkWell(
        onTap: player.key == null ? null : () => widget.onPlayer(player.key, player.toPlayerJson()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: 10),
          child: Row(children: [
            Expanded(
              flex: 14,
              child: Row(children: [
                player.logo != null
                    ? NetImage(url: player.logo, size: 26, fallbackLetter: player.name, fit: BoxFit.cover)
                    : Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
                        child: Text(player.name.isEmpty ? '?' : player.name[0],
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.white)),
                      ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text)),
                ),
              ]),
            ),
            Expanded(
              flex: 11,
              child: Text(player.role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 52,
              child: Text(player.tag,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: player.isPlaying ? AppColors.live : AppColors.textSecondary,
                    fontWeight: player.isPlaying ? FontWeight.w800 : FontWeight.w600,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}
