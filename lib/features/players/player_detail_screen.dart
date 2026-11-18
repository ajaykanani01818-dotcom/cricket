import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/json.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/tabs.dart';
import '../ads/ads.dart';
import 'player_models.dart';
import 'widgets/gradient_card.dart';
import 'widgets/player_widgets.dart';

/// Ported from RN `src/screens/PlayerDetailScreen.tsx`.
///
/// [initialPlayer] is the list item the user tapped (country list / ranking
/// row). It renders the hero (and personal details) immediately while
/// /players/:key/info loads, and stays on screen when the profile does not
/// exist yet (API 404 "Player not found!!") instead of an error.
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key, required this.playerKey, this.initialPlayer});
  final String playerKey;
  final JsonMap? initialPlayer;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  static const heroHeight = 280.0;

  PlayerProfile? _initial;

  /// Ranking rows only carry name/logo; country-list items also carry
  /// dob/role/styles and can fill the Personal card before info arrives.
  bool _initialHasPersonal = false;
  PlayerProfile? _info;
  bool _loading = false;
  Object? _error;
  String _rankFormat = 'test';
  int _gen = 0;
  final _scroll = ScrollController();

  String get _key => widget.playerKey.trim().isNotEmpty ? widget.playerKey.trim() : (_initial?.playerKey ?? '');

  @override
  void initState() {
    super.initState();
    _parseInitial();
    if (_key.isNotEmpty) _fetch();
  }

  void _parseInitial() {
    final ip = widget.initialPlayer;
    _initial = ip == null || ip.isEmpty ? null : PlayerProfile.fromJson(ip, withDetails: false);
    _initialHasPersonal = ip != null && (ip['role'] != null || ip['dob'] != null || ip['battingStyle'] != null);
  }

  @override
  void didUpdateWidget(PlayerDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.playerKey != widget.playerKey) {
      _parseInitial();
      _info = null;
      if (_key.isNotEmpty) _fetch();
    }
  }

  @override
  void dispose() {
    // RN useRecordDetailExit.
    AdsManager.instance.recordDetailExit();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await PlayerService.instance.getPlayerInfo(_key);
      if (!mounted || gen != _gen) return;
      final data = res.dataMap;
      setState(() {
        if (data.isEmpty) {
          _info = null;
          _error = const ApiException(404, 'Player not found');
        } else {
          _info = PlayerProfile.fromJson(data);
        }
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _info = null;
      });
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  bool get _notFound => _error is ApiException && (_error as ApiException).isNotFound;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          const ScreenBannerSlots(screen: 'player_detail', onlyPosition: 'top'),
          Expanded(child: _body()),
          const FixedBottomBanner(screen: 'player_detail'),
        ]),
      ),
    );
  }

  Widget _body() {
    final p = _info ?? _initial;
    if (_key.isEmpty && p == null) {
      return const Center(
        child: EmptyState(key: ValueKey('player_detail_not_found'), icon: Icons.person_off_outlined, title: 'Player not found'),
      );
    }

    // Nothing to show in the header yet → RN full-page shimmer.
    if (p == null) {
      if (_loading || (_error == null && _info == null)) {
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomReserve(context)),
          child: const PlayerDetailShimmer(),
        );
      }
      return Center(
        child: SingleChildScrollView(
          child: _notFound
              ? const EmptyState(
                  key: ValueKey('player_detail_not_found'),
                  icon: Icons.person_off_outlined,
                  title: 'Player not found',
                  subtitle: "This player's profile isn't available yet.",
                )
              : ErrorRetry(key: const ValueKey('player_detail_error'), message: friendlyError(_error!), onRetry: _fetch),
        ),
      );
    }

    final showPersonal = _info != null || _initialHasPersonal;
    final sections = <Widget>[
      if (showPersonal) ...[
        const DetailSectionLabel('Personal'),
        _wrap(StatCard(rows: [
          StatLine('Born', p.bornText),
          StatLine('Age', p.ageText),
          StatLine('Batting', p.battingText),
          StatLine('Bowling', p.bowlingText),
          StatLine('Role', p.roleText),
        ])),
      ],
    ];

    if (_info == null) {
      if (_loading || _error == null) {
        sections.add(PlayerDetailShimmer(showHero: false, showPersonal: !showPersonal));
      } else {
        sections.add(_statusCard());
      }
    } else {
      sections.addAll(_infoSections(_info!));
    }

    return Stack(children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: heroHeight,
        child: IgnorePointer(child: _ParallaxHero(controller: _scroll, height: heroHeight, player: p)),
      ),
      ListView(
        key: const ValueKey('player_detail_scroll'),
        controller: _scroll,
        padding: EdgeInsets.only(bottom: bottomReserve(context, 24)),
        children: [
          const SizedBox(height: heroHeight),
          ...sections,
          const SizedBox(height: 32),
        ],
      ),
    ]);
  }

  Widget _wrap(Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xs),
        child: child,
      );

  /// Shown under the header when the info request failed.
  Widget _statusCard() {
    final notFound = _notFound;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, 26, Spacing.lg, 0),
      child: GradientCard(
        key: ValueKey(notFound ? 'player_detail_not_found' : 'player_detail_error'),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: Spacing.xxl),
        child: Column(children: [
          Icon(notFound ? Icons.person_search_outlined : Icons.cloud_off_outlined, size: 28, color: AppColors.textMuted),
          const SizedBox(height: Spacing.md),
          Text(
            notFound ? 'Detailed profile not available yet' : friendlyError(_error!),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: notFound ? FontWeight.w700 : FontWeight.w400,
              color: notFound ? AppColors.text : AppColors.error,
            ),
          ),
          if (notFound) ...[
            const SizedBox(height: Spacing.xs),
            const Text('Stats, rankings and bio for this player will appear here once available.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
          ] else ...[
            const SizedBox(height: 14),
            TryAgainButton(key: const ValueKey('player_detail_retry'), onPressed: _fetch),
          ],
        ]),
      ),
    );
  }

  List<Widget> _infoSections(PlayerProfile info) {
    final ranks = info.ranks;
    return [
      if (ranks != null) ...[
        const DetailSectionLabel('ICC Rankings'),
        _wrap(Column(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: SegmentedControl<String>(
              key: const ValueKey('player_detail_rank_format'),
              compact: true,
              options: const [SegmentOption('test', 'Test'), SegmentOption('odi', 'ODI'), SegmentOption('t20', 'T20')],
              value: _rankFormat,
              onChanged: (v) => setState(() => _rankFormat = v),
            ),
          ),
          StatCard(rows: [
            StatLine('Batting', ranks.rank('batting', _rankFormat)),
            StatLine('Bowling', ranks.rank('bowling', _rankFormat)),
            StatLine('All-rounder', ranks.rank('all', _rankFormat)),
          ]),
        ])),
      ],
      const Padding(
        padding: EdgeInsets.fromLTRB(Spacing.lg, 18, Spacing.lg, 0),
        child: ListNativeAd(placement: 'player_detail_feed'),
      ),
      if (info.batting.isNotEmpty) ...[
        const DetailSectionLabel('Batting Stats'),
        for (final b in info.batting) _formatBlock(b),
      ],
      if (info.bowling.isNotEmpty) ...[
        const DetailSectionLabel('Bowling Stats'),
        for (final b in info.bowling) _formatBlock(b),
      ],
      if (info.teams.isNotEmpty) ...[
        const DetailSectionLabel('Teams'),
        _wrap(TeamsCard(teams: info.teams)),
      ],
      if (info.description.isNotEmpty) ...[
        const DetailSectionLabel('About'),
        _wrap(GradientCard(
          padding: const EdgeInsets.symmetric(vertical: Spacing.lg, horizontal: 18),
          child: SizedBox(
            width: double.infinity,
            child: Text(info.description,
                style: const TextStyle(fontSize: 13, color: AppColors.graphite, height: 20 / 13, letterSpacing: 0.1)),
          ),
        )),
      ],
    ];
  }

  Widget _formatBlock(FormatStats f) => _wrap(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.xs, 0, Spacing.xs, Spacing.sm),
          child: Text(f.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.graphite, letterSpacing: 0.5)),
        ),
        StatCard(rows: f.rows),
      ]));
}

