import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';

/// Minimal load/refresh/error state holder used by screens.
///  - keeps showing previous data while refreshing (no flicker)
///  - ignores results that arrive after dispose or after a newer request
///    (prevents setState-after-dispose and stale overwrites)
class Loadable<T> extends ChangeNotifier {
  Loadable(this._loader);
  final Future<T> Function() _loader;

  T? data;
  Object? error;
  bool loading = false;
  int _generation = 0;
  bool _disposed = false;

  bool get hasData => data != null;
  String? get errorMessage => error == null ? null : friendlyError(error!);

  Future<void> load({bool silent = false}) async {
    final gen = ++_generation;
    loading = true;
    if (!silent) error = null;
    _notify();
    try {
      final result = await _loader();
      if (_disposed || gen != _generation) return;
      data = result;
      error = null;
    } catch (e) {
      if (_disposed || gen != _generation) return;
      error = e;
    } finally {
      if (!_disposed && gen == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Periodic refresh that pauses while the app is backgrounded.
class AutoRefresh with WidgetsBindingObserver {
  AutoRefresh(this.interval, this.onTick);
  final Duration interval;
  final VoidCallback onTick;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onTick();
      _schedule();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  void stop() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
