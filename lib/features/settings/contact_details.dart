import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand/brand.dart';
import '../../core/theme/app_theme.dart';
import 'legal_layout.dart';
import 'settings_widgets.dart';

/// Contact facts shown in Settings and Support. Defaults to [Brand]; any null
/// field is hidden (no placeholder). Injectable for tests.
@immutable
class ContactInfo {
  const ContactInfo({
    required this.email,
    this.feedbackSubject,
    this.websiteUrl,
    this.supportUrl,
    this.phone,
    this.address,
    this.twitterUrl,
    this.instagramUrl,
    this.facebookUrl,
  });

  static const brand = ContactInfo(
    email: Brand.supportEmail,
    feedbackSubject: Brand.feedbackSubject,
    websiteUrl: Brand.websiteUrl,
    supportUrl: Brand.supportUrl,
    phone: Brand.phone,
    address: Brand.address,
    twitterUrl: Brand.twitterUrl,
    instagramUrl: Brand.instagramUrl,
    facebookUrl: Brand.facebookUrl,
  );

  final String email;
  final String? feedbackSubject;
  final String? websiteUrl;
  final String? supportUrl;
  final String? phone;
  final String? address;
  final String? twitterUrl;
  final String? instagramUrl;
  final String? facebookUrl;

  /// mailto: with a %20-encoded subject (mail apps show '+' literally).
  Uri mailUri() => Uri.parse(
    feedbackSubject == null
        ? 'mailto:$email'
        : 'mailto:$email?subject=${Uri.encodeComponent(feedbackSubject!)}',
  );
}

/// Email address as selectable text plus "Send email" and "Copy address".
class SupportEmailBlock extends StatelessWidget {
  const SupportEmailBlock({
    super.key,
    this.info = ContactInfo.brand,
    this.keyPrefix = 'support',
    this.note,
  });
  final ContactInfo info;
  final String keyPrefix;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline, size: 22, color: p.ink),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Text(
                  'Email',
                  style: AppText.name.copyWith(fontSize: 16, color: p.ink),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 22 + Spacing.lg,
              top: Spacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  info.email,
                  key: ValueKey('${keyPrefix}_email_text'),
                  style: AppText.reading.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(note!, style: AppText.meta.copyWith(color: p.inkMuted)),
                ],
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  children: [
                    TextButton.icon(
                      key: ValueKey('${keyPrefix}_email_send'),
                      style: TextButton.styleFrom(
                        foregroundColor: p.brandText,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm,
                        ),
                      ),
                      onPressed: () =>
                          LinkLauncher.open(context, info.mailUri()),
                      icon: Icon(
                        Icons.send_outlined,
                        size: 18,
                        color: p.brandText,
                      ),
                      label: Text(
                        'Send email',
                        style: AppText.name.copyWith(color: p.brandText),
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey('${keyPrefix}_email_copy'),
                      style: TextButton.styleFrom(
                        foregroundColor: p.brandText,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm,
                        ),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: info.email),
                          );
                        } catch (_) {}
                        messenger
                          ?..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Email address copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                      },
                      icon: Icon(
                        Icons.copy_outlined,
                        size: 18,
                        color: p.brandText,
                      ),
                      label: Text(
                        'Copy address',
                        style: AppText.name.copyWith(color: p.brandText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows for the optional contact fields; only non-null ones are built.
List<Widget> optionalContactRows(BuildContext context, ContactInfo info) {
  final p = context.palette;
  void open(String url) => LinkLauncher.open(context, Uri.parse(url));
  return [
    if (info.phone case final phone?)
      SettingsRow(
        key: const ValueKey('contact_phone'),
        icon: Icons.call_outlined,
        title: 'Phone',
        subtitle: phone,
        external: true,
        onTap: () => open('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}'),
      ),
    if (info.address case final address?)
      Padding(
        key: const ValueKey('contact_address'),
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.place_outlined, size: 22, color: p.ink),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Address',
                    style: AppText.name.copyWith(fontSize: 16, color: p.ink),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    address,
                    style: AppText.meta.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    if (info.twitterUrl case final url?)
      SettingsRow(
        key: const ValueKey('contact_twitter'),
        icon: Icons.alternate_email,
        title: 'X (Twitter)',
        external: true,
        onTap: () => open(url),
      ),
    if (info.instagramUrl case final url?)
      SettingsRow(
        key: const ValueKey('contact_instagram'),
        icon: Icons.photo_camera_outlined,
        title: 'Instagram',
        external: true,
        onTap: () => open(url),
      ),
    if (info.facebookUrl case final url?)
      SettingsRow(
        key: const ValueKey('contact_facebook'),
        icon: Icons.thumb_up_alt_outlined,
        title: 'Facebook',
        external: true,
        onTap: () => open(url),
      ),
  ];
}
