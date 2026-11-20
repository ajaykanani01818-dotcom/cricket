import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/titles.dart';
import '../common/live_match_card.dart';
import '../common/match_parsing.dart';
import '../common/match_row.dart';
import '../common/tap_guard.dart';
import '../common/visible_poller.dart';
import '../home/home_controller.dart' show latestResults, startingSoon;
import '../search/search_index.dart';

/// Live list poll cadence (perf budget §13).
const Duration kLivePollInterval = Duration(seconds: 20);

/// Groups matches by series name, keeping first-seen order.
List<(String series, List<MatchSummary> matches)> groupBySeries(
  List<MatchSummary> matches,
) {
  final order = <String>[];
  final map = <String, List<MatchSummary>>{};
  for (final m in matches) {
    final key = m.series.trim().isEmpty ? 'Other matches' : m.series.trim();
    final bucket = map[key];
    if (bucket == null) {
      order.add(key);
      map[key] = [m];
    } else {
      bucket.add(m);
    }
  }
  return [for (final k in order) (k, map[k]!)];
}

int _liveRank(MatchSummary m) => switch (m.phase) {
  MatchPhase.live => 0,
  MatchPhase.paused => 1,
  _ => 2,
};

/// The Live list's sorting rule (PRD §7: sensible, documented, nothing
/// silently omitted):
/// 1. Series groups keep the provider's order of first appearance (the
///    provider lists its featured competitions first).
/// 2. Inside a group, matches in play come first, then paused ones
///    (stumps, breaks, delays), then anything else the feed sent; ties keep
///    the provider's order.
/// Every match `/match/live` returns is shown.
List<(String series, List<MatchSummary> matches)> sortLiveGroups(
  List<MatchSummary> matches,
) => [
  for (final g in groupBySeries(matches))
    (g.$1, _stableSort(g.$2, (a, b) => _liveRank(a) - _liveRank(b))),
];

