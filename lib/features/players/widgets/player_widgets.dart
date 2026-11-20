import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../player_models.dart';

/// Max content width for the Discover pages (lists read badly when they
/// stretch across a 1440 px window).
const double kDiscoverMaxWidth = 720;

/// Centres [child] and caps it at [kDiscoverMaxWidth].
class Capped extends StatelessWidget {
  const Capped({
    super.key,
    required this.child,
    this.maxWidth = kDiscoverMaxWidth,
  });
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Player photo, or the player's initials on a neutral disc when there is no
/// usable image URL (many players have none).
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 40,
  });
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final u = url?.trim() ?? '';
    final hasImage = u.startsWith('http://') || u.startsWith('https://');
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: p.hairline),
        ),
        alignment: Alignment.center,
        child: hasImage
            ? NetImage(
                url: u,
                size: size - 2,
                fallbackLetter: name,
                fit: BoxFit.cover,
              )
            : Padding(
                padding: EdgeInsets.all(size * 0.16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    initialsOf(name),
                    textScaler: TextScaler.noScaling,
                    style: AppFont.style(
                      size: size * 0.36,
                      weight: FontWeight.w700,
                      width: 90,
                      color: p.inkMuted,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// A small tinted label ("#5 Test").
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.text, this.semanticsLabel});
  final String text;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: p.brandTint,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: AppFont.style(
            size: 12,
            weight: FontWeight.w700,
            color: p.ink,
            tabularFigures: true,
          ),
        ),
      ),
    );
  }
}

/// One player in a list: avatar, name, role line, ICC badge.
class PlayerRow extends StatelessWidget {
  const PlayerRow({
    super.key,
    required this.player,
    this.onPress,
    this.showCountry = false,
  });
  final CountryPlayer player;
  final ValueChanged<CountryPlayer>? onPress;

  /// Search results mix countries, so the country goes in the second line.
  final bool showCountry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sub = [
      if (showCountry && player.country.isNotEmpty) player.country,
      ?player.subtitle,
    ].join(', ');
    return Semantics(
      button: onPress != null,
      label: [
        player.name,
        if (sub.isNotEmpty) sub,
        ?player.rankLabel,
      ].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onTap: onPress == null ? null : () => onPress!(player),
        child: Container(
          color: p.surface,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: 10,
          ),
          child: Row(
            children: [
              PlayerAvatar(url: player.logo, name: player.name, size: 44),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.name,
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta,
                      ),
                    ],
                  ],
                ),
              ),
              if (player.rankBadge != null) ...[
                const SizedBox(width: Spacing.sm),
                RankBadge(text: player.rankBadge!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton mirroring [PlayerRow].
class PlayerRowSkeleton extends StatelessWidget {
  const PlayerRowSkeleton({super.key, this.nameWidth = 150});
  final double nameWidth;

  @override
  Widget build(BuildContext context) => Container(
    color: context.palette.surface,
    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 10),
    child: Row(
      children: [
        const ShimmerBox(width: 44, height: 44, radius: 22),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: nameWidth, height: 14, radius: 4),
              const SizedBox(height: 6),
              const ShimmerBox(width: 110, height: 11, radius: 4),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Skeleton list of [count] player rows.
class PlayersSkeleton extends StatelessWidget {
  const PlayersSkeleton({super.key, this.count = 8});
  final int count;

  @override
  Widget build(BuildContext context) => ShimmerGroup(
    child: Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const RowDivider(),
          PlayerRowSkeleton(nameWidth: 110.0 + (i * 37) % 70),
        ],
      ],
    ),
  );
}

/// Hairline between list rows, inset past the avatar.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key, this.indent = 72});
  final double indent;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.surface,
    child: Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      color: context.palette.hairline,
    ),
  );
}

/// Section heading inside a Discover page.
class PageSectionTitle extends StatelessWidget {
  const PageSectionTitle(this.text, {super.key, this.trailing, this.padding});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding:
        padding ??
        const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.xxl,
          Spacing.lg,
          Spacing.sm,
        ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: AppText.sectionTitle),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Format-wise career table. The format column stays put while the stat
