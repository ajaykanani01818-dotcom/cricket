import 'package:flutter/material.dart';

import '../../../core/api/json.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import 'match_section_title.dart';
import 'tab_common.dart';
import 'tab_scorecard_parse.dart';

/// Ported from RN `MatchScorecardTab`.
/// [scorecard] is the `data` object of GET /match/:id/scorecard (null while
/// loading / when absent). The `{result: {...}}` wrapper is unwrapped by
/// [parseScorecard]; the already-unwrapped `result` object is accepted too.
///
/// Performance: the payload is parsed only when a new map identity arrives,
/// and the parsed view-model is kept when its content is unchanged, so live
/// polls with identical data reuse the previously built subtree.
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
  int _selected = 0;

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
    if (next == _view) return; // same content → keep old instance (cached subtree)
    _view = next;
    // RN keeps the index; clamp so a shorter payload can't index out of range.
    if (_selected >= _view.innings.length) _selected = 0;
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (widget.loading && !view.hasInnings) {
      return const TabLoading(key: ValueKey('scorecard_loading'), text: 'Loading scorecard...');
    }
    if (!view.hasInnings) {
      return const Padding(
        key: ValueKey('scorecard_empty'),
        padding: EdgeInsets.all(40),
        child: TabEmptyText('No scorecard data available'),
      );
    }
    if (_built == null || !identical(_builtView, view) || _builtSelected != _selected) {
      _builtView = view;
      _builtSelected = _selected;
      _built = _ScorecardBody(view: view, selected: _selected, onSelect: _select);
    }
    return _built ?? const SizedBox.shrink();
  }
}

class _ScorecardBody extends StatelessWidget {
  const _ScorecardBody({required this.view, required this.selected, required this.onSelect});
  final ScorecardView view;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final inning = view.innings[selected];
    final target = view.target;
    return TabScrollBody(
      storageKey: 'match_scorecard_tab',
      children: [
        if (target != null) _TargetCard(target: target),
        _HeroCard(view: view, inning: inning, selected: selected, onSelect: onSelect),
        _BattingSection(inning: inning),
        _BowlingSection(inning: inning),
        if (inning.fallOfWickets.isNotEmpty) _FowSection(inning: inning),
      ],
    );
  }
}

// ── Target ──────────────────────────────────────────────────────────────────

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.target});
  final String target;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('scorecard_target'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.gold.withAlpha(0x12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withAlpha(0x55)),
      ),
      child: Row(
        children: [
          const Icon(Icons.track_changes, size: 16, color: AppColors.goldDark),
          const SizedBox(width: 10),
          const Text('TARGET',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.goldDark, letterSpacing: 0.7)),
          const Spacer(),
          Text(target,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.goldDark, fontFeatures: tabularFigures)),
          const SizedBox(width: 4),
          Text(' runs',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.goldDark.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

// ── Hero card: inning dropdown, team, score, extras ─────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.view, required this.inning, required this.selected, required this.onSelect});
  final ScorecardView view;
  final ScInning inning;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final short = inning.shortName;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _InningDropdown(view: view, selected: selected, onSelect: onSelect),
          ),
          Container(height: 0.5, color: AppColors.borderSubtle, margin: const EdgeInsets.symmetric(vertical: 8)),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inning.teamName,
                    key: const ValueKey('scorecard_hero_team'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text, height: 19 / 14)),
                const SizedBox(height: 2),
                Text('Innings ${selected + 1}${short != null ? ' · $short' : ''}',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.12)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text.rich(
                          key: const ValueKey('scorecard_hero_score'),
                          TextSpan(children: [
                            TextSpan(text: inning.runs, style: _heroRuns),
                            const TextSpan(
                                text: '/',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                            TextSpan(text: inning.wickets, style: _heroRuns),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('RUNS',
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: 0.3)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
                  decoration: BoxDecoration(
                    color: AppColors.pitch.withAlpha(0x18),
                    borderRadius: BorderRadius.circular(Radii.full),
                    border: Border.all(color: AppColors.pitch.withAlpha(0x35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 11, color: AppColors.pitch),
                      const SizedBox(width: 3),
                      Text('${inning.overs} overs',
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.pitchDark, fontFeatures: tabularFigures)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 15, color: AppColors.pitch),
                    const SizedBox(width: 6),
                    const Expanded(
                        child: Text('Extras', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text))),
                    Text(inning.extras,
                        key: const ValueKey('scorecard_extras_total'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.pitch, fontFeatures: tabularFigures)),
                  ],
                ),
                if (inning.extrasDetail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(inning.extrasDetail,
                      style: const TextStyle(
                          fontSize: 12, height: 17 / 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _heroRuns = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.pitch, fontFeatures: tabularFigures, letterSpacing: -0.2);

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.url, required this.size, required this.iconSize});
  final String? url;
  final double size, iconSize;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u != null) return NetImage(url: u, size: size, background: AppColors.borderSubtle, fallbackLetter: '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.borderSubtle,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Icon(Icons.flag_outlined, size: iconSize, color: AppColors.pitch),
    );
  }
}

