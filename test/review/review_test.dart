import 'package:crickbex/features/review/review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  DateTime now = DateTime(2026, 6, 1, 10);
  DateTime call() => now;
}

void main() {
  group('canAskForReview (pure)', () {
    final now = DateTime(2026, 6, 1);
    test('needs 2 sessions and 3 meaningful actions', () {
      expect(canAskForReview(sessionCount: 1, actionCount: 10, lastRequestMs: null, now: now), isFalse);
      expect(canAskForReview(sessionCount: 2, actionCount: 2, lastRequestMs: null, now: now), isFalse);
      expect(canAskForReview(sessionCount: 2, actionCount: 3, lastRequestMs: null, now: now), isTrue);
    });

    test('30-day cooldown after a store request', () {
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(canAskForReview(sessionCount: 5, actionCount: 5, lastRequestMs: ago(const Duration(days: 29, hours: 23)), now: now), isFalse);
      expect(canAskForReview(sessionCount: 5, actionCount: 5, lastRequestMs: ago(const Duration(days: 30)), now: now), isTrue);
    });
  });

  group('ReviewStore', () {
    test('counts sessions/actions and records the request time', () async {
      SharedPreferences.setMockInitialValues({});
      final clock = _Clock();
      final store = ReviewStore(clock: clock.call);
      expect(await store.canAsk(), isFalse);
      await store.recordSession();
      await store.recordSession();
      for (var i = 0; i < 3; i++) {
        await store.recordMeaningfulAction();
      }
      expect(await store.sessionCount(), 2);
      expect(await store.meaningfulActionCount(), 3);
      expect(await store.canAsk(), isTrue);
      await store.recordReviewRequested();
      expect(await store.lastRequestMs(), clock.now.millisecondsSinceEpoch);
      expect(await store.canAsk(), isFalse);
      clock.now = clock.now.add(const Duration(days: 30));
      expect(await store.canAsk(), isTrue);
    });

    test('malformed / legacy string values never crash', () async {
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
  });

  group('ReviewController', () {
    testWidgets('auto prompt shows after 2s when eligible, once per run', (tester) async {
      SharedPreferences.setMockInitialValues({ReviewStore.keySessionCount: 3, ReviewStore.keyActionCount: 5});
      final c = ReviewController(openStoreListing: () async => true, exitApp: () {});
      await c.requestReviewIfAppropriate();
      expect(c.ratingModalVisible, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(c.ratingModalVisible, isTrue);
      c.closeRatingModal();
      await c.requestReviewIfAppropriate();
      await tester.pump(const Duration(seconds: 3));
      expect(c.ratingModalVisible, isFalse);
      c.dispose();
    });

    testWidgets('not eligible → no prompt', (tester) async {
      SharedPreferences.setMockInitialValues({ReviewStore.keySessionCount: 1});
      final c = ReviewController(openStoreListing: () async => true, exitApp: () {});
      await c.requestReviewIfAppropriate();
      await tester.pump(const Duration(seconds: 3));
      expect(c.ratingModalVisible, isFalse);
      c.dispose();
    });

    testWidgets('dispose cancels a pending auto prompt', (tester) async {
      SharedPreferences.setMockInitialValues({ReviewStore.keySessionCount: 3, ReviewStore.keyActionCount: 5});
      final c = ReviewController(openStoreListing: () async => true, exitApp: () {});
      await c.requestReviewIfAppropriate();
      c.dispose();
      await tester.pump(const Duration(seconds: 3));
    });

    test('openStoreListing records the request only on success', () async {
      SharedPreferences.setMockInitialValues({});
      final failing = ReviewController(openStoreListing: () async => false, exitApp: () {});
      await failing.openStoreListing();
      expect(await failing.store.lastRequestMs(), isNull);
      final ok = ReviewController(openStoreListing: () async => true, exitApp: () {});
      await ok.openStoreListing();
      expect(await ok.store.lastRequestMs(), isNotNull);
      final throwing = ReviewController(openStoreListing: () => throw StateError('x'), exitApp: () {});
      await throwing.openStoreListing();
    });
  });

  group('ReviewHost + RatingModal', () {
    late ReviewController c;
    var storeOpened = 0;
    var exited = 0;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storeOpened = 0;
      exited = 0;
      c = ReviewController(
        openStoreListing: () async {
          storeOpened++;
          return true;
        },
        exitApp: () => exited++,
      );
    });

    Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          builder: (context, child) => ReviewHost(controller: c, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () => ReviewScope.maybeOf(context)!.showRatingModal(),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));

    testWidgets('records one session on mount and exposes ReviewScope', (tester) async {
      await pumpHost(tester);
      await tester.pump();
      expect(await c.store.sessionCount(), 1);
      expect(find.byKey(const ValueKey('review_modal')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      expect(find.text('Enjoying CrickBex?'), findsOneWidget);
      expect(find.byKey(const ValueKey('review_exit_app')), findsNothing);
    });

    testWidgets('3+ stars → loader → store opened after 2s, modal closed', (tester) async {
      await pumpHost(tester);
      c.showRatingModal();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review_star_4')));
      await tester.pump();
      expect(find.text('Opening the store…'), findsOneWidget);
      expect(find.byKey(const ValueKey('review_maybe_later')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('review_star_1')), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(storeOpened, 1);
      expect(c.ratingModalVisible, isFalse);
      expect(await c.store.lastRequestMs(), isNotNull);
    });

    testWidgets('1–2 stars → hint + Send feedback closes without store', (tester) async {
      await pumpHost(tester);
      c.showRatingModal();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review_star_2')));
      await tester.pump();
      expect(find.text('Tell us what we can improve via Contact Us.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review_send_feedback')));
      await tester.pump();
      expect(c.ratingModalVisible, isFalse);
      expect(storeOpened, 0);
    });

    testWidgets('Maybe later and backdrop tap dismiss', (tester) async {
      await pumpHost(tester);
      c.showRatingModal();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review_maybe_later')));
      await tester.pump();
      expect(c.ratingModalVisible, isFalse);
      c.showRatingModal();
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(c.ratingModalVisible, isFalse);
    });

    testWidgets('exit flow shows "Exit app" which exits', (tester) async {
      await pumpHost(tester);
      c.showRatingModalForExit();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review_exit_app')));
      await tester.pump();
      expect(exited, 1);
      expect(c.ratingModalVisible, isFalse);
    });

    testWidgets('Android back closes the modal first', (tester) async {
      await pumpHost(tester);
      c.showRatingModal();
      await tester.pump();
      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      expect(handled, isTrue);
      expect(c.ratingModalVisible, isFalse);
    });

    testWidgets('dismiss during store redirect cancels the redirect', (tester) async {
      await pumpHost(tester);
      c.showRatingModal();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review_star_5')));
      await tester.pump();
      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      expect(handled, isTrue);
      expect(c.ratingModalVisible, isFalse);
      expect(find.byType(RatingModal), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(storeOpened, 0);
    });

    testWidgets('narrow screen: star row fits without overflow', (tester) async {
      tester.view.physicalSize = const Size(300, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHost(tester);
      c.showRatingModal();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
