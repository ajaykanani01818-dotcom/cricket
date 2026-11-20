import 'package:flutter/material.dart';

import 'review_controller.dart';

/// Owns the [ReviewController], records one session per launch and exposes it
/// via [ReviewScope]. Draws no rating UI of its own (the system review sheet
/// is requested by the controller); it only shows the "Press back again to
/// exit" hint when the controller asks for it.
///
/// Sits in `MaterialApp.router(builder: ...)`, below the app's
/// ScaffoldMessenger.
class ReviewHost extends StatefulWidget {
  const ReviewHost({super.key, required this.child, this.controller});
  final Widget child;

  /// Injected in tests; otherwise created and disposed here.
  final ReviewController? controller;

  @override
  State<ReviewHost> createState() => _ReviewHostState();
}

class _ReviewHostState extends State<ReviewHost> {
  late final ReviewController _c = widget.controller ?? ReviewController();
  int _hintTick = 0;

  @override
  void initState() {
    super.initState();
    _hintTick = _c.exitHintTick;
    _c.recordSessionOnce();
    _c.addListener(_onChange);
  }

  void _onChange() {
    if (_c.exitHintTick == _hintTick) return;
    _hintTick = _c.exitHintTick;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: ValueKey('exit_hint'),
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ReviewScope(controller: _c, child: widget.child);
}
