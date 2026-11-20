import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/json.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/shimmer_box.dart';
import '../../core/widgets/titles.dart';
import '../players/player_models.dart';
import '../players/players_screen.dart';
import '../players/widgets/player_widgets.dart';
import '../rankings/ranking_models.dart';
import '../rankings/ranking_screen.dart';
import 'discover_cache.dart';

/// Ongoing series for the hub preview: total count + the first few names.
class SeriesPreview {
  const SeriesPreview({required this.total, required this.items});
  final int? total;
  final List<({String id, String name})> items;
}

Future<SeriesPreview> loadSeriesPreview({bool force = false}) =>
    DiscoverCache.get('discover:series', () async {
      final res = await MatchService.instance.getSeries(
        status: 'ONGOING',
        page: 1,
        perPage: 3,
      );
      final raw = res.data is List ? res.data : J.map(res.data)['series'];
      final items = <({String id, String name})>[];
      for (final s in J.maps(raw)) {
        final name = J.text(s['name']);
        final id =
            J.text(s['sb_series_key']) ?? J.text(s['_id']) ?? J.text(s['key']);
        if (name != null && id != null) items.add((id: id, name: name));
        if (items.length == 3) break;
      }
      final total = res.pageInfo?.total;
      return SeriesPreview(
        total: total ?? (items.length < 3 ? items.length : null),
        items: items,
      );
    }, force: force);

/// The men's #1 team in each format for the hub preview. A format whose
/// call fails is left out; all failing is an error.
Future<List<(String, RankingRowItem)>> loadLeadersPreview({
  bool force = false,
}) async {
  final results = await Future.wait([
    for (final f in kFormatOptions)
      loadRankings(RankKind.teams, format: f.$1, gender: 'MALE', force: force)
          .then<(String, RankingRowItem)?>(
            (l) => l.isEmpty ? null : (f.$2, l.first),
          )
          .catchError((Object _) => null),
  ]);
  final out = results.whereType<(String, RankingRowItem)>().toList();
  if (out.isEmpty) throw StateError('no rankings');
  return out;
}

/// Discover tab: a calm index of Series, Rankings and Players. Each entry
/// carries a one-line live preview from the cached services (ongoing series,
/// who is #1 in each format, trending players) so the hub answers a question
/// before it is opened. Previews fail quietly; the entries always work.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

enum _S { loading, ready, failed }

class _DiscoverScreenState extends State<DiscoverScreen> {
  _S _seriesState = _S.loading;
  SeriesPreview? _series;
  _S _leadersState = _S.loading;
  List<(String, RankingRowItem)> _leaders = const [];
  _S _playersState = _S.loading;
  List<CountryPlayer> _trending = const [];
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll({bool force = false}) => Future.wait([
    _run(() => loadSeriesPreview(force: force), (v) {
      _series = v;
      _seriesState = v.items.isEmpty && (v.total ?? 0) == 0
          ? _S.failed
          : _S.ready;
    }, () => _seriesState = _S.failed),
    _run(() => loadLeadersPreview(force: force), (v) {
      _leaders = v;
      _leadersState = _S.ready;
    }, () => _leadersState = _S.failed),
    _run(() => loadTrendingPlayers(force: force), (v) {
      _trending = v.take(8).toList();
      _playersState = v.isEmpty ? _S.failed : _S.ready;
    }, () => _playersState = _S.failed),
  ]);

  Future<void> _run<T>(
    Future<T> Function() load,
    void Function(T) ok,
    VoidCallback fail,
  ) async {
    try {
      final v = await load();
      if (mounted) setState(() => ok(v));
    } catch (_) {
      if (mounted) setState(fail);
    }
  }

