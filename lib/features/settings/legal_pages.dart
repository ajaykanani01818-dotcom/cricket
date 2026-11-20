import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/brand/brand.dart';
import '../../core/router/app_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/titles.dart';
import 'contact_details.dart';
import 'legal_documents.dart';
import 'legal_layout.dart';
import 'menu_screens.dart';
import 'settings_widgets.dart';
import 'simple_html.dart';

/// Parsed once (the bundled HTML is constant).
final List<HtmlBlock> privacyBlocks = parseSimpleHtml(privacyPolicyHtml);
final List<HtmlBlock> termsBlocks = parseSimpleHtml(termsOfUseHtml);

/// Handles a link inside a bundled legal document: the sibling legal page
/// opens in the app, everything else outside it.
void openLegalLink(BuildContext context, String href) {
  final h = href.trim();
  final page = switch (h) {
    'privacy-policy.html' => 'privacy',
    'terms.html' => 'terms',
    'support.html' => 'contact',
    _ => null,
  };
  if (page != null) {
    try {
      AppNav.page<void>(context, page);
      return;
    } catch (_) {
      // Not under the app router: fall back to the hosted page.
    }
  }
  final uri = Uri.tryParse(h);
  if (uri == null) return;
  final target = uri.hasScheme
      ? uri
      : Uri.parse(Brand.websiteUrl).resolveUri(uri);
  LinkLauncher.open(context, target);
}

class _LegalDocumentPage extends StatelessWidget {
  const _LegalDocumentPage({
    required this.title,
    required this.blocks,
    required this.url,
    required this.contentKey,
    required this.webKey,
  });
  final String title;
  final List<HtmlBlock> blocks;
  final String url;
  final String contentKey;
  final String webKey;

  @override
  Widget build(BuildContext context) {
    return LegalPageLayout(
      title: title,
      showBanners: false,
      footer: OpenOnWebLink(key: ValueKey(webKey), url: url),
      children: [
        SimpleHtmlView(
          key: ValueKey(contentKey),
          blocks: blocks,
          hideTitle: true,
          onLink: (href) => openLegalLink(context, href),
        ),
      ],
    );
  }
}

/// Privacy policy: the hosted page's text, word for word, rendered natively.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => _LegalDocumentPage(
    title: 'Privacy policy',
    blocks: privacyBlocks,
    url: Brand.privacyUrl,
    contentKey: 'privacy_content',
    webKey: 'privacy_open_online',
  );
}

/// Terms of use: the hosted page's text, word for word, rendered natively.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => _LegalDocumentPage(
    title: 'Terms of use',
    blocks: termsBlocks,
    url: Brand.termsUrl,
    contentKey: 'terms_content',
    webKey: 'terms_open_online',
  );
}

/// About Cric Ticker.
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LegalPageLayout(
      title: 'About ${Brand.appName}',
      footer: OpenOnWebLink(
        key: const ValueKey('about_website'),
        url: Brand.websiteUrl,
        label: 'Visit the website',
      ),
      children: [
        Column(
          key: const ValueKey('about_content'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm),
              child: BrandWordmark(height: 28),
            ),
            Text(
              Brand.tagline,
              style: AppText.name.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: Spacing.xs),
            const AppVersionText(),
            const SizedBox(height: Spacing.xl),
            const LegalSection(paragraphs: [kAppDescription]),
            const LegalSection(
              title: 'Data and coverage',
              paragraphs: [
                'Scores, commentary and statistics come from third-party data providers and can lag behind the broadcast. $kCoverageNote',
              ],
            ),
            const LegalSection(
              title: 'Independent',
              paragraphs: [
                '${Brand.appName} is not affiliated with, endorsed by or sponsored by the ICC, any national cricket board, league, team or player.',
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Help and support (same content as the hosted support page).
class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key, this.contact = ContactInfo.brand});
  final ContactInfo contact;

  static const faqs = [
    (
      'A score looks behind the match',
      'Live data can lag behind the broadcast. Pull down on the screen to refresh. If a match stays wrong for more than a few minutes, email us the match name.',
    ),
    (
      'A match or competition is missing',
      "Coverage depends on the data available from our providers. Tell us which competition you want and we'll check whether it can be added.",
    ),
    (
      'How do I switch between light and dark mode?',
      'Open Settings in the app and choose Light, Dark or System.',
    ),
    (
      'Do I need an account?',
      'No. Everything in the app works without signing in.',
    ),
    (
      'How do I delete my data?',
      'The app has no accounts, so we hold no profile about you. Uninstalling the app removes everything it stored on your phone. See the privacy policy for details, or email us with any request.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final extra = optionalContactRows(context, contact);
    return LegalPageLayout(
      title: 'Help and support',
      footer: contact.supportUrl == null
          ? null
          : OpenOnWebLink(
              key: const ValueKey('contact_web'),
              url: contact.supportUrl!,
            ),
      children: [
        Text(
          'We usually reply within a few working days.',
          style: AppText.meta.copyWith(color: p.inkMuted),
        ),
        const SizedBox(height: Spacing.md),
        SettingsGroup(
          children: [
            SupportEmailBlock(
              key: const ValueKey('contact_email_block'),
              info: contact,
              keyPrefix: 'contact',
              note:
                  'Include your phone model, the app version (Settings, About) and what happened.',
            ),
            ...extra,
          ],
        ),
        const SizedBox(height: Spacing.xl),
        Semantics(
          header: true,
          child: Text(
            'Common questions',
            style: AppText.sectionTitle.copyWith(color: p.ink),
          ),
        ),
        const SizedBox(height: Spacing.md),
        for (final (q, a) in faqs)
          LegalSection(
            children: [
              Text(q, style: AppText.h4.copyWith(color: p.ink)),
              const SizedBox(height: Spacing.xs),
              Text(a, style: AppText.reading.copyWith(color: p.ink)),
            ],
          ),
      ],
    );
  }
}

/// App info: name, version, platform.
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final platform = kIsWeb
        ? 'Web'
        : (defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Android');
    Widget row(String key, String label, Widget value) => Padding(
      key: ValueKey('app_info_$key'),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.meta.copyWith(color: p.inkMuted)),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: AppText.name.copyWith(fontSize: 16, color: p.ink),
            child: value,
          ),
        ],
      ),
    );
    return LegalPageLayout(
      title: 'App info',
      children: [
        SettingsGroup(
          children: [
            row('name', 'App name', const Text(Brand.appName)),
            row(
              'version',
              'Version',
              AppVersionText(
                prefix: '',
                style: AppText.name.copyWith(fontSize: 16, color: p.ink),
              ),
            ),
            row('platform', 'Platform', Text(platform)),
          ],
        ),
        const SizedBox(height: Spacing.xl),
        const LegalSection(paragraphs: [kAppDescription, kCoverageNote]),
        LegalSection(paragraphs: ['© ${DateTime.now().year} ${Brand.appName}']),
      ],
    );
  }
}
