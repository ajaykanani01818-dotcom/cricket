/// Bundled copies of the hosted legal pages (Brand.privacyUrl / Brand.termsUrl).
/// Source: Y/legal-site/privacy-policy.html and terms.html (the `<main>` element,
/// copied verbatim). Keep word for word in sync with the hosted pages:
/// test/settings/legal_documents_test.dart compares them when legal-site/ is
/// checked out next to the app.
library;

const String privacyPolicyHtml = r'''<main>
<h1>Privacy policy</h1>
<p class="meta">Effective 18 November 2026</p>
<p>This policy explains what information the Cric Ticker mobile app ("Cric Ticker", "the app", "we") handles, why, and the choices you have. It applies to the Cric Ticker app for Android and iOS and to this website.</p>

<h2>1. Summary</h2>
<ul>
<li>You do not need an account. We never ask for your name, phone number, email address or location.</li>
<li>Your app settings stay on your device.</li>
<li>To deliver scores, the app talks to our servers over an encrypted connection. Our servers see your IP address for security and to prevent abuse.</li>
<li>If the app shows ads, Google AdMob may collect device identifiers as described in section 5.</li>
<li>We do not sell your personal information.</li>
</ul>

<h2>2. Information stored on your device</h2>
<p>The app saves a small amount of data on your phone so it works the way you left it:</p>
<ul>
<li>your settings, such as light or dark theme;</li>
<li>recently loaded cricket data, so screens open quickly and work briefly offline;</li>
<li>counters that decide when to ask you to rate the app.</li>
</ul>
<p>This data is not sent to us. You can remove it at any time by clearing the app's storage or uninstalling the app.</p>

<h2>3. Information processed by our servers</h2>
<p>When the app requests scores, fixtures, rankings or other cricket data, our servers receive the request together with your device's IP address and basic technical details (time of the request and the data requested). We use this only to deliver the data, keep the service secure, limit abusive or automated traffic, and fix problems. We do not use it to identify you or build a profile, and we keep server logs only for a limited period.</p>
<p>Requests between the app and our servers are encrypted.</p>

<h2>4. Permissions</h2>
<p>On Android the app uses the Internet permission and the network-state permission, to load data and show whether you are offline. The app does not request access to your camera, microphone, contacts, photos, files or location.</p>

<h2>5. Advertising</h2>
<p>The app may display ads served by Google AdMob. When ads are shown, Google and its partners may collect and use information such as your device's advertising ID, IP address, approximate location derived from the IP address, and interactions with ads, to show and measure ads and prevent fraud. Where required by law (for example in the EEA and the UK), the app asks for your consent before personalised ads are shown, and you can change your choice later.</p>
<p>You can reset or delete your advertising ID, or opt out of personalised ads, in your device settings. Learn more in <a href="https://policies.google.com/technologies/ads">How Google uses information from sites or apps that use its services</a> and the <a href="https://policies.google.com/privacy">Google Privacy Policy</a>.</p>

<h2>6. Ratings and store services</h2>
<p>If you choose to rate the app, the rating is handled by Google Play or the Apple App Store under their own privacy policies. We do not receive your account details.</p>

<h2>7. Sharing</h2>
<p>We do not sell or rent personal information. Information is shared only with service providers that help run the app (hosting and, if ads are shown, Google AdMob), or when required by law.</p>

<h2>8. Children</h2>
<p>Cric Ticker is a general-audience sports app and is not directed at children under 13. We do not knowingly collect personal information from children. If you believe a child has provided personal information, contact us and we will delete it.</p>

<h2>9. Your choices and data deletion</h2>
<p>Because there are no accounts, we hold no profile about you to delete. You can delete everything the app stores by uninstalling it. You can control ad personalisation in your device settings. For any privacy request, including access or deletion requests where a law gives you those rights, email us at the address below.</p>

<h2>10. Security</h2>
<p>We use encryption in transit and limit access to our systems. No method of transmission or storage is completely secure, but we work to protect the information we process.</p>

<h2>11. Changes to this policy</h2>
<p>We may update this policy. When we do, we will change the effective date at the top of this page. Significant changes will also be noted in the app's release notes.</p>

<h2>12. Contact</h2>
<p>Questions or requests about privacy: <a href="mailto:ajaykanani01818@gmail.com">ajaykanani01818@gmail.com</a></p>
</main>''';

const String termsOfUseHtml = r'''<main>
<h1>Terms of use</h1>
<p class="meta">Effective 18 November 2026</p>
<p>These terms apply when you use the Cric Ticker app or this website. By using the app you agree to them. If you do not agree, please do not use the app.</p>

<h2>1. What the app provides</h2>
<p>Cric Ticker shows cricket information such as live scores, commentary, scorecards, fixtures, standings, rankings and player statistics. The app is free and does not require an account.</p>

<h2>2. Accuracy and availability</h2>
<p>Cricket data comes from third-party sources and may be delayed, incomplete or occasionally wrong. Scores labelled live may lag behind the actual match. The app is provided "as is" and "as available"; we do not guarantee that it will always be accurate, complete, uninterrupted or error-free, and coverage of competitions may change.</p>

<h2>3. No betting or gambling use</h2>
<p>Cric Ticker is for information and entertainment only. Do not rely on it for betting, gambling, fantasy contests or any financial decision. We are not responsible for any loss arising from such use.</p>

<h2>4. Not affiliated</h2>
<p>Cric Ticker is independent. It is not affiliated with, endorsed by or sponsored by the ICC, any national cricket board, league, team or player. Team names, logos and other marks belong to their respective owners and are used only to identify teams and competitions.</p>

<h2>5. Acceptable use</h2>
<p>You agree not to:</p>
<ul>
<li>copy, scrape, resell or redistribute the app's data or content;</li>
<li>access or attempt to access our servers or data except through the app as provided;</li>
<li>reverse engineer, decompile or tamper with the app or its network communication, except where the law expressly allows it;</li>
<li>interfere with or overload the service, or use bots or automated tools against it;</li>
<li>use the app for any unlawful purpose.</li>
</ul>

<h2>6. Intellectual property</h2>
<p>The app, its design, code and branding belong to Cric Ticker and are protected by law. We grant you a personal, non-exclusive, non-transferable licence to use the app on your own devices for personal, non-commercial purposes.</p>

<h2>7. Advertising</h2>
<p>The app may show ads from third parties. We are not responsible for the content of third-party ads or the websites they link to.</p>

<h2>8. Limitation of liability</h2>
<p>To the fullest extent permitted by law, Cric Ticker is not liable for any indirect, incidental or consequential loss, or any loss of data, profits or opportunities, arising from your use of or inability to use the app.</p>

<h2>9. Changes and termination</h2>
<p>We may change, suspend or discontinue any part of the app, and we may update these terms. The effective date above shows when they last changed. Continuing to use the app after a change means you accept the updated terms.</p>

<h2>10. Privacy</h2>
<p>How we handle information is described in our <a href="privacy-policy.html">privacy policy</a>.</p>

<h2>11. Contact</h2>
<p>Questions about these terms: <a href="mailto:ajaykanani01818@gmail.com">ajaykanani01818@gmail.com</a></p>
</main>''';
