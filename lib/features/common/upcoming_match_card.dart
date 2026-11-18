import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/fixture_status.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/net_image.dart';
import 'countdown_timer.dart';
import 'match_time.dart';

enum UpcomingCardVariant { upcoming, completed, cancelled }

enum SeriesStatusChipVariant { upcoming, live, finished, cancelled, abandoned }

class SeriesStatusChip {
  const SeriesStatusChip(this.label, this.variant);
  final String label;
  final SeriesStatusChipVariant variant;
}

String ordinalSuffix(int n) {
  final j = n % 10, k = n % 100;
  if (j == 1 && k != 11) return 'st';
  if (j == 2 && k != 12) return 'nd';
  if (j == 3 && k != 13) return 'rd';
  return 'th';
}

/// RN `isMatchLive` (UpcomingMatchCard).
bool isMatchLiveForCard(MatchSummary m, {bool completed = false, bool cancelled = false}) {
  if (completed || cancelled) return false;
  final k = m.fixtureCardKind;
  if (k == FixtureCardKind.cancelled || k == FixtureCardKind.abandoned) return false;
  if (m.isLive) return true;
  final u = m.status.toUpperCase();
  return u == 'LIVE' || u == 'IN_PROGRESS' || u.contains('LIVE');
}

/// RN `hasResult` for the completed variant.
bool hasDisplayableResult(MatchSummary m) {
  final s = m.status;
  return s.isNotEmpty && (s.contains('won') || s.contains('beat') || s.length > 2);
}

const _chipStyles = {
  SeriesStatusChipVariant.upcoming: (Color(0x1AF59E0B), Color(0x4DF59E0B), AppColors.gold),
  SeriesStatusChipVariant.live: (Color(0x14EF3B3B), Color(0x40EF3B3B), AppColors.live),
  SeriesStatusChipVariant.finished: (Color(0x1422C55E), Color(0x4022C55E), AppColors.win),
  SeriesStatusChipVariant.cancelled: (Color(0x1A78716C), Color(0x4057534E), AppColors.voidText),
  SeriesStatusChipVariant.abandoned: (Color(0x1478716C), Color(0x4078716C), AppColors.voidText),
};

/// Ported from RN `UpcomingMatchCard`: fixture card with meta pills, teams,
/// "Starts in" countdown (upcoming) or result row (completed). The
/// series-detail props are kept so the Series feature can reuse it.
class UpcomingMatchCard extends StatelessWidget {
  const UpcomingMatchCard({
    super.key,
    required this.match,
    this.onTap,
    this.variant = UpcomingCardVariant.upcoming,
    this.embedded = false,
    this.listMatchNumber,
    this.seriesDetailLayout = false,
    this.seriesDetailStatusChip,
    this.seriesDetailExternalResultFooter = false,
    this.matchesListFrame = false,
  });

  final MatchSummary match;
  final VoidCallback? onTap;
  final UpcomingCardVariant variant;
  final bool embedded;
  final int? listMatchNumber;
  final bool seriesDetailLayout;
  final SeriesStatusChip? seriesDetailStatusChip;
  final bool seriesDetailExternalResultFooter;
  final bool matchesListFrame;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final isCompleted = variant == UpcomingCardVariant.completed;
    final isCancelled = variant == UpcomingCardVariant.cancelled;
    final hasResult = isCompleted && hasDisplayableResult(m);
    final hideResultDup = isCompleted && seriesDetailLayout && seriesDetailExternalResultFooter;
    final statusFromChip = seriesDetailLayout && seriesDetailStatusChip != null;
    final showMatchNo = seriesDetailLayout && (listMatchNumber ?? 0) > 0;
    final showFormat = !seriesDetailLayout && m.format != null;
    final showSeries = !seriesDetailLayout && m.series.isNotEmpty;
    final showResultPill = hasResult && !hideResultDup && !statusFromChip;
    final showVoidPill = isCancelled && !statusFromChip;
    final showLivePill = !statusFromChip && isMatchLiveForCard(m, completed: isCompleted, cancelled: isCancelled);
    final voidLabel = m.fixtureCardKind == FixtureCardKind.abandoned ? 'Abandoned' : 'Cancelled';
    const voidShort = {'Cancelled', 'Abandoned', 'cancelled', 'abandoned'};
    final st = m.status.trim();
    final showVoidDetail = isCancelled && st.isNotEmpty && !voidShort.contains(st);
    final venue = m.venue.trim();

