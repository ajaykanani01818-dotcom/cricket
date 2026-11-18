import 'package:flutter/material.dart';

import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../common/tap_guard.dart';
import 'matches_controller.dart';
import 'matches_tab_panel.dart';

const _tabItems = [
  SectionTabItem('live', 'Live'),
  SectionTabItem('upcoming', 'Upcoming'),
  SectionTabItem('completed', 'Recent'),
];
const _tabOrder = MatchesTab.values; // live, upcoming, completed

/// Ported from RN `MatchesScreen`: swipeable Live / Upcoming / Recent pages
/// (RN PagerView → PageView), grouped by series, paginated "Recent".
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  late final MatchesController _c = MatchesController()..start();
  final _pager = PageController();
  final _guard = TapGuard();
  int _index = 0;

  @override
  void dispose() {
    _guard.dispose();
    _pager.dispose();
    _c.dispose();
    super.dispose();
  }

  // Tab tap → animate pager; index state follows onPageChanged.
  void _onTabSelect(String key) {
    final i = _tabOrder.indexWhere((t) => t.name == key);
    if (i < 0 || i == _index) return;
    setState(() => _index = i); // underline moves immediately
    _pager.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _openMatch(MatchSummary m) {
    if (m.id.isEmpty) return;
    _guard.run(() {
      AppNav.match(context, m.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Content clears the floating tab bar (shell inset) + fixed banner reserve.
    final bottomPad = MediaQuery.paddingOf(context).bottom + 60 + Spacing.md;
    return Material(
      color: AppColors.bg,
      child: Stack(children: [
        Column(children: [
          const ScreenTitle(title: 'Matches'),
          const ScreenBannerSlots(screen: 'matches', onlyPosition: 'top'),
          SectionTabs(tabs: _tabItems, activeKey: _tabOrder[_index].name, onSelect: _onTabSelect),
          Expanded(
            child: PageView(
              key: const ValueKey('matches_pager'),
              controller: _pager,
              onPageChanged: (i) {
                if (i != _index) setState(() => _index = i);
              },
              children: [
                for (final t in _tabOrder)
                  MatchesTabPanel(
                    key: ValueKey('matches_panel_${t.name}'),
                    tab: t,
                    controller: _c,
                    onMatchTap: _openMatch,
                    bottomPadding: bottomPad,
                  ),
              ],
            ),
          ),
        ]),
        Positioned(left: 0, right: 0, bottom: MediaQuery.paddingOf(context).bottom, child: const FixedBottomBanner(screen: 'matches')),
      ]),
    );
  }
}
