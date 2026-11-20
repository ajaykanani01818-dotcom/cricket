import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/network_status.dart';
import 'core/services/cricket_services.dart';
import 'core/theme/theme_controller.dart';
import 'features/ads/ads.dart';
import 'features/startup/startup_screens.dart';
import 'features/startup/startup_video.dart';

/// Brand intro on cold start. Off with --dart-define=STARTUP_INTRO=false.
const bool _kIntro = bool.fromEnvironment('STARTUP_INTRO', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final intro = _introEnabled();
  if (intro) StartupVideoIntro.preload();
  // Theme choice is read before the first frame so the app never flashes
  // the wrong theme; it also styles the status and navigation bars. The
  // intro's mark is decoded meanwhile (≤300 ms) so the first Flutter frame
  // matches the native splash exactly.
  await Future.wait([
    ThemeController.instance.load(),
    NetworkStatus.instance.start(),
    if (intro) IntroAssets.warmUp(),
  ]);
  // Warm DNS/TLS to the API while the intro plays (result ignored).
  MatchService.instance.getLiveMatches().then((_) {}, onError: (_) {});
  runApp(
    CrickbexApp(showIntro: intro, introFreezeAt: intro ? _introFreeze() : null),
  );
  // Ads start once the app is running (never blocking first paint).
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => AdsManager.instance.initialize(),
  );
}

/// Mobile: always. Web (dev/screenshot builds only): opt in with `?intro=1`
/// so the shared responsive screenshot harness is unaffected.
bool _introEnabled() {
  if (!_kIntro) return false;
  if (!kIsWeb) return true;
  final q = Uri.base.queryParameters;
  return q.containsKey('intro') || q.containsKey('intro_t');
}

/// Web screenshot aid: `?intro_t=700` holds the intro at 700 ms.
Duration? _introFreeze() {
  if (!kIsWeb) return null;
  final ms = int.tryParse(Uri.base.queryParameters['intro_t'] ?? '');
  return ms == null ? null : Duration(milliseconds: ms);
}
