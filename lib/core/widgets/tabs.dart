import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SectionTabItem {
  final String key;
  final String label;
  final IconData? icon;
  const SectionTabItem(this.key, this.label, {this.icon});
}

/// Ported from RN `SectionTabs`.
/// - default: underline tabs (blue sliding indicator).
/// - seriesStatus: pill chips.
/// Pass [scrollable] for many tabs. For swipeable pages, drive it from a
/// PageController and call onSelect from onPageChanged.
class SectionTabs extends StatelessWidget {
  const SectionTabs({
    super.key,
    required this.tabs,
    required this.activeKey,
    required this.onSelect,
    this.seriesStatusVariant = false,
    this.scrollable = false,
  });
  final List<SectionTabItem> tabs;
  final String activeKey;
  final ValueChanged<String> onSelect;
  final bool seriesStatusVariant;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (seriesStatusVariant) {
      final p = context.palette;
      return Container(
        color: p.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in tabs)
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.sm),
                  child: ChoiceChip(
                    key: ValueKey('tab_${t.key}'),
                    label: Text(t.label),
                    selected: t.key == activeKey,
                    onSelected: (_) => onSelect(t.key),
                    showCheckmark: false,
                    selectedColor: p.brandTint,
                    backgroundColor: p.surface,
                    side: BorderSide(
                      color: t.key == activeKey ? p.brand : p.hairline,
                    ),
                    labelStyle: AppFont.style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: p.ink,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final p = context.palette;
    Widget tab(SectionTabItem t) {
      final active = t.key == activeKey;
      return InkWell(
        key: ValueKey('tab_${t.key}'),
        onTap: () => onSelect(t.key),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: scrollable ? 14 : 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.icon != null) ...[
                      Icon(
                        t.icon,
                        size: 16,
                        color: active ? p.ink : p.inkMuted,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        t.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                          size: 14,
                          weight: active ? FontWeight.w700 : FontWeight.w600,
                          color: active ? p.ink : p.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: active ? 28 : 0,
                decoration: BoxDecoration(
                  color: p.brand,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      padding: const EdgeInsets.only(top: 4),
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: tabs.map(tab).toList()),
            )
          : Row(children: tabs.map((t) => Expanded(child: tab(t))).toList()),
    );
  }
}

class SegmentOption<K> {
  final K key;
  final String label;
  const SegmentOption(this.key, this.label);
}

/// Ported from RN `SegmentedControl`: dark sliding pill on a light track.
class SegmentedControl<K> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });
  final List<SegmentOption<K>> options;
  final K value;
  final ValueChanged<K> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final index = options
        .indexWhere((o) => o.key == value)
        .clamp(0, options.length - 1);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.ink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final o in options)
                    Expanded(
                      child: InkWell(
                        key: ValueKey('segment_${o.key}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onChanged(o.key),
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: compact ? 30 : 34,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            o.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: o.key == value ? p.surface : p.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
