import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Recent search queries, stored on the device only (PRD §11), newest
/// first, case-insensitively unique, at most [max]. Settings can offer
/// "Clear recent searches" through [clear].
class RecentSearches {
  RecentSearches._();

  static const prefsKey = 'recentSearches';
  static const max = 8;

  static Future<List<String>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(prefsKey);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is String && e.trim().isNotEmpty) e.trim(),
      ].take(max).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> add(String query) async {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    final current = await load();
    if (q.length < 2) return current;
    final next = [
      q,
      ...current.where((e) => e.toLowerCase() != q.toLowerCase()),
    ].take(max).toList();
    await _save(next);
    return next;
  }

  static Future<List<String>> remove(String query) async {
    final next = [
      for (final e in await load())
        if (e.toLowerCase() != query.toLowerCase()) e,
    ];
    await _save(next);
    return next;
  }

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(prefsKey);

  static Future<void> _save(List<String> list) async =>
      (await SharedPreferences.getInstance()).setString(
        prefsKey,
        jsonEncode(list),
      );
}
