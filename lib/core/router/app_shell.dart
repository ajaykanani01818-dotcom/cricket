import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/offline_banner.dart';
import 'app_nav.dart';

/// Bottom-bar items, in [AppTab] order.
const kShellTabs = [
  AppBottomBarItem(icon: Icons.home_rounded, label: 'Home', keyName: 'home'),
  AppBottomBarItem(icon: Icons.sensors, label: 'Live', keyName: 'live'),
  AppBottomBarItem(
    icon: Icons.sports_cricket,
    label: 'Matches',
    keyName: 'matches',
  ),
  AppBottomBarItem(icon: Icons.explore, label: 'Discover', keyName: 'discover'),
  AppBottomBarItem(
    icon: Icons.settings,
    label: 'Settings',
    keyName: 'settings',
  ),
];

/// App shell: offline strip on top, the active tab, and the fixed orange
/// [AppBottomBar] as `Scaffold.bottomNavigationBar` (`extendBody: false`, so
/// content always ends above the bar).
///
/// Android back: pops the current tab's stack; at a tab root returns to
/// Home; on the Home root opens the rating prompt (which has "Exit app"), or
/// falls back to double-back-to-exit.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;

  /// A tab always opens at its root (RN popToTopOnBlur).
  void _onTab(int index) => widget.shell.goBranch(index, initialLocation: true);

  void _onRootBack() {
    if (widget.shell.currentIndex != AppTab.home.index) {
      _onTab(AppTab.home.index);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(p),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final router = GoRouter.of(context);
          if (router.canPop()) {
            router.pop();
          } else {
            _onRootBack();
          }
        },
        child: Scaffold(
          key: const ValueKey('app_shell'),
          extendBody: false,
          backgroundColor: p.canvas,
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(child: widget.shell),
            ],
          ),
          bottomNavigationBar: AppBottomBar(
            items: kShellTabs,
            currentIndex: widget.shell.currentIndex,
            onTap: _onTab,
          ),
        ),
      ),
    );
  }
}
