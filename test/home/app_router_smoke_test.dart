import 'package:crickbex/core/router/app_router.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/features/live/live_screen.dart';
import 'package:crickbex/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

/// Smoke test against the REAL app router + AppShell: Home mounts inside the
/// shell, the bottom bar switches tabs, and search pushes on the Home stack.
void main() {
  testWidgets('real router: Home tab → Matches tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FakeApi(defaultRoutes()).install();
    final router = buildRouter();
    await tester.pumpWidget(
      MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    );
    await settle(tester);
    expect(location(router), '/home');
    expect(find.text('Live now'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('app_bar_search')));
    await settle(tester);
    expect(location(router), '/home/search');
    expect(find.byType(SearchScreen), findsOneWidget);
    router.go('/home');
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('tab_bar_live')));
    await settle(tester);
    expect(location(router), '/live');
    expect(find.byType(LiveScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab_bar_matches')));
    await settle(tester);
    expect(location(router), '/matches');
    await tester.pumpWidget(const SizedBox());
  });
}
