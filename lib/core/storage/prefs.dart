import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted flags — ported from RN onboardingStorage / reviewStorage /
/// useFavorites / noAdsStorage (same semantics, SharedPreferences instead of AsyncStorage).
class AppPrefs {
  AppPrefs._();
  static const _onboardingSeen = 'hasSeenOnboarding';
  static const _favorites = 'favorites';

  static Future<bool> hasSeenOnboarding() async =>
      (await SharedPreferences.getInstance()).getBool(_onboardingSeen) ?? false;

  static Future<void> setHasSeenOnboarding() async =>
      (await SharedPreferences.getInstance()).setBool(_onboardingSeen, true);

  static Future<Set<String>> favorites() async =>
      ((await SharedPreferences.getInstance()).getStringList(_favorites) ??
              const [])
          .toSet();

  static Future<bool> toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_favorites) ?? const []).toSet();
    final added = set.add(id);
    if (!added) set.remove(id);
    await prefs.setStringList(_favorites, set.toList());
    return added;
  }

  static Future<int?> getInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key);
  static Future<void> setInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);
  static Future<bool?> getBool(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key);
  static Future<void> setBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);
  static Future<String?> getString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  static Future<void> setString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
