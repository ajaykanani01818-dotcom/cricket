import 'package:flutter/material.dart';

import '../../../core/api/json.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../widgets/md_ui.dart';
import 'tab_scorecard_parse.dart';

/// Scorecard tab (research §3.6): one innings at a time, batting and
/// bowling tables with tabular numbers (the tables scroll sideways when
/// they no longer fit), extras and total, yet to bat, fall of wickets and
/// partnership runs derived from it (labelled as derived).
///
/// [scorecard] is the `data` object of GET /match/:id/scorecard (the
/// `{result: …}` wrapper is unwrapped by [parseScorecard]). The parsed view
/// is reused while its content is unchanged, so identical polls rebuild
/// nothing.
class MatchScorecardTab extends StatefulWidget {
  const MatchScorecardTab({super.key, required this.scorecard, required this.loading});
  final JsonMap? scorecard;
  final bool loading;

  @override
  State<MatchScorecardTab> createState() => _MatchScorecardTabState();
}

class _MatchScorecardTabState extends State<MatchScorecardTab> {
  JsonMap? _source;
  bool _parsed = false;
  ScorecardView _view = ScorecardView.empty;
  int? _selected;

  Widget? _built;
  ScorecardView? _builtView;
  int _builtSelected = -1;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MatchScorecardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_parsed && identical(widget.scorecard, _source)) return;
    _parsed = true;
    _source = widget.scorecard;
    final next = parseScorecard(_source);
    if (next == _view) return;
    _view = next;
    if (_selected != null && _selected! >= _view.innings.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (widget.loading && !view.hasInnings) return const _ScorecardSkeleton(key: ValueKey('scorecard_loading'));
    if (!view.hasInnings) {
      return const Padding(
        key: ValueKey('scorecard_empty'),
        padding: EdgeInsets.symmetric(vertical: Spacing.xl),
        child: EmptyState(
          icon: Icons.table_chart_outlined,
          title: 'Scorecard not available',
          subtitle: 'The data provider has not sent a scorecard for this match yet.',
        ),
      );
    }
    // Default to the latest innings.
    final sel = _selected ?? view.innings.length - 1;
    if (_built == null || !identical(_builtView, view) || _builtSelected != sel) {
      _builtView = view;
      _builtSelected = sel;
      _built = _ScorecardBody(view: view, selected: sel, onSelect: (i) => setState(() => _selected = i));
    }
    return _built!;
  }
}

String _ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };

/// "BAN 1st" labels in batting order.
List<String> inningsLabels(ScorecardView view) {
  final counts = <String, int>{};
  return [
    for (final inn in view.innings)
      () {
        final name = inn.shortName ?? inn.teamName;
        final n = (counts[name] ?? 0) + 1;
        counts[name] = n;
        return '$name ${_ordinal(n)}';
      }(),
  ];
}

class _ScorecardBody extends StatelessWidget {
  const _ScorecardBody({required this.view, required this.selected, required this.onSelect});
  final ScorecardView view;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inning = view.innings[selected];
    final labels = inningsLabels(view);
    final total = inning.runs == '-'
        ? null
        : inning.wickets == '10'
            ? '${inning.runs} all out'
            : inning.wickets == '-'
                ? inning.runs
                : '${inning.runs}/${inning.wickets}';
    return Column(
      key: const ValueKey('scorecard_body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.innings.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.md),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < labels.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: ChoiceChip(
                      key: ValueKey('scorecard_inning_option_$i'),
                      label: Text(labels[i]),
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
        Padding(
          padding: const EdgeInsets.only(top: Spacing.lg),
          child: Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(inning.teamName, key: const ValueKey('scorecard_hero_team'), style: AppFont.style(size: 17, weight: FontWeight.w700, color: p.ink)),
              if (total != null)
                Text(total, key: const ValueKey('scorecard_hero_score'), style: AppText.scoreCard.copyWith(color: p.ink)),
              if (inning.overs != '-') Text('${inning.overs} ov', style: AppText.figures.copyWith(color: p.inkMuted)),
            ],
          ),
        ),
        if (view.target != null)
          Padding(
            key: const ValueKey('scorecard_target'),
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text('Target ${view.target}', style: AppText.meta.copyWith(color: p.ink)),
          ),
        _Batting(inning: inning),
        _Bowling(inning: inning),
        if (inning.fallOfWickets.isNotEmpty) _Fow(inning: inning),
      ],
    );
  }
}

