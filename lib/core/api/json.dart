/// Null-safe accessors for loosely-typed API JSON (the API is not strict about
/// types: numbers sometimes arrive as strings, fields are often missing).
typedef JsonMap = Map<String, dynamic>;

class J {
  J._();

  static JsonMap map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  static List<dynamic> list(dynamic v) => v is List ? v : const [];

  static List<JsonMap> maps(dynamic v) =>
      list(v).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  static String str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    return v.toString();
  }

  /// Trimmed string or null when empty/"-".
  static String? text(dynamic v) {
    final s = str(v).trim();
    return s.isEmpty || s == '-' ? null : s;
  }

  static int? integer(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.isFinite ? v.toInt() : null;
    if (v is String) {
      final t = v.trim();
      final i = int.tryParse(t);
      if (i != null) return i;
      final d = double.tryParse(t);
      return d != null && d.isFinite ? d.toInt() : null;
    }
    return null;
  }

  /// Finite double or null ("NaN"/"Infinity" are treated as missing).
  static double? number(dynamic v) {
    final d = v is num
        ? v.toDouble()
        : (v is String ? double.tryParse(v.trim()) : null);
    return d != null && d.isFinite ? d : null;
  }

  static bool boolean(dynamic v, [bool fallback = false]) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return fallback;
  }

  /// Walks a dotted path, e.g. J.at(json, 'teams.t1.name').
  static dynamic at(dynamic v, String path) {
    dynamic cur = v;
    for (final part in path.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else if (cur is List) {
        final i = int.tryParse(part);
        cur = (i != null && i >= 0 && i < cur.length) ? cur[i] : null;
      } else {
        return null;
      }
    }
    return cur;
  }
}
