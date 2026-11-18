import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import 'review_storage.dart';

/// Play Store listing with the reviews section expanded (RN PLAY_STORE_URL).
const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.crickbex.dark&showAllReviews=true';

/// iOS: search until a fixed App Store ID exists (RN IOS_STORE_SEARCH_URL).
const iosStoreSearchUrl = 'https://apps.apple.com/search?term=CrickBex&entity=software';

/// Opens the store listing: in_app_review first, falling back to the URL.
Future<bool> defaultOpenStoreListing() async {
  try {
    await InAppReview.instance.openStoreListing();
    return true;
  } catch (_) {
    // fall through to the plain URL
  }
  try {
    final url = Uri.parse(defaultTargetPlatform == TargetPlatform.iOS ? iosStoreSearchUrl : playStoreUrl);
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Review prompt state — ported from RN `ReviewContext`.
class ReviewController extends ChangeNotifier {
  ReviewController({
    ReviewStore? store,
    Future<bool> Function()? openStoreListing,
    VoidCallback? exitApp,
    this.autoPromptDelay = const Duration(seconds: 2),
  })  : store = store ?? ReviewStore(),
        _openStore = openStoreListing ?? defaultOpenStoreListing,
        _exitApp = exitApp ?? (() => SystemNavigator.pop());

  final ReviewStore store;
  final Future<bool> Function() _openStore;
  final VoidCallback _exitApp;
  final Duration autoPromptDelay;

  bool _visible = false;
  bool _openedFromExit = false;
  bool _sessionRecorded = false;
  bool _autoPromptScheduled = false;
  bool _disposed = false;
  Timer? _autoPromptTimer;

  bool get ratingModalVisible => _visible;

  /// True when opened from Android back at the root — modal adds "Exit app".
  bool get openedFromExit => _openedFromExit;

  void _set({required bool visible, required bool fromExit}) {
    if (_disposed) return;
    _visible = visible;
    _openedFromExit = fromExit;
    notifyListeners();
  }

  /// Records one session per app launch (main app visible).
  Future<void> recordSessionOnce() async {
    if (_sessionRecorded) return;
    _sessionRecorded = true;
    await store.recordSession();
  }

  void showRatingModal() => _set(visible: true, fromExit: false);

  void showRatingModalForExit() => _set(visible: true, fromExit: true);

  void closeRatingModal() => _set(visible: false, fromExit: false);

  void exitApp() {
    closeRatingModal();
    _exitApp();
  }

  Future<void> recordMeaningfulAction() => store.recordMeaningfulAction();

  /// Auto prompt (once per app run) after a short pause, when eligible.
  Future<void> requestReviewIfAppropriate() async {
    if (_autoPromptScheduled) return;
    _autoPromptScheduled = true;
    final canAsk = await store.canAsk();
    if (!canAsk || _disposed) return;
    _autoPromptTimer?.cancel();
    // Show after a short delay so we don't interrupt right after a tap.
    _autoPromptTimer = Timer(autoPromptDelay, () {
      _autoPromptTimer = null;
      showRatingModal();
    });
  }

  /// 3–5 stars: open the store listing and remember the request (cooldown).
  Future<void> openStoreListing() async {
    try {
      final ok = await _openStore();
      if (ok) await store.recordReviewRequested();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _autoPromptTimer?.cancel();
    super.dispose();
  }
}

/// Exposes the [ReviewController] (RN `useReviewOptional`).
class ReviewScope extends InheritedNotifier<ReviewController> {
  const ReviewScope({super.key, required ReviewController controller, required super.child}) : super(notifier: controller);

  /// Null when no review host is mounted (RN `useReviewOptional`).
  static ReviewController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReviewScope>()?.notifier;

  /// Non-listening lookup for callbacks.
  static ReviewController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReviewScope>()?.notifier;
}
