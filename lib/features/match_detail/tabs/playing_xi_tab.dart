import 'package:flutter/material.dart';

import '../../../core/services/cricket_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../widgets/md_ui.dart';
import 'tab_common.dart';
import 'tab_playing_xi_parse.dart';

/// Playing XI + bench (Info tab). Loads /match/:id/playing11 and
/// /match/:id/squad (the squad adds the bench and wicketkeeper flags; its
/// failure is tolerated) and re-polls slowly while live. Captain and
/// wicketkeeper are text tags. Teams sit side by side on wide screens.
class MatchPlayingXITab extends StatefulWidget {
  const MatchPlayingXITab({super.key, required this.matchId, required this.isLive, this.service, this.onPlayerTap});
  final String matchId;
  final bool isLive;
  final MatchService? service;
  final void Function(String playerKey)? onPlayerTap;

  @override
  State<MatchPlayingXITab> createState() => _MatchPlayingXITabState();
}

class _Lineups {
  const _Lineups(this.xi, this.squad);
  final PlayingXIView xi;
  final SquadView squad;
  String get signature => '${xi.signature}#${squad.signature}';
}

class _MatchPlayingXITabState extends State<MatchPlayingXITab> with LiveTabPolling {
  late Loadable<_Lineups> _state;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final matchId = widget.matchId;
    final service = widget.service ?? MatchService.instance;
    late final Loadable<_Lineups> l;
    l = Loadable<_Lineups>(() async {
      final squadF = service.getMatchSquad(matchId).then((r) => parseSquad(r.data)).catchError((Object _) => SquadView.empty);
      final xi = parsePlayingXI((await service.getMatchPlayingXI(matchId)).data);
      final next = _Lineups(xi, await squadF);
      final prev = l.data;
      return prev != null && prev.signature == next.signature ? prev : next;
    });
    _state = l;
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
            return ErrorRetry(key: const ValueKey('playing_xi_error'), title: "Line-ups didn't load", message: err, onRetry: _state.load);
          }
          return const _LineupSkeleton();
        }
        if (!data.xi.hasMatch) {
          return const MdNote(
            key: ValueKey('playing_xi_empty'),
            'Playing XI not announced yet. It appears here once the provider sends the team sheets.',
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
          );
        }
        return _LineupBody(data: data, onPlayerTap: widget.onPlayerTap);
      },
    );
  }
}

class _LineupBody extends StatelessWidget {
  const _LineupBody({required this.data, this.onPlayerTap});
  final _Lineups data;
  final void Function(String key)? onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final t1 = _TeamList(key: const ValueKey('playing_xi_team1'), team: data.xi.team1, bench: data.squad.bench1, keepers: data.squad.keepers, onPlayerTap: onPlayerTap);
    final t2 = _TeamList(key: const ValueKey('playing_xi_team2'), team: data.xi.team2, bench: data.squad.bench2, keepers: data.squad.keepers, onPlayerTap: onPlayerTap);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 600) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: t1),
          const SizedBox(width: Spacing.xl),
          Expanded(child: t2),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [t1, const SizedBox(height: Spacing.lg), t2]);
    });
  }
}

class _TeamList extends StatelessWidget {
  const _TeamList({super.key, required this.team, required this.bench, required this.keepers, this.onPlayerTap});
  final XiTeam team;
  final List<XiPlayer> bench;
  final Set<String> keepers;
  final void Function(String key)? onPlayerTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Row(children: [
          TeamLogo(url: team.logo, name: team.name, size: 24),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text(team.name, style: AppFont.style(size: 15, weight: FontWeight.w700, color: p.ink))),
        ]),
      ),
      if (team.players.isEmpty)
        const MdNote('No players listed.', padding: EdgeInsets.zero)
      else
        for (final pl in team.players) _PlayerRow(key: ValueKey('playing_xi_player_${pl.id}'), player: pl, keepers: keepers, onTap: onPlayerTap),
      if (bench.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.xs),
          child: Text('Bench', style: AppFont.style(size: 13, weight: FontWeight.w700, color: p.inkMuted)),
        ),
        for (final pl in bench) _PlayerRow(key: ValueKey('playing_xi_bench_${pl.id}'), player: pl, keepers: keepers, onTap: onPlayerTap),
      ],
    ]);
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({super.key, required this.player, required this.keepers, this.onTap});
  final XiPlayer player;
  final Set<String> keepers;
  final void Function(String key)? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wk = player.isWicketKeeper || keepers.contains(player.id);
    final synthetic = RegExp(r'^(playingXI|bench|substitutes)_Team\d-\d+$').hasMatch(player.id);
    final tappable = onTap != null && !synthetic;
    final child = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs + 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(children: [
        NetImage(url: player.avatar, size: 32, fallbackLetter: player.name, background: p.surfaceAlt),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: Spacing.xs + 2, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(player.name, style: AppFont.style(size: 14, weight: FontWeight.w600, color: p.ink, height: 1.3)),
              if (player.isCaptain) const MdTag('C'),
              if (wk) const MdTag('WK'),
            ]),
            Text(player.roleLabel, style: AppText.small.copyWith(color: p.inkMuted)),
          ]),
        ),
        if (tappable) Icon(Icons.chevron_right, size: 18, color: p.inkMuted),
      ]),
    );
    final label = '${player.name}${player.isCaptain ? ', captain' : ''}${wk ? ', wicketkeeper' : ''}, ${player.roleLabel}';
    return Semantics(
      label: label,
      button: tappable,
      excludeSemantics: true,
      child: tappable ? InkWell(onTap: () => onTap!(player.id), child: child) : child,
    );
  }
}

class _LineupSkeleton extends StatelessWidget {
  const _LineupSkeleton();

  @override
  Widget build(BuildContext context) => ShimmerGroup(
        key: const ValueKey('playing_xi_loading'),
        child: Column(children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.xs + 2),
              child: Row(children: [
                ShimmerBox(width: 32, height: 32, radius: 16),
                SizedBox(width: Spacing.md),
                Expanded(child: ShimmerBox(height: 14, radius: 4)),
              ]),
            ),
        ]),
      );
}
