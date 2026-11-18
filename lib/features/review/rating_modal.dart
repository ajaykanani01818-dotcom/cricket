import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Ratings at or above this open the store after a short loader.
const int kMinStarsForStore = 3;
const Duration kStoreRedirectDelay = Duration(seconds: 2);

/// "Enjoying CrickBex?" card — ported from RN `RatingModal`.
///
/// Rendered as an overlay (backdrop + card); tapping the backdrop dismisses.
class RatingModal extends StatefulWidget {
  const RatingModal({
    super.key,
    required this.onClose,
    required this.onOpenStore,
    this.showExitAppButton = false,
    this.onExitApp,
  });

  final VoidCallback onClose;

  /// Called after the 2s loader when the user picked 3–5 stars.
  final VoidCallback onOpenStore;
  final bool showExitAppButton;
  final VoidCallback? onExitApp;

  @override
  State<RatingModal> createState() => _RatingModalState();
}

class _RatingModalState extends State<RatingModal> {
  int _rating = 0;
  bool _redirecting = false;
  Timer? _timer;

  void _clearTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _clearTimer();
    super.dispose();
  }

  void _dismiss() {
    _clearTimer();
    widget.onClose();
  }

  void _onStar(int value) {
    if (_redirecting) return;
    _clearTimer();
    if (value >= kMinStarsForStore) {
      setState(() {
        _rating = value;
        _redirecting = true;
      });
      _timer = Timer(kStoreRedirectDelay, () {
        _timer = null;
        widget.onClose();
        widget.onOpenStore();
      });
      return;
    }
    setState(() => _rating = value);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = math.min(width - 40, 340.0);
    // Size the star row so it never overflows the card on narrow devices.
    const cardPadX = 24.0, starGap = 4.0, starTouch = 4.0;
    final content = cardWidth - cardPadX * 2 - 2; // minus 1px border each side
    final fit = ((content - (5 * starTouch * 2 + 4 * starGap)) / 5).floorToDouble();
    final starSize = fit.clamp(26.0, 40.0);
    final lowRating = _rating > 0 && _rating < kMinStarsForStore;

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        key: const ValueKey('review_backdrop'),
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: Container(
          color: const Color(0x59000000),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () {}, // swallow taps on the card
            child: Container(
              key: const ValueKey('review_modal'),
              width: cardWidth,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: cardPadX),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderSubtle),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8))],
              ),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_redirecting)
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 28),
                      child: SizedBox(
                        height: 100,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          CircularProgressIndicator(color: AppColors.pitch),
                          SizedBox(height: 14),
                          Text('Opening the store…',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ]),
                      ),
                    )
                  else ...[
                    Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(bottom: 16),
                      alignment: Alignment.center,
                      child: Image.asset(
                        'assets/images/rating-star.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                        semanticLabel: 'Cute star',
                        errorBuilder: (_, _, _) => const Icon(Icons.star, size: 44, color: AppColors.gold),
                      ),
                    ),
                    const Text('Enjoying CrickBex?',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text, letterSpacing: 0.2)),
                    const SizedBox(height: 8),
                    const Text(
                      'Your feedback helps us improve and build a better experience for cricket fans.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.favorite, size: 16, color: Color(0xFFE53935)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text('Made with love for cricket fans',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 20),
                  ],
                  Opacity(
                    opacity: _redirecting ? 0.85 : 1,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 1; i <= 5; i++) ...[
                        if (i > 1) const SizedBox(width: starGap),
                        Semantics(
                          button: true,
                          label: '$i star${i == 1 ? '' : 's'}',
                          child: InkResponse(
                            key: ValueKey('review_star_$i'),
                            onTap: _redirecting ? null : () => _onStar(i),
                            radius: starSize / 2 + 6,
                            child: Padding(
                              padding: const EdgeInsets.all(starTouch),
                              child: Icon(
                                _rating >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: starSize,
                                color: _rating >= i ? AppColors.gold : AppColors.border,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 20),
                  if (!_redirecting && lowRating) ...[
                    const Text('Tell us what we can improve via Contact Us.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('review_send_feedback'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.pitch,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _dismiss,
                        child: const Text('Send feedback', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.white)),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (!_redirecting)
                    TextButton(
                      key: const ValueKey('review_maybe_later'),
                      onPressed: _dismiss,
                      child: const Text('Maybe later', style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                    ),
                  if (!_redirecting && widget.showExitAppButton && widget.onExitApp != null)
                    TextButton(
                      key: const ValueKey('review_exit_app'),
                      onPressed: () {
                        _clearTimer();
                        widget.onExitApp!();
                      },
                      child: const Text('Exit app', style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
