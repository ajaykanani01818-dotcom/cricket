/// Settings tab and every page reached from it (privacy policy, terms of use,
/// about, help and support, app info, legacy "More").
library;

export 'contact_details.dart' show ContactInfo, SupportEmailBlock;
export 'legal_layout.dart' show LegalPageLayout, LinkLauncher, OpenOnWebLink;
export 'legal_pages.dart'
    show
        PrivacyPolicyScreen,
        TermsScreen,
        AboutUsScreen,
        ContactUsScreen,
        AppInfoScreen,
        privacyBlocks,
        termsBlocks;
export 'menu_screens.dart'
    show
        SettingsScreen,
        SettingsBody,
        MoreScreen,
        kAppDescription,
        kCoverageNote;
export 'settings_widgets.dart' show AppVersion;
