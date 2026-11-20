import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/shimmer_box.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import 'player_models.dart';
import 'widgets/player_widgets.dart';

/// Player profile: header facts, ICC ranks, format-wise career tables,
/// debuts, teams and bio. Only what the provider sends is shown; there is no
/// recent-form section because the API has no per-match player data, and no
/// follow button (PRD §12).
///
/// [initialPlayer] is the list item the user tapped (country list, ranking
/// row, trending). It renders the header immediately while
/// `/players/:key/info` loads, and stays on screen when the full profile does
/// not exist yet (API 404) instead of an error page.
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({
    super.key,
    required this.playerKey,
    this.initialPlayer,
  });
  final String playerKey;
  final JsonMap? initialPlayer;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  PlayerProfile? _initial;
  PlayerProfile? _info;
  bool _loading = false;
  Object? _error;
  int _gen = 0;

  String get _key => widget.playerKey.trim().isNotEmpty
      ? widget.playerKey.trim()
      : (_initial?.playerKey ?? '');

  @override
  void initState() {
    super.initState();
    _parseInitial();
    if (_key.isNotEmpty) _fetch();
  }

  void _parseInitial() {
    final ip = widget.initialPlayer;
    _initial = ip == null || ip.isEmpty
        ? null
        : PlayerProfile.fromJson(ip, withDetails: false);
  }

  @override
  void didUpdateWidget(PlayerDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.playerKey != widget.playerKey) {
      _parseInitial();
      _info = null;
      if (_key.isNotEmpty) _fetch();
    }
  }

  @override
  void dispose() {
    AdsManager.instance.recordDetailExit();
    super.dispose();
  }

  Future<void> _fetch() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await PlayerService.instance.getPlayerInfo(_key);
      if (!mounted || gen != _gen) return;
      final data = res.dataMap;
      setState(() {
        if (data.isEmpty) {
          _info = null;
          _error = const ApiException(404, 'Player not found');
        } else {
          _info = PlayerProfile.fromJson(data);
        }
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _info = null;
      });
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  bool get _notFound =>
      _error is ApiException && (_error as ApiException).isNotFound;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.canvas,
      child: Column(
        children: [
          const ScreenTitle(title: 'Player profile'),
          const ScreenBannerSlots(screen: 'player_detail', onlyPosition: 'top'),
          Expanded(child: _body()),
          const FixedBottomBanner(screen: 'player_detail'),
        ],
      ),
    );
  }

  Widget _body() {
    final p = _info ?? _initial;
    if (_key.isEmpty && p == null) {
      return const Center(
        child: SingleChildScrollView(
          child: EmptyState(
            key: ValueKey('player_detail_not_found'),
            icon: Icons.person_off_outlined,
            title: 'Player not found',
            subtitle:
                'This link does not point to a player. Go back and pick one from the list.',
          ),
        ),
      );
    }

    if (p == null) {
      if (_loading || (_error == null && _info == null)) {
        return const SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: Capped(child: PlayerDetailSkeleton()),
        );
      }
      return Center(
        child: SingleChildScrollView(
          child: _notFound
              ? const EmptyState(
                  key: ValueKey('player_detail_not_found'),
                  icon: Icons.person_off_outlined,
                  title: 'No profile for this player yet',
                  subtitle:
                      'The data provider has not published it. Go back and pick another player.',
                )
              : ErrorRetry(
                  key: const ValueKey('player_detail_error'),
                  title: "Profile didn't load",
                  message: friendlyError(_error!),
                  onRetry: _fetch,
                ),
        ),
      );
    }

    final info = _info;
    return ListView(
      key: const ValueKey('player_detail_scroll'),
      padding: const EdgeInsets.only(bottom: Spacing.xxxl),
      children: [
        Capped(child: _Header(player: p)),
        if (info == null)
          if (_loading || _error == null)
            const Capped(child: PlayerDetailSkeleton(showHeader: false))
          else
            Capped(child: _statusBlock())
        else
          ..._details(info).map((w) => Capped(child: w)),
      ],
    );
  }

  /// Under the header when the profile request failed.
  Widget _statusBlock() {
    if (_notFound) {
      return const EmptyState(
        key: ValueKey('player_detail_not_found'),
        icon: Icons.person_search_outlined,
        title: 'Career stats not available yet',
        subtitle:
            'The data provider has not published a full profile for this player. Check back later.',
      );
    }
    return EmptyState(
      key: const ValueKey('player_detail_error'),
      icon: Icons.cloud_off_outlined,
      title: "Career stats didn't load",
      subtitle: friendlyError(_error!),
      hint: 'Check your connection, then try again.',
      actionLabel: 'Try again',
      onAction: _fetch,
    );
  }

  List<Widget> _details(PlayerProfile info) {
    final pad = const EdgeInsets.symmetric(horizontal: Spacing.lg);
    final ranks = info.ranks;
    return [
      if (ranks != null) ...[
        const PageSectionTitle('ICC rankings'),
        Padding(
          padding: pad,
          child: _RanksTable(ranks: ranks),
        ),
      ],
      const Padding(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, 0),
        child: ListNativeAd(placement: 'player_detail_feed'),
      ),
      if (!info.battingTable.isEmpty) ...[
        const PageSectionTitle('Batting career'),
        Padding(
          padding: pad,
          child: CareerTableView(
            key: const ValueKey('player_batting_table'),
            scrollKey: const ValueKey('player_batting_scroll'),
            title: 'Batting',
            table: info.battingTable,
          ),
        ),
        _legend(info.battingTable.legend),
      ],
      if (!info.bowlingTable.isEmpty) ...[
        const PageSectionTitle('Bowling career'),
        Padding(
          padding: pad,
          child: CareerTableView(
            key: const ValueKey('player_bowling_table'),
            scrollKey: const ValueKey('player_bowling_scroll'),
            title: 'Bowling',
            table: info.bowlingTable,
          ),
        ),
        _legend(info.bowlingTable.legend),
      ],
      if (info.battingTable.isEmpty && info.bowlingTable.isEmpty)
        const EmptyState(
          key: ValueKey('player_detail_no_stats'),
          icon: Icons.table_chart_outlined,
          title: 'No career stats published yet',
          subtitle: 'Stats appear here once the data provider adds them.',
        ),
      if (info.debuts.isNotEmpty) ...[
        const PageSectionTitle('Debuts'),
        Padding(
          padding: pad,
          child: _Debuts(debuts: info.debuts),
        ),
      ],
      if (info.teams.isNotEmpty) ...[
        const PageSectionTitle('Teams'),
        Padding(
          padding: pad,
          child: _Teams(teams: info.teams),
        ),
      ],
      if (info.description.isNotEmpty) ...[
        const PageSectionTitle('About'),
        Padding(
          padding: pad,
          child: _Bio(text: info.description),
        ),
      ],
    ];
  }

  Widget _legend(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
    child: Text(text, style: AppText.meta),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.player});
  final PlayerProfile player;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final facts = player.facts;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        Spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlayerAvatar(url: player.logo, name: player.name, size: 72),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        player.name,
                        key: const ValueKey('player_detail_name'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          size: 26,
                          weight: FontWeight.w800,
                          height: 1.1,
                          color: p.ink,
                        ),
                      ),
                    ),
                    if (player.country.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        player.country,
                        style: AppText.meta.copyWith(fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 560 ? 3 : 2;
                const gap = Spacing.lg;
                final w = ((c.maxWidth - gap * (cols - 1)) / cols)
                    .floorToDouble();
                return Wrap(
                  spacing: gap,
                  runSpacing: Spacing.md,
                  children: [
                    for (final f in facts)
                      SizedBox(
                        width: w,
                        child: MergeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.$1, style: AppText.small),
                              const SizedBox(height: 2),
                              Text(f.$2, style: AppText.name),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Category × format grid; categories with no rank in any format are left
/// out, single missing cells show a dash.
class _RanksTable extends StatelessWidget {
  const _RanksTable({required this.ranks});
  final IccRanks ranks;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cats = IccRanks.categories
        .where((c) => ranks.hasCategory(c.$1))
        .toList();
    Widget pad(Widget w, {bool right = true}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.md,
      ),
      child: Align(
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: w,
      ),
    );
    final numStyle = AppFont.style(
      size: 17,
      weight: FontWeight.w800,
      width: AppFont.scoreWidth,
      color: p.ink,
      tabularFigures: true,
    );
    return Container(
      key: const ValueKey('player_ranks_table'),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.6)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: p.surfaceAlt),
            children: [
              pad(Text('Category', style: AppText.small), right: false),
              for (final f in IccRanks.formats)
                pad(Text(f.$2, style: AppText.small)),
            ],
          ),
          for (final c in cats)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.hairline)),
              ),
              children: [
                pad(Text(c.$2, style: AppText.name), right: false),
                for (final f in IccRanks.formats)
                  pad(
                    Semantics(
                      label: ranks.rank(c.$1, f.$1) == null
                          ? '${f.$2} ${c.$2.toLowerCase()}: not ranked'
                          : '${f.$2} ${c.$2.toLowerCase()} rank ${ranks.rank(c.$1, f.$1)!.substring(1)}',
                      excludeSemantics: true,
                      child: Text(
                        ranks.rank(c.$1, f.$1) ?? kDash,
                        style: ranks.rank(c.$1, f.$1) == null
                            ? numStyle.copyWith(color: p.inkMuted)
                            : numStyle,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Debuts extends StatelessWidget {
  const _Debuts({required this.debuts});
  final List<Debut> debuts;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ts = MediaQuery.textScalerOf(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < debuts.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: p.hairline)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
              ),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: ts.scale(64).clamp(64.0, 120.0),
                      child: Text(debuts[i].format, style: AppText.name),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (debuts[i].match != null)
                            Text(
                              debuts[i].match!,
                              style: AppText.reading.copyWith(fontSize: 14),
                            ),
                          if (debuts[i].date != null)
                            Text(debuts[i].date!, style: AppText.meta),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Teams extends StatelessWidget {
  const _Teams({required this.teams});
  final List<String> teams;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        for (final t in teams)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.chip),
              border: Border.all(color: p.hairline),
            ),
            child: Text(t, style: AppText.name.copyWith(fontSize: 14)),
          ),
      ],
    );
  }
}

