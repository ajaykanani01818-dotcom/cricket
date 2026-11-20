import 'package:crickbex/features/review/review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  DateTime now = DateTime(2026, 6, 1, 10);
  DateTime call() => now;
}

void main() {
  group('canAskForReview (pure eligibility rules)', () {
    final now = DateTime(2026, 6, 1);
    bool ask({
      int sessions = 5,
      int actions = 5,
      int? last,
      bool positive = true,
      bool askedThisRun = false,
    }) => canAskForReview(
      sessionCount: sessions,
      actionCount: actions,
      lastRequestMs: last,
      now: now,
      positiveMoment: positive,
      askedThisRun: askedThisRun,
    );

    test('never on the first launch, nor before 3 sessions', () {
      expect(ask(sessions: 0), isFalse);
      expect(ask(sessions: 1), isFalse);
      expect(ask(sessions: 2), isFalse);
      expect(ask(sessions: 3), isTrue);
    });

    test('needs at least 3 match views', () {
      expect(ask(actions: 2), isFalse);
      expect(ask(actions: 3), isTrue);
    });

    test('only after a positive moment', () {
      expect(ask(positive: false), isFalse);
    });

    test('at most once per app run', () {
      expect(ask(askedThisRun: true), isFalse);
    });

    test('at most once per 30 days; a clock set back never unlocks', () {
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(ask(last: ago(const Duration(days: 29, hours: 23))), isFalse);
      expect(ask(last: ago(const Duration(days: 30))), isTrue);
      expect(
        ask(last: now.add(const Duration(days: 3)).millisecondsSinceEpoch),
        isFalse,
      );
    });

    test('rule constants', () {
      expect(ReviewRules.minSessionsBeforeAsk, 3);
      expect(ReviewRules.minMeaningfulActions, 3);
      expect(ReviewRules.cooldownDays, 30);
    });
  });

  group('ReviewStore', () {
    test('counts sessions/actions and records the request time', () async {
      SharedPreferences.setMockInitialValues({});
      final clock = _Clock();
      final store = ReviewStore(clock: clock.call);
      expect(await store.canAsk(), isFalse);
      for (var i = 0; i < 3; i++) {
        await store.recordSession();
        await store.recordMeaningfulAction();
      }
      expect(await store.sessionCount(), 3);
      expect(await store.meaningfulActionCount(), 3);
      expect(await store.canAsk(), isTrue);
      expect(await store.canAsk(positiveMoment: false), isFalse);
      await store.recordReviewRequested();
      expect(await store.lastRequestMs(), clock.now.millisecondsSinceEpoch);
      expect(await store.canAsk(), isFalse);
      clock.now = clock.now.add(const Duration(days: 30));
      expect(await store.canAsk(), isTrue);
    });

    test('malformed / string values never crash', () async {
      SharedPreferences.setMockInitialValues({
        ReviewStore.keySessionCount: 'abc',
        ReviewStore.keyActionCount: '7',
        ReviewStore.keyLastRequest: 'x',
      });
      final store = ReviewStore();
      expect(await store.sessionCount(), 0);
      expect(await store.meaningfulActionCount(), 7);
      expect(await store.lastRequestMs(), isNull);
      expect(await store.recordSession(), 1);
    });

    test('negative counts are clamped to 0', () async {
      SharedPreferences.setMockInitialValues({ReviewStore.keyActionCount: -4});
      expect(await ReviewStore().meaningfulActionCount(), 0);
    });

    test('storage keys carry no legacy brand', () {
      for (final k in [
        ReviewStore.keyLastRequest,
        ReviewStore.keyActionCount,
        ReviewStore.keySessionCount,
      ]) {
        expect(k.toLowerCase(), isNot(contains('crickbex')));
      }
    });
  });

  group('ReviewController', () {
    const eligible = {
      ReviewStore.keySessionCount: 3,
      ReviewStore.keyActionCount: 5,
    };

    ReviewController make(
      List<String> log, {
      bool requestOk = true,
      void Function()? exit,
    }) => ReviewController(
      requestReview: () async {
        log.add('requestReview');
        return requestOk;
      },
      openStoreListing: () async {
        log.add('store');
        return true;
      },
      exitApp: exit ?? () => log.add('exit'),
    );

    testWidgets(
      'positive moment + eligible → system review API after the delay, once per run',
      (tester) async {
        SharedPreferences.setMockInitialValues(eligible);
        final log = <String>[];
        final c = make(log);
        expect(
          await c.requestReviewIfAppropriate(positiveMoment: true),
          isTrue,
        );
        expect(log, isEmpty, reason: 'not on top of the tap');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(log, ['requestReview']);
        expect(await c.store.lastRequestMs(), isNotNull);

        expect(
          await c.requestReviewIfAppropriate(positiveMoment: true),
          isFalse,
        );
        await tester.pump(const Duration(seconds: 3));
        expect(log, ['requestReview']);
        c.dispose();
      },
    );

    testWidgets('opening a match (no positive moment) never asks', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(eligible);
      final log = <String>[];
      final c = make(log);
      expect(await c.requestReviewIfAppropriate(), isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(log, isEmpty);
      c.dispose();
    });

    testWidgets('not eligible (first sessions) → no request', (tester) async {
      SharedPreferences.setMockInitialValues({
        ReviewStore.keySessionCount: 1,
        ReviewStore.keyActionCount: 9,
      });
      final log = <String>[];
      final c = make(log);
      expect(await c.requestReviewIfAppropriate(positiveMoment: true), isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(log, isEmpty);
      c.dispose();
    });

    testWidgets('within the 30-day cooldown → no request', (tester) async {
      SharedPreferences.setMockInitialValues({
        ...eligible,
        ReviewStore.keyLastRequest: DateTime.now()
            .subtract(const Duration(days: 10))
            .millisecondsSinceEpoch,
      });
      final log = <String>[];
      final c = make(log);
      expect(await c.requestReviewIfAppropriate(positiveMoment: true), isFalse);
      c.dispose();
    });

    testWidgets('API unavailable → cooldown not consumed', (tester) async {
      SharedPreferences.setMockInitialValues(eligible);
      final c = make(<String>[], requestOk: false);
      await c.requestReviewIfAppropriate(positiveMoment: true);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(await c.store.lastRequestMs(), isNull);
      c.dispose();
    });

    testWidgets('dispose cancels a pending request', (tester) async {
      SharedPreferences.setMockInitialValues(eligible);
      final log = <String>[];
      final c = make(log);
      await c.requestReviewIfAppropriate(positiveMoment: true);
      c.dispose();
      await tester.pump(const Duration(seconds: 3));
      expect(log, isEmpty);
    });

    test('openStoreListing (Settings) never throws', () async {
      SharedPreferences.setMockInitialValues({});
      final ok = make(<String>[]);
      expect(await ok.openStoreListing(), isTrue);
      final throwing = ReviewController(
        openStoreListing: () => throw StateError('x'),
        exitApp: () {},
      );
      expect(await throwing.openStoreListing(), isFalse);
    });
  });

  group('back on Home (ReviewHost)', () {
    testWidgets(
      'never shows a rating prompt: hint first, exit on second press within 2 s',
      (tester) async {
        SharedPreferences.setMockInitialValues(const {
          ReviewStore.keySessionCount: 9,
          ReviewStore.keyActionCount: 9,
        });
        final log = <String>[];
        var t = DateTime(2026, 6, 1, 10);
        final c = ReviewController(
          requestReview: () async {
            log.add('requestReview');
            return true;
          },
          openStoreListing: () async {
            log.add('store');
            return true;
          },
          exitApp: () => log.add('exit'),
          clock: () => t,
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                ReviewHost(controller: c, child: child!),
            home: const Scaffold(body: Text('home')),
          ),
        );

        c.showRatingModalForExit(); // what AppShell calls at the Home root
        await tester.pump();
        expect(find.text('Press back again to exit'), findsOneWidget);
        expect(find.textContaining('Enjoying'), findsNothing);
        expect(find.byIcon(Icons.star_rounded), findsNothing);
        expect(log, isEmpty, reason: 'no review request and no store on back');

        t = t.add(const Duration(seconds: 1));
        c.showRatingModalForExit();
        await tester.pump();
        expect(log, ['exit']);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('a slow second press shows the hint again instead of exiting', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final log = <String>[];
      var t = DateTime(2026, 6, 1, 10);
      final c = ReviewController(
        exitApp: () => log.add('exit'),
        clock: () => t,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ReviewHost(controller: c, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      );
      c.showRatingModalForExit();
      t = t.add(const Duration(seconds: 3));
      c.showRatingModalForExit();
      await tester.pump();
      expect(log, isEmpty);
      expect(c.exitHintTick, 2);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
      'host records exactly one session per launch and exposes the scope',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final c = ReviewController(exitApp: () {});
        addTearDown(c.dispose);
        ReviewController? seen;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                ReviewHost(controller: c, child: child!),
            home: Builder(
              builder: (context) {
                seen = ReviewScope.maybeOf(context);
                return const Text('page');
              },
            ),
          ),
        );
        await tester.pump();
        expect(seen, same(c));
        await c.recordSessionOnce();
        expect(await c.store.sessionCount(), 1);
      },
    );
  });
}
