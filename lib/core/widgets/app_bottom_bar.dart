import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One destination of [AppBottomBar].
@immutable
class AppBottomBarItem {
  const AppBottomBarItem({
    required this.icon,
    required this.label,
    required this.keyName,
  });
  final IconData icon;
  final String label;

  /// Test key suffix: the item is keyed `tab_bar_<keyName>`.
  final String keyName;
}

/// The owner's bottom bar: solid brand #ED800C, FIXED and flush to the
/// bottom edge, full width, square corners, [barHeight] dp plus the
/// gesture/safe-area inset — which is filled with the same orange. It never
/// scrolls or hides. Use it as `Scaffold.bottomNavigationBar` with
/// `extendBody: false` so no content sits under it.
///
/// Items: filled icons in onBrand at 72 %; the active item is an ink pill
/// with a brand-coloured icon, and its label is full onBrand. Labels stay
/// visible at 12 sp minimum and never wrap.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppBottomBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double barHeight = 64;

  /// Max width of the item row (the orange bar itself is always full width).
  static const double maxItemsWidth = 600;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inset = MediaQuery.paddingOf(context).bottom;
    return Material(
      key: const ValueKey('app_bottom_bar'),
      color: p.brand,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: barHeight,
          // The bar spans the full width; on tablets/desktop the five items
          // stay grouped in the middle instead of spreading edge to edge.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxItemsWidth),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _Item(
                        item: items[i],
                        selected: i == currentIndex,
                        onTap: () => onTap(i),
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

class _Item extends StatelessWidget {
  const _Item({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final AppBottomBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.onBrand : p.onBrand.withValues(alpha: 0.72);
    // Labels: scale with the user's text size up to 1.3x so five labels fit
    // at 320 dp; never below 12 sp.
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(minScaleFactor: 1, maxScaleFactor: 1.3);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey('tab_bar_${item.keyName}'),
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        splashColor: p.onBrand.withValues(alpha: 0.12),
        highlightColor: p.onBrand.withValues(alpha: 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? p.onBrand : null,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 22, color: selected ? p.brand : fg),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                textScaler: scaler,
                style: AppFont.style(
                  size: 12,
                  weight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: fg,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