/// Bio collapsed to 4 lines with a "Show more" toggle when it is longer.
class _Bio extends StatefulWidget {
  const _Bio({required this.text});
  final String text;

  @override
  State<_Bio> createState() => _BioState();
}

class _BioState extends State<_Bio> {
  static const _lines = 4;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = AppText.reading;
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth < 640 ? c.maxWidth : 640);
        final long = tp.didExceedMaxLines;
        tp.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                widget.text,
                key: const ValueKey('player_bio'),
                maxLines: _open ? null : _lines,
                overflow: _open ? null : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (long)
              TextButton(
                key: const ValueKey('player_bio_toggle'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 44),
                ),
                onPressed: () => setState(() => _open = !_open),
                child: Text(_open ? 'Show less' : 'Show more'),
              ),
          ],
        );
      },
    );
  }
}

/// Skeleton mirroring the profile. [showHeader] false when the real header
/// (from the list item) is already on screen.
class PlayerDetailSkeleton extends StatelessWidget {
  const PlayerDetailSkeleton({super.key, this.showHeader = true});
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.hairline),
      ),
    );
    Widget title(double w) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xxl,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ShimmerBox(width: w, height: 16, radius: 4),
      ),
    );
    return ShimmerGroup(
      key: const ValueKey('player_detail_shimmer'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader)
            Container(
              color: p.surface,
              padding: const EdgeInsets.all(Spacing.xl),
              child: const Row(
                children: [
                  ShimmerBox(width: 72, height: 72, radius: 36),
                  SizedBox(width: Spacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 180, height: 22, radius: 4),
                        SizedBox(height: 8),
                        ShimmerBox(width: 90, height: 13, radius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          title(110),
          block(132),
          title(130),
          block(220),
        ],
      ),
    );
  }
}
