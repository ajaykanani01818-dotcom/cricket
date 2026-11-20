import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/pressable.dart';

/// Installed version as "1.2.3 (7)"; null when unknown.
class AppVersion {
  AppVersion._();

  static Future<String?>? _cached;

  static Future<String?> load() => _cached ??= _read();

  static Future<String?> _read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isEmpty) return null;
      final b = info.buildNumber.trim();
      return b.isEmpty ? v : '$v ($b)';
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void debugReset() => _cached = null;
}

/// "Version 1.2.3 (7)", or nothing while unknown (never a placeholder).
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key, this.prefix = 'Version ', this.style});
  final String prefix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FutureBuilder<String?>(
      future: AppVersion.load(),
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) return const SizedBox.shrink();
        return Text(
          '$prefix$v',
          key: const ValueKey('app_version'),
          style: style ?? AppText.meta.copyWith(color: p.inkMuted),
        );
      },
    );
  }
}

/// Sentence-case label above a settings group.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xs,
        Spacing.xl,
        Spacing.xs,
        Spacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: AppText.name.copyWith(fontSize: 14, color: p.inkMuted),
        ),
      ),
    );
  }
}

/// A surface panel with a hairline; children are separated by hairlines.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: p.hairline),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One tappable settings row: leading icon, title, optional subtitle and a
/// trailing widget (chevron by default).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.semanticsLabel,
    this.external = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? semanticsLabel;

  /// Opens outside the app (shows an "open in new" glyph).
  final bool external;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final trail =
        trailing ??
        Icon(
          external ? Icons.open_in_new : Icons.chevron_right,
          size: external ? 18 : 22,
          color: p.inkMuted,
        );
    return Semantics(
      button: onTap != null,
      label:
          semanticsLabel ??
          [title, ?subtitle].join('. ') +
              (external ? '. Opens outside the app' : ''),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: p.ink),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.name.copyWith(
                          fontSize: 16,
                          color: p.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppText.meta.copyWith(color: p.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                trail,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A radio-style choice row (one of a mutually exclusive group).
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: [title, ?subtitle].join('. '),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          color: selected ? p.brandTint : null,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: p.ink),
                const SizedBox(width: Spacing.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.name.copyWith(
                        fontSize: 16,
                        color: p.ink,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppText.meta.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? p.brandText : p.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
