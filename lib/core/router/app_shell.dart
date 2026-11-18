import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../features/review/review_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_banner.dart';

/// Bottom navigation shell — ported from RN TabNavigatorWithInsets +
/// GlassTabBar + TabIcon + ExitBackHandler.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Live'),
    (Icons.sports_cricket_outlined, Icons.sports_cricket, 'Matches'),
    (Icons.emoji_events_outlined, Icons.emoji_events, 'Series'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Ranking'),
    (Icons.people_outline, Icons.people, 'Players'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  /// RN tabs use popToTopOnBlur, so a tab always opens at its root.
  void _onTab(int index) => widget.shell.goBranch(index, initialLocation: true);

  /// ExitBackHandler: back at a tab root returns to Live; on Live, a second
  /// back within 2s exits.
  void _onRootBack() {
    if (widget.shell.currentIndex != 0) {
      _onTab(0);
      return;
    }
    // RN ExitBackHandler: back on the Live root opens the rating modal, which
    // has an "Exit app" action. Fallback: double-back to exit.
    final review = ReviewScope.read(context);
    if (review != null) {
      review.showRatingModalForExit();
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return PopScope(
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
        extendBody: true,
        body: Column(children: [
          const OfflineBanner(),
          Expanded(child: widget.shell),
        ]),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + (bottomInset > 0 ? bottomInset : 8)),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [Color(0xF21669E0), Color(0xF20B5CD4), Color(0xF20A4BB0)]),
              border: Border.all(color: const Color(0x2EFFFFFF)),
              boxShadow: const [BoxShadow(color: Color(0x550B5CD4), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: widget.shell.currentIndex == i,
                    label: _tabs[i].$3,
                    child: InkResponse(
                      key: ValueKey('tab_bar_${_tabs[i].$3.toLowerCase()}'),
                      onTap: () => _onTab(i),
                      radius: 28,
                      child: _TabIcon(outline: _tabs[i].$1, filled: _tabs[i].$2, focused: widget.shell.currentIndex == i),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.outline, required this.filled, required this.focused});
  final IconData outline, filled;
  final bool focused;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedScale(
              scale: focused ? 1 : 0.6,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: focused ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x4D04264D), blurRadius: 6, offset: Offset(0, 3))],
                  ),
                ),
              ),
            ),
            Icon(focused ? filled : outline, size: focused ? 22 : 23, color: focused ? AppColors.pitch : const Color(0x99FFFFFF)),
          ]),
        ),
      );
}
