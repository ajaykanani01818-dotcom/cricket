import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Empty / error state. Writing rule (design skill): say what happened and
/// what to do next, in the interface's voice; an empty screen is an
/// invitation to act. Quiet visual: muted icon, sentence-case title, body,
/// one action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.sports_cricket_outlined,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.hint,
  });

  /// Optional second line: how to fix it.
  final String? hint;

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Spacing.xxxl,
        horizontal: Spacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: p.inkMuted),
            const SizedBox(height: Spacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.sectionTitle,
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppText.reading.copyWith(
                  color: p.inkMuted,
                  fontSize: 14,
                ),
              ),
            ],
            if (hint != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(hint!, textAlign: TextAlign.center, style: AppText.meta),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Spacing.lg),
              FilledButton(
                key: const ValueKey('empty_state_action'),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard load-failure view. [message] is the specific reason (from
/// `friendlyError`); the title says what failed and the action retries.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = "Scores didn't load",
  });
  final String message;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    title: title,
    subtitle: message,
    hint: 'Check your connection, then try again.',
    actionLabel: 'Try again',
    onAction: onRetry,
  );
}
