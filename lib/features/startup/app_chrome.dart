import 'package:flutter/widgets.dart';

import '../review/review_controller.dart';
import '../review/review_host.dart';
import 'version_gate.dart';

/// App-level chrome around the main (router) app — RN App.tsx's
/// `<ReviewProvider><VersionUpdateGate/>…</ReviewProvider>`.
///
/// Use in `MaterialApp.router(builder: (context, child) => AppChrome(child: child!))`.
/// Provides [ReviewScope] (rating prompt) to every screen and the (currently
/// inert) version update gate on top.
class AppChrome extends StatelessWidget {
  const AppChrome({super.key, required this.child, this.reviewController, this.versionGate = versionGateConfig});

  final Widget child;

  /// Injected in tests.
  final ReviewController? reviewController;
  final VersionGateConfig? versionGate;

  @override
  Widget build(BuildContext context) => VersionUpdateGate(
        config: versionGate,
        child: ReviewHost(controller: reviewController, child: child),
      );
}
