import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/match_detail/tabs/playing_xi_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

http.Response? lineupRoute(http.Request r) {
  if (r.url.path.endsWith('/playing11')) return okJson(fixture('match_playing11'));
  if (r.url.path.endsWith('/squad')) return okJson(fixture('match_squad'));
  return null;
}

void main() {
  final original = MatchService.instance;
  tearDown(() => MatchService.instance = original);

  testWidgets('skeleton → XI with C / WK text tags, bench from the squad; players tappable', (tester) async {
    final calls = installService(lineupRoute);
    String? tapped;
    await tester.pumpWidget(host(MatchPlayingXITab(matchId: 'm1', isLive: false, onPlayerTap: (k) => tapped = k)));
    expect(find.byKey(const ValueKey('playing_xi_loading')), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(calls.toSet(), {'/match/m1/playing11', '/match/m1/squad'});
    expect(find.text('South Africa'), findsOneWidget);
    expect(find.text('Bangladesh'), findsOneWidget);
    final shanto = find.byKey(const ValueKey('playing_xi_player_najmul_hossain_shanto'));
    expect(find.descendant(of: shanto, matching: find.text('C')), findsOneWidget);
    final mushfiq = find.byKey(const ValueKey('playing_xi_player_mushfiqur_rahim'));
    expect(find.descendant(of: mushfiq, matching: find.text('WK')), findsOneWidget);
    expect(find.text('Bench'), findsNWidgets(2));
    await tester.ensureVisible(find.byKey(const ValueKey('playing_xi_player_aiden_markram')));
    await tester.tap(find.byKey(const ValueKey('playing_xi_player_aiden_markram')));
    expect(tapped, 'aiden_markram');
  });

  testWidgets('teams side by side on wide screens', (tester) async {
    installService(lineupRoute);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    final a = tester.getTopLeft(find.byKey(const ValueKey('playing_xi_team1')));
    final b = tester.getTopLeft(find.byKey(const ValueKey('playing_xi_team2')));
    expect(a.dy, b.dy);
    expect(b.dx, greaterThan(a.dx));
  });

  testWidgets('missing match → not announced; squad failure tolerated', (tester) async {
    installService((r) => r.url.path.endsWith('/playing11') ? okJson({'message': 'ok', 'data': {}}) : serverError());
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('playing_xi_empty')), findsOneWidget);
  });

  testWidgets('server error → error state; Try again recovers', (tester) async {
    var fail = true;
    installService((r) => fail ? serverError() : lineupRoute(r));
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('playing_xi_error')), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('playing_xi_team1')), findsOneWidget);
  });

  testWidgets('live: re-polls every 30 s while ticking; skips while offstage', (tester) async {
    final calls = installService(lineupRoute);
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: true)));
    await tester.pump();
    await tester.pump();
    expect(calls.length, 2);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(calls.length, 4);
    // A new (offstage) instance loads once, then its polls are skipped.
    await tester.pumpWidget(host(const TickerMode(enabled: false, child: MatchPlayingXITab(matchId: 'm1', isLive: true))));
    await tester.pump();
    final n = calls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(calls.length, n);
  });

  testWidgets('matchId change reloads for the new match', (tester) async {
    final calls = installService(lineupRoute);
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm2', isLive: false)));
    await tester.pump();
    expect(calls, contains('/match/m2/playing11'));
  });
}
