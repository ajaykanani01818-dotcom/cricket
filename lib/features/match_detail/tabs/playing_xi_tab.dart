import 'package:flutter/material.dart';

import '../../../core/services/cricket_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/shimmer_box.dart';
import 'tab_common.dart';
import 'tab_playing_xi_parse.dart';

/// Ported from RN `MatchPlayingXITab`. Loads GET /match/:id/playing11 itself
/// and re-polls silently every 15s while [isLive].
class MatchPlayingXITab extends StatefulWidget {
  const MatchPlayingXITab({super.key, required this.matchId, required this.isLive});
  final String matchId;
  final bool isLive;

  @override
  State<MatchPlayingXITab> createState() => _MatchPlayingXITabState();
}

class _MatchPlayingXITabState extends State<MatchPlayingXITab> with LiveTabPolling {
  late Loadable<PlayingXIView> _state;
  PlayingXIView? _builtFor;
  Widget? _built;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final matchId = widget.matchId;
    late final Loadable<PlayingXIView> l;
    l = Loadable<PlayingXIView>(() async {
      final res = await MatchService.instance.getMatchPlayingXI(matchId);
      final next = parsePlayingXI(res.data);
      final prev = l.data;
      // Unchanged poll → keep the old instance so the built list is reused.
      return prev != null && prev == next ? prev : next;
    });
    _state = l;
    _builtFor = null;
    _built = null;
    l.load();
    configurePolling(widget.isLive, () => l.load(silent: true));
  }

  @override
  void didUpdateWidget(MatchPlayingXITab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchId != widget.matchId) {
      _state.dispose();
      _start();
    } else if (oldWidget.isLive != widget.isLive) {
      configurePolling(widget.isLive, () => _state.load(silent: true));
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final data = _state.data;
        if (data == null) {
          final err = _state.errorMessage;
          if (err != null && !_state.loading) {
            return ErrorRetry(key: const ValueKey('playing_xi_error'), message: err, onRetry: _state.load);
          }
          return const _PlayingXIShimmer();
        }
        if (!identical(data, _builtFor) || _built == null) {
          _builtFor = data;
          _built = data.hasMatch
              ? _PlayingXIBody(view: data)
              : const Padding(
                  key: ValueKey('playing_xi_empty'),
                  padding: EdgeInsets.all(40),
                  child: TabEmptyText('No Playing XI data available'),
                );
        }
        return _built ?? const SizedBox.shrink();
      },
    );
  }
}

class _PlayingXIBody extends StatelessWidget {
  const _PlayingXIBody({required this.view});
  final PlayingXIView view;

  @override
  Widget build(BuildContext context) => TabScrollBody(
        storageKey: 'match_playing_xi_tab',
        children: [
          _TeamCard(key: const ValueKey('playing_xi_team1'), team: view.team1),
          _TeamCard(key: const ValueKey('playing_xi_team2'), team: view.team2),
        ],
      );
}

const _teamCardDecoration = BoxDecoration(
  color: AppColors.card,
  borderRadius: BorderRadius.all(Radius.circular(8)),
  border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
);

const _teamHeaderDecoration =
    BoxDecoration(color: AppColors.tableHeaderBg, borderRadius: BorderRadius.all(Radius.circular(6)));

const _rowBorder = BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)));

class _TeamCard extends StatelessWidget {
  const _TeamCard({super.key, required this.team});
  final XiTeam team;

  @override
  Widget build(BuildContext context) {
    final logo = team.logo;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: _teamCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: _teamHeaderDecoration,
            child: Row(
              children: [
                if (logo != null) ...[
                  NetImage(url: logo, size: 28, radius: 0, background: Colors.transparent, fallbackLetter: team.name),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text('${team.name} Squad',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.tableHeaderText)),
                ),
              ],
            ),
          ),
          if (team.players.isEmpty)
            const TabEmptyText('No players available')
          else
            for (final p in team.players) _PlayerRow(key: ValueKey('playing_xi_player_${p.id}'), player: p),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.bg, required this.fg, this.border});
  final String text;
  final Color bg, fg;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: border == null ? null : Border.all(color: border ?? bg),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({super.key, required this.player});
  final XiPlayer player;

  @override
  Widget build(BuildContext context) {
    final avatar = player.avatar;
    final country = player.country;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: _rowBorder,
      child: Row(
        children: [
          // RN: person icon when the URL is missing (NetImage shows the
          // initial letter when the URL fails to load).
          avatar != null
              ? NetImage(url: avatar, size: 40, fit: BoxFit.cover, background: AppColors.borderSubtle, fallbackLetter: player.name)
              : Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.borderSubtle, shape: BoxShape.circle),
                  child: const Icon(Icons.person, size: 26, color: AppColors.textMuted, semanticLabel: 'Player'),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(player.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                      ),
                      if (player.isCaptain) ...[
                        const SizedBox(width: 8),
                        const _Badge(text: 'C', bg: AppColors.goldLight, fg: AppColors.goldDark, border: AppColors.gold),
                      ],
                      if (player.isWicketKeeper) ...[
                        const SizedBox(width: 8),
                        const _Badge(text: 'WK', bg: AppColors.silver, fg: AppColors.white),
                      ],
                    ],
                  ),
                ),
                Text(player.roleLabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (country != null) ...[
                  const SizedBox(height: 2),
                  Text(country, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shimmer (RN PlayingXIShimmerTeam ×2, 5 rows each) ───────────────────────

class _PlayingXIShimmer extends StatelessWidget {
  const _PlayingXIShimmer();

  @override
  Widget build(BuildContext context) => ShimmerGroup(
        key: const ValueKey('playing_xi_loading'),
        child: TabScrollBody(
          storageKey: 'match_playing_xi_tab_loading',
          children: [for (var t = 0; t < 2; t++) const _ShimmerTeam()],
        ),
      );
}

class _ShimmerTeam extends StatelessWidget {
  const _ShimmerTeam();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: _teamCardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: _teamHeaderDecoration,
              child: const Row(children: [
                ShimmerBox(width: 28, height: 28, radius: 6),
                SizedBox(width: 8),
                ShimmerBox(width: 140, height: 16, radius: 4),
              ]),
            ),
            for (var i = 0; i < 5; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: _rowBorder,
                child: const Row(
                  children: [
                    ShimmerBox(width: 40, height: 40, radius: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(widthFactor: 0.55, child: ShimmerBox(height: 14, radius: 4)),
                          SizedBox(height: 6),
                          FractionallySizedBox(widthFactor: 0.30, child: ShimmerBox(height: 11, radius: 4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
