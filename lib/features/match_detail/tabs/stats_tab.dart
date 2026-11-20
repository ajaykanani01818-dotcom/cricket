import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/cricket_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../widgets/md_ui.dart';
import 'tab_common.dart';
import 'tab_scorecard_parse.dart';
import 'tab_stats_parse.dart';

/// Stats tab (research §3.7). Loads analytics + scoring rate + boundaries
/// in parallel (each failure tolerated) and re-polls while live.
///
/// The one chart we own: runs per over (Manhattan) for the selected
/// innings, with wickets marked from the fall of wickets, and a separate
/// worm (cumulative runs) chart: two measures, two charts, one axis each.
/// Every chart has a text equivalent underneath (PRD §13).
class MatchStatsTab extends StatefulWidget {
  const MatchStatsTab({super.key, required this.matchId, required this.isLive, this.service, this.scorecard});
  final String matchId;
  final bool isLive;
  final MatchService? service;

  /// For wicket marks (fall of wickets) and innings order.
  final ScorecardView? scorecard;

  @override
  State<MatchStatsTab> createState() => _MatchStatsTabState();
}

/// Fetches the three stats endpoints. When ALL three fail, the first error
/// is rethrown so the tab shows an error + retry instead of an empty page.
Future<StatsView> loadMatchStats(MatchService service, String matchId, {List<String> order = const []}) async {
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
  return parseStats(analytics: results[0], scoringRate: results[1], boundaries: results[2], order: order);
}

class _MatchStatsTabState extends State<MatchStatsTab> with LiveTabPolling {
  late Loadable<StatsView> _state;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final matchId = widget.matchId;
    late final Loadable<StatsView> l;
    l = Loadable<StatsView>(() async {
      final next = await loadMatchStats(
        widget.service ?? MatchService.instance,
        matchId,
        order: widget.scorecard?.inningsOrder ?? const [],
      );
      final prev = l.data;
      return prev != null && prev == next ? prev : next;
    });
    _state = l;
    l.load();
    configurePolling(widget.isLive, () => l.load(silent: true));
  }

  @override
  void didUpdateWidget(MatchStatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId != widget.matchId) {
      _state.dispose();
      _selected = null;
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
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
              child: ErrorRetry(key: const ValueKey('stats_error'), title: "Stats didn't load", message: err, onRetry: _state.load),
            );
          }
          return const _StatsSkeleton(key: ValueKey('stats_loading'));
        }
        if (data.isEmpty) {
          return const Padding(
            key: ValueKey('stats_empty'),
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: EmptyState(
              icon: Icons.bar_chart,
              title: 'Stats not available',
              subtitle: 'Over-by-over figures appear once the provider sends them.',
            ),
          );
        }
        final sel = (_selected ?? data.innings.length - 1).clamp(0, data.innings.length - 1);
        return _StatsBody(
          view: data,
          selected: sel,
          scorecard: widget.scorecard,
          onSelect: (i) => setState(() => _selected = i),
        );
      },
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.view, required this.selected, required this.onSelect, this.scorecard});
  final StatsView view;
  final int selected;
  final ValueChanged<int> onSelect;
  final ScorecardView? scorecard;

  /// Wicket overs (1-based) for an innings key, from the scorecard FoW.
  List<int> _wicketOvers(InningsStatsVM inn) {
    final sc = scorecard;
    if (sc == null) return const [];
    final idx = sc.inningsOrder.indexOf(inn.key);
    if (idx < 0 || idx >= sc.innings.length) return const [];
    return [for (final f in sc.innings[idx].fallOfWickets) ?wicketOverFromFow(f.over)];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inn = view.innings[selected];
    final wkts = _wicketOvers(inn);
    String na(Object? v) => v == null ? '–' : '$v';
    return Column(
      key: const ValueKey('stats_body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Comparison across innings (real fields only).
        const MdSectionTitle('By innings'),
        NumTable(
          key: const ValueKey('stats_scoring_rate'),
          nameHeader: 'Innings',
          columns: const ['RR', '4s', '6s', 'Dot %'],
          minNameWidth: 104,
          rows: [
            for (final i in view.innings)
              NumRow(
                name: i.shortLabel,
                values: [
                  i.runRate?.toStringAsFixed(2) ?? '–',
                  na(i.fours),
                  na(i.sixes),
                  i.dotPercent == null ? '–' : i.dotPercent!.toStringAsFixed(1),
                ],
                semanticsLabel:
                    '${i.label}: run rate ${i.runRate?.toStringAsFixed(2) ?? 'not available'}, ${i.fours ?? 'no data on'} fours, ${i.sixes ?? 'no data on'} sixes, dot balls ${i.dotPercent?.toStringAsFixed(1) ?? 'not available'} percent',
              ),
          ],
        ),
        const MdNote('RR is runs per over. A dash means the provider did not send that figure.'),
        if (view.innings.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.lg),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < view.innings.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: ChoiceChip(
                      key: ValueKey('stats_innings_$i'),
                      label: Text(view.innings[i].shortLabel),
                      selected: i == selected,
                      onSelected: (_) => onSelect(i),
                      showCheckmark: false,
                      selectedColor: p.brandTint,
                      backgroundColor: p.surface,
                      side: BorderSide(color: i == selected ? p.brand : p.hairline),
                      labelStyle: AppFont.style(size: 13, weight: FontWeight.w700, color: p.ink),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
                    ),
                  ),
              ]),
            ),
          ),
        if (inn.overRuns.isNotEmpty) ...[
          MdSectionTitle('Runs per over, ${inn.label}'),
          OverChart(key: ValueKey('stats_manhattan_${inn.key}'), runs: inn.overRuns, wicketOvers: wkts),
          MdNote(manhattanSummary(inn.overRuns, wkts), padding: const EdgeInsets.only(top: Spacing.sm)),
          MdSectionTitle('Running total, ${inn.label}'),
          WormChart(key: ValueKey('stats_worm_${inn.key}'), runs: inn.overRuns, wicketOvers: wkts),
          MdNote(wormSummary(inn.overRuns), padding: const EdgeInsets.only(top: Spacing.sm)),
        ],
        if (inn.dotPercent != null || inn.boundaries != null) ...[
          MdSectionTitle('Scoring, ${inn.label}'),
          if (inn.dotPercent != null)
            MdKeyValue(
              valueKey: const ValueKey('stats_dot_ball'),
              label: 'Dot balls',
              value: '${inn.dotPercent!.toStringAsFixed(1)}%${inn.dotBalls != null && inn.totalBalls != null ? ' (${inn.dotBalls} of ${inn.totalBalls} balls)' : ''}',
            ),
          if (inn.boundaries != null)
            MdKeyValue(
              valueKey: const ValueKey('stats_boundaries'),
              label: 'Boundaries',
              value: '${inn.boundaries} (${_count(inn.fours, 'four', 'fours')}, ${_count(inn.sixes, 'six', 'sixes')})',
            ),
        ],
        if (inn.bowling.isNotEmpty) ...[
          MdSectionTitle('Bowler economy, ${inn.label}'),
          EconomyBars(key: ValueKey('stats_economy_${inn.key}'), bowlers: inn.bowling),
        ],
      ],
    );
  }
}

