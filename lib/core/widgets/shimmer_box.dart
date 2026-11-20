import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Skeleton group. Previously a shader shimmer; now static surfaceAlt blocks
/// (the perf budget forbids saveLayer/shader effects, and a skeleton that
/// mirrors the real layout is what makes loading feel fast). The name and
/// constructor are kept for existing screens. Marks its subtree as a single
/// "Loading" semantics node.
class ShimmerGroup extends StatelessWidget {
  const ShimmerGroup({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(label: 'Loading', excludeSemantics: true, child: child);
}

/// One skeleton block (surfaceAlt, radius [radius]).
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
    this.margin,
  });
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    margin: margin,
    decoration: BoxDecoration(
      color: context.palette.surfaceAlt,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
