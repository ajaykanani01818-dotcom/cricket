/// Build-time configuration. The app talks ONLY to the local
/// livescore-postdata API — there is deliberately no production fallback.
///
/// Values come from `--dart-define-from-file=env/local.json`
/// (see env/local.example.json). Run:
///   flutter run --dart-define-from-file=env/local.json
class Env {
  Env._();

  /// e.g. http://192.168.1.3:8001/api/cricbex (must include /api/cricbex).
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// livescore-postdata's SB_LIVE_SCORE_API_KEY.
  static const String apiKey = String.fromEnvironment('API_KEY');

  static bool get isConfigured => apiBaseUrl.isNotEmpty && apiKey.isNotEmpty;
}
