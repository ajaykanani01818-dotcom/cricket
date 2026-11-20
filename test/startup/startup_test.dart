import 'package:crickbex/features/review/review.dart';
import 'package:crickbex/features/startup/startup_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('version gate', () {
    test('compareSemver', () {
      expect(compareSemver('1.0.0', '1.0.0'), 0);
      expect(compareSemver('1.0', '1.0.0'), 0);
      expect(compareSemver('v1.2.3', '1.2.3'), 0);
      expect(compareSemver('1.2.3', '1.10.0'), -1);
      expect(compareSemver('2.0.0', '1.99.99'), 1);
      expect(compareSemver('1.0.0-beta', '1.0.1'), -1);
      expect(compareSemver('garbage', '0.0.0'), 0);
    });

    test('isUpdateRequired', () {
      expect(versionGateConfig, isNull, reason: 'inert, same as RN');
      expect(isUpdateRequired('1.0.0', null), isFalse);
      expect(
        isUpdateRequired(
          '1.0.0',
          const VersionGateConfig(minimumAppVersion: ''),
        ),
        isFalse,
      );
      expect(
        isUpdateRequired(
          '1.0.0',
          const VersionGateConfig(minimumAppVersion: '1.0.1'),
        ),
        isTrue,
      );
      expect(
        isUpdateRequired(
          '1.2.0',
          const VersionGateConfig(minimumAppVersion: '1.0.1'),
        ),
        isFalse,
      );
      expect(
        isUpdateRequired(
          '',
          const VersionGateConfig(minimumAppVersion: '0.0.1'),
        ),
        isTrue,
      );
    });

    testWidgets(
      'inert config renders only the child and never reads the version',
      (tester) async {
        var reads = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: VersionUpdateGate(
              installedVersion: () async {
                reads++;
                return '0.0.1';
              },
              child: const Text('app'),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('app'), findsOneWidget);
        expect(find.byKey(const ValueKey('version_gate_card')), findsNothing);
        expect(reads, 0);
      },
    );

    testWidgets('soft gate: Update opens store, Maybe later dismisses', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: VersionUpdateGate(
            config: const VersionGateConfig(minimumAppVersion: '2.0.0'),
            installedVersion: () async => '1.0.0',
            openStore: (u) async => opened.add(u),
            child: const Text('app'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('New version ready'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version_gate_update')));
      await tester.pump();
      expect(opened.single, contains('com.cricticker.app'));
      await tester.tap(find.byKey(const ValueKey('version_gate_later')));
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_card')), findsNothing);
    });

    testWidgets('force gate: no Maybe later, back is swallowed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VersionUpdateGate(
            config: const VersionGateConfig(
              minimumAppVersion: '2.0.0',
              forceUpdate: true,
            ),
            installedVersion: () async => '1.0.0',
            openStore: (_) async {},
            child: const Text('app'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_later')), findsNothing);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_card')), findsOneWidget);
    });

    testWidgets('up-to-date install → no gate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VersionUpdateGate(
            config: const VersionGateConfig(minimumAppVersion: '1.0.0'),
            installedVersion: () async => '1.0.0',
            child: const Text('app'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('version_gate_card')), findsNothing);
    });
  });

  testWidgets('AppChrome provides ReviewScope to router pages', (tester) async {
    final c = ReviewController(
      openStoreListing: () async => true,
      exitApp: () {},
    );
    ReviewController? seen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(reviewController: c, child: child!),
        home: Builder(
          builder: (context) {
            seen = ReviewScope.maybeOf(context);
            return const Text('page');
          },
        ),
      ),
    );
    expect(find.text('page'), findsOneWidget);
    expect(seen, same(c));
  });
}
