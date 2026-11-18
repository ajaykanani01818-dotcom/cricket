/// Offline copy of the privacy policy — ported verbatim from RN
/// `src/constants/privacyPolicyHtml.ts`. Rendered natively by [parseSimpleHtml]
/// (no WebView). Keep roughly in sync with https://crickbex.com/privacy-policy.
const String privacyPolicyHtml = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
<title>Privacy Policy — CrickBex</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 20px 20px 40px;
    background: #F8FAFC;
    color: #0F172A;
    font-family: -apple-system, Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.6;
  }
  h1 {
    font-size: 20px;
    font-weight: 800;
    margin: 0 0 4px;
    color: #0F172A;
  }
  .updated {
    font-size: 12px;
    color: #94A3B8;
    margin-bottom: 24px;
  }
  h2 {
    font-size: 15px;
    font-weight: 800;
    margin: 24px 0 8px;
    color: #0F172A;
  }
  p {
    font-size: 14px;
    color: #475569;
    margin: 0 0 8px;
  }
</style>
</head>
<body>
  <h1>Privacy Policy</h1>
  <div class="updated">Last updated: July 2026</div>

  <h2>1. Overview</h2>
  <p>CrickBex ("the app") provides cricket information: live scores, match details, series, rankings, and players. This policy describes how the app handles information. By using the app, you agree to this Privacy Policy.</p>

  <h2>2. App permissions</h2>
  <p>Internet – To load live scores, match details, series, rankings, players, and to show ads. Required for the app to function.</p>
  <p>Advertising ID – Used by Google Mobile Ads (AdMob) for ad delivery, frequency capping, and measurement. You can limit or reset ad personalization in your device settings.</p>
  <p>We do not request camera, microphone, contacts, or media storage.</p>

  <h2>3. What data we collect</h2>
  <p>The app itself does not create an account for you, does not track a visitor or device ID, and does not send your location or device information to us. We do not collect your name, email, or phone number unless you contact us directly.</p>
  <p>Advertising: The app shows ads via Google Mobile Ads (AdMob). AdMob may collect data for ad delivery, analytics, and fraud prevention, in accordance with its own privacy policy. We do not use your cricket or match activity for ad targeting.</p>

  <h2>4. Third-party services</h2>
  <p>Google Mobile Ads (AdMob) – In-app advertising. Privacy: https://policies.google.com/technologies/ads</p>
  <p>Google Play – App distribution and updates. Privacy: https://policies.google.com/privacy</p>
  <p>The app also fetches public cricket data (scores, series, rankings, players) from our data provider to display within the app.</p>

  <h2>5. Local storage on your device</h2>
  <p>Some preferences (such as favorites, onboarding status, and the "no ads for 30 minutes" reward) are stored only on your device and are not sent to us. This data is cleared when you clear app data or uninstall the app.</p>

  <h2>6. Children's privacy</h2>
  <p>CrickBex is not directed at users under 13. We do not knowingly collect personal information from children under 13.</p>

  <h2>7. Changes to this policy</h2>
  <p>We may update this policy from time to time. The "Last updated" date above will be revised when we do. Continued use of the app after changes means you accept the updated policy.</p>

  <h2>8. Contact</h2>
  <p>Questions about this policy? Contact us via the Contact Us page in this app.</p>
</body>
</html>''';