String _count(int? n, String one, String many) => n == null ? '– $many' : '$n ${n == 1 ? one : many}';

/// Text equivalent of the Manhattan chart.
String manhattanSummary(List<int> runs, List<int> wicketOvers) {
  if (runs.isEmpty) return '';
  var hi = 0;
  for (var i = 1; i < runs.length; i++) {
    if (runs[i] > runs[hi]) hi = i;
  }
  final total = runs.fold(0, (a, b) => a + b);
  final b = StringBuffer('Highest over: ${runs[hi]} runs (over ${hi + 1}). ');
  b.write('$total runs in ${runs.length} overs.');
  if (wicketOvers.isNotEmpty) b.write(' Wickets in overs ${wicketOvers.join(', ')}.');
  return b.toString();
}

/// Text equivalent of the worm chart.
String wormSummary(List<int> runs) {
  if (runs.isEmpty) return '';
  var cum = 0;
  final marks = <String>[];
  for (var i = 0; i < runs.length; i++) {
    cum += runs[i];
    if ((i + 1) % 10 == 0) marks.add('$cum after ${i + 1}');
  }
  return marks.isEmpty ? '$cum runs after ${runs.length} overs.' : '${marks.join(', ')}; $cum after ${runs.length} overs.';
}

// ─────────────────────────────────────────────────────────────────────────────
// Charts
// ─────────────────────────────────────────────────────────────────────────────

/// Manhattan: one bar per over (brand fill, 2 px surface gap, rounded data
/// end on the baseline), recessive grid, wicket marks as ink "W" tags above
/// the over. Tap or drag reads out one over.
class OverChart extends StatefulWidget {
  const OverChart({super.key, required this.runs, this.wicketOvers = const []});
  final List<int> runs;
  final List<int> wicketOvers;