/// RN renders the menu absolutely positioned under the trigger, over the
/// content below. Here: an [OverlayPortal] that follows the trigger; a tap
/// outside closes it.
class _InningDropdown extends StatefulWidget {
  const _InningDropdown({required this.view, required this.selected, required this.onSelect});
  final ScorecardView view;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<_InningDropdown> createState() => _InningDropdownState();
}

class _InningDropdownState extends State<_InningDropdown> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _groupId = Object();
  double _width = 0;

  void _toggle() => setState(() => _portal.isShowing ? _portal.hide() : _portal.show());

  void _close() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final inning = view.innings[widget.selected];
    final open = _portal.isShowing;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 6),
            child: TapRegion(
              groupId: _groupId,
              onTapOutside: (_) => _close(),
              child: SizedBox(width: _width, child: _menu(view)),
            ),
          ),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          _width = constraints.maxWidth;
          return TapRegion(
            groupId: _groupId,
            child: GestureDetector(
              key: const ValueKey('scorecard_inning_dropdown'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    _TeamLogo(url: inning.logo, size: 36, iconSize: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inning.teamName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text, height: 18 / 14)),
                          const SizedBox(height: 2),
                          Text('Innings ${widget.selected + 1}',
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.pitch,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.pitchDark.withAlpha(0x55), width: 1.5),
                      ),
                      child: Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 17, color: AppColors.white),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _menu(ScorecardView view) {
    return Material(
      key: const ValueKey('scorecard_inning_menu'),
      color: AppColors.card,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < view.innings.length; i++) _option(view.innings[i], i),
        ],
      ),
    );
  }

  Widget _option(ScInning inning, int index) {
    final active = index == widget.selected;
    return InkWell(
      key: ValueKey('scorecard_inning_option_$index'),
      onTap: () {
        _close();
        widget.onSelect(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.pitch.withAlpha(0x10) : null,
          border: const Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 0.5)),
        ),
        child: Row(
          children: [
            _TeamLogo(url: inning.logo, size: 32, iconSize: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inning.teamName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 17 / 13,
                          color: active ? AppColors.pitchDark : AppColors.text)),
                  const SizedBox(height: 2),
                  Text('Innings ${index + 1}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 24,
              child: active ? const Icon(Icons.check_circle, size: 20, color: AppColors.pitch) : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tables ──────────────────────────────────────────────────────────────────

const _cellStyle = TextStyle(fontSize: 12, color: AppColors.text, fontFeatures: tabularFigures);
const _nameStyle = TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w600);
const _headStatStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText);
const _headNameStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText);

Widget _statCell(String text, {double width = 32, TextStyle style = _cellStyle}) => SizedBox(
      width: width,
      child: Padding(padding: const EdgeInsets.only(top: 1), child: Text(text, textAlign: TextAlign.center, style: style)),
    );

Widget _headCell(String text, {double width = 32}) =>
    SizedBox(width: width, child: Text(text, textAlign: TextAlign.center, style: _headStatStyle));

class _StatSection extends StatelessWidget {
  const _StatSection({required this.icon, required this.label, required this.children, super.key});
  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [MatchSectionTitle(icon: icon, label: label, variant: 'stat'), ...children],
        ),
      );
}

class _Table extends StatelessWidget {
  const _Table({required this.header, required this.rows});
  final List<Widget> header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.tableHeaderBg,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(children: header),
            ),
            ...rows,
          ],
        ),
      );
}

BoxDecoration _rowDecoration(bool first) => BoxDecoration(
      color: AppColors.cardAlt,
      border: first ? null : const Border(top: BorderSide(color: AppColors.borderSubtle, width: 0.5)),
    );

class _BattingSection extends StatelessWidget {
  const _BattingSection({required this.inning});
  final ScInning inning;

