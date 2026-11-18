// Frame-timing scenarios. Run in PROFILE mode with the driver so timings are real:
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart --dart-define-from-file=env/local.json -d DEVICE_ID
// Results: build/perf/<scenario>.timeline_summary.json
import 'package:crickbex/app.dart';
import 'package:crickbex/core/network/network_status.dart';
import 'package:crickbex/core/storage/prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as w;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

Future<void> flingDownUp(WidgetTester tester, Finder scrollable, {int times = 3}) async {
  for (var i = 0; i < times; i++) {
    await tester.fling(scrollable, const Offset(0, -900), 2500);
    await settle(tester, const Duration(milliseconds: 900));
  }
  for (var i = 0; i < times; i++) {
    await tester.fling(scrollable, const Offset(0, 900), 2500);
    await settle(tester, const Duration(milliseconds: 900));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  strictTaps();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('performance scenarios', (tester) async {
    // Diagnostic mode: per-widget build events in the timeline (inflates times).
    if (const bool.fromEnvironment('PERF_DIAG')) w.debugProfileBuildsEnabled = true;
    await NetworkStatus.instance.start();
    await AppPrefs.setHasSeenOnboarding();
    await binding.traceAction(() async {
      await tester.pumpWidget(const CrickbexApp());
      expect(await pumpUntil(tester, find.byKey(const ValueKey('home_scroll')), timeout: const Duration(seconds: 40)), isTrue);
      await settle(tester, const Duration(seconds: 5));
    }, reportKey: 'startup');

    await binding.traceAction(() async {
      await flingDownUp(tester, find.byKey(const ValueKey('home_scroll')));
    }, reportKey: 'home_scroll');

    // First visit of each tab (builds the screen), traced separately.
    for (final t in ['matches', 'series', 'ranking', 'players', 'settings']) {
      await binding.traceAction(() async {
        await tapTab(tester, t);
        await settle(tester, const Duration(seconds: 2));
      }, reportKey: 'first_visit_$t');
    }
    await binding.traceAction(() async {
      for (var i = 0; i < 2; i++) {
        for (final t in ['matches', 'series', 'ranking', 'players', 'settings', 'live']) {
          await tapTab(tester, t);
        }
      }
    }, reportKey: 'tab_switching_revisit');

    await tapTab(tester, 'matches');
    await tester.tap(find.byKey(const ValueKey('tab_completed')));
    await pumpUntil(tester, keyPrefix('match-completed-'));
    await settle(tester, const Duration(seconds: 2));
    await binding.traceAction(() async {
      await flingDownUp(tester, find.byType(Scrollable).hitTestable().first, times: 4);
    }, reportKey: 'matches_recent_scroll');

    await tester.tap(keyPrefix('match-completed-').first);
    await pumpUntil(tester, find.byKey(const ValueKey('match_detail_scroll')));
    await settle(tester, const Duration(seconds: 2));
    await binding.traceAction(() async {
      for (final tab in ['scorecard', 'commentary', 'stats', 'playingXI', 'live']) {
        final t = find.byKey(ValueKey('match_detail_tab_$tab'));
        if (t.evaluate().isEmpty) continue;
        await tester.ensureVisible(t);
        await tester.pump();
        await tester.tap(t);
        await settle(tester, const Duration(milliseconds: 1500));
      }
      final c = find.byKey(const ValueKey('match_detail_tab_commentary'));
      if (c.evaluate().isNotEmpty) {
        await tester.tap(c);
        await settle(tester, const Duration(seconds: 2));
        await flingDownUp(tester, find.byKey(const ValueKey('match_detail_scroll')));
      }
    }, reportKey: 'match_detail_tabs_and_commentary');
    await goBack(tester);

    await tapTab(tester, 'ranking');
    await pumpUntil(tester, keyPrefix('ranking_row_'));
    await settle(tester, const Duration(seconds: 1));
    await binding.traceAction(() async {
      await flingDownUp(tester, find.byKey(const ValueKey('rankings_list')));
      for (final seg in ['segment_T20', 'segment_TEST', 'segment_ODI']) {
        final f = find.byKey(ValueKey(seg));
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first);
          await settle(tester, const Duration(milliseconds: 1200));
        }
      }
    }, reportKey: 'rankings_scroll_and_toggle');

    await tapTab(tester, 'players');
    await pumpUntil(tester, keyPrefix('players_row_'));
    await settle(tester, const Duration(seconds: 1));
    await binding.traceAction(() async {
      await flingDownUp(tester, find.byKey(const ValueKey('players_list')), times: 5);
    }, reportKey: 'players_infinite_scroll');

    await tapTab(tester, 'series');
    await pumpUntil(tester, keyPrefix('series_card_'));
    await binding.traceAction(() async {
      await tester.tap(keyPrefix('series_card_').first);
      await pumpUntil(tester, find.byKey(const ValueKey('series_detail_pager')));
      await settle(tester, const Duration(seconds: 2));
      for (final label in ['Points', 'Stats', 'Squads', 'Results']) {
        final t = find.textContaining(label);
        if (t.evaluate().isEmpty) continue;
        await tester.tap(t.first);
        await settle(tester, const Duration(milliseconds: 1500));
      }
    }, reportKey: 'series_detail_navigation');
  });
}
