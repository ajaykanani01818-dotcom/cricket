import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value.dart';

/// Shared bits for the Match Detail sub-tabs (scorecard / playing XI / stats).

/// Body of a tab. RN renders each tab as a nested `ScrollView` inside the page
/// ScrollView, so the host screen may give us either a bounded height (tab
/// view / Expanded) or an unbounded one (inside a parent scroll view).
///  - bounded   → own ListView with a [PageStorageKey] (scroll offset survives
///                rebuilds and tab switches),
///  - unbounded → plain Column; the parent scroll view scrolls.
class TabScrollBody extends StatelessWidget {
  const TabScrollBody({super.key, required this.storageKey, required this.children, this.padding = EdgeInsets.zero});

  final String storageKey;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedHeight) {
        return Padding(
          padding: padding,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
      }
      return ListView(key: PageStorageKey<String>(storageKey), padding: padding, children: children);
    });
  }
}

/// Centered spinner + caption (RN `loadingContainer` / `loadingText`).
class TabLoading extends StatelessWidget {
  const TabLoading({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppColors.pitch)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
      );
}

/// RN `emptyText` (muted centered text with padding 20).
class TabEmptyText extends StatelessWidget {
  const TabEmptyText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
      );
}

/// Live polling every 15s (RN `setInterval(..., 15000)` when `isLive`).
/// Pauses while the app is backgrounded ([AutoRefresh]) and skips ticks while
/// this subtree's tickers are disabled (route covered / offstage tab).
mixin LiveTabPolling<T extends StatefulWidget> on State<T> {
  static const pollInterval = Duration(seconds: 15);
  AutoRefresh? _poller;

  void configurePolling(bool isLive, VoidCallback onTick) {
    stopPolling();
    if (!isLive) return;
    _poller = AutoRefresh(pollInterval, () {
      if (!mounted) return;
      if (!TickerMode.getValuesNotifier(context).value.enabled) return;
      onTick();
    })
      ..start();
  }

  void stopPolling() {
    _poller?.stop();
    _poller = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

const tabularFigures = [FontFeature.tabularFigures()];
