import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../../players/player_models.dart';
import '../../players/widgets/player_widgets.dart';
import '../ranking_models.dart';

/// Column widths shared by the header and the rows so figures line up.
class RankColumns {
  RankColumns(BuildContext context, {required this.isTeam})
    : _ts = MediaQuery.textScalerOf(context),
      _width =
          math.min(MediaQuery.sizeOf(context).width, kDiscoverMaxWidth) -
          2 * Spacing.lg;
  final TextScaler _ts;
  final double _width;
  final bool isTeam;

  /// Too narrow for a separate Points column (320 px at large text): the
  /// points move under the team name and the avatar is dropped.
  bool get compact {
    final fixed =
        rank + 32 + Spacing.md + Spacing.sm + rating + (isTeam ? points : 0);
    return _width - fixed < _ts.scale(110);
  }

  bool get showPointsColumn => isTeam && !compact;

  double get rank => _ts.scale(36).clamp(36.0, 64.0);
  double get rating => _ts.scale(56).clamp(56.0, 100.0);
  double get points => _ts.scale(64).clamp(64.0, 112.0);
}

TextStyle _figure(
  BuildContext context,
  double size, {
  FontWeight weight = FontWeight.w600,
  Color? color,
}) => AppFont.style(
  size: size,
  weight: weight,
  width: AppFont.scoreWidth,
  color: color ?? context.palette.ink,
  tabularFigures: true,
);

Widget _avatar(RankingRowItem item, bool isTeam, double size) => isTeam
    ? ExcludeSemantics(
        child: TeamLogo(url: null, name: item.name, size: size),
      )
    : PlayerAvatar(url: item.image, name: item.name, size: size);

/// The top three, as a ranked list whose rows grow with rank: the leader
/// gets a big condensed numeral and a tinted band, 2 and 3 a medium one.
/// No medals and no podium steps.
class RankingLeaders extends StatelessWidget {
  const RankingLeaders({
    super.key,
    required this.items,
    required this.isTeam,
    this.onItemPress,
  });
  final List<RankingRowItem> items;
  final bool isTeam;
  final ValueChanged<RankingRowItem>? onItemPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('ranking_leaders'),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.symmetric(horizontal: BorderSide(color: p.hairline)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: p.hairline,
                indent: Spacing.lg,
              ),
            _LeaderRow(
              item: items[i],
              first: i == 0,
              isTeam: isTeam,
              onPress: isTeam || onItemPress == null
                  ? null
                  : () => onItemPress!(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.item,
    required this.first,
    required this.isTeam,
    this.onPress,
  });
  final RankingRowItem item;
  final bool first;
  final bool isTeam;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ts = MediaQuery.textScalerOf(context);
    final numeral = first ? 52.0 : 34.0;
    final sub = [
      if (item.rating != null) 'Rating ${item.rating}',
      if (item.points != null) '${item.points} points',
    ];
    final row = Container(
      color: first ? p.brandTint : null,
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        first ? Spacing.lg : Spacing.md,
        Spacing.lg,
        first ? Spacing.lg : Spacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40.0 * math.min(ts.scale(1), 1.2),
            child: Text(
              '${item.rank}',
              textScaler: ts.clamp(maxScaleFactor: 1.2),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: _figure(
                context,
                numeral,
                weight: FontWeight.w800,
                color: first ? p.brandText : p.ink,
              ).copyWith(height: 1.0),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          _avatar(item, isTeam, first ? 48 : 40),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: first
                      ? AppText.sectionTitle
                      : AppText.name.copyWith(fontSize: 16),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub.join(', '), style: AppText.meta),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onPress != null,
      label: item.semanticsLabel,
      excludeSemantics: true,
      child: Pressable(
        key: ValueKey('ranking_top_${item.rank}'),
        onTap: onPress,
        child: row,
      ),
    );
  }
}

/// Table header above the dense rows.
class RankingTableHeader extends StatelessWidget {
  const RankingTableHeader({
    super.key,
    required this.isTeam,
    required this.label,
  });
  final bool isTeam;

  /// "Ranks 4 to 20" / "3 results".
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cols = RankColumns(context, isTeam: isTeam);
    final s = AppText.small;
    return Container(
      margin: const EdgeInsets.only(top: Spacing.xl),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(
          top: BorderSide(color: p.hairline),
          bottom: BorderSide(color: p.hairline),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: s)),
          SizedBox(
            width: cols.rating,
            child: Text('Rating', textAlign: TextAlign.right, style: s),
          ),
          if (cols.showPointsColumn)
            SizedBox(
              width: cols.points,
              child: Text('Points', textAlign: TextAlign.right, style: s),
            ),
        ],
      ),
    );
  }
}

/// Dense ranked row (rank, avatar, name, rating[, points]).
class RankingListRow extends StatelessWidget {
  const RankingListRow({
    super.key,
    required this.item,
    required this.isTeam,
    this.onPress,
  });
  final RankingRowItem item;
  final bool isTeam;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cols = RankColumns(context, isTeam: isTeam);
    final fig = _figure(context, 17);
    Widget figure(String? v, double w) => SizedBox(
      width: w,
      child: Text(
        v ?? kDash,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        textAlign: TextAlign.right,
        style: v == null ? fig.copyWith(color: p.inkMuted) : fig,
      ),
    );
    return Semantics(
      button: !isTeam && onPress != null,
      label: item.semanticsLabel,
      excludeSemantics: true,
      child: Pressable(
        onTap: isTeam ? null : onPress,
        child: Container(
          color: p.surface,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: cols.rank,
                child: Text(
                  '${item.rank}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: _figure(context, 17, color: p.inkMuted),
                ),
              ),
              if (!cols.compact) ...[
                _avatar(item, isTeam, 32),
                const SizedBox(width: Spacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.name,
                    ),
                    if (isTeam && !cols.showPointsColumn && item.points != null)
                      Text('${item.points} points', style: AppText.meta),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              figure(item.rating, cols.rating),
              if (cols.showPointsColumn) figure(item.points, cols.points),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton mirroring the leaders + dense rows.
class RankingSkeleton extends StatelessWidget {
  const RankingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(double avatar, double pad, double nameW) => Container(
      color: p.surface,
      padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: pad),
      child: Row(
        children: [
          ShimmerBox(width: avatar * 0.6, height: avatar * 0.6, radius: 4),
          const SizedBox(width: Spacing.md),
          ShimmerBox(width: avatar, height: avatar, radius: avatar / 2),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ShimmerBox(width: nameW, height: 14, radius: 4),
            ),
          ),
          const ShimmerBox(width: 40, height: 16, radius: 4),
        ],
      ),
    );
    return ShimmerGroup(
      key: const ValueKey('rankings_shimmer'),
      child: Column(
        children: [
          const SizedBox(height: Spacing.lg),
          row(48, Spacing.lg, 160),
          row(40, Spacing.md, 130),
          row(40, Spacing.md, 140),
          const SizedBox(height: Spacing.xl),
          for (var i = 0; i < 8; i++) ...[
            if (i > 0) Divider(height: 1, color: p.hairline),
            row(32, Spacing.sm + 2, 100.0 + (i * 29) % 80),
          ],
        ],
      ),
    );
  }
}
