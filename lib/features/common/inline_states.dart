import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'gradient_card.dart';

/// RN Home/MatchesTabPanel inline "empty / error" card with optional
/// dark "Try Again" button.
class InlineMessageCard extends StatelessWidget {
  const InlineMessageCard({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.isError = false,
    this.padding = const EdgeInsets.symmetric(vertical: Spacing.xxl, horizontal: Spacing.xl),
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// Error text is red in MatchesTabPanel; Home uses secondary text for both.
  final bool isError;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GradientCard(
        padding: padding,
        child: SizedBox(
          width: double.infinity,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: isError ? AppColors.error : AppColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              DarkButton(key: actionKey, label: actionLabel!, onPressed: onAction!),
            ],
          ]),
        ),
      );
}

/// RN `retryBtn` style: near-black pill with white bold label.
class DarkButton extends StatelessWidget {
  const DarkButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.text,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            child: Text(label,
                style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ),
        ),
      );
}

/// RN `InlineLoader`: small centered spinner.
class InlineLoader extends StatelessWidget {
  const InlineLoader({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.xxl),
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.pitch)),
        ),
      );
}
