import 'package:flutter/widgets.dart';

import '../../../core/widgets/async_value.dart';

/// Secondary-tab polling while live (stats, line-ups): every 30 s. The
/// score itself polls every 10 s in the screen. Pauses while the app is
/// backgrounded ([AutoRefresh]) and skips ticks while this subtree's
/// tickers are disabled (route covered / offstage tab).
mixin LiveTabPolling<T extends StatefulWidget> on State<T> {
  static const pollInterval = Duration(seconds: 30);
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