List<T> _stableSort<T>(List<T> list, int Function(T, T) cmp) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = cmp(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

/// Live tab: every live match, grouped by series ([sortLiveGroups]), with
/// the live count in the bar and the last refresh time. Refreshed every
/// 20 s while visible and in the foreground. With nothing live it shows the
/// next start (counting down) and the latest results, never a blank page.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, this.service});
  final MatchService? service;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  MatchService get _svc => widget.service ?? MatchService.instance;
  late final VisiblePoller _poller = VisiblePoller(
    interval: kLivePollInterval,
    onTick: () => _load(silent: true),
  );
  final _tap = TapGuard();

  List<MatchSummary>? _matches;
  String? _error;
  bool _loading = false;
  int _gen = 0;
  DateTime? _updated;

  /// Shown only while nothing is live.
  MatchSummary? _next;
  List<MatchSummary> _results = const [];
  bool _fallbackLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poller.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setScreenVisible(isScreenVisible(context));
  }

  @override
  void dispose() {
    _poller.dispose();
    _tap.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loading && silent) return;
    final gen = ++_gen;
    _loading = true;
    if (!silent && mounted) setState(() => _error = null);
    try {
      final list = parseMatchList((await _svc.getLiveMatches()).data);
      if (!mounted || gen != _gen) return;
      SearchIndex.instance.addMatches(list);
      setState(() {
        _matches = list;
        _error = null;
        _updated = DateTime.now();
      });
      if (list.isEmpty && (!_fallbackLoaded || !silent)) {
        unawaited(_loadFallback());
      }
    } catch (e) {
      if (!mounted || gen != _gen) return;
      // A failed silent poll keeps the last good list on screen.
      if (_matches == null || !silent) {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (gen == _gen) _loading = false;
    }
  }

  /// Next start + latest results for the nothing-live state. Failures just
  /// leave those parts out.
  Future<void> _loadFallback() async {
    _fallbackLoaded = true;
    Future<List<MatchSummary>> get(Future<ApiResponse> Function() f) async {
      try {
        return parseMatchList((await f()).data);
      } catch (_) {
        return const [];
      }
    }

    final r = await Future.wait([
      get(_svc.getUpcomingMatches),
      get(_svc.getRecentMatches),
    ]);
    if (!mounted) return;
    setState(() {
      _next = startingSoon(r[0]).firstOrNull;
      _results = latestResults(r[1]).take(3).toList();
    });
  }

  void _open(MatchSummary m) {
    if (m.id.isEmpty) return;
    _tap.run(() => AppNav.match<void>(context, m.id));
  }

  Widget _width(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );

  Widget _updatedLine() {
    final t = _updated;
    if (t == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('live_updated'),
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Text(
        'Updated ${DateFormat('h:mm a', 'en_US').format(t)}. '
        'Refreshes every ${kLivePollInterval.inSeconds} seconds.',
        style: AppText.small.copyWith(color: context.palette.inkMuted),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final next = _next;
    return ListView(
      key: const ValueKey('live_empty_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        _width(
          EmptyState(
            key: const ValueKey('live_empty'),
            icon: Icons.sensors_off_outlined,
            title: 'No matches are live right now',
            subtitle: 'Live scores show up here the moment a match starts.',
            actionLabel: 'See upcoming matches',
            onAction: () => AppNav.tab(context, AppTab.matches),
          ),
        ),
        if (next != null) ...[
          _width(const SectionHeader(title: 'Next to start')),
          _width(
            MatchRowGroup(
              children: [
                MatchRow(
                  key: ValueKey('live_next_${next.id}'),
                  match: next,
                  onTap: () => _open(next),
                ),
              ],
            ),
          ),
        ],
        if (_results.isNotEmpty) ...[
          _width(const SectionHeader(title: 'Latest results')),
          _width(
            MatchRowGroup(
              children: [
                for (final m in _results)
                  MatchRow(
                    key: ValueKey('live_result_${m.id}'),
                    match: m,
                    onTap: () => _open(m),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final matches = _matches;
    Widget body;
    if (matches == null && _error == null) {
      body = const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: Spacing.sm),
          child: SkeletonList(cards: 3, rows: 0),
        ),
      );
    } else if (_error != null && (matches == null || matches.isEmpty)) {
      body = Center(
        child: SingleChildScrollView(
          child: ErrorRetry(
            key: const ValueKey('live_error'),
            message: _error!,
            onRetry: _load,
          ),
        ),
      );
    } else if (matches!.isEmpty) {
      body = RefreshIndicator(
        color: p.brandText,
        onRefresh: _load,
        child: _empty(context),
      );
    } else {
      final groups = sortLiveGroups(matches);
      final items = <Object>[#updated];
      for (final g in groups) {
        items
          ..add(g)
          ..addAll(g.$2);
      }
      body = RefreshIndicator(
        color: p.brandText,
        onRefresh: _load,
        child: ListView.builder(
          key: const ValueKey('live_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final it = items[i];
            if (it == #updated) return _width(_updatedLine());
            if (it is (String, List<MatchSummary>)) {
              final n = it.$2.length;
              return _width(
                SectionHeader(
                  key: ValueKey('live_series_$i'),
                  title: it.$1,
                  overline: n == 1 ? '1 match' : '$n matches',
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.lg,
                    Spacing.lg,
                    Spacing.xs,
                  ),
                ),
              );
            }
            final m = it as MatchSummary;
            return _width(
              Padding(
                key: ValueKey('live_match_${m.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.xs + 2,
                ),
                child: LiveMatchCard(
                  match: m,
                  fullWidth: true,
                  showSeries: false,
                  heroTags: true,
                  onTap: () => _open(m),
                ),
              ),
            );
          },
        ),
      );
    }
    final count = matches?.length ?? 0;
    return ColoredBox(
      color: p.canvas,
      child: Column(
        children: [
          ScreenTitle(
            title: 'Live',
            showBack: false,
            actions: [
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.md),
                  child: Semantics(
                    label: count == 1 ? '1 match live' : '$count matches live',
                    excludeSemantics: true,
                    child: Text(
                      '$count live',
                      key: const ValueKey('live_count'),
                      style: AppFont.withWeight(
                        AppText.meta.copyWith(color: p.ink),
                        FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
