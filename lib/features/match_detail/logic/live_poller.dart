import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// `true` while the screen is actually visible to the user:
///  - the app is in the foreground (AppLifecycleState), and
///  - the route is not covered by another opaque route / not in an inactive
///    tab branch (both of those disable [TickerMode] for the subtree).
///
/// Bind the TickerMode notifier from `didChangeDependencies` via
/// [bindTickerMode] (`TickerMode.getValuesNotifier(context)`).
class ScreenVisibility extends ValueNotifier<bool> with WidgetsBindingObserver {
  ScreenVisibility() : super(true) {
    WidgetsBinding.instance.addObserver(this);
    final s = WidgetsBinding.instance.lifecycleState;
    _appActive = s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
    _recompute();
  }

  bool _appActive = true;
  ValueListenable<TickerModeData>? _ticker;
  bool _disposed = false;

  void bindTickerMode(ValueListenable<TickerModeData> notifier) {
    if (identical(notifier, _ticker)) return;
    _ticker?.removeListener(_recompute);
    _ticker = notifier..addListener(_recompute);
    _recompute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appActive = true;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appActive = false;
      case AppLifecycleState.inactive:
        break; // transient (notification shade, app switcher animation)
    }
    _recompute();
  }

  void _recompute() {
    if (_disposed) return;
    value = _appActive && (_ticker?.value.enabled ?? true);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.removeListener(_recompute);
    super.dispose();
  }
}

/// Visibility-aware periodic task.
///  - runs only while [setEnabled] is true AND [visibility] is true;
///  - never overlaps: the next tick is scheduled after the previous one
///    completes;
///  - when the screen becomes visible again after a pause (app resumed /
///    covering route popped) it ticks immediately (data is stale), then
///    continues at [interval].
class Poller {
  Poller({required this.interval, required this.task, required this.visibility}) {
    visibility.addListener(_onVisibility);
  }

  final Duration interval;
  final Future<void> Function() task;
  final ValueListenable<bool> visibility;

  Timer? _timer;
  bool _enabled = false;
  bool _running = false;
  bool _disposed = false;
  bool _missedWhilePaused = false;

  bool get enabled => _enabled;
  bool get isScheduled => _timer?.isActive ?? false;
  bool get isRunning => _running;
  bool get _active => _enabled && visibility.value && !_disposed;

  /// [runNow] — tick immediately instead of waiting one interval.
  void setEnabled(bool enabled, {bool runNow = false}) {
    if (_disposed) return;
    if (enabled == _enabled && !runNow) return;
    _enabled = enabled;
    _missedWhilePaused = false;
    _timer?.cancel();
    _timer = null;
    if (!enabled) return;
    if (runNow) {
      _tick();
    } else {
      _schedule();
    }
  }

  void _onVisibility() {
    if (_disposed || !_enabled) return;
    if (!visibility.value) {
      if (_timer != null) _missedWhilePaused = true;
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_running || _timer != null) return;
    if (_missedWhilePaused) {
      _missedWhilePaused = false;
      _tick();
    } else {
      _schedule();
    }
  }

  void _schedule() {
    if (!_active || _running) return;
    _timer?.cancel();
    _timer = Timer(interval, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    if (!_active || _running) return;
    _running = true;
    try {
      await task();
    } catch (_) {
      // background poll failures are silent
    } finally {
      _running = false;
      if (!_disposed) {
        if (_enabled && !visibility.value) {
          _missedWhilePaused = true;
        } else {
          _schedule();
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    visibility.removeListener(_onVisibility);
  }
}
