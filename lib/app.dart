import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand/brand.dart';
import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/empty_state.dart';
import 'features/startup/startup_screens.dart';

/// Root widget. Launches straight into the router (Home), no onboarding.
/// On a cold start ([showIntro]) the ≤1.4 s brand intro plays on top of the
/// already-building Home ([StartupIntroHost]), then fades into it. Theme follows [ThemeController] (System / Light /
/// Dark); switching rebuilds the MaterialApp but never the router, so every
/// tab keeps its navigation stack.
class CrickbexApp extends StatefulWidget {
  const CrickbexApp({
    super.key,
    this.router,
    this.themeController,
    this.requireEnv = true,
    this.showIntro = false,
    this.introFreezeAt,
  });

  final GoRouter? router;

  /// Defaults to [ThemeController.instance].
  final ThemeController? themeController;

  /// Show the "API not configured" screen when no env is compiled in.
  /// Tests pass false.
  final bool requireEnv;

  /// Play the animated brand intro over Home (main.dart: cold start).
  final bool showIntro;

  /// Screenshot aid: hold the intro at this time (see [StartupIntroHost]).
  final Duration? introFreezeAt;

  @override
  State<CrickbexApp> createState() => _CrickbexAppState();
}

class _CrickbexAppState extends State<CrickbexApp> {
  late final GoRouter _router = widget.router ?? buildRouter();
  ThemeController get _theme =>
      widget.themeController ?? ThemeController.instance;

  static final _light = buildAppTheme();
  static final _dark = buildAppTheme(brightness: Brightness.dark);

  @override
  void dispose() {
    if (widget.router == null) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requireEnv && !Env.isConfigured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: Brand.appName,
        theme: _light,
        darkTheme: _dark,
        home: const Scaffold(
          body: Center(
            child: EmptyState(
              icon: Icons.settings_ethernet,
              title: 'API not configured',
              subtitle:
                  'Run with --dart-define-from-file=env/local.json (API_BASE_URL and API secret of the local API).',
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp.router(
        title: Brand.appName,
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: _theme.mode,
        themeAnimationDuration: Duration.zero,
        routerConfig: _router,
        scrollBehavior: const AppScrollBehavior(),
        // Version gate + rating prompt sit above every route.
        builder: (context, child) => StartupIntroHost(
          enabled: widget.showIntro,
          freezeAt: widget.introFreezeAt,
          child: PaletteSync(
            child: AppChrome(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
