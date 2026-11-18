import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/pressable.dart';

const double liveCardWidth = 312;
const double liveCardHeight = 230;
const double liveCardCompactHeight = 210;
const double liveCardMargin = 12;

/// Colors that change based on live vs non-live state (RN `useCardColors`).
class _CardColors {
  const _CardColors({
    required this.cardBg,
    required this.cardBorder,
    required this.shadow,
    required this.seriesText,
    required this.formatBadgeBg,
    required this.formatText,
    required this.placeholderBg,
    required this.placeholderText,
    required this.teamText,
    required this.scoreText,
    required this.vsText,
    required this.footerBorder,
    required this.liveBadgeBg,
    required this.liveBadgeBorder,
    required this.liveDot,
    required this.liveText,
    required this.statusColor,
    required this.chaseColor,
    required this.resultColor,
  });
  final Color cardBg, cardBorder, shadow, seriesText, formatBadgeBg, formatText, placeholderBg, placeholderText;
  final Color teamText, scoreText, vsText, footerBorder, liveBadgeBg, liveBadgeBorder, liveDot, liveText;
  final Color statusColor, chaseColor, resultColor;

  static const live = _CardColors(
    cardBg: AppColors.pitch,
    cardBorder: AppColors.pitchDark,
    shadow: Color(0x470860C4),
    seriesText: Color(0xBFFFFFFF),
    formatBadgeBg: Color(0x33FFFFFF),
    formatText: AppColors.white,
    placeholderBg: Color(0x33FFFFFF),
    placeholderText: AppColors.white,
    teamText: AppColors.white,
    scoreText: AppColors.white,
    vsText: Color(0x80FFFFFF),
    footerBorder: Color(0x33FFFFFF),
    liveBadgeBg: Color(0x33FFFFFF),
    liveBadgeBorder: Color(0x4DFFFFFF),
    liveDot: AppColors.white,
    liveText: AppColors.white,
    statusColor: AppColors.white,
    chaseColor: AppColors.goldLight,
    resultColor: Color(0xBFFFFFFF),
  );

  static const normal = _CardColors(
    cardBg: AppColors.card,
    cardBorder: AppColors.border,
    shadow: Color(0x24000000),
    seriesText: AppColors.textSecondary,
    formatBadgeBg: AppColors.cardAlt,
    formatText: AppColors.textSecondary,
    placeholderBg: AppColors.neutralSurface,
    placeholderText: AppColors.textMuted,
    teamText: AppColors.text,
    scoreText: AppColors.text,
    vsText: AppColors.textMuted,
    footerBorder: AppColors.borderSubtle,
    liveBadgeBg: Color(0x14EF3B3B),
    liveBadgeBorder: Color(0x33EF3B3B),
    liveDot: AppColors.live,
    liveText: AppColors.live,
    statusColor: AppColors.text,
    chaseColor: AppColors.pitch,
    resultColor: AppColors.textSecondary,
  );
}

/// Ported from RN `LiveMatchCard`: score card used in the Home carousel
/// (fixed 312x230) and, with [fullWidth]/[compact], in the Matches list.
/// Blue when the match is live (with a blinking LIVE badge), white otherwise.
class LiveMatchCard extends StatelessWidget {
  const LiveMatchCard({super.key, required this.match, required this.onTap, this.fullWidth = false, this.compact = false});

  final MatchSummary match;
  final VoidCallback? onTap;
  final bool fullWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isLive = match.isLive;
    final c = isLive ? _CardColors.live : _CardColors.normal;
    final statusText = match.chaseSummaryLine ?? match.status;
    final isChase = match.chaseSummaryLine != null;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: Text(match.series.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: c.seriesText)),
        ),
        if (match.format != null)
          Container(
            margin: const EdgeInsets.only(left: Spacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
            decoration: BoxDecoration(color: c.formatBadgeBg, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Text(match.format!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: c.formatText)),
          ),
      ]),
    );

    Widget team(String name, String? logo, String? score) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: logo != null
                    ? NetImage(url: logo, size: 34, radius: 0, background: Colors.transparent, fallbackLetter: name)
                    : Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.placeholderBg, shape: BoxShape.circle),
                        child: Text(name.isEmpty ? '?' : name[0],
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.placeholderText)),
                      ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(name.isEmpty ? '-' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: c.teamText)),
              const SizedBox(height: Spacing.xs + 2),
              Text(score ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.scoreText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ]),
          ),
        );

    final scoreRow = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      team(match.team1, match.team1Logo, match.team1Score),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        child: Text('vs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.vsText)),
      ),
      team(match.team2, match.team2Logo, match.team2Score),
    ]);

    final footer = Container(
      margin: const EdgeInsets.only(top: Spacing.xl),
      padding: const EdgeInsets.only(top: Spacing.sm),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.footerBorder))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (isLive) ...[
          Container(
            key: const ValueKey('common_live_badge'),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: c.liveBadgeBg,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.liveBadgeBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              BlinkingDot(color: c.liveDot),
              const SizedBox(width: 5),
              Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.liveText)),
            ]),
          ),
          const SizedBox(width: Spacing.sm),
        ],
        if (statusText.isNotEmpty)
          Expanded(
            child: Text(
              statusText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isChase ? FontWeight.w700 : FontWeight.w600,
                color: isChase ? c.chaseColor : (isLive ? c.statusColor : c.resultColor),
              ),
            ),
          ),
      ]),
    );

    // Fixed card height (carousel): the score area flexes and scales down
    // instead of overflowing on large text scales. List (compact/fullWidth):
    // natural height with a floor.
    final fixedHeight = !fullWidth && !compact;
    final body = fixedHeight
        ? Column(children: [
            header,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: liveCardWidth - 34, child: scoreRow)),
              ),
            ),
            footer,
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            header,
            Padding(padding: const EdgeInsets.symmetric(vertical: Spacing.sm), child: scoreRow),
            footer,
          ]);

    return Semantics(
      button: true,
      label: '${match.team1} vs ${match.team2}${isLive ? ', live' : ''}',
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: fullWidth ? double.infinity : liveCardWidth,
          height: fixedHeight ? liveCardHeight : null,
          constraints: compact ? const BoxConstraints(minHeight: liveCardCompactHeight) : null,
          margin: fullWidth ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: liveCardMargin / 2),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.cardBorder),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: isLive ? 16 : 14, offset: const Offset(0, 6))],
          ),
          child: body,
        ),
      ),
    );
  }
}

/// 6px dot pulsing 1 → 0.35 opacity (RN blink loop). Uses a ticker, so it
/// stops automatically while its tab/route is offstage (TickerMode).
class BlinkingDot extends StatefulWidget {
  const BlinkingDot({super.key, required this.color, this.size = 6});
  final Color color;
  final double size;

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600), lowerBound: 0.35, upperBound: 1)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}
