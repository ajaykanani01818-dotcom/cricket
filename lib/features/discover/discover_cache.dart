import 'dart:async';

import 'package:flutter/foundation.dart';

/// Small in-memory cache shared by the Discover hub, Rankings and Players:
/// successful results are kept for [ttl], identical in-flight requests are
/// shared, failures are never cached (the next visit retries).
class DiscoverCache {
  DiscoverCache._();

  static const defaultTtl = Duration(minutes: 10);
  static final Map<String, (DateTime, Object?)> _values = {};
  static final Map<String, Future<Object?>> _inFlight = {};

  /// Fresh cached value for [key], or null.
  static T? peek<T>(String key, {Duration ttl = defaultTtl}) {
    final v = _values[key];
    if (v == null) return null;
    if (DateTime.now().difference(v.$1) > ttl) {
      _values.remove(key);
      return null;
    }
    final data = v.$2;
    return data is T ? data : null;
  }

  /// Cached value, or the result of [load] (stored on success).
  /// [force] skips the cached value (pull-to-refresh, retry).
  static Future<T> get<T>(
    String key,
    Future<T> Function() load, {
    Duration ttl = defaultTtl,
    bool force = false,
  }) async {
    if (!force) {
      final hit = peek<T>(key, ttl: ttl);
      if (hit != null) return hit;
    }
    final pending = _inFlight[key];
    if (pending != null) return (await pending) as T;
    final future = load();
    _inFlight[key] = future;
    try {
      final value = await future;
      _values[key] = (DateTime.now(), value);
      return value;
    } finally {
      _inFlight.remove(key);
    }
  }

  @visibleForTesting
  static void clear() {
    _values.clear();
    _inFlight.clear();
  }
}
