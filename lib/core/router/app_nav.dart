import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/json.dart';

/// The five bottom-bar tabs, in bar order (never reorder: research §1 rule).
enum AppTab {
  home('/home'),
  live('/live'),
  matches('/matches'),
  discover('/discover'),
  settings('/settings');

  const AppTab(this.path);
  final String path;
}

/// Discover hub sections (pushed on the Discover tab's stack).
enum DiscoverSection {
  series('series'),
  rankings('rankings'),
  players('players');

  const DiscoverSection(this.segment);
  final String segment;
  String get path => '/discover/$segment';
}

/// Navigation helpers. Detail pages are pushed onto the CURRENT tab's stack
/// (each tab keeps its own stack); every tab root has the match / player /
/// series-detail / info routes.
class AppNav {
  AppNav._();

  /// The Future returned by the navigation helpers completes once the page
  /// transition has had [pushFrames] frames, NOT when the pushed page closes.
  ///
  /// The push Future normally completes on pop, but it never completes when
  /// the page is removed another way (a bottom-bar tab switch resets the
  /// branch). Screens clear their tap guards (`_navigating`, TapGuard) when
  /// this Future completes, so an unfinished one locked every later tap on
  /// that screen (e.g. the Home "Live now" card did nothing until "All live"
  /// was used). Callers only need "navigation started", never a result.
  /// Frame-based on purpose: no Timer, so nothing stays pending in tests.
  static const pushFrames = 18;

  static Future<T?> _push<T>(BuildContext context, String location, {Object? extra}) {
    unawaited(context.push<T>(location, extra: extra).then<void>((_) {}, onError: (Object _) {}));
    return _afterFrames<T>(pushFrames);
  }

  static Future<T?> _afterFrames<T>(int frames) async {
    for (var i = 0; i < frames; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  /// First path segment of the current location, e.g. '/home', '/discover'.
  static String tabRoot(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    return seg.isEmpty ? AppTab.home.path : '/${seg.first}';
  }

  /// Switch tab (opens the tab at its root, like a bottom-bar tap).
  static void tab(BuildContext context, AppTab tab) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      shell.goBranch(tab.index, initialLocation: true);
    } else {
      context.go(tab.path);
    }
  }

  /// Open a Discover section (Series / Rankings / Players).
  static void discover(BuildContext context, DiscoverSection section) =>
      context.go(section.path);

  static Future<T?> match<T>(BuildContext context, String matchId) =>
      _push<T>(context, '${tabRoot(context)}/match/${Uri.encodeComponent(matchId)}');

  /// [player] optional pre-fetched list item (rendered while info loads).
  static Future<T?> player<T>(
    BuildContext context,
    String playerKey, {
    JsonMap? player,
  }) => _push<T>(
    context,
    '${tabRoot(context)}/player/${Uri.encodeComponent(playerKey)}',
    extra: player,
  );

  static Future<T?> seriesDetail<T>(
    BuildContext context,
    String seriesId, {
    String? seriesName,
  }) => _push<T>(
    context,
    '${tabRoot(context)}/series-detail/${Uri.encodeComponent(seriesId)}',
    extra: seriesName,
  );

  // [B1 search] Begin screen agent B1 edit.
  /// Full-screen search (PRD §11), pushed on the current tab's stack.
  static Future<T?> search<T>(BuildContext context) =>
      _push<T>(context, '${tabRoot(context)}/search');
  // [B1 search] End screen agent B1 edit.

  /// Info pages ('more' | 'privacy' | 'terms' | 'about' | 'contact' |
  /// 'app-info'): pushed on the current tab (every tab has them).
  static Future<T?> page<T>(BuildContext context, String name) =>
      _push<T>(context, '${tabRoot(context)}/$name');
}
