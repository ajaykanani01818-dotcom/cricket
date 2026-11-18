import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/net_image.dart';
import 'series_models.dart';

/// Ported from RN `SeriesResultsMatchCard` + `UpcomingMatchCard` in its
/// `embedded` + `seriesDetailLayout` mode (the only mode Series Detail uses):
/// match-no pill, status chip, venue, teams row, "Starts in" countdown,
/// void reason row, and the "View Scorecard" footer for finished matches.
class SeriesFixtureCard extends StatelessWidget {
  const SeriesFixtureCard({super.key, required this.fixture, required this.onOpen});
  final SeriesFixture fixture;
  final VoidCallback onOpen;

  static const _chip = {
    FixtureChipVariant.upcoming: (Color(0x1AF59E0B), Color(0x4DF59E0B), AppColors.gold),
    FixtureChipVariant.live: (Color(0x14EF3B3B), Color(0x40EF3B3B), AppColors.live),
    FixtureChipVariant.finished: (Color(0x1422C55E), Color(0x4022C55E), AppColors.win),
    FixtureChipVariant.cancelled: (Color(0x1A78716C), Color(0x4057534E), AppColors.voidText),
    FixtureChipVariant.abandoned: (Color(0x1478716C), Color(0x4078716C), AppColors.voidText),
  };

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final (chipBg, chipBorder, chipText) = _chip[f.chipVariant]!;
    final tappable = f.matchId.isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: '${f.team1} vs ${f.team2}${f.format != null ? ', ${f.format}' : ''}',
          child: InkWell(
            key: ValueKey('series_fixture_${f.listKey}'),
            onTap: tappable ? onOpen : null,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Meta header
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.neutralSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderNeutral, width: 0.5),
                        ),
                        child: Text('${f.matchNumber}${ordinalSuffix(f.matchNumber)} match',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: 0.2)),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(Radii.full),
                          border: Border.all(color: chipBorder),
                        ),
                        child: Text(f.chipLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: chipText, letterSpacing: 0.25)),
                      ),
                    ]),
                    if (f.venue.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: Spacing.xs),
                          Expanded(
                            child: Text(f.venue,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.1)),
                          ),
                        ]),
                      ),
                  ]),
                ),
                // Teams row
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: _Team(name: f.team1, logo: f.team1Logo)),
                    const SizedBox(width: Spacing.sm),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.neutralSurface,
                        borderRadius: BorderRadius.circular(Radii.full),
                        border: Border.all(color: AppColors.borderNeutral),
                      ),
                      alignment: Alignment.center,
                      child: const Text('VS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: _Team(name: f.team2, logo: f.team2Logo)),
                  ]),
                ),
                if (f.isUpcomingVariant && f.date.isAfter(DateTime.now())) _StartsIn(target: f.date),
                if (f.showVoidDetail)
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
                        child: Text(f.statusLine,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text, height: 17 / 12)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
        if (f.isCompleted)
          Container(
            padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.xs, Spacing.md, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSubtle, width: 0.5))),
            child: Row(children: [
              Expanded(
                child: Text(f.finishedMessage,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 16 / 12, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'View scorecard',
                child: InkWell(
                  key: ValueKey('series_fixture_scorecard_${f.listKey}'),
                  onTap: tappable ? onOpen : null,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: AppColors.pitch),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('View Scorecard',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.pitch, letterSpacing: 0.2)),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 14, color: AppColors.pitch),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({required this.name, this.logo});
  final String name;
  final String? logo;

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderNeutral),
            color: AppColors.surfaceSubtle,
          ),
          child: NetImage(url: logo, size: 42, fallbackLetter: name, fit: BoxFit.cover, background: AppColors.surfaceSubtle),
        ),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text)),
      ]);
}

/// RN `StartsInBig`: centered countdown, ticks every minute, hides when past.
class _StartsIn extends StatefulWidget {
  const _StartsIn({required this.target});
  final DateTime target;

  @override
  State<_StartsIn> createState() => _StartsInState();
}

class _StartsInState extends State<_StartsIn> {
  Timer? _timer;
  String? _label;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    final l = startsInLabel(widget.target, DateTime.now());
    if (l == null) _timer?.cancel();
    if (!mounted) return;
    if (l != _label) setState(() => _label = l);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = _label;
    if (l == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs * 2, bottom: Spacing.xs),
      child: Column(children: [
        Container(
          width: 32,
          height: 2,
          margin: const EdgeInsets.only(bottom: Spacing.md),
          decoration: BoxDecoration(color: AppColors.pitch, borderRadius: BorderRadius.circular(1)),
        ),
        const Text('STARTS IN',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Text(l,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.pitch,
              letterSpacing: -0.4,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
      ]),
    );
  }
}
