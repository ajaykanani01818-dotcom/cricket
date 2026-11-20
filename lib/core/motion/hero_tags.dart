/// Shared-element tags for the one orchestrated moment: match card → Match
/// Centre header (research §9.1). A card wraps its team logos and score in
/// `Hero(tag: MatchHeroTags.x(matchId))`; the Match Centre header uses the
/// same tags, so the logos and score digits travel on push (320 ms,
/// [Motion.emphasized]) and back (250 ms).
///
/// Rules: a tag must be unique per route, so a screen that shows the same
/// match twice (e.g. Live rail + results list) passes `heroTags: false` on
/// the second card. Hero flights use [matchHeroFlight] so text keeps its
/// style mid-flight; with reduced motion the flight is skipped (fade).
library;

import 'package:flutter/widgets.dart';

import 'motion.dart';

class MatchHeroTags {
  MatchHeroTags._();
  static String team1Logo(String matchId) => 'match:$matchId:t1logo';
  static String team2Logo(String matchId) => 'match:$matchId:t2logo';
  static String team1Score(String matchId) => 'match:$matchId:t1score';
  static String team2Score(String matchId) => 'match:$matchId:t2score';
}

/// Hero that respects reduced motion and keeps text rendering correct in
/// flight (wraps the flying child in a DefaultTextStyle-less placeholder).
class MatchHero extends StatelessWidget {
  const MatchHero({
    super.key,
    required this.tag,
    required this.child,
    this.enabled = true,
  });
  final String tag;
  final Widget child;

  /// False for the second appearance of the same match on one screen.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || Motion.reducedOf(context)) return child;
    return Hero(
      tag: tag,
      flightShuttleBuilder: matchHeroFlight,
      transitionOnUserGestures: true,
      child: child,
    );
  }
}

/// Flight shuttle: shows the destination widget (so the score lands in the
/// header's size) without the yellow-underline text glitch.
Widget matchHeroFlight(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final hero =
      (direction == HeroFlightDirection.push
              ? toContext.widget
              : fromContext.widget)
          as Hero;
  return DefaultTextStyle(
    style: DefaultTextStyle.of(toContext).style,
    child: FittedBox(fit: BoxFit.contain, child: hero.child),
  );
}
