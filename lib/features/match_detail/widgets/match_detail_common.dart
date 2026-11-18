import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../logic/commentary_html.dart';
import '../logic/match_detail_logic.dart';

/// RN getBallColor.
Color ballColor(String? value) => switch (ballTone(value)) {
      BallTone.four => AppColors.gold,
      BallTone.six => AppColors.goldLight,
      BallTone.wicket => AppColors.error,
      BallTone.dot => AppColors.dot,
      BallTone.run => AppColors.run,
    };

/// Round ball chip.
class BallCircle extends StatelessWidget {
  const BallCircle({super.key, required this.value, this.size = 34, this.fontSize = 14, this.bordered = false});
  final String value;
  final double size;
  final double fontSize;
  final bool bordered;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ballColor(value),
          shape: BoxShape.circle,
          border: bordered ? Border.all(color: AppColors.border) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: fontSize)),
          ),
        ),
      );
}

/// RN styles.sectionCard (+ optional scorecardStatSection padding).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.stat = false});
  final Widget child;
  final bool stat;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: stat ? Spacing.md : Spacing.sm),
        padding: stat ? const EdgeInsets.fromLTRB(10, Spacing.sm, 10, Spacing.sm) : const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Renders API commentary HTML (strong/b/em/i/br) as one rich Text. The runs
/// are parsed once when data arrives (see [CommentaryBall.textRuns]).
class CommentaryRichParagraph extends StatelessWidget {
  const CommentaryRichParagraph({super.key, required this.runs, this.style});
  final List<CommentaryTextRun> runs;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          for (final r in runs)
            TextSpan(
              text: r.text,
              style: TextStyle(
                fontWeight: r.bold ? FontWeight.w800 : FontWeight.w400,
                fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
        ]),
        style: style ?? const TextStyle(fontSize: 14, color: AppColors.text),
      );
}

const _headerStat = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText);
const _cellStyle = TextStyle(fontSize: 12, color: AppColors.text, fontFeatures: [FontFeature.tabularFigures()]);

/// Dark header band of a stats table: first label flexible, then fixed-width stat columns.
class StatTableHeader extends StatelessWidget {
  const StatTableHeader({super.key, required this.first, required this.columns, this.lastWidth = 42});
  final String first;
  final List<String> columns;
  final double lastWidth;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.tableHeaderBg,
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.xs),
        child: Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.xs),
              child: Text(first, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.tableHeaderText)),
            ),
          ),
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: i == columns.length - 1 ? lastWidth : 36,
              child: Text(columns[i], textAlign: TextAlign.center, style: _headerStat),
            ),
        ]),
      );
}

class StatCell extends StatelessWidget {
  const StatCell(this.text, {super.key, this.width = 36});
  final String text;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(text, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: _cellStyle),
        ),
      );
}

/// Rounded bordered table container.
class StatTable extends StatelessWidget {
  const StatTable({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Grey table row with hairline top border (none on first).
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.child, this.first = false});
  final Widget child;
  final bool first;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.xs),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          border: first ? null : const Border(top: BorderSide(color: AppColors.borderSubtle, width: 0.5)),
        ),
        child: child,
      );
}
