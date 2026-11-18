import 'package:flutter/material.dart';

import 'rating_modal.dart';
import 'review_controller.dart';

/// RN `ReviewProvider`: owns the [ReviewController], records one session per
/// launch, exposes it via [ReviewScope] and renders the rating modal above
/// [child]. Android back closes the modal first (RN ExitBackHandler).
///
/// Designed to sit in `MaterialApp.router(builder: ...)` (above the Navigator),
/// so the modal is drawn in a Stack rather than via showDialog.
class ReviewHost extends StatefulWidget {
  const ReviewHost({super.key, required this.child, this.controller});
  final Widget child;

  /// Injected in tests; otherwise created and disposed here.
  final ReviewController? controller;

  @override
  State<ReviewHost> createState() => _ReviewHostState();
}

class _ReviewHostState extends State<ReviewHost> with WidgetsBindingObserver {
  late final ReviewController _c = widget.controller ?? ReviewController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.recordSessionOnce();
  }

  @override
  Future<bool> didPopRoute() async {
    // Dismiss rating modal first — same as RN Modal onRequestClose.
    if (_c.ratingModalVisible) {
      _c.closeRatingModal();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReviewScope(
      controller: _c,
      child: ListenableBuilder(
        listenable: _c,
        child: widget.child,
        builder: (context, child) => Stack(fit: StackFit.expand, children: [
          child!,
          if (_c.ratingModalVisible)
            Positioned.fill(
              child: RatingModal(
                onClose: _c.closeRatingModal,
                onOpenStore: _c.openStoreListing,
                showExitAppButton: _c.openedFromExit,
                onExitApp: _c.exitApp,
              ),
            ),
        ]),
      ),
    );
  }
}
