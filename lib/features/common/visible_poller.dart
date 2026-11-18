import 'dart:async';

import 'package:flutter/widgets.dart';

/// Periodic refresh that runs only while BOTH the app is in the foreground
/// AND the owning screen is actually visible (its tab is the active shell
/// branch and no detail route is pushed on top of it).
///
/// Extends the idea of core `AutoRefresh` (app lifecycle only) with route /
/// tab visibility — tabs in a StatefulShellRoute.indexedStack stay mounted
/// offstage, so lifecycle alone would keep polling hidden tabs.
///
/// When it becomes active again after being paused it ticks immediately
/// (RN useHomeData: "Returned to foreground — fetch immediately").
/// Overlap protection is the caller's job (the tick should be a no-op while a
/// request is in flight).
class VisiblePoller with WidgetsBindingObserver {
  VisiblePoller({required this.interval, required this.onTick});

  final Duration interval;
  final VoidCallback onTick;

  Timer? _timer;
  bool _started = false;
  bool _appActive = true;
  bool _screenVisible = true;
  bool _disposed = false;

  bool get isRunning => _timer != null;
  bool get _active => _started && !_disposed && _appActive && _screenVisible;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _apply(tickNow: false);
  }

  /// Call from didChangeDependencies with [isScreenVisible].
  void setScreenVisible(bool visible) {
    if (visible == _screenVisible) return;
    final wasActive = _active;
    _screenVisible = visible;
    _apply(tickNow: !wasActive);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _active;
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _appActive = false;
    } else {
      return; // inactive: transient (dialogs, app switcher) — keep state.
    }
    _apply(tickNow: !wasActive);
  }

  void _apply({required bool tickNow}) {
    if (_active) {
      if (_timer != null) return;
      if (tickNow) onTick();
      _timer = Timer.periodic(interval, (_) => onTick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}

/// True when the widget's tab is the active branch (TickerMode) and its route
/// is the top-most one. Registers dependencies, so call it from
/// didChangeDependencies/build to be notified when it changes.
bool isScreenVisible(BuildContext context) =>
    TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
