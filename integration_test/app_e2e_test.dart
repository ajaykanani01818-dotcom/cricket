// End-to-end journey on a real device against the LOCAL livescore-postdata.
//   flutter test integration_test/app_e2e_test.dart -d DEVICE_ID --dart-define-from-file=env/local.json
import 'package:crickbex/app.dart';
import 'package:crickbex/core/network/network_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  strictTaps();

  final errors = <FlutterErrorDetails>[];

  setUpAll(() async {
    await NetworkStatus.instance.start();
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d);
      prev?.call(d);
    };
  });

  testWidgets('full journey across every tab with real local data', (tester) async {
    await tester.pumpWidget(const CrickbexApp());

    // Splash → onboarding (first run) → main.
    final onboardingOrHome = find.byWidgetPredicate((w) =>
        w.key == const ValueKey('onboarding_next') || w.key == const ValueKey('tab_bar_live'));
    expect(await pumpUntil(tester, onboardingOrHome), isTrue, reason: 'startup never finished');
    for (var i = 0; i < 6 && find.byKey(const ValueKey('onboarding_next')).evaluate().isNotEmpty; i++) {
      await tester.tap(find.byKey(const ValueKey('onboarding_next')));
      await settle(tester, const Duration(milliseconds: 900));
    }
    expect(await pumpUntil(tester, find.byKey(const ValueKey('tab_bar_live'))), isTrue);

    // ---- Home ----
    expect(await pumpUntil(tester, find.byKey(const ValueKey('home_scroll'))), isTrue, reason: 'home never loaded');
    await settle(tester, const Duration(seconds: 2));
    expectNoErrorView('home');
    final homeCard = keyPrefix('home_upcoming_card_').evaluate().isNotEmpty ? keyPrefix('home_upcoming_card_') : keyPrefix('home_live_card_');
    if (homeCard.evaluate().isNotEmpty) {
      await tester.ensureVisible(homeCard.first);
      await tester.tap(homeCard.first);
      expect(await pumpUntil(tester, find.byKey(const ValueKey('match_detail_scroll'))), isTrue, reason: 'match detail from home');
      expectNoErrorView('match detail (home)');
      await goBack(tester);
    }

    // ---- Matches: Recent → match detail → every tab ----
    await tapTab(tester, 'matches');
    await tester.tap(find.byKey(const ValueKey('tab_completed')));
    expect(await pumpUntil(tester, keyPrefix('match-completed-')), isTrue, reason: 'recent matches never loaded');
    expectNoErrorView('matches/recent');
    await tester.tap(keyPrefix('match-completed-').first);
    expect(await pumpUntil(tester, find.byKey(const ValueKey('match_detail_scroll'))), isTrue);
    for (final tab in ['scorecard', 'commentary', 'stats', 'playingXI', 'live']) {
      final t = find.byKey(ValueKey('match_detail_tab_$tab'));
      if (t.evaluate().isEmpty) continue;
      await tester.ensureVisible(t);
      await tester.pump();
      await tester.tap(t);
      await settle(tester, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('match_detail_error')), findsNothing, reason: 'match detail tab $tab');
    }
    await goBack(tester);

    // ---- Series: list → detail → every sub-view ----
    await tapTab(tester, 'series');
    expect(await pumpUntil(tester, keyPrefix('series_card_')), isTrue, reason: 'series list never loaded');
    await tester.tap(keyPrefix('series_card_').first);
    expect(await pumpUntil(tester, find.byKey(const ValueKey('series_detail_pager'))), isTrue);
    for (final label in ['Points', 'Stats', 'Squads', 'Results']) {
      final t = find.textContaining(label);
      if (t.evaluate().isEmpty) continue;
      await tester.tap(t.first);
      await settle(tester, const Duration(seconds: 2));
    }
    expect(find.byKey(const ValueKey('series_detail_retry')), findsNothing);
    await goBack(tester);

    // ---- Ranking: switch modes / formats ----
    await tapTab(tester, 'ranking');
    expect(await pumpUntil(tester, keyPrefix('ranking_row_')), isTrue, reason: 'rankings never loaded');
    for (final seg in ['segment_ODI', 'segment_T20', 'segment_TEST']) {
      final f = find.byKey(ValueKey(seg));
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await settle(tester, const Duration(milliseconds: 1500));
      }
    }
    expectNoErrorView('ranking');

    // ---- Players: list → detail ----
    await tapTab(tester, 'players');
    expect(await pumpUntil(tester, keyPrefix('players_row_')), isTrue, reason: 'players never loaded');
    await tester.tap(keyPrefix('players_row_').first);
    final playerLoaded = find.byWidgetPredicate((w) =>
        w.key == const ValueKey('player_detail_name') || w.key == const ValueKey('player_detail_not_found'));
    expect(await pumpUntil(tester, playerLoaded), isTrue, reason: 'player detail never loaded');
    expect(find.byKey(const ValueKey('player_detail_error')), findsNothing);
    await goBack(tester);

    // ---- Settings: open each page ----
    await tapTab(tester, 'settings');
    expect(await pumpUntil(tester, find.byKey(const ValueKey('settings_list'))), isTrue);
    for (final page in ['privacy', 'about', 'contact']) {
      final f = find.byKey(ValueKey('settings_item_$page'));
      if (f.evaluate().isEmpty) continue;
      await tester.tap(f);
      await settle(tester, const Duration(milliseconds: 1200));
      await goBack(tester);
    }

    // ---- Back to Live; repeated tab hopping must not leak or crash ----
    for (var i = 0; i < 3; i++) {
      for (final t in ['live', 'matches', 'series', 'ranking', 'players', 'settings']) {
        await tapTab(tester, t);
      }
    }
    await tapTab(tester, 'live');

    expect(errors.where((e) => !e.toString().contains('NetworkImageLoadException')), isEmpty,
        reason: errors.map((e) => e.exceptionAsString()).join('\n'));
  });
}
