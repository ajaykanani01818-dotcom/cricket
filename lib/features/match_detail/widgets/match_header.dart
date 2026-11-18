import 'package:flutter/material.dart';

import '../../../core/api/json.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../logic/match_detail_logic.dart';

/// Ported from RN MatchHeader / the inline "Match Header — ESPN-style compact
/// horizontal layout" in MatchDetailScreen.tsx.
class MatchHeader extends StatelessWidget {
  const MatchHeader({
    super.key,
    required this.match,
    required this.team1Score,
    required this.team2Score,
    required this.battingTeam,
    required this.momLoading,
    required this.momInfo,
    this.onSeriesTap,
    this.onMomTap,
  });

  final MatchDetailVM match;
  final String team1Score, team2Score; // already formatted
  final TeamSide battingTeam;
  final bool momLoading;
  final JsonMap? momInfo;
  final VoidCallback? onSeriesTap;
  final VoidCallback? onMomTap;

  bool get _showRoles => match.isLive && !match.isMatchWon;

  /// Show only when finished + API key exists; while loading or after successful player fetch.
  bool get showPlayerOfMatchCard => match.momEligible && (momLoading || momInfo != null);

  Widget _teamRow(TeamVM team, String score, TeamSide side, bool first) {
    final batting = battingTeam == side;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(children: [
        team.logo != null
            ? NetImage(url: team.logo, size: 28, fallbackLetter: team.name, background: AppColors.borderSubtle)
            : Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: AppColors.borderSubtle, shape: BoxShape.circle),
                child: const Icon(Icons.shield_outlined, size: 16, color: AppColors.textMuted),
              ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
        ),
        if (_showRoles) ...[
          const SizedBox(width: 10),
          Container(
            key: ValueKey('match_detail_role_${side.name}'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: batting ? AppColors.pitch : AppColors.textMuted,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(batting ? 'BAT' : 'BOWL',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.white, letterSpacing: 0.5)),
          ),
        ],
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 60, maxWidth: 170),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              score,
              key: ValueKey('match_detail_score_${side.name}'),
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: batting && _showRoles ? AppColors.pitch : AppColors.text,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Series + Live badge
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 6),
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: match.seriesKey != null && onSeriesTap != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          key: const ValueKey('match_detail_series_link'),
                          onTap: onSeriesTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                child: Text(match.seriesName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.pitch)),
                              ),
                              const SizedBox(width: Spacing.xs),
                              const Icon(Icons.chevron_right, size: 14, color: AppColors.pitch),
                            ]),
                          ),
                        ),
                      )
                    : Text(match.seriesName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ),
            if (match.isLive)
              Container(
                key: const ValueKey('match_detail_live_badge'),
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
                decoration: BoxDecoration(color: AppColors.live, borderRadius: BorderRadius.circular(Radii.xs)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
                  const SizedBox(width: Spacing.xs),
                  const Text('LIVE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.white, letterSpacing: 0.5)),
                ]),
              ),
          ]),
        ),
        // Meta line
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xs),
          child: Text(match.metaLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ),
        if (match.toss != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
            child: Text(match.toss!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic)),
          ),
        // Team score rows
        Container(
          margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            _teamRow(match.t1, team1Score, TeamSide.team1, true),
            _teamRow(match.t2, team2Score, TeamSide.team2, false),
          ]),
        ),
        // Result
        if (match.isMatchWon && match.resultMessage != null)
          Container(
            key: const ValueKey('match_detail_result'),
            margin: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.md),
            decoration: BoxDecoration(
              color: const Color(0x1222C55E),
              borderRadius: BorderRadius.circular(6),
              border: const Border(left: BorderSide(color: AppColors.win, width: 3)),
            ),
            child: Text(match.resultMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.win)),
          ),
        if (showPlayerOfMatchCard) _momCard(),
      ]),
    );
  }

  Widget _momCard() {
    final info = momInfo;
    final enabled = !momLoading && info != null;
    final name = J.str(info?['name'], '-');
    final logo = J.text(info?['logo']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, 10, Spacing.lg, Spacing.sm),
      child: Material(
        color: const Color(0xA6FFFFFF),
        borderRadius: BorderRadius.circular(Radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('match_detail_mom_card'),
          onTap: enabled ? onMomTap : null,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: AppColors.gold),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.md, 10, 10, 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [
                          Icon(Icons.emoji_events, size: 14, color: AppColors.gold),
                          SizedBox(width: 5),
                          Text('PLAYER OF THE MATCH',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.goldDark, letterSpacing: 0.5)),
                        ]),
                        const SizedBox(height: 6),
                        if (momLoading)
                          const Row(children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pitch)),
                            SizedBox(width: Spacing.sm),
                            Text('Loading...',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ])
                        else if (info != null)
                          Row(children: [
                            logo != null
                                ? NetImage(url: logo, size: 36, fallbackLetter: name, background: AppColors.cardAlt)
                                : Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
                                    child: const Icon(Icons.person, size: 18, color: AppColors.pitch),
                                  ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Text(name,
                                  key: const ValueKey('match_detail_mom_name'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)),
                            ),
                          ]),
                      ]),
                    ),
                    if (enabled) const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
