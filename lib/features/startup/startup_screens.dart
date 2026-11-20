/// Startup: native splash (icon mark on #17130F) → ≤1.4 s animated brand
/// intro over the already-loading Home → Home. No onboarding.
library;

export 'app_chrome.dart' show AppChrome;
export 'startup_intro.dart'
    show
        StartupIntroHost,
        StartupIntro,
        IntroTimeline,
        IntroGeometry,
        IntroAssets;
export 'version_gate.dart'
    show
        VersionUpdateGate,
        VersionGateConfig,
        versionGateConfig,
        compareSemver,
        isUpdateRequired;
