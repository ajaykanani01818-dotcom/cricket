import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/json.dart';

/// Navigation helpers. Detail pages are pushed onto the CURRENT tab's stack
/// (same as RN, where each tab has its own stack with MatchDetail/PlayerDetail).
class AppNav {
  AppNav._();

  /// '/live', '/matches', '/series', '/ranking', '/players' or '/settings'.
  static String tabRoot(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    return seg.isEmpty ? '/live' : '/${seg.first}';
  }

  static Future<T?> match<T>(BuildContext context, String matchId) =>
      context.push<T>('${tabRoot(context)}/match/${Uri.encodeComponent(matchId)}');

  /// [player] optional pre-fetched list item (rendered while info loads).
  static Future<T?> player<T>(BuildContext context, String playerKey, {JsonMap? player}) =>
      context.push<T>('${tabRoot(context)}/player/${Uri.encodeComponent(playerKey)}', extra: player);

  static Future<T?> seriesDetail<T>(BuildContext context, String seriesId, {String? seriesName}) =>
      context.push<T>('${tabRoot(context)}/series-detail/${Uri.encodeComponent(seriesId)}', extra: seriesName);

  /// Pages that only exist in some stacks (More/legal pages): pushed under /live or /settings.
  static Future<T?> page<T>(BuildContext context, String name) {
    final root = tabRoot(context);
    final base = root == '/settings' ? '/settings' : '/live';
    return context.push<T>('$base/$name');
  }
}
