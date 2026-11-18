import 'package:flutter/widgets.dart';

/// RN `snapToInterval` + `decelerationRate="fast"` for horizontal carousels
/// whose items are narrower than the viewport (PageView can't do that).
class SnapScrollPhysics extends ScrollPhysics {
  const SnapScrollPhysics({required this.itemExtent, super.parent});
  final double itemExtent;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) => SnapScrollPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  double _target(ScrollMetrics p, Tolerance t, double velocity) {
    var page = p.pixels / itemExtent;
    if (velocity < -t.velocity) {
      page -= 0.5;
    } else if (velocity > t.velocity) {
      page += 0.5;
    }
    return (page.roundToDouble() * itemExtent).clamp(p.minScrollExtent, p.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final t = toleranceFor(position);
    final target = _target(position, t, velocity);
    if ((target - position.pixels).abs() > t.distance) {
      return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: t);
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => false;
}
