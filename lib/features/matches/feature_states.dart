import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Empty / error message for the Matches and Series screens: muted icon,
/// sentence-case title, what to do next, one action. Same look as the core
/// `EmptyState`, but the container and the action carry caller keys (tests
/// and the e2e driver find them by key).
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.sports_cricket_outlined,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.isError = false,
  });

  final String title;
  final String? body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xxxl, horizontal: Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: isError ? p.negative : p.inkMuted),
              const SizedBox(height: Spacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppText.sectionTitle.copyWith(color: p.ink),
              ),
              if (body != null && body!.trim().isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: AppText.reading.copyWith(color: p.inkMuted, fontSize: 14),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Spacing.lg),
                FilledButton(key: actionKey, onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Load-failure message. [reason] is the specific cause (`friendlyError`).
class ErrorMessage extends StatelessWidget {
  const ErrorMessage({super.key, required this.title, required this.reason, required this.onRetry, this.retryKey});
  final String title;
  final String reason;
  final VoidCallback onRetry;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) => StateMessage(
    icon: Icons.cloud_off_outlined,
    title: title,
    body: reason,
    actionLabel: 'Try again',
    onAction: onRetry,
    actionKey: retryKey,
    isError: true,
  );
}

/// Full-width band in [color] whose content is centred and capped at
/// [maxWidth], so tabs and chips line up with the centred lists on tablets
/// and desktop.
class MaxWidthBand extends StatelessWidget {
  const MaxWidthBand({super.key, required this.child, this.maxWidth = 720, this.color});
  final Widget child;
  final double maxWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color ?? context.palette.surface,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // Tight width: a scrollable tab row would otherwise shrink-wrap and
        // centre itself with a short hairline.
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}