class _Batting extends StatelessWidget {
  const _Batting({required this.inning});
  final ScInning inning;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = inning.batting;
    return Column(
      key: const ValueKey('scorecard_batting'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MdSectionTitle('Batting'),
        if (b.isEmpty)
          const MdNote('Batting details not available.', padding: EdgeInsets.zero)
        else
          NumTable(
            nameHeader: 'Batter',
            columns: const ['R', 'B', '4s', '6s', 'SR'],
            rows: [
              for (final x in b)
                NumRow(
                  key: ValueKey('scorecard_bat_${x.id}'),
                  name: x.name,
                  tags: [if (!x.isOut) const MdTag('not out')],
                  detail: x.isOut && x.outLine.isNotEmpty ? x.outLine : null,
                  values: [x.runs, x.balls, x.fours, x.sixes, x.strikeRate],
                  strongValue: 0,
                  semanticsLabel:
                      '${x.name}${x.isOut ? ', ${x.outLine}' : ', not out'}: ${x.runs} runs from ${x.balls} balls, ${x.fours} fours, ${x.sixes} sixes, strike rate ${x.strikeRate}',
                ),
            ],
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.sm + 2),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.hairline), bottom: BorderSide(color: p.hairline))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Extras', style: AppFont.style(size: 14, weight: FontWeight.w600, color: p.ink)),
                  if (inning.extrasDetail.isNotEmpty)
                    TextSpan(text: '  ${inning.extrasDetail}', style: AppFont.style(size: 13, color: p.inkMuted)),
                ]),
              ),
            ),
            Text(inning.extras, key: const ValueKey('scorecard_extras_total'), style: AppFont.style(size: 14, weight: FontWeight.w700, color: p.ink, tabularFigures: true)),
          ]),
        ),
        if (inning.yetToBat.isNotEmpty)
          Padding(
            key: const ValueKey('scorecard_yet_to_bat'),
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Yet to bat: ', style: AppFont.style(size: 14, weight: FontWeight.w600, color: p.ink)),
              TextSpan(text: inning.yetToBat.map((y) => y.name).join(', '), style: AppFont.style(size: 14, color: p.inkMuted, height: 1.4)),
            ])),
          ),
      ],
    );
  }
}

class _Bowling extends StatelessWidget {
  const _Bowling({required this.inning});
  final ScInning inning;

  @override
  Widget build(BuildContext context) {
    final b = inning.bowling;
    return Column(
      key: const ValueKey('scorecard_bowling'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MdSectionTitle('Bowling'),
        if (b.isEmpty)
          const MdNote('Bowling details not available.', padding: EdgeInsets.zero)
        else
          NumTable(
            nameHeader: 'Bowler',
            columns: const ['O', 'M', 'R', 'W', 'Econ'],
            rows: [
              for (final x in b)
                NumRow(
                  key: ValueKey('scorecard_bowl_${x.id}'),
                  name: x.name,
                  values: [x.overs, x.maidens, x.runs, x.wickets, x.economy],
                  strongValue: 3,
                  semanticsLabel: '${x.name}: ${x.overs} overs, ${x.maidens} maidens, ${x.runs} runs, ${x.wickets} wickets, economy ${x.economy}',
                ),
            ],
          ),
      ],
    );
  }
}

/// Partnership runs between wickets from the fall-of-wickets scores
/// ("5/1", "207/2" → 5, 202). Null entries when a score does not parse.
List<int?> derivedPartnerships(List<ScFow> fow) {
  int? runsOf(String s) => int.tryParse(s.split('/').first.trim());
  final out = <int?>[];
  int? prev = 0;
  for (final f in fow) {
    final r = runsOf(f.score);
    out.add(r != null && prev != null ? r - prev : null);
    prev = r;
  }
  return out;
}

class _Fow extends StatelessWidget {
  const _Fow({required this.inning});
  final ScInning inning;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fow = inning.fallOfWickets;
    final parts = derivedPartnerships(fow);
    return Column(
      key: const ValueKey('scorecard_fow'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MdSectionTitle('Fall of wickets'),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (var i = 0; i < fow.length; i++)
              Container(
                key: ValueKey('scorecard_fow_${fow[i].id}'),
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs + 2),
                decoration: BoxDecoration(border: Border.all(color: p.hairline), borderRadius: BorderRadius.circular(Radii.chip)),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: fow[i].score, style: AppFont.style(size: 14, weight: FontWeight.w800, color: p.ink, tabularFigures: true)),
                  TextSpan(text: '  ${fow[i].name}', style: AppFont.style(size: 13, weight: FontWeight.w500, color: p.ink)),
                  if (fow[i].over != '-')
                    TextSpan(text: '  ${fow[i].over} ov', style: AppFont.style(size: 12, color: p.inkMuted, tabularFigures: true)),
                ])),
              ),
          ],
        ),
        if (parts.any((x) => x != null)) ...[
          const MdSectionTitle('Partnership runs'),
          Wrap(
            key: const ValueKey('scorecard_partnerships'),
            spacing: Spacing.lg,
            runSpacing: Spacing.xs,
            children: [
              for (var i = 0; i < parts.length; i++)
                if (parts[i] != null)
                  Text('${_ordinal(i + 1)} wkt ${parts[i]}', style: AppFont.style(size: 14, color: p.ink, tabularFigures: true)),
            ],
          ),
          const MdNote('Derived from the fall of wickets (runs only; balls are not supplied).'),
        ],
      ],
    );
  }
}

class _ScorecardSkeleton extends StatelessWidget {
  const _ScorecardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading scorecard',
        child: ShimmerGroup(
          child: Padding(
            padding: const EdgeInsets.only(top: Spacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0.5, child: ShimmerBox(height: 22, radius: 4)),
              const SizedBox(height: Spacing.lg),
              const ShimmerBox(height: 28, radius: 4),
              for (var i = 0; i < 6; i++) const Padding(padding: EdgeInsets.only(top: Spacing.sm), child: ShimmerBox(height: 36, radius: 4)),
            ]),
          ),
        ),
      );
}
