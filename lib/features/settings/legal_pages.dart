import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import 'legal_layout.dart';
import 'privacy_policy_html.dart';
import 'simple_html.dart';

/// Live policy page (RN PRIVACY_POLICY_URL). The app renders the bundled copy
/// natively and links here for the latest version.
const privacyPolicyUrl = 'https://crickbex.com/privacy-policy';
const supportEmail = 'crickbex@gmail.com';
const supportUrl = 'https://crickbex.com/contact';

/// Parsed once (the bundled HTML is constant).
final List<HtmlBlock> _privacyBlocks = parseSimpleHtml(privacyPolicyHtml);

/// Ported from RN `PrivacyPolicyScreen` (WebView → native rendering of the
/// bundled copy; no banners, same as RN).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPageLayout(
      title: 'Privacy Policy',
      showBanners: false,
      children: [
        DelayedContent(
          builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SimpleHtmlView(key: const ValueKey('privacy_content'), blocks: _privacyBlocks),
            const SizedBox(height: Spacing.xl),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('privacy_open_online'),
                onPressed: () => LinkLauncher.open(context, Uri.parse(privacyPolicyUrl)),
                icon: const Icon(Icons.open_in_new, size: 18, color: AppColors.pitch),
                label: const Text('View the latest version on crickbex.com',
                    style: TextStyle(color: AppColors.pitch, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Ported from RN `TermsScreen`.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPageLayout(
      title: 'Terms & Conditions',
      children: [
        DelayedContent(
          builder: (context) => const Column(
            key: ValueKey('terms_content'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: EdgeInsets.only(bottom: Spacing.xxl), child: Text('Last updated: February 2025', style: LegalText.lastUpdated)),
              LegalSection(title: '1. Acceptance of Terms', paragraphs: [
                'By downloading or using CrickBex you agree to these Terms. If you do not agree, do not use the app.',
              ]),
              LegalSection(title: '2. Service', paragraphs: [
                'CrickBex provides cricket information: live scores, schedules, series, rankings, and player statistics. Content is for personal use only.',
              ]),
              LegalSection(title: '3. Acceptable Use', paragraphs: [
                'You must not violate laws, attempt unauthorized access, copy or distribute our content without permission, or use automated scraping.',
              ]),
              LegalSection(title: '4. Intellectual Property', paragraphs: [
                'All app content and features are owned by CrickBex or licensors and protected by law.',
              ]),
              LegalSection(title: '5. Disclaimer', paragraphs: [
                'The app is provided as is. We do not guarantee accuracy of scores or statistics. Use at your own risk.',
              ]),
              LegalSection(title: '6. Liability', paragraphs: [
                'To the fullest extent permitted by law, CrickBex is not liable for indirect or consequential damages from use of the app.',
              ]),
              LegalSection(title: '7. Changes', paragraphs: [
                'We may change these Terms. Continued use means acceptance. We may suspend or terminate access for violations.',
              ]),
              LegalSection(title: '8. Contact', paragraphs: ['Questions? Contact us via the Contact Us page in this app.']),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ported from RN `AboutUsScreen`.
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPageLayout(
      title: 'About Us',
      children: [
        DelayedContent(
          builder: (context) => Column(key: const ValueKey('about_content'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset('assets/images/icon.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      cacheWidth: 216,
                      errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72)),
                ),
                const SizedBox(height: 12),
                const Text('CrickBex', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                const SizedBox(height: 4),
                const Text('Live Scores & Updates', style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ]),
            ),
            const LegalSection(title: 'Who We Are', paragraphs: [
              'CrickBex is your premium destination for cricket. We deliver live scores, match schedules, series, and player rankings so you never miss a moment of the game.',
            ]),
            const LegalSection(title: 'What We Offer', bullets: [
              'Live match scores and ball-by-ball updates',
              'Upcoming matches and series schedules',
              'ICC and format-based player rankings',
              'Player profiles and statistics',
            ]),
            const LegalSection(title: 'Our Commitment', paragraphs: [
              'We are committed to providing accurate, timely, and easy-to-use cricket information. Your feedback helps us improve. Reach out through the Contact Us page.',
            ]),
            const LegalSection(title: 'Thank You', paragraphs: [
              'Thank you for choosing CrickBex. We hope you enjoy using the app as much as we enjoy building it for cricket fans worldwide.',
            ]),
          ]),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Material(
        color: AppColors.card,
        elevation: 1,
        shadowColor: const Color(0x0A000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: const BorderSide(color: AppColors.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(children: [
              Icon(icon, size: 22, color: AppColors.pitch),
              const SizedBox(width: Spacing.md),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.pitch))),
              const SizedBox(width: Spacing.md),
              const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ported from RN `ContactUsScreen` (no initial shimmer, same as RN).
class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPageLayout(
      title: 'Contact Us',
      children: [
        const LegalSection(paragraphs: ['For support, feedback, or general inquiries, please use one of the options below.']),
        LegalSection(
          title: 'Email',
          paragraphs: const ['We aim to respond within 24 to 48 hours on business days.'],
          children: [
            _LinkRow(
              key: const ValueKey('contact_email'),
              icon: Icons.mail_outline,
              text: supportEmail,
              onTap: () => LinkLauncher.open(context, Uri.parse('mailto:$supportEmail')),
            ),
          ],
        ),
        LegalSection(title: 'Website', children: [
          _LinkRow(
            key: const ValueKey('contact_web'),
            icon: Icons.language,
            text: 'crickbex.com/contact',
            onTap: () => LinkLauncher.open(context, Uri.parse(supportUrl)),
          ),
        ]),
        const LegalSection(title: 'Privacy and Terms', paragraphs: [
          'For questions about our Privacy Policy or Terms and Conditions, refer to those pages in this app or contact us via email.',
        ]),
      ],
    );
  }
}

/// Ported from RN `AppInfoScreen` (version from package_info_plus instead of a constant).
class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  static const _name = 'CrickBex';
  String _version = '…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.trim().isEmpty ? '-' : info.version.trim();
    } catch (_) {
      version = '-';
    }
    if (!mounted) return;
    setState(() => _version = version);
  }

  Widget _card(String label, String value, String key) => Container(
        key: ValueKey('app_info_$key'),
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: Spacing.xs),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Android';
    return LegalPageLayout(
      title: 'App Info',
      children: [
        _card('App Name', _name, 'name'),
        _card('Version', _version, 'version'),
        _card('Platform', platform, 'platform'),
        const LegalSection(title: 'About This App', paragraphs: [
          'CrickBex provides live cricket scores, match schedules, series, and player rankings. Content is for personal and non-commercial use.',
        ]),
        const LegalSection(title: 'Legal', paragraphs: [
          'By using this app you agree to our Terms & Conditions and Privacy Policy. You can read them from the More section in the app.',
        ]),
        LegalSection(title: 'Copyright', paragraphs: ['© ${DateTime.now().year} CrickBex. All rights reserved.']),
      ],
    );
  }
}
