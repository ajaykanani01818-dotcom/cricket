import '../../core/storage/prefs.dart';

/// Onboarding configuration — ported from RN `src/config/onboardingConfig.ts`.
///
/// [alwaysShowOnboarding]:
///   - true  → show onboarding every app launch
///   - false → show only on first launch (persisted via [AppPrefs])
///   - null  → never show onboarding
class OnboardingConfig {
  OnboardingConfig._();

  static bool? alwaysShowOnboarding = false;

  /// RN setOnboardingConfigFromRemote: accepts only bool or explicit null.
  static void setFromRemote(Map<String, Object?> payload) {
    if (!payload.containsKey('always_show_onboarding')) return;
    final v = payload['always_show_onboarding'];
    if (v == null || v is bool) alwaysShowOnboarding = v as bool?;
  }

  static bool get isAlwaysShow => alwaysShowOnboarding == true;
  static bool get isDisabled => alwaysShowOnboarding == null;
}

/// RN App.tsx `shouldShowOnboarding()`.
Future<bool> shouldShowOnboarding() async {
  if (OnboardingConfig.isDisabled) return false;
  if (OnboardingConfig.isAlwaysShow) return true;
  try {
    return !(await AppPrefs.hasSeenOnboarding());
  } catch (_) {
    return true;
  }
}

/// RN App.tsx `handleOnboardingComplete` persistence step.
Future<void> markOnboardingComplete() async {
  if (OnboardingConfig.isAlwaysShow) return;
  try {
    await AppPrefs.setHasSeenOnboarding();
  } catch (_) {}
}