    final pills = <Widget>[
      if (showMatchNo)
        _pill(
          bg: AppColors.neutralSurface,
          border: AppColors.borderNeutral,
          radius: 6,
          child: Text('$listMatchNumber${ordinalSuffix(listMatchNumber!)} match',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: 0.2)),
        ),
      if (seriesDetailStatusChip != null)
        _pill(
          bg: _chipStyles[seriesDetailStatusChip!.variant]!.$1,
          border: _chipStyles[seriesDetailStatusChip!.variant]!.$2,
          child: Text(seriesDetailStatusChip!.label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.25, color: _chipStyles[seriesDetailStatusChip!.variant]!.$3)),
        ),
      if (showFormat)
        _pill(
          bg: AppColors.neutralSurface,
          child: Text(m.format!.toUpperCase(),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.3)),
        ),
      if (showLivePill)
        _pill(
          key: const ValueKey('common_upcoming_live_pill'),
          bg: const Color(0x14EF3B3B),
          border: const Color(0x33EF3B3B),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.live, letterSpacing: 0.75)),
          ]),
        ),
      if (showVoidPill)
        _pill(
          bg: const Color(0x1478716C),
          border: const Color(0x3378716C),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.block, size: 12, color: AppColors.voidText),
            const SizedBox(width: Spacing.xs),
            Text(voidLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.voidText, letterSpacing: 0.4)),
          ]),
        ),
      if (showResultPill)
        _pill(
          key: const ValueKey('common_result_pill'),
          bg: const Color(0x1422C55E),
          border: const Color(0x3322C55E),
          horizontal: 6,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 12, color: AppColors.win),
            SizedBox(width: Spacing.xs),
            Text('Result', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.win, letterSpacing: 0.3)),
          ]),
        ),
    ];

    final hasMeta = pills.isNotEmpty || showSeries || venue.isNotEmpty;
    final time = DateTime.tryParse(m.date);
    final timeInfo = time == null ? null : formatMatchTime(time, MinuteClock.now());

    Widget team(String name, String? logo) => Expanded(
          child: Column(children: [
            Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderNeutral),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: logo != null
                  ? NetImage(url: logo, size: 42, fit: BoxFit.cover, fallbackLetter: name, background: AppColors.surfaceSubtle)
                  : Text(name.isEmpty ? '?' : name[0],
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
            ),
            Text(name.isEmpty ? '-' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text)),
          ]),
        );

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (hasMeta)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (final p in pills) ...[p, const SizedBox(width: Spacing.sm)],
              if (showSeries)
                Flexible(
                  child: Text(m.series.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.3)),
                ),
            ]),
            if (venue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(venue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.1)),
                  ),
                ]),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          team(m.team1, m.team1Logo),
          const SizedBox(width: Spacing.sm),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.neutralSurface,
              borderRadius: BorderRadius.circular(Radii.full),
              border: Border.all(color: AppColors.borderNeutral),
            ),
            child: const Text('VS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          ),
          const SizedBox(width: Spacing.sm),
          team(m.team2, m.team2Logo),
        ]),
      ),
      if (variant == UpcomingCardVariant.upcoming && m.date.isNotEmpty) StartsInBig(targetDate: m.date),
      if (hasResult && !hideResultDup)
        Container(
          key: const ValueKey('common_result_row'),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x0F22C55E),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: const Color(0x2622C55E)),
          ),
          child: Row(children: [
            const Icon(Icons.emoji_events_outlined, size: 12, color: AppColors.win),
            const SizedBox(width: 6),
            Expanded(
              child: Text(m.status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
          ]),
        ),
      if (showVoidDetail)
        Container(
          margin: const EdgeInsets.only(bottom: Spacing.xs),
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: const Color(0x0F78716C),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: const Color(0x2678716C)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, size: 12, color: AppColors.voidText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(st,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.4)),
            ),
          ]),
        ),
    ]);

    final radius = embedded ? 10.0 : Radii.lg;
    return Semantics(
      button: true,
      label: '${m.team1} vs ${m.team2}${m.format != null ? ', ${m.format}' : ''}'
          '${timeInfo != null ? ', ${timeInfo.dayLabel} ${timeInfo.time}' : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(radius),
          border: embedded ? null : Border.all(color: AppColors.borderStrong),
          boxShadow: embedded ? null : const [BoxShadow(color: Color(0x1F000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Padding(padding: EdgeInsets.all(embedded ? Spacing.sm : Spacing.lg), child: content),
          ),
        ),
      ),
    );
  }

  static Widget _pill({Key? key, required Color bg, Color? border, double radius = Radii.full, double horizontal = Spacing.sm, required Widget child}) =>
      Container(
        key: key,
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border),
        ),
        child: child,
      );
}
