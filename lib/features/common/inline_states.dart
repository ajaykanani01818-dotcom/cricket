import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Inline "empty / error" panel for a section (Home, Matches): a flat
/// surface with a hairline, the message, and an optional action.
class InlineMessageCard extends StatelessWidget {
  const InlineMessageCard({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.isError = false,
    this.padding = const EdgeInsets.symmetric(
      vertical: Spacing.xl,
      horizontal: Spacing.xl,
    ),
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// Error text in the negative colour (with an icon, never colour alone).
  final bool isError;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.hairline),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isError) ...[
              Icon(Icons.error_outline, size: 20, color: p.negative),
              const SizedBox(height: Spacing.xs),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppText.reading.copyWith(
                fontSize: 14,
                color: isError ? p.negative : p.inkMuted,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Spacing.md),
              DarkButton(
                key: actionKey,
                label: actionLabel!,
                onPressed: onAction!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Secondary action button: ink fill, surface label (reads in both themes).
class DarkButton extends StatelessWidget {
  const DarkButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.ink,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppFont.style(
                size: 14,
                weight: FontWeight.w700,
                color: p.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small centred spinner for a section that is still loading.
class InlineLoader extends StatelessWidget {
  const InlineLoader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Spacing.xxl),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: context.palette.brandText,
        ),
      ),
    ),
  );
}