/// columns scroll sideways when they do not fit (320 px phones, large text).
class CareerTableView extends StatelessWidget {
  const CareerTableView({
    super.key,
    required this.table,
    required this.title,
    this.scrollKey,
  });
  final CareerTable table;

  /// "Batting" / "Bowling" (for the spoken summary).
  final String title;
  final Key? scrollKey;

  static double _baseWidth(String col) => switch (col) {
    'BBI' => 60,
    'Runs' || 'Wkts' || 'Econ' => 58,
    _ => 52,
  };

  String _spoken() => [
    '$title career',
    for (final r in table.rows)
      '${r.format}: ${[for (var i = 0; i < table.columns.length; i++) '${table.columns[i]} ${r.cells[i] == kDash ? 'not available' : r.cells[i]}'].join(', ')}',
  ].join('. ');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ts = MediaQuery.textScalerOf(context);
    final rowH = math.max(44.0, ts.scale(15) * 1.25 + 22);
    final headH = math.max(36.0, ts.scale(12) * 1.25 + 18);
    final widest = table.rows.fold<double>(0, (w, r) {
      final tp = TextPainter(
        text: TextSpan(text: r.format, style: AppText.name),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: ts,
      )..layout();
      final width = tp.width;
      tp.dispose();
      return math.max(w, width);
    });
    // Fits the longest format name ("The Hundred"), within limits so the
    // stat columns keep most of a 320 px screen.
    final firstW = (widest + 2 * Spacing.sm + 2)
        .clamp(ts.scale(72), math.max(ts.scale(72), 150.0))
        .toDouble();
    final numStyle = AppFont.style(
      size: 15,
      weight: FontWeight.w600,
      color: p.ink,
      tabularFigures: true,
    );
    final headStyle = AppText.small;

    Widget cell(
      String text,
      double w,
      double h,
      TextStyle style, {
      TextAlign align = TextAlign.right,
    }) => SizedBox(
      width: w,
      height: h,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Align(
          alignment: align == TextAlign.right
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            textAlign: align,
            style: style,
          ),
        ),
      ),
    );

    return Semantics(
      label: _spoken(),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: p.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: firstW,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: p.hairline)),
              ),
              child: Column(
                children: [
                  ColoredBox(
                    color: p.surfaceAlt,
                    child: cell(
                      'Format',
                      firstW - 1,
                      headH,
                      headStyle,
                      align: TextAlign.left,
                    ),
                  ),
                  for (final r in table.rows)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: p.hairline)),
                      ),
                      child: cell(
                        r.format,
                        firstW - 1,
                        rowH - 1,
                        AppText.name,
                        align: TextAlign.left,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final base = [
                    for (final col in table.columns) ts.scale(_baseWidth(col)),
                  ];
                  final sum = base.fold<double>(0, (a, b) => a + b);
                  // Stretch to fill wide screens; scroll when it does not fit.
                  final k = sum < c.maxWidth ? c.maxWidth / sum : 1.0;
                  final widths = [
                    for (final w in base) (w * k).floorToDouble(),
                  ];
                  final total = widths.fold<double>(0, (a, b) => a + b);
                  return SingleChildScrollView(
                    key: scrollKey,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: total,
                      child: Column(
                        children: [
                          ColoredBox(
                            color: p.surfaceAlt,
                            child: Row(
                              children: [
                                for (var i = 0; i < table.columns.length; i++)
                                  cell(
                                    table.columns[i],
                                    widths[i],
                                    headH,
                                    headStyle,
                                  ),
                              ],
                            ),
                          ),
                          for (final r in table.rows)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: p.hairline),
                                ),
                              ),
                              child: Row(
                                children: [
                                  for (var i = 0; i < table.columns.length; i++)
                                    cell(
                                      i < r.cells.length ? r.cells[i] : kDash,
                                      widths[i],
                                      rowH - 1,
                                      i < r.cells.length && r.cells[i] == kDash
                                          ? numStyle.copyWith(color: p.inkMuted)
                                          : numStyle,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
