import 'dart:async';

import 'package:flutter/material.dart';

/// Ported from RN `HeaderShimmerOverlay`: a subtle light band that sweeps
/// across a header surface once every [interval]. Place it in a [Stack] over
/// the header. Ignores pointers, pauses with [TickerMode] (covered routes /
/// inactive tabs) since it uses an AnimationController.
///
/// (In RN it is used by LegalPageLayout; ported here with the match-detail
/// header family so other features can import it.)
class HeaderShimmerOverlay extends StatefulWidget {
  const HeaderShimmerOverlay({
    super.key,
    this.interval = const Duration(milliseconds: 6000),
    this.duration = const Duration(milliseconds: 900),
    this.opacity = 0.38,
  });

  final Duration interval;
  final Duration duration;
  final double opacity;

  @override
  State<HeaderShimmerOverlay> createState() => _HeaderShimmerOverlayState();
}

class _HeaderShimmerOverlayState extends State<HeaderShimmerOverlay> with SingleTickerProviderStateMixin {
  static const _bandWidth = 140.0;
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _run();
    _timer = Timer.periodic(widget.interval, (_) => _run());
  }

  void _run() {
    if (!mounted) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
          return ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                if (_c.value == 0 || _c.value == 1) return const SizedBox.shrink();
                final dx = -_bandWidth + (width + _bandWidth * 2) * _c.value;
                return Stack(children: [
                  Positioned(top: 0, bottom: 0, left: dx, width: _bandWidth, child: child!),
                ]);
              },
              child: Opacity(
                opacity: widget.opacity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0x00000000), Color(0x0A000000), Color(0x00000000)]),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
