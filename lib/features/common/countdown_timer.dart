import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'match_time.dart';

/// Rebuilds [builder] every minute via the shared [MinuteClock] (one timer
/// for every countdown on screen).
class MinuteBuilder extends StatefulWidget {
  const MinuteBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<MinuteBuilder> createState() => _MinuteBuilderState();
}

class _MinuteBuilderState extends State<MinuteBuilder> {
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
  Widget build(BuildContext context) =>
      widget.builder(context, MinuteClock.now());
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
    return MinuteBuilder(
      builder: (context, now) {
        final left = countdownWithin24h(target, now);
        if (left == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: context.palette.brandText,
              ),
              const SizedBox(width: Spacing.xs),
              Flexible(
                child: Text(
                  'Starts in $left',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    size: 12,
                    weight: FontWeight.w700,
                    color: context.palette.brandText,
                    tabularFigures: true,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// RN UpcomingMatchCard `StartsInBig`: big centered "Starts in / 2h 5m".
class StartsInBig extends StatelessWidget {
  const StartsInBig({super.key, required this.targetDate});
  final String targetDate;

  @override
  Widget build(BuildContext context) {
    final target = DateTime.tryParse(targetDate);
    if (target == null) return const SizedBox.shrink();
    return MinuteBuilder(
      builder: (context, now) {
        final label = startsInLabel(target, now);
        if (label == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(
            top: Spacing.xs * 2,
            bottom: Spacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Starts in', style: AppText.small),
              const SizedBox(height: 2),
              Text(
                label,
                key: const ValueKey('common_starts_in_value'),
                style: AppText.scoreCard.copyWith(color: context.palette.ink),
              ),
            ],
          ),
        );
      },
    );
  }
}
