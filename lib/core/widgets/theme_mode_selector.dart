import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import 'tabs.dart';

/// Settings control: System / Light / Dark. Applies instantly and persists
/// (see [ThemeController]). Drop it into the Settings screen.
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key, this.controller});

  /// Defaults to [ThemeController.instance].
  final ThemeController? controller;

  static const options = [
    SegmentOption(ThemeMode.system, 'System'),
    SegmentOption(ThemeMode.light, 'Light'),
    SegmentOption(ThemeMode.dark, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = controller ?? ThemeController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Semantics(
        label: 'Theme',
        child: SegmentedControl<ThemeMode>(
          key: const ValueKey('theme_mode_selector'),
          options: options,
          value: c.mode,
          onChanged: c.setMode,
        ),
      ),
    );
  }
}
