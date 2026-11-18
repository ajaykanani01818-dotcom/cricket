import 'package:crickbex/core/services/cricket_services.dart';
import 'package:crickbex/features/match_detail/tabs/playing_xi_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

void main() {
  final original = MatchService.instance;
  tearDown(() => MatchService.instance = original);

  testWidgets('shimmer → real fixture data', (tester) async {
    final calls = installService((r) => r.url.path == '/match/m1/playing11' ? okJson(fixture('match_playing11')) : null);
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    expect(find.byKey(const ValueKey('playing_xi_loading')), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('playing_xi_loading')), findsNothing);
    expect(find.text('South Africa Squad'), findsOneWidget);
    expect(find.byKey(const ValueKey('playing_xi_player_aiden_markram')), findsOneWidget);
    expect(find.text('Aiden Markram'), findsOneWidget);
    expect(calls, ['/match/m1/playing11']);

    // Team 2 further down the list.
    await tester.scrollUntilVisible(find.text('Najmul Hossain Shanto'), 300);
    final shanto = find.byKey(const ValueKey('playing_xi_player_najmul_hossain_shanto'));
    expect(find.descendant(of: shanto, matching: find.text('C')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mushfiqur Rahim'), 300);
    final mushfiq = find.byKey(const ValueKey('playing_xi_player_mushfiqur_rahim'));
    expect(find.descendant(of: mushfiq, matching: find.text('WK')), findsOneWidget);
  });

  testWidgets('missing match → empty state', (tester) async {
    installService((r) => okJson({'message': 'ok', 'data': {}}));
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.text('No Playing XI data available'), findsOneWidget);
  });

  testWidgets('empty team lists show "No players available"', (tester) async {
    installService((r) => okJson({
          'data': {
            'match': {
              'teams': {
                'team1': {'name': 'India'},
                'team2': {'name': 'Australia'},
              },
              'playingXI_Team1': [],
            }
          }
        }));
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.text('India Squad'), findsOneWidget);
    expect(find.text('Australia Squad'), findsOneWidget);
    expect(find.text('No players available'), findsNWidgets(2));
  });

  testWidgets('server error → error state; Retry recovers', (tester) async {
    var fail = true;
    installService((r) => fail ? serverError() : okJson(fixture('match_playing11')));
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('playing_xi_error')), findsOneWidget);
    expect(find.text('Boom'), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('empty_state_action')));
    await tester.pump();
    await tester.pump();
    expect(find.text('South Africa Squad'), findsOneWidget);
  });

  testWidgets('live: polls every 15s silently, keeps data + scroll; stops on dispose', (tester) async {
    var n = 0;
    final calls = installService((r) {
      n++;
      return n == 2 ? serverError() : okJson(fixture('match_playing11'));
    });
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: true)));
    await tester.pump();
    await tester.pump();
    expect(find.text('South Africa Squad'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    final pos = tester.state<ScrollableState>(scrollable).position.pixels;
    final before = tester.widget(find.byKey(const ValueKey('playing_xi_team1')));

    await tester.pump(const Duration(seconds: 15)); // poll #2 fails silently
    await tester.pump();
    expect(calls, hasLength(2));
    expect(find.byKey(const ValueKey('playing_xi_error')), findsNothing);
    expect(find.byKey(const ValueKey('playing_xi_loading')), findsNothing);

    await tester.pump(const Duration(seconds: 15)); // poll #3, identical data
    await tester.pump();
    expect(calls, hasLength(3));
    expect(identical(tester.widget(find.byKey(const ValueKey('playing_xi_team1'))), before), isTrue);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, pos);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(calls, hasLength(3));
  });

  testWidgets('not live: no polling', (tester) async {
    final calls = installService((r) => okJson(fixture('match_playing11')));
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 45));
    expect(calls, hasLength(1));
  });

  testWidgets('polling skips ticks while tickers are disabled (offstage)', (tester) async {
    final calls = installService((r) => okJson(fixture('match_playing11')));
    Widget build(bool enabled) => host(TickerMode(
          enabled: enabled,
          child: const MatchPlayingXITab(matchId: 'm1', isLive: true),
        ));
    await tester.pumpWidget(build(true));
    await tester.pump();
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(seconds: 31));
    expect(calls, hasLength(1));
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(calls, hasLength(2));
  });

  testWidgets('matchId change reloads for the new match', (tester) async {
    final calls = installService((r) => okJson(fixture('match_playing11')));
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm2', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(calls, ['/match/m1/playing11', '/match/m2/playing11']);
  });

  testWidgets('works inside a parent scroll view; network failure surfaces an error', (tester) async {
    installService((r) => okJson(fixture('match_playing11')));
    await tester.pumpWidget(scrollHost(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Bangladesh Squad'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // Network failure (MockClient throwing) → friendly message.
    installServiceThrowing();
    await tester.pumpWidget(host(const MatchPlayingXITab(matchId: 'm1', isLive: false)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('playing_xi_error')), findsOneWidget);
  });
}

void installServiceThrowing() => installService((r) => throw http.ClientException('offline'));
