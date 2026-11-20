import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Ported from RN `useNetworkStatus` — drives the offline banner.
class NetworkStatus extends ValueNotifier<bool> {
  NetworkStatus._() : super(true);
  static final NetworkStatus instance = NetworkStatus._();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get isOnline => value;

  Future<void> start([Connectivity? connectivity]) async {
    final c = connectivity ?? Connectivity();
    try {
      value = _online(await c.checkConnectivity());
    } catch (_) {}
    _sub ??= c.onConnectivityChanged.listen(
      (r) => value = _online(r),
      onError: (_) {},
    );
  }

  static bool _online(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);

  @visibleForTesting
  void debugSet(bool online) => value = online;
}
