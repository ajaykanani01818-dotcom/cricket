import 'package:crickbex/core/router/app_router.dart';
import 'package:crickbex/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/helpers.dart';

/// Smoke test against the REAL app router + AppShell: Home and Matches mount
/// inside the shell, and the bottom tab bar switches between them.
void main() {
  testWidgets('real router: Live tab → Matches tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FakeApi(defaultRoutes()).install();
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(theme: buildAppTheme(), routerConfig: router));
    await settle(tester);
    expect(find.text('Live Matches'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('tab_bar_matches')));
    await settle(tester);
    expect(location(router), '/matches');
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.text('No live matches right now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
