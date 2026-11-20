import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage/prefs.dart';
import 'app_theme.dart';

/// User theme choice: System (default), Light or Dark. Persisted in
/// [AppPrefs] under [prefsKey], loaded before `runApp` ([load]) and applied
/// instantly (no tween) without touching the navigation state: the router is
/// owned above the MaterialApp and is never rebuilt.
///
/// Legacy `AppColors.*` getters read [AppPalette.active], which this class
/// keeps in sync with the effective brightness. Because `const` widgets built
/// with the old palette would not rebuild on their own, a brightness change
/// marks EVERY element dirty ([rebuildAllElements]).
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const prefsKey = 'themeMode';

  /// Test/screenshot override: `--dart-define=THEME_MODE=dark|light|system`
  /// wins over the stored choice (not persisted).
  static const _forced = String.fromEnvironment('THEME_MODE');

  ThemeMode _mode = ThemeMode.system;
  bool _observing = false;

  ThemeMode get mode => _mode;

  /// Brightness actually on screen.
  Brightness get effectiveBrightness => switch (_mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  AppPalette get palette => AppPalette.forBrightness(effectiveBrightness);

  static ThemeMode parse(String? s) => switch (s) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Reads the stored mode (call before runApp) and starts following the
  /// platform brightness.
  Future<void> load() async {
    String? stored;
    try {
      stored = await AppPrefs.getString(prefsKey);
    } catch (_) {}
    _mode = parse(_forced.isNotEmpty ? _forced : stored);
    _observe();
    _apply(force: true);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _observe();
    _apply();
    notifyListeners();
    try {
      await AppPrefs.setString(prefsKey, mode.name);
    } catch (_) {}
  }

  void _observe() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode != ThemeMode.system) return;
    _apply();
    notifyListeners();
  }

  void _apply({bool force = false}) {
    final next = palette;
    final changed = !identical(next, AppPalette.active);
    AppPalette.active = next;
    if (changed || force) {
      SystemChrome.setSystemUIOverlayStyle(systemOverlayFor(next));
    }
    if (changed) rebuildAllElements();
  }

  /// Test-only reset.
  @visibleForTesting
  void debugReset() {
    _mode = ThemeMode.system;
    AppPalette.active = AppPalette.light;
  }
}

/// Marks every mounted element dirty so `const` subtrees that read
/// `AppColors.*` / `AppText.*` repaint with the new palette.
void rebuildAllElements() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
  root.markNeedsBuild();
}

/// Keeps [AppPalette.active] in sync with the theme an app is actually built
/// with. Wrap a MaterialApp's `builder` child with it; it is a no-op when the
/// palette already matches. Used by tests and by apps that do not go through
/// [ThemeController] (e.g. `MaterialApp(theme: buildAppTheme())`).
class PaletteSync extends StatelessWidget {
  const PaletteSync({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>();
    if (p != null) AppPalette.active = p;
    return child;
  }
}
