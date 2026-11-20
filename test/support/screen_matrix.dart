import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Responsive test matrix: pump any widget at every viewport x text scale x
/// brightness and collect layout overflow errors ("A RenderFlex overflowed by
/// N pixels ...", "overflowed by" from any render object).
///
/// The viewport list is the same one `tool/responsive/shoot_web.py` uses.
///
/// ```dart
/// testWidgets('home is overflow-free', (tester) async {
///   final report = await pumpScreenMatrix(tester, name: 'home', build: (c) => MyApp());
///   // pumpScreenMatrix already failed the test if failOnOverflow is true.
/// });
/// ```
///
/// Text scale and brightness are applied through the test platform dispatcher
/// (`MediaQuery.textScaler` / `platformBrightness`), so they reach widgets that
/// build their own MaterialApp. [MatrixCase.brightness] is also exposed to
/// [build] so a caller can pass `themeMode` / `darkTheme` explicitly.
class MatrixViewport {
  const MatrixViewport(this.name, this.width, this.height);
  final String name;
  final double width;
  final double height;
  Size get size => Size(width, height);
  @override
  String toString() => '${width.toInt()}x${height.toInt()}';
}

const List<MatrixViewport> kMatrixViewports = [
  MatrixViewport('small-phone', 320, 640),
  MatrixViewport('phone', 360, 780),
  MatrixViewport('iphone', 390, 844),
  MatrixViewport('large-phone', 412, 915),
  MatrixViewport('foldable', 600, 960),
  MatrixViewport('tablet', 820, 1180),
  MatrixViewport('laptop', 1280, 800),
  MatrixViewport('desktop', 1440, 900),
];

const List<double> kMatrixTextScales = [1.0, 1.3, 2.0];
const List<Brightness> kMatrixBrightness = [Brightness.light, Brightness.dark];

class MatrixCase {
  const MatrixCase(this.viewport, this.textScale, this.brightness);
  final MatrixViewport viewport;
  final double textScale;
  final Brightness brightness;
  String get id => '$viewport@${textScale}x/${brightness.name}';
  @override
  String toString() => id;
}

class OverflowFinding {
  OverflowFinding(this.matrixCase, this.message);
  final MatrixCase matrixCase;

  /// First lines of the error (includes "overflowed by N pixels on the ...").
  final String message;

  @override
  String toString() => '[${matrixCase.id}] $message';
}

class MatrixReport {
  MatrixReport(this.name);
  final String name;
  final List<MatrixCase> cases = [];
  final List<OverflowFinding> overflows = [];

  bool get isClean => overflows.isEmpty;

  /// Case ids with at least one overflow.
  Set<String> get failingCases => {for (final o in overflows) o.matrixCase.id};

  String format() {
    final b = StringBuffer('screen matrix "$name": ${cases.length} cases, '
        '${overflows.length} overflow error(s) in ${failingCases.length} case(s)\n');
    for (final o in overflows) {
      b.writeln('  $o');
    }
    return b.toString();
  }
}

bool _isOverflow(FlutterErrorDetails d) {
  final s = d.exceptionAsString();
  return s.contains('overflowed by') || s.contains('RenderFlex overflowed');
}

final _sourceRef = RegExp(r'(lib/[\w/]+\.dart:\d+(:\d+)?)');

String _summary(FlutterErrorDetails d) {
  final first = d.exceptionAsString().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  // "The relevant error-causing widget was: Row  Row:file:///.../lib/x.dart:12:5"
  final where = _sourceRef.firstMatch(d.toString())?.group(1);
  return where == null ? first : '$first  at $where';
}

/// Default settle: a fixed number of frames (pumpAndSettle never returns while
/// shimmers / live dots animate).
Future<void> defaultMatrixSettle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps `build(case)` once per matrix case and collects overflow errors.
///
/// - [setUp] runs before each case (e.g. reinstall a FakeApi, reset prefs).
/// - [settle] advances frames after pumping (default: [defaultMatrixSettle]).
/// - [interact] optional per-case action after settling (scroll, tap a tab);
///   overflows during it are collected too.
/// - Non-overflow errors are forwarded to the test framework unchanged (they
///   still fail the test).
/// - [failOnOverflow]: fail the test when any overflow was found (default
///   true). The report is printed and, when [reportDir] is set, written to
///   `<reportDir>/<name>.txt`.
Future<MatrixReport> pumpScreenMatrix(
  WidgetTester tester, {
  required String name,
  required Widget Function(MatrixCase c) build,
  List<MatrixViewport> viewports = kMatrixViewports,
  List<double> textScales = kMatrixTextScales,
  List<Brightness> brightness = kMatrixBrightness,
  double devicePixelRatio = 1.0,
  Future<void> Function(MatrixCase c)? setUp,
  Future<void> Function(WidgetTester tester) settle = defaultMatrixSettle,
  Future<void> Function(WidgetTester tester, MatrixCase c)? interact,
  bool failOnOverflow = true,
  String? reportDir = 'build/screen_matrix',
}) async {
  final report = MatrixReport(name);
  final original = FlutterError.onError;
  MatrixCase? current;
  FlutterError.onError = (details) {
    final c = current;
    if (c != null && _isOverflow(details)) {
      report.overflows.add(OverflowFinding(c, _summary(details)));
    } else {
      original?.call(details);
    }
  };
  try {
    for (final vp in viewports) {
      for (final ts in textScales) {
        for (final br in brightness) {
          final c = MatrixCase(vp, ts, br);
          report.cases.add(c);
          tester.view.devicePixelRatio = devicePixelRatio;
          tester.view.physicalSize = vp.size * devicePixelRatio;
          tester.platformDispatcher.textScaleFactorTestValue = ts;
          tester.platformDispatcher.platformBrightnessTestValue = br;
          await setUp?.call(c);
          current = c;
          await tester.pumpWidget(KeyedSubtree(key: ValueKey(c.id), child: build(c)));
          await settle(tester);
          if (interact != null) await interact(tester, c);
          current = null;
          // Unmount so the next case starts from a fresh state.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    }
  } finally {
    current = null;
    FlutterError.onError = original;
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  }

  final text = report.format();
  debugPrint(text);
  if (reportDir != null) {
    try {
      Directory(reportDir).createSync(recursive: true);
      File('$reportDir/$name.txt').writeAsStringSync(text);
    } catch (_) {}
  }
  if (failOnOverflow && !report.isClean) {
    fail(text);
  }
  return report;
}
