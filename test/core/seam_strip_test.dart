import 'package:crickbex/core/theme/app_theme.dart';
import 'package:crickbex/core/widgets/seam_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

final _theme = buildAppTheme();

Widget _host(Widget child, {bool reduce = false}) => MaterialApp(
  theme: _theme,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  ),
);

List<Ball> _b(List<String> l) => [for (final x in l) Ball.parse(x)];

void main() {
  group('Ball.parse encoding', () {
    final cases = <String, (BallKind, String, String)>{
      '0': (BallKind.dot, '', 'Dot ball'),
      '•': (BallKind.dot, '', 'Dot ball'),
      '1': (BallKind.runs, '1', '1 run'),
      '2': (BallKind.runs, '2', '2 runs'),
      '3': (BallKind.runs, '3', '3 runs'),
      '4': (BallKind.four, '4', 'Four'),
      '6': (BallKind.six, '6', 'Six'),
      'W': (BallKind.wicket, 'W', 'Wicket'),
      'WK': (BallKind.wicket, 'W', 'Wicket'),
      'NB': (BallKind.extra, 'nb', 'No ball'),
      '1NB': (BallKind.extra, 'nb', 'No ball, 1 run'),
      'WD': (BallKind.extra, 'wd', 'Wide'),
      '2wd': (BallKind.extra, 'wd', 'Wide, 2 runs'),
      'LB1': (BallKind.extra, 'lb', 'Leg bye, 1 run'),
      '4B': (BallKind.extra, 'b', 'Bye, 4 runs'),
      'X?': (BallKind.unknown, 'X?', 'X?'),
    };
    cases.forEach((raw, want) {
      test('"$raw" → ${want.$1.name} "${want.$2}" / "${want.$3}"', () {
        final b = Ball.parse(raw);
        expect(b.kind, want.$1);
        expect(b.glyph, want.$2);
        expect(b.description, want.$3);
      });
    });

    test('wides and no-balls are not legal deliveries; byes are', () {
      expect(Ball.parse('WD').isLegal, isFalse);
      expect(Ball.parse('1NB').isLegal, isFalse);
      expect(Ball.parse('LB').isLegal, isTrue);
      expect(Ball.parse('4').isLegal, isTrue);
    });

    test('never colour-only: every non-dot kind carries a glyph', () {
      for (final raw in ['1', '4', '6', 'W', 'NB', 'WD', 'B', 'LB', '???']) {
        expect(Ball.parse(raw).glyph, isNotEmpty, reason: raw);
      }
    });
  });

  group('diffBalls (only genuinely new balls animate)', () {
    test(
      'same list → none',
      () => expect(
        diffBalls(_b(['1', '4']), _b(['1', '4'])).change,
        SeamChange.none,
      ),
    );
    test(
      'one appended → oneNew',
      () => expect(
        diffBalls(_b(['1']), _b(['1', '4'])).change,
        SeamChange.oneNew,
      ),
    );
    test('several appended → catchUp (no replay) with count', () {
      final d = diffBalls(_b(['1']), _b(['1', '4', '0', 'W']));
      expect(d.change, SeamChange.catchUp);
      expect(d.added, 3);
    });
    test(
      'not a continuation → newOver',
      () => expect(
        diffBalls(_b(['1', '4', '6']), _b(['0'])).change,
        SeamChange.newOver,
      ),
    );
  });

  group('SeamStrip widget', () {
    testWidgets('semantics label per ball, in order', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SeamStrip.labels(
            const ['0', '1', '4', '6', 'WK', '1NB'],
            overLabel: 'Ov 61',
            summary: '12 runs',
          ),
        ),
      );
      final labels = <String>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) labels.add(n.label);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.getSemantics(find.byKey(const ValueKey('seam_strip_paint'))));
      expect(
        labels,
        containsAllInOrder(const [
          'Ball 1: Dot ball',
          'Ball 2: 1 run',
          'Ball 3: Four',
          'Ball 4: Six',
          'Ball 5: Wicket',
          'Ball 6: No ball, 1 run',
        ]),
      );
      expect(find.text('Ov 61'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('first build never animates; one new ball drops in', (
      tester,
    ) async {
      await tester.pumpWidget(_host(SeamStrip.labels(const ['1', '0'])));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(_host(SeamStrip.labels(const ['1', '0', '4'])));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(const ValueKey('seam_catch_up')), findsNothing);
    });

    testWidgets(
      'catch-up: >1 new balls show the final state + "+N balls", no animation',
      (tester) async {
        await tester.pumpWidget(_host(SeamStrip.labels(const ['1'])));
        await tester.pumpWidget(
          _host(SeamStrip.labels(const ['1', '4', '0', '6'])),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.hasRunningAnimations, isFalse);
        expect(find.text('+3 balls'), findsOneWidget);
        // The next single ball clears the chip.
        await tester.pumpWidget(
          _host(SeamStrip.labels(const ['1', '4', '0', '6', '2'])),
        );
        expect(find.byKey(const ValueKey('seam_catch_up')), findsNothing);
        await tester.pump(const Duration(milliseconds: 300));
      },
    );

    testWidgets('reduced motion: a new ball does not animate', (tester) async {
      await tester.pumpWidget(
        _host(SeamStrip.labels(const ['1']), reduce: true),
      );
      await tester.pumpWidget(
        _host(SeamStrip.labels(const ['1', '4']), reduce: true),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets(
      'more than 6 balls (extras) widen the slots; no overflow at 320 px × 2.0',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final labels = ['1', 'WD', '0', '1NB', '4', '6', 'W', '2'];
        await tester.pumpWidget(
          _host(
            SeamStrip.labels(labels, overLabel: 'Ov 12', summary: '16 runs'),
          ),
        );
        expect(tester.takeException(), isNull);
        final painter =
            (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('seam_strip_paint')),
                    )
                    .painter!
                as SeamPainter);
        expect(painter.slots, 8);
      },
    );
  });
}
