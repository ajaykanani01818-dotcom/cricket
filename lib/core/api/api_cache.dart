import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ported from RN `src/services/apiCache.ts`: memory cache + persisted cache
/// with TTLs, so screens can render instantly and refresh in the background.
class CacheTtl {
  CacheTtl._();
  static const live = Duration(seconds: 30);
  static const short = Duration(minutes: 2);
  static const medium = Duration(minutes: 5);
  static const long = Duration(minutes: 10);
  static const extended = Duration(minutes: 30);
}

class _Entry {
  final dynamic data;
  final int timestamp;
  final int ttlMs;
  _Entry(this.data, this.timestamp, this.ttlMs);
  bool get fresh => DateTime.now().millisecondsSinceEpoch - timestamp < ttlMs;
  Map<String, dynamic> toJson() => {'data': data, 'timestamp': timestamp, 'ttl': ttlMs};
}

class ApiCache {
  ApiCache._();
  static const _prefix = '@api_cache:';
  static const _maxEntries = 50;
  static final Map<String, _Entry> _memory = {};

  static String key(String endpoint, [Map<String, Object?>? params]) =>
      '$_prefix$endpoint${params == null ? '' : jsonEncode(params)}';

  /// Fresh cached value or null.
  static Future<dynamic> get(String endpoint, [Map<String, Object?>? params]) async {
    final k = key(endpoint, params);
    final mem = _memory[k];
    if (mem != null) {
      if (mem.fresh) return mem.data;
      _memory.remove(k);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(k);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final entry = _Entry(m['data'], m['timestamp'] as int, m['ttl'] as int);
      if (entry.fresh) {
        _memory[k] = entry;
        return entry.data;
      }
      await prefs.remove(k);
    } catch (_) {}
    return null;
  }

  static Future<void> set(String endpoint, Map<String, Object?>? params, dynamic data, Duration ttl) async {
    final k = key(endpoint, params);
    final entry = _Entry(data, DateTime.now().millisecondsSinceEpoch, ttl.inMilliseconds);
    _memory[k] = entry;
    if (_memory.length > _maxEntries) _memory.remove(_memory.keys.first);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(k, jsonEncode(entry.toJson()));
      final keys = prefs.getKeys().where((e) => e.startsWith(_prefix)).toList();
      if (keys.length > _maxEntries) {
        for (final old in keys.take(keys.length - _maxEntries)) {
          await prefs.remove(old);
        }
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _memory.clear();
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((e) => e.startsWith(_prefix)).toList()) {
      await prefs.remove(k);
    }
  }
}