  @override
  State<OverChart> createState() => _OverChartState();
}

class _OverChartState extends State<OverChart> {
  int? _hover;

  void _pick(Offset local, double width) {
    final n = widget.runs.length;
    final plotLeft = _ChartLayout.axisW;
    final x = (local.dx - plotLeft).clamp(0, width - plotLeft - 1);
    final i = (x / ((width - plotLeft) / n)).floor().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final runs = widget.runs;
    final h = _hover;
    final cum = h == null ? null : runs.take(h + 1).fold<int>(0, (a, b) => a + b);
    final readout = h == null
        ? 'Tap a bar to read an over'
        : 'Over ${h + 1}: ${runs[h]} runs, total $cum${widget.wicketOvers.contains(h + 1) ? ', wicket' : ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(readout, key: const ValueKey('stats_chart_readout'), style: AppText.small.copyWith(color: h == null ? p.inkMuted : p.ink)),
      const SizedBox(height: Spacing.xs),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Semantics(
          label: manhattanSummary(runs, widget.wicketOvers),
          child: GestureDetector(
            onTapDown: (d) => _pick(d.localPosition, w),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, w),
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(w, 180),
                painter: _ManhattanPainter(runs: runs, wickets: widget.wicketOvers, p: p, selected: h),
              ),
            ),
          ),
        );
      }),
    ]);
  }
}

class _ChartLayout {
  static const double axisW = 28;
  static const double bottom = 18;
  static const double top = 14;

  static double niceMax(num v) {
    if (v <= 0) return 4;
    final steps = [4, 8, 12, 16, 20, 24, 32, 40, 60, 80, 100, 120, 160, 200, 250, 300, 400, 500, 600, 800, 1000];
    for (final s in steps) {
      if (v <= s) return s.toDouble();
    }
    return (v / 100).ceil() * 100.0;
  }
}

void _label(Canvas canvas, String s, Offset at, Color color, {double size = 11, bool right = false, bool center = false, FontWeight w = FontWeight.w500}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: AppFont.style(size: size, weight: w, color: color, tabularFigures: true, height: 1)),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  var o = at;
  if (right) o = o.translate(-tp.width, 0);
  if (center) o = o.translate(-tp.width / 2, 0);
  tp.paint(canvas, o);
  tp.dispose();
}

void _grid(Canvas canvas, Size size, double max, AppPalette p, int n) {
  final plotH = size.height - _ChartLayout.bottom - _ChartLayout.top;
  final line = Paint()
    ..color = p.hairline
    ..strokeWidth = 1;
  for (var k = 0; k <= 2; k++) {
    final v = max * k / 2;
    final y = _ChartLayout.top + plotH * (1 - k / 2);
    canvas.drawLine(Offset(_ChartLayout.axisW, y), Offset(size.width, y), line);
    _label(canvas, v.round().toString(), Offset(_ChartLayout.axisW - 4, y - 5), p.inkMuted, right: true);
  }
  // x labels: every 5 / 10 / 20 overs depending on length.
  final step = n <= 25 ? 5 : n <= 60 ? 10 : 20;
  final bw = (size.width - _ChartLayout.axisW) / n;
  for (var o = step; o <= n; o += step) {
    final x = _ChartLayout.axisW + bw * (o - 0.5);
    _label(canvas, '$o', Offset(x, size.height - _ChartLayout.bottom + 5), p.inkMuted, center: true);
  }
}

