import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Any tap that misses its target fails the test instead of silently passing.
void strictTaps() => WidgetController.hitTestWarningShouldBeFatal = true;

/// Pumps real frames until [finder] matches or [timeout] passes.
/// Uses short pumps so network I/O on the device can complete.
Future<bool> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// First widget whose ValueKey string starts with [prefix].
Finder keyPrefix(String prefix) => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey && k.value is String && (k.value as String).startsWith(prefix);
    });

Future<void> settle(WidgetTester tester, [Duration d = const Duration(milliseconds: 800)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Fails the test if an error view is on screen.
void expectNoErrorView(String where) {
  final errors = find.byWidgetPredicate((w) {
    final k = w.key;
    if (k is! ValueKey || k.value is! String) return false;
    final s = k.value as String;
    return s.endsWith('_error') || s.contains('_error_') || s == 'match_detail_error' || s == 'player_detail_error';
  });
  expect(errors, findsNothing, reason: 'error view visible on $where');
}

Future<void> tapTab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('tab_bar_$name')));
  await settle(tester);
}

/// Navigates back (system back semantics via the router).
Future<void> goBack(WidgetTester tester) async {
  final NavigatorState nav = tester.state(find.byType(Navigator).last);
  await nav.maybePop();
  await settle(tester);
}
