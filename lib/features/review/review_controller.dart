import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/brand/brand.dart';
import 'review_storage.dart';

/// Store page for "Rate Cric Ticker" in Settings: the App Store listing when
/// its id is known, else App Store search on iOS, else the Play listing.
Uri storeListingUri({TargetPlatform? platform}) {
  final p = platform ?? defaultTargetPlatform;
  if (!kIsWeb && p == TargetPlatform.iOS) {
    final id = Brand.appStoreId;
    return Uri.parse(
      id == null
          ? Brand.appStoreSearchUrl
          : 'https://apps.apple.com/app/id$id?action=write-review',
    );
  }
  return Uri.parse(Brand.playStoreUrl);
}

/// Opens the store listing in the store app (or the browser on web).
Future<bool> defaultOpenStoreListing() async {
  try {
    return await launchUrl(
      storeListingUri(),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Asks the OS for its native rating sheet. The OS decides whether it is
/// shown (Play quota, iOS max 3 per year), so this never promises a sheet.
Future<bool> defaultRequestReview() async {
  if (kIsWeb) return false; // in_app_review has no web implementation
  try {
    final r = InAppReview.instance;
    if (!await r.isAvailable()) return false;
    await r.requestReview();
    return true;
  } catch (_) {
    return false;
  }
}

/// Review prompt policy. No custom star dialog and no sentiment gating: when
/// [ReviewRules] allow it, the app calls the system review API directly, and
/// Settings has an always-visible "Rate Cric Ticker" row that opens the store.
class ReviewController extends ChangeNotifier {
  ReviewController({
    ReviewStore? store,
    Future<bool> Function()? requestReview,
    Future<bool> Function()? openStoreListing,
    VoidCallback? exitApp,
    this.promptDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : store = store ?? ReviewStore(),
       _requestReview = requestReview ?? defaultRequestReview,
       _openStore = openStoreListing ?? defaultOpenStoreListing,
       _exitApp = exitApp ?? (() => SystemNavigator.pop()),
       _clock = clock ?? DateTime.now;

  final ReviewStore store;
  final Future<bool> Function() _requestReview;
  final Future<bool> Function() _openStore;
  final VoidCallback _exitApp;
  final DateTime Function() _clock;

  /// Pause between the positive moment and the request, so the sheet never
  /// lands on top of a tap.
  final Duration promptDelay;

  bool _sessionRecorded = false;
  bool _askedThisRun = false;
  bool _disposed = false;
  Timer? _promptTimer;
  DateTime? _lastRootBack;
  int _exitHintTick = 0;

  /// True once a review was requested in this app run.
  bool get askedThisRun => _askedThisRun;

  /// Bumped when "Press back again to exit" should be shown (ReviewHost).
  int get exitHintTick => _exitHintTick;

  /// Records one session per app launch.
  Future<void> recordSessionOnce() async {
    if (_sessionRecorded) return;
    _sessionRecorded = true;
    await store.recordSession();
  }

  /// One match view (counts towards [ReviewRules.minMeaningfulActions]).
  Future<void> recordMeaningfulAction() => store.recordMeaningfulAction();

  /// Requests the system review sheet after [promptDelay] when the user has
  /// just had a [positiveMoment] (e.g. viewed a completed match) and
  /// [ReviewRules] allow it. Without a positive moment this does nothing:
  /// merely opening a match is not a reason to ask.
  ///
  /// Returns true when a request was scheduled.
  Future<bool> requestReviewIfAppropriate({bool positiveMoment = false}) async {
    if (!positiveMoment || _askedThisRun || _disposed) return false;
    final ok = await store.canAsk(
      positiveMoment: positiveMoment,
      askedThisRun: _askedThisRun,
    );
    if (!ok || _disposed || _askedThisRun) return false;
    _askedThisRun = true;
    _promptTimer?.cancel();
    _promptTimer = Timer(promptDelay, () async {
      _promptTimer = null;
      if (_disposed) return;
      try {
        if (await _requestReview()) await store.recordReviewRequested();
      } catch (_) {}
    });
    return true;
  }

  /// Settings "Rate Cric Ticker": opens the store listing (always available,
  /// for every user). Returns false when nothing could open it.
  Future<bool> openStoreListing() async {
    try {
      return await _openStore();
    } catch (_) {
      return false;
    }
  }

  /// Android back on the Home root. Never shows a rating prompt: first press
  /// asks for "Press back again to exit" ([exitHintTick]), a second press
  /// within 2 s exits.
  ///
  /// (Name kept for `AppShell`, which calls it at the Home root.)
  void showRatingModalForExit() {
    if (_disposed) return;
    final now = _clock();
    final last = _lastRootBack;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      _lastRootBack = null;
      _exitApp();
      return;
    }
    _lastRootBack = now;
    _exitHintTick++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _promptTimer?.cancel();
    super.dispose();
  }
}

/// Exposes the [ReviewController].
class ReviewScope extends InheritedNotifier<ReviewController> {
  const ReviewScope({
    super.key,
    required ReviewController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Null when no review host is mounted.
  static ReviewController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReviewScope>()?.notifier;

  /// Non-listening lookup for callbacks.
  static ReviewController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReviewScope>()?.notifier;
}
