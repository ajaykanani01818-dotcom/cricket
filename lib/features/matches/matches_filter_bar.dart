import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/app_theme.dart';
import '../common/match_time.dart';
import 'feature_states.dart';
import 'match_filters.dart';

/// Day strip (All dates / Yesterday / Today / Tomorrow / calendar) and the
/// format chips (All / Test / ODI / T20 / Other, plus Women when the data
/// has women's matches). Pure UI: it reports a new [MatchFilters] and never
/// loads anything.
class MatchesFilterBar extends StatelessWidget {
  const MatchesFilterBar({super.key, required this.filters, required this.onChanged, required this.showDays, required this.showWomen});

  final MatchFilters filters;
  final ValueChanged<MatchFilters> onChanged;

  /// Hidden on the Live segment (live means now).
  final bool showDays;
  final bool showWomen;

  Future<void> _pickDate(BuildContext context) async {
    final today = dayOf(MinuteClock.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: filters.day ?? today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'Show matches on',
      confirmText: 'Show',
    );
    if (picked != null) onChanged(filters.copyWith(day: dayOf(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final today = dayOf(MinuteClock.now());
    final quick = {
      'yesterday': DateTime(today.year, today.month, today.day - 1),
      'today': today,
      'tomorrow': DateTime(today.year, today.month, today.day + 1),
    };
    final custom = filters.day != null && !quick.values.contains(filters.day);

    final days = <Widget>[
      _Chip(
        key: const ValueKey('matches_day_all'),
        label: 'All dates',
        selected: filters.day == null,
        onTap: () => onChanged(filters.copyWith(clearDay: true)),
      ),
      for (final e in quick.entries)
        _Chip(
          key: ValueKey('matches_day_${e.key}'),
          label: dayLabel(e.value, today),
          selected: filters.day == e.value,
          onTap: () => onChanged(filters.day == e.value ? filters.copyWith(clearDay: true) : filters.copyWith(day: e.value)),
        ),
      _Chip(
        key: const ValueKey('matches_day_pick'),
        icon: Icons.calendar_month_outlined,
        label: custom ? DateFormat('EEE d MMM', 'en_US').format(filters.day!) : 'Pick a date',
        selected: custom,
        semanticsLabel: custom ? 'Date ${DateFormat.yMMMMEEEEd('en_US').format(filters.day!)}, change date' : 'Pick a date',
        onTap: () => _pickDate(context),
      ),
    ];

    final formats = <Widget>[
      for (final f in FormatFilter.values)
        _Chip(
          key: ValueKey('matches_format_${f.name}'),
          label: f.label,
          selected: filters.format == f,
          onTap: () => onChanged(filters.copyWith(format: f)),
        ),
      if (showWomen || filters.women) ...[
        Container(
          width: 1,
          height: 20,
          color: p.hairline,
          margin: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        ),
        _Chip(
          key: const ValueKey('matches_filter_women'),
          label: 'Women',
          icon: filters.women ? Icons.check : null,
          selected: filters.women,
          onTap: () => onChanged(filters.copyWith(women: !filters.women)),
        ),
      ],
    ];

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: MaxWidthBand(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: Motion.of(context).orZero(Motion.statusCrossfade),
              alignment: Alignment.topCenter,
              child: showDays ? _ChipRow(key: const ValueKey('matches_day_strip'), children: days) : const SizedBox(width: double.infinity),
            ),
            _ChipRow(key: const ValueKey('matches_format_chips'), children: formats),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
    child: Row(
      children: [for (final c in children) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: c)],
    ),
  );
}

/// Filter chip: 32 dp visual inside a 48 dp touch target, radius 6,
/// brandTint fill + ink label when selected (shape and weight change too,
/// so selection is never colour-only).
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.semanticsLabel});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? p.brandTint : p.surface,
                borderRadius: BorderRadius.circular(Radii.chip),
                border: Border.all(color: selected ? p.brand : p.hairline, width: selected ? 1.5 : 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: p.ink), const SizedBox(width: 6)],
                  Text(
                    label,
                    maxLines: 1,
                    style: AppFont.style(
                      size: 13,
                      weight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? p.ink : p.inkMuted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
