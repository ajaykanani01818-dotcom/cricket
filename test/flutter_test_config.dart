import 'dart:async';

import 'package:crickbex/features/ads/ads_config.dart';
import 'package:crickbex/features/startup/startup_video.dart';

/// Applies to every test file. Production ships with ads switched off
/// (AdsConfig.adsHardDisabled) and plays the splash from a video; tests
/// exercise the ads logic and the code-drawn intro (no platform decoder).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AdsConfig.adsHardDisabled = false;
  StartupVideoIntro.enabled = false;
  await testMain();
}
