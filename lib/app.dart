import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/startup/startup_screens.dart';

enum _Phase { splash, onboarding, main }

/// Startup sequence (same as RN App.tsx): Splash → (optional) Onboarding → Main.
class CrickbexApp extends StatefulWidget {
  const CrickbexApp({super.key, this.skipSplash = false, this.router});

  /// Tests start straight in the main app.
  final bool skipSplash;
  final GoRouter? router;

  @override
  State<CrickbexApp> createState() => _CrickbexAppState();
}

class _CrickbexAppState extends State<CrickbexApp> {
  late _Phase _phase = widget.skipSplash ? _Phase.main : _Phase.splash;
  late final GoRouter _router = widget.router ?? buildRouter();

  Future<void> _afterSplash() async {
    final show = await shouldShowOnboarding();
    if (!mounted) return;
    setState(() => _phase = show ? _Phase.onboarding : _Phase.main);
  }

  Future<void> _onboardingDone() async {
    await markOnboardingComplete();
    if (mounted) setState(() => _phase = _Phase.main);
  }

  @override
  void dispose() {
    if (widget.router == null) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildAppTheme();
    if (!Env.isConfigured && !widget.skipSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'API not configured.\nRun with --dart-define-from-file=env/local.json\n(API_BASE_URL + API_KEY of local livescore-postdata).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    switch (_phase) {
      case _Phase.splash:
        return MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: SplashScreen(onFinish: _afterSplash));
      case _Phase.onboarding:
        return MaterialApp(debugShowCheckedModeBanner: false, theme: theme, scrollBehavior: const AppScrollBehavior(), home: OnboardingScreen(onComplete: _onboardingDone));
      case _Phase.main:
        return MaterialApp.router(
          title: 'CrickBex',
          debugShowCheckedModeBanner: false,
          theme: theme,
          routerConfig: _router,
          scrollBehavior: const AppScrollBehavior(),
          // Version gate + rating prompt sit above every route.
          builder: (context, child) => AppChrome(child: child ?? const SizedBox.shrink()),
        );
    }
  }
}