  Future<void> _guard(Future<void> Function() go) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await go();
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ColoredBox(
      color: p.canvas,
      child: Column(
        children: [
          ScreenTitle(
            title: 'Discover',
            showBack: false,
            onSearch: () => AppNav.search(context),
          ),
          Expanded(
            child: RefreshIndicator(
              color: p.brandText,
              onRefresh: () => _loadAll(force: true),
              child: ListView(
                key: const ValueKey('discover_list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: Spacing.xxl),
                children: [
                  Capped(child: _seriesSection()),
                  Capped(child: _rankingsSection()),
                  Capped(child: _playersSection()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Series: count line + up to three ongoing series ──
  Widget _seriesSection() {
    final s = _series;
    final total = s?.total;
    final line = switch (_seriesState) {
      _S.ready when total != null && total > 0 =>
        total == 1 ? '1 series in progress' : '$total series in progress',
      _S.ready => 'Series in progress',
      _ => 'Fixtures, points tables and squads',
    };
    return _Entry(
      section: DiscoverSection.series,
      icon: Icons.emoji_events_outlined,
      title: 'Series',
      line: line,
      lineLoading: _seriesState == _S.loading,
      preview: switch (_seriesState) {
        _S.loading => const _LinesSkeleton(lines: 2),
        _S.failed => const _PreviewNote(
          key: ValueKey('discover_series_error'),
          text: "Couldn't load a preview. Open Series to see every tournament.",
        ),
        _S.ready => Column(
          key: const ValueKey('discover_series_preview'),
          children: [
            for (final it in s!.items)
              _PreviewLink(
                key: ValueKey('discover_series_${it.id}'),
                text: it.name,
                onTap: () => _guard(() async {
                  await AppNav.seriesDetail<void>(
                    context,
                    it.id,
                    seriesName: it.name,
                  );
                }),
              ),
          ],
        ),
      },
    );
  }

  // ── Rankings: #1 team per format ──
  Widget _rankingsSection() => _Entry(
    section: DiscoverSection.rankings,
    icon: Icons.leaderboard_outlined,
    title: 'Rankings',
    line: "Men's team leaders by format",
    preview: switch (_leadersState) {
      _S.loading => const _LinesSkeleton(lines: 1, tall: true),
      _S.failed => const _PreviewNote(
        key: ValueKey('discover_rankings_error'),
        text: "Couldn't load the leaders. Open Rankings to try again.",
      ),
      _S.ready => _LeadersStrip(
        key: const ValueKey('discover_rankings_preview'),
        leaders: _leaders,
      ),
    },
  );

  // ── Players: trending avatars ──
  Widget _playersSection() => _Entry(
    section: DiscoverSection.players,
    icon: Icons.person_search_outlined,
    title: 'Players',
    line: _playersState == _S.ready
        ? 'Trending now'
        : 'Profiles and career numbers',
    preview: switch (_playersState) {
      _S.loading => const _AvatarsSkeleton(),
      _S.failed => const _PreviewNote(
        key: ValueKey('discover_players_error'),
        text:
            "Couldn't load trending players. Open Players to search by name or country.",
      ),
      _S.ready => SingleChildScrollView(
        key: const ValueKey('discover_players_preview'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final pl in _trending)
              TrendingPlayerTile(
                player: pl,
                size: 48,
                onPress: (pl) => _guard(() async {
                  if (pl.playerKey.isEmpty) return;
                  await AppNav.player<void>(
                    context,
                    pl.playerKey,
                    player: pl.raw,
                  );
                }),
              ),
          ],
        ),
      ),
    },
  );
}

/// One hub entry: a tappable heading row (title, preview line, chevron) and
/// a preview underneath. Entries are separated by space and a hairline, not
/// boxed into identical cards.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.section,
    required this.icon,
    required this.title,
    required this.line,
    required this.preview,
    this.lineLoading = false,
  });
  final DiscoverSection section;
  final IconData icon;
  final String title;
  final String line;
  final bool lineLoading;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Open $title. $line',
            excludeSemantics: true,
            child: Pressable(
              key: ValueKey('discover_${section.segment}'),
              onTap: () => AppNav.discover(context, section),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.xl,
                    Spacing.sm,
                    Spacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 24, color: p.brandText),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppFont.style(
                                size: 20,
                                weight: FontWeight.w800,
                                height: 1.15,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (lineLoading)
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: ShimmerBox(
                                  width: 140,
                                  height: 12,
                                  radius: 4,
                                ),
                              )
                            else
                              Text(line, style: AppText.meta),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: p.inkMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          preview,
        ],
      ),
    );
  }
}

/// A single tappable line in a preview (e.g. a series name).
class _PreviewLink extends StatelessWidget {
  const _PreviewLink({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: text,
    excludeSemantics: true,
    child: Pressable(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg + 36,
            Spacing.sm,
            Spacing.lg,
            Spacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.name,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Three compact columns: format, team, rating.
class _LeadersStrip extends StatelessWidget {
  const _LeadersStrip({super.key, required this.leaders});
  final List<(String, RankingRowItem)> leaders;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg + 36,
        Spacing.xs,
        Spacing.lg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < leaders.length; i++) ...[
            if (i > 0) const SizedBox(width: Spacing.md),
            Expanded(
              child: Semantics(
                label:
                    '${leaders[i].$1}: ${leaders[i].$2.name} is number 1'
                    '${leaders[i].$2.rating == null ? '' : ', rating ${leaders[i].$2.rating}'}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(leaders[i].$1, style: AppText.small),
                    const SizedBox(height: 2),
                    Text(
                      leaders[i].$2.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.name,
                    ),
                    if (leaders[i].$2.rating != null)
                      Text(
                        leaders[i].$2.rating!,
                        style: AppFont.style(
                          size: 22,
                          weight: FontWeight.w800,
                          width: AppFont.scoreWidth,
                          color: p.ink,
                          tabularFigures: true,
                          height: 1.15,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewNote extends StatelessWidget {
  const _PreviewNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg + 36,
      Spacing.xs,
      Spacing.lg,
      0,
    ),
    child: Text(text, style: AppText.meta),
  );
}

class _LinesSkeleton extends StatelessWidget {
  const _LinesSkeleton({required this.lines, this.tall = false});
  final int lines;
  final bool tall;

  @override
  Widget build(BuildContext context) => ShimmerGroup(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg + 36,
        Spacing.sm,
        Spacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: FractionallySizedBox(
                widthFactor: 0.8 - i * 0.2,
                child: ShimmerBox(height: tall ? 44 : 14, radius: 4),
              ),
            ),
        ],
      ),
    ),
  );
}

class _AvatarsSkeleton extends StatelessWidget {
  const _AvatarsSkeleton();

  @override
  Widget build(BuildContext context) => ShimmerGroup(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: ClipRect(
        child: Wrap(
          spacing: 28,
          runSpacing: 0,
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < 5; i++)
              const ShimmerBox(width: 48, height: 48, radius: 24),
          ],
        ),
      ),
    ),
  );
}
