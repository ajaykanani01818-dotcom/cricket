import 'package:flutter/material.dart';

/// Ported from RN `AnimatedPressable`: scales down slightly while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, this.onTap, required this.child, this.pressScale = 0.97, this.enabled = true});
  final VoidCallback? onTap;
  final Widget child;
  final double pressScale;
  final bool enabled;

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
    final active = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => _set(true) : null,
      onTapUp: active ? (_) => _set(false) : null,
      onTapCancel: active ? () => _set(false) : null,
      onTap: active ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? widget.pressScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
