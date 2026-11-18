import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/cricket_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value.dart';
import '../../../core/widgets/empty_state.dart';
import 'match_section_title.dart';
import 'tab_common.dart';
import 'tab_stats_parse.dart';

/// Ported from RN `MatchStatsTab`. Loads analytics + scoring-rate +
/// boundaries in parallel (each failure tolerated individually, like RN's
/// `.catch(() => null)`) and re-polls silently every 15s while [isLive].
class MatchStatsTab extends StatefulWidget {
  const MatchStatsTab({super.key, required this.matchId, required this.isLive});
  final String matchId;
  final bool isLive;

  @override
  State<MatchStatsTab> createState() => _MatchStatsTabState();
}

/// Fetches the three stats endpoints. RN swallows every individual failure;
/// here, when ALL three fail, the first error is rethrown so the tab shows an
/// error + Retry instead of a screen of zeros.
Future<StatsView> loadMatchStats(MatchService service, String matchId) async {
  Object? firstError;
  Future<dynamic> safe(Future<ApiResponse> f) async {
    try {
      return (await f).data;
    } catch (e) {
      firstError ??= e;
      return null;
    }
  }

  final results = await Future.wait([
    safe(service.getMatchAnalytics(matchId)),
    safe(service.getMatchScoringRate(matchId)),
    safe(service.getMatchBoundaries(matchId)),
  ]);
  final err = firstError;
  if (err != null && results.every((r) => r == null)) throw err;
  return parseStats(analytics: results[0], scoringRate: results[1], boundaries: results[2]);
}

class _MatchStatsTabState extends State<MatchStatsTab> with LiveTabPolling {
  late Loadable<StatsView> _state;
  StatsView? _builtFor;
  Widget? _built;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final matchId = widget.matchId;
    late final Loadable<StatsView> l;
    l = Loadable<StatsView>(() async {
      final next = await loadMatchStats(MatchService.instance, matchId);
      final prev = l.data;
      return prev != null && prev == next ? prev : next;
    });
    _state = l;
    _builtFor = null;
    _built = null;
    l.load();
    configurePolling(widget.isLive, () => l.load(silent: true));
  }

  @override
  void didUpdateWidget(MatchStatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId != widget.matchId) {
      _state.dispose();
      _start();
    } else if (oldWidget.isLive != widget.isLive) {
      configurePolling(widget.isLive, () => _state.load(silent: true));
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final data = _state.data;
        if (data == null) {
          final err = _state.errorMessage;
          if (err != null && !_state.loading) {
            return ErrorRetry(key: const ValueKey('stats_error'), message: err, onRetry: _state.load);
          }
          return const TabLoading(key: ValueKey('stats_loading'), text: 'Loading statistics...');
        }
        if (!identical(data, _builtFor) || _built == null) {
          _builtFor = data;
          _built = _StatsBody(view: data);
        }
        return _built ?? const SizedBox.shrink();
      },
    );
  }
}

const _sectionDecoration = BoxDecoration(
  color: AppColors.card,
  borderRadius: BorderRadius.all(Radius.circular(8)),
  border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
);

class _Section extends StatelessWidget {
  const _Section({super.key, required this.icon, required this.label, required this.child});
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: _sectionDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MatchSectionTitle(icon: icon, label: label),
            child,
          ],
        ),
      );
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.view});
  final StatsView view;

  @override
  Widget build(BuildContext context) => TabScrollBody(
        storageKey: 'match_stats_tab',
        children: [
          _Section(
            key: const ValueKey('stats_scoring_rate'),
            icon: Icons.bar_chart, // RN 📊
            label: 'Scoring Rate',
            child: _TwoValues(left: view.scoringRate1, right: view.scoringRate2),
          ),
          _Section(
            key: const ValueKey('stats_boundaries'),
            icon: Icons.track_changes, // RN 🎯
            label: 'Boundaries',
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BoundaryTeam(title: 'Team 1', stat: view.boundaries1),
                  const SizedBox(height: 16),
                  _BoundaryTeam(title: 'Team 2', stat: view.boundaries2),
                ],
              ),
            ),
          ),
          _Section(
            key: const ValueKey('stats_dot_ball'),
            icon: Icons.circle, // RN ⚫
            label: 'Dot Ball Percentage',
            child: _TwoValues(left: view.dotBall1, right: view.dotBall2),
          ),
        ],
      );
}

class _TwoValues extends StatelessWidget {
  const _TwoValues({required this.left, required this.right});
  final String left, right;

  Widget _item(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [_item(left, 'Team 1'), _item(right, 'Team 2')]),
      );
}

class _BoundaryTeam extends StatelessWidget {
  const _BoundaryTeam({required this.title, required this.stat});
  final String title;
  final BoundaryStat stat;

  Widget _item(int value, String label) => Column(
        children: [
          Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [_item(stat.fours, '4s'), _item(stat.sixes, '6s'), _item(stat.total, 'Total')],
            ),
          ],
        ),
      );
}
