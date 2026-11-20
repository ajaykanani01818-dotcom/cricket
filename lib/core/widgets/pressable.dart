import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/app_palette.dart';

/// Tap feedback for any custom tappable surface: scales to [pressScale]
/// (0.98) and lays a brandTint wash over the child while pressed. Works on
/// opaque children (the wash is a foreground decoration, unlike an InkWell
/// splash that paints under an opaque child). Reduced motion: no scale, the
/// wash stays.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
    this.pressScale = 0.98,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.showHighlight = true,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final double pressScale;
  final bool enabled;

  /// Shape of the pressed wash (match the child's corners).
  final BorderRadius borderRadius;
  final bool showHighlight;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    final motion = Motion.of(context);
    Widget child = widget.child;
    if (widget.showHighlight) {
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: _down ? context.palette.brandTint : const Color(0x00000000),
          borderRadius: widget.borderRadius,
        ),
        child: child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => _set(true) : null,
      onTapUp: active ? (_) => _set(false) : null,
      onTapCancel: active ? () => _set(false) : null,
      onTap: active ? widget.onTap : null,
      onLongPress: active ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _down && !motion.reduced ? widget.pressScale : 1,
        duration: motion.orZero(Motion.tap),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
