import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// Ported from RN `Shimmer`. Wrap a group of [ShimmerBox]es in one
/// [ShimmerGroup] so they animate with a single shader (cheaper than one
/// animation per box).
class ShimmerGroup extends StatelessWidget {
  const ShimmerGroup({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: AppColors.cardAlt,
        highlightColor: AppColors.white,
        period: const Duration(milliseconds: 1200),
        child: child,
      );
}

class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.width, required this.height, this.radius = 8, this.margin});
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(radius)),
      );
}
