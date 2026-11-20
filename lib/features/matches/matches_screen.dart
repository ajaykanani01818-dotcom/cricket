import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/tabs.dart';
import '../../core/widgets/titles.dart';
import '../ads/ads.dart';
import '../common/tap_guard.dart';
import 'feature_states.dart';
import 'matches_controller.dart';
import 'matches_filter_bar.dart';
import 'matches_tab_panel.dart';

const _tabItems = [SectionTabItem('live', 'Live'), SectionTabItem('upcoming', 'Upcoming'), SectionTabItem('completed', 'Results')];
const _tabOrder = MatchesTab.values; // live, upcoming, completed

/// Matches tab: Live / Upcoming / Results pages (swipeable), a day strip and
/// format chips that filter the loaded lists client-side, rows grouped by
/// series under sticky headers, paginated Results, pull-to-refresh.
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

  void _showTab(MatchesTab t) {
    final i = _tabOrder.indexOf(t);
    if (i < 0 || i == _index) return;
    setState(() => _index = i); // indicator moves immediately
    _pager.animateToPage(i, duration: Motion.of(context).d(Motion.tabSwitch), curve: Motion.standard);
  }

  void _onTabSelect(String key) {
    final i = _tabOrder.indexWhere((t) => t.name == key);
    if (i >= 0) _showTab(_tabOrder[i]);
  }

  void _openMatch(MatchSummary m) {
    if (m.id.isEmpty) return;
    _guard.run(() {
      AppNav.match(context, m.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.canvas,
      child: Column(
        children: [
          ScreenTitle(
            title: 'Matches',
            actions: [
              IconButton(
                key: const ValueKey('matches_search'),
                tooltip: 'Search matches, series and players',
                onPressed: () => _guard.run(() {
                  AppNav.search(context);
                }),
                icon: Icon(Icons.search, color: context.palette.ink),
              ),
            ],
          ),
          const ScreenBannerSlots(screen: 'matches', onlyPosition: 'top'),
          MaxWidthBand(
            child: SectionTabs(tabs: _tabItems, activeKey: _tabOrder[_index].name, onSelect: _onTabSelect),
          ),
          ListenableBuilder(
            listenable: _c,
            builder: (context, _) => MatchesFilterBar(
              filters: _c.filters,
              onChanged: _c.setFilters,
              showDays: _tabOrder[_index] != MatchesTab.live,
              showWomen: _c.womenAvailable,
            ),
          ),
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
                    onShowTab: _showTab,
                  ),
              ],
            ),
          ),
          const FixedBottomBanner(screen: 'matches'),
        ],
      ),
    );
  }
}
