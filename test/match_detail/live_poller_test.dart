import 'dart:async';

import 'package:crickbex/features/match_detail/logic/live_poller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interval = Duration(seconds: 10);

  testWidgets('ticks every interval while enabled and visible; stops when disabled', (tester) async {
    final vis = ValueNotifier(true);
    var ticks = 0;
    final p = Poller(interval: interval, visibility: vis, task: () async => ticks++);
    p.setEnabled(true);
    await tester.pump(const Duration(seconds: 9));
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    await tester.pump(interval);
    expect(ticks, 2);
    p.setEnabled(false);
    await tester.pump(const Duration(minutes: 1));
    expect(ticks, 2);
    p.dispose();
  });

  testWidgets('never overlaps: next tick waits for the slow one', (tester) async {
    final vis = ValueNotifier(true);
    var started = 0;
    Completer<void>? pending;
    final p = Poller(
      interval: interval,
      visibility: vis,
      task: () {
        started++;
        pending = Completer<void>();
        return pending!.future;
      },
    );
    p.setEnabled(true);
    await tester.pump(interval);
    expect(started, 1);
    await tester.pump(const Duration(minutes: 1)); // still in flight
    expect(started, 1);
    pending!.complete();
    await tester.pump();
    await tester.pump(interval);
    expect(started, 2);
    pending!.complete();
    p.dispose();
  });

  testWidgets('pauses while invisible and ticks immediately when visible again', (tester) async {
    final vis = ValueNotifier(true);
    var ticks = 0;
    final p = Poller(interval: interval, visibility: vis, task: () async => ticks++);
    p.setEnabled(true);
    await tester.pump(const Duration(seconds: 5));
    vis.value = false;
    await tester.pump(const Duration(minutes: 2));
    expect(ticks, 0);
    vis.value = true;
    await tester.pump();
    expect(ticks, 1);
    await tester.pump(interval);
    expect(ticks, 2);
    p.dispose();
  });

  testWidgets('runNow ticks at once; errors are swallowed; dispose cancels', (tester) async {
    final vis = ValueNotifier(true);
    var ticks = 0;
    final p = Poller(
      interval: interval,
      visibility: vis,
      task: () async {
        ticks++;
        throw Exception('x');
      },
    );
    p.setEnabled(true, runNow: true);
    await tester.pump();
    expect(ticks, 1);
    await tester.pump(interval);
    expect(ticks, 2);
    p.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(ticks, 2);
  });

  testWidgets('ScreenVisibility follows app lifecycle and TickerMode', (tester) async {
    final v = ScreenVisibility();
    expect(v.value, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(v.value, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(v.value, isTrue);

    final enabled = ValueNotifier(true);
    late BuildContext ctx;
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (_, e, _) => TickerMode(
        enabled: e,
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ),
    ));
    v.bindTickerMode(TickerMode.getValuesNotifier(ctx));
    expect(v.value, isTrue);
    enabled.value = false;
    await tester.pump();
    expect(v.value, isFalse);
    enabled.value = true;
    await tester.pump();
    expect(v.value, isTrue);
    v.dispose();
  });
}
