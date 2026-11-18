import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/network/network_status.dart';
import 'features/ads/ads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await NetworkStatus.instance.start();
  runApp(const CrickbexApp());
  // Ads start once the app is running (never on/blocking the splash).
  WidgetsBinding.instance.addPostFrameCallback((_) => AdsManager.instance.initialize());
}