class _ManhattanPainter extends CustomPainter {
  _ManhattanPainter({required this.runs, required this.wickets, required this.p, this.selected});
  final List<int> runs;
  final List<int> wickets;
  final AppPalette p;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final n = runs.length;
    if (n == 0) return;
    final max = _ChartLayout.niceMax(runs.reduce(math.max));
    _grid(canvas, size, max, p, n);
    final plotH = size.height - _ChartLayout.bottom - _ChartLayout.top;
    final bw = (size.width - _ChartLayout.axisW) / n;
    final gap = bw > 8 ? 2.0 : bw > 4 ? 1.0 : 0.0;
    final base = _ChartLayout.top + plotH;
    final fill = Paint()..color = p.brand;
    final sel = Paint()..color = p.ink;
    for (var i = 0; i < n; i++) {
      final hgt = plotH * runs[i] / max;
      if (hgt <= 0) continue;
      final rect = Rect.fromLTWH(_ChartLayout.axisW + bw * i + gap / 2, base - hgt, math.max(1, bw - gap), hgt);
      final r = math.min(4.0, rect.width / 2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: Radius.circular(r), topRight: Radius.circular(r)),
        i == selected ? sel : fill,
      );
    }
    // Wicket marks: small inverted ink tag above the over.
    for (final o in wickets) {
      final i = o - 1;
      if (i < 0 || i >= n) continue;
      final hgt = plotH * runs[i] / max;
      final c = Offset(_ChartLayout.axisW + bw * (i + 0.5), base - hgt - 7);
      final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 11, height: 11), const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = p.ink);
      _label(canvas, 'W', c.translate(0, -4), p.surface, size: 8, center: true, w: FontWeight.w800);
    }
    final axis = Paint()
      ..color = p.inkMuted
      ..strokeWidth = 1;
    canvas.drawLine(Offset(_ChartLayout.axisW, base), Offset(size.width, base), axis);
  }

  @override
  bool shouldRepaint(_ManhattanPainter old) =>
      old.p != p || old.selected != selected || !_same(old.runs, runs) || !_same(old.wickets, wickets);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Worm: cumulative runs, one 2 px line, wicket dots on the line.
class WormChart extends StatelessWidget {
  const WormChart({super.key, required this.runs, this.wicketOvers = const []});
  final List<int> runs;
  final List<int> wicketOvers;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: wormSummary(runs),
      child: RepaintBoundary(
        child: CustomPaint(size: const Size(double.infinity, 150), painter: _WormPainter(runs: runs, wickets: wicketOvers, p: p)),
      ),
    );
  }
}

class _WormPainter extends CustomPainter {
  _WormPainter({required this.runs, required this.wickets, required this.p});
  final List<int> runs;
  final List<int> wickets;
  final AppPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final n = runs.length;
    if (n == 0) return;
    final cum = <int>[];
    var s = 0;
    for (final r in runs) {
      s += r;
      cum.add(s);
    }
    final max = _ChartLayout.niceMax(s);
    _grid(canvas, size, max, p, n);
    final plotH = size.height - _ChartLayout.bottom - _ChartLayout.top;
    final base = _ChartLayout.top + plotH;
    final bw = (size.width - _ChartLayout.axisW) / n;
    Offset pt(int i) => Offset(_ChartLayout.axisW + bw * (i + 1), base - plotH * cum[i] / max);
    final path = Path()..moveTo(_ChartLayout.axisW, base);
    for (var i = 0; i < n; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = p.brandText
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (final o in wickets) {
      final i = o - 1;
      if (i < 0 || i >= n) continue;
      canvas.drawCircle(pt(i), 5, Paint()..color = p.surface);
      canvas.drawCircle(pt(i), 4, Paint()..color = p.ink);
    }
    canvas.drawLine(Offset(_ChartLayout.axisW, base), Offset(size.width, base), Paint()..color = p.inkMuted);
  }

  @override
  bool shouldRepaint(_WormPainter old) => old.p != p || !_same(old.runs, runs) || !_same(old.wickets, wickets);
}

/// Horizontal economy bars with the value written beside each bar (text in
/// ink, never the bar colour).
class EconomyBars extends StatelessWidget {
  const EconomyBars({super.key, required this.bowlers});
  final List<BowlerEconomy> bowlers;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final max = bowlers.map((b) => b.economy).fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in bowlers)
          Semantics(
            label: '${b.name}: economy ${b.economy.toStringAsFixed(2)}${b.overs != null ? ' in ${b.overs} overs' : ''}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs + 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFont.style(size: 14, weight: FontWeight.w600, color: p.ink))),
                  Text(
                    '${b.economy.toStringAsFixed(2)}${b.overs != null ? '  ${b.overs} ov' : ''}',
                    style: AppFont.style(size: 13, color: p.inkMuted, tabularFigures: true),
                  ),
                ]),
                const SizedBox(height: 4),
                LayoutBuilder(builder: (context, c) {
                  final w = max <= 0 ? 0.0 : c.maxWidth * (b.economy / max);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: math.max(2, w),
                      height: 8,
                      decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(4)),
                    ),
                  );
                }),
              ]),
            ),
          ),
      ],
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading stats',
        child: const ShimmerGroup(
          child: Padding(
            padding: EdgeInsets.only(top: Spacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ShimmerBox(height: 120, radius: 6),
              SizedBox(height: Spacing.lg),
              ShimmerBox(height: 180, radius: 6),
            ]),
          ),
        ),
      );
}
