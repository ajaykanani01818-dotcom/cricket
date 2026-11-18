import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'match_time.dart';

/// Rebuilds [builder] every minute via the shared [MinuteClock].
class _MinuteBuilder extends StatefulWidget {
  const _MinuteBuilder({required this.builder});
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<_MinuteBuilder> createState() => _MinuteBuilderState();
}

class _MinuteBuilderState extends State<_MinuteBuilder> {
  @override
  void initState() {
    super.initState();
    MinuteClock.instance.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MinuteClock.instance.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, MinuteClock.now());
}

/// Ported from RN `CountdownTimer`: "Starts in Xh Xm" for matches within 24h.
/// Renders nothing when the match is further away or already started.
class CountdownTimer extends StatelessWidget {
  const CountdownTimer({super.key, required this.targetDate});

  /// ISO start date.
  final String targetDate;

  @override
  Widget build(BuildContext context) {
    final target = DateTime.tryParse(targetDate);
    if (target == null) return const SizedBox.shrink();
    return _MinuteBuilder(builder: (context, now) {
      final left = countdownWithin24h(target, now);
      if (left == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.timer_outlined, size: 12, color: AppColors.pitch),
          const SizedBox(width: Spacing.xs),
          Text('Starts in $left',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.pitch, letterSpacing: 0.3)),
        ]),
      );
    });
  }
}

/// RN UpcomingMatchCard `StartsInBig`: big centered "STARTS IN / 2h 5m".
class StartsInBig extends StatelessWidget {
  const StartsInBig({super.key, required this.targetDate});
  final String targetDate;

  @override
  Widget build(BuildContext context) {
    final target = DateTime.tryParse(targetDate);
    if (target == null) return const SizedBox.shrink();
    return _MinuteBuilder(builder: (context, now) {
      final label = startsInLabel(target, now);
      if (label == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Spacing.xs * 2, bottom: Spacing.xs),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 32,
            height: 2,
            margin: const EdgeInsets.only(bottom: Spacing.md),
            decoration: BoxDecoration(color: AppColors.pitch, borderRadius: BorderRadius.circular(1)),
          ),
          const Text('STARTS IN',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Text(label,
              key: const ValueKey('common_starts_in_value'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.pitch,
                letterSpacing: -0.4,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
        ]),
      );
    });
  }
}