  @override
  Widget build(BuildContext context) {
    final batting = inning.batting;
    return _StatSection(
      key: const ValueKey('scorecard_batting'),
      icon: Icons.sports_cricket, // RN 🏏
      label: 'Batting',
      children: [
        _Table(
          header: [
            const Expanded(
                child: Padding(padding: EdgeInsets.only(right: 4), child: Text('Batter', style: _headNameStyle))),
            _headCell('R'),
            _headCell('B'),
            _headCell('4s'),
            _headCell('6s'),
            _headCell('SR', width: 42),
          ],
          rows: batting.isEmpty
              ? const [TabEmptyText('No batting data')]
              : [
                  for (var i = 0; i < batting.length; i++)
                    Container(
                      key: ValueKey('scorecard_bat_${batting[i].id}'),
                      decoration: _rowDecoration(i == 0),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    batting[i].isOut ? batting[i].name : '${batting[i].name} *',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: batting[i].isOut ? _nameStyle : _nameStyle.copyWith(color: AppColors.win),
                                  ),
                                ),
                              ),
                              _statCell(batting[i].runs),
                              _statCell(batting[i].balls),
                              _statCell(batting[i].fours),
                              _statCell(batting[i].sixes),
                              _statCell(batting[i].strikeRate, width: 42),
                            ],
                          ),
                          if (batting[i].outLine.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                              child: Text(batting[i].outLine,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 17 / 12)),
                            ),
                        ],
                      ),
                    ),
                ],
        ),
        if (inning.yetToBat.isNotEmpty)
          Container(
            key: const ValueKey('scorecard_yet_to_bat'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSubtle))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Yet to Bat:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in inning.yetToBat)
                      Container(
                        key: ValueKey('scorecard_ytb_${p.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.cardAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(p.name, style: const TextStyle(fontSize: 12, color: AppColors.text)),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BowlingSection extends StatelessWidget {
  const _BowlingSection({required this.inning});
  final ScInning inning;

  @override
  Widget build(BuildContext context) {
    final bowling = inning.bowling;
    return _StatSection(
      key: const ValueKey('scorecard_bowling'),
      icon: Icons.sports_baseball, // RN ⚾
      label: 'Bowling',
      children: [
        _Table(
          header: [
            const Expanded(
                child: Padding(padding: EdgeInsets.only(right: 4), child: Text('Bowler', style: _headNameStyle))),
            _headCell('O'),
            _headCell('M'),
            _headCell('R'),
            _headCell('W'),
            _headCell('Econ.', width: 44),
          ],
          rows: bowling.isEmpty
              ? const [TabEmptyText('No bowling data')]
              : [
                  for (var i = 0; i < bowling.length; i++)
                    Container(
                      key: ValueKey('scorecard_bowl_${bowling[i].id}'),
                      decoration: _rowDecoration(i == 0),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(bowling[i].name, maxLines: 2, overflow: TextOverflow.ellipsis, style: _nameStyle),
                            ),
                          ),
                          _statCell(bowling[i].overs),
                          _statCell(bowling[i].maidens),
                          _statCell(bowling[i].runs),
                          _statCell(bowling[i].wickets),
                          _statCell(bowling[i].economy, width: 44),
                        ],
                      ),
                    ),
                ],
        ),
      ],
    );
  }
}

class _FowSection extends StatelessWidget {
  const _FowSection({required this.inning});
  final ScInning inning;

  @override
  Widget build(BuildContext context) {
    final fow = inning.fallOfWickets;
    return _StatSection(
      key: const ValueKey('scorecard_fow'),
      icon: Icons.track_changes, // RN 🎯
      label: 'Fall of Wickets',
      children: [
        _Table(
          header: [
            _headCell('#'),
            const Expanded(
                child: Padding(padding: EdgeInsets.only(right: 4), child: Text('Batter', style: _headNameStyle))),
            _headCell('Score', width: 56),
            _headCell('Over', width: 44),
          ],
          rows: [
            for (var i = 0; i < fow.length; i++)
              Container(
                key: ValueKey('scorecard_fow_${fow[i].id}'),
                decoration: _rowDecoration(i == 0),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text('${i + 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, fontFeatures: tabularFigures)),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(fow[i].name, maxLines: 2, overflow: TextOverflow.ellipsis, style: _nameStyle),
                      ),
                    ),
                    SizedBox(width: 56, child: Text(fow[i].score, textAlign: TextAlign.center, style: _cellStyle)),
                    SizedBox(
                      width: 44,
                      child: Text(fow[i].over,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error, fontFeatures: tabularFigures)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