/// Hero that fades / scales / drifts up as the content scrolls over it
/// (RN Animated parallax). Only this widget rebuilds on scroll.
class _ParallaxHero extends StatelessWidget {
  const _ParallaxHero({required this.controller, required this.height, required this.player});
  final ScrollController controller;
  final double height;
  final PlayerProfile player;

  @override
  Widget build(BuildContext context) {
    final hero = ColoredBox(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.xxxl, Spacing.xxl, Spacing.xxxl, Spacing.lg),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Container(
            width: 128,
            height: 128,
            margin: const EdgeInsets.only(bottom: Spacing.lg),
            padding: const EdgeInsets.all(Spacing.xs),
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: NetImage(url: player.logo, size: 118, fallbackLetter: player.initial, fit: BoxFit.cover, background: AppColors.cardAlt),
          ),
          Text(player.name,
              key: const ValueKey('player_detail_name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.text, letterSpacing: -0.6, height: 1.15)),
          const SizedBox(height: Spacing.xs),
          Text(player.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.2)),
          const SizedBox(height: 10),
          Container(width: 24, height: 2, decoration: BoxDecoration(color: AppColors.pitch, borderRadius: BorderRadius.circular(1))),
        ]),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      child: hero,
      builder: (context, child) {
        final y = controller.hasClients && controller.positions.length == 1 ? controller.offset : 0.0;
        final opacity = y <= 0
            ? 1.0
            : y < height * 0.5
                ? 1 - 0.45 * (y / (height * 0.5))
                : (0.55 * (1 - ((y - height * 0.5) / (height * 0.35)))).clamp(0.0, 0.55);
        final scale = y < 0 ? (1 + 0.15 * (-y / height)).clamp(1.0, 1.15) : (1 - 0.12 * (y / height)).clamp(0.88, 1.0);
        final dy = -(y.clamp(0.0, height)) * 0.4;
        if (opacity <= 0) return const SizedBox.shrink();
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(0, dy), child: Transform.scale(scale: scale, child: child)),
        );
      },
    );
  }
}
