import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ported from RN `EmptyState` (also used for error states with a Retry action).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.sports_cricket_outlined,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxxl, horizontal: Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.textMuted),
          ),
          const SizedBox(height: Spacing.lg),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
          if (subtitle != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: Spacing.lg),
            FilledButton(
              key: const ValueKey('empty_state_action'),
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.pitch,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl, vertical: Spacing.md),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
              ),
              child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard error view with Retry.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load data',
        subtitle: message,
        actionLabel: 'Retry',
        onAction: onRetry,
      );
}
