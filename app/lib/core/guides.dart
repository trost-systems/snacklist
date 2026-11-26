import 'package:family_groceries/core/environment.dart';

/// The public site, snacklist.app (`site/` in this repo). Its guides open
/// in the app (`core/deep_links.dart`, `guides/`); the pages below open in
/// the system browser (`openLegalPage`), so none of them may be claimed:
/// on Android a claimed URL would come straight back to the app.
const guidesBaseUrl = 'https://snacklist.app';

/// The imprint on snacklist.app (`site/content/legal/`), German or English.
Uri imprintUrl(String languageCode) => Uri.parse(
  languageCode == 'de'
      ? '$guidesBaseUrl/impressum'
      : '$guidesBaseUrl/en/imprint',
);

/// The privacy policy on snacklist.app (`site/content/legal/`), German or
/// English. Every privacy link in the app goes here.
Uri privacyPolicyUrl(String languageCode) => Uri.parse(
  languageCode == 'de'
      ? '$guidesBaseUrl/datenschutz'
      : '$guidesBaseUrl/en/privacy',
);

/// The terms of use on snacklist.app (`site/content/legal/`), German or
/// English. Every terms link in the app goes here, on every platform.
Uri termsUrl(String languageCode) => Uri.parse(
  languageCode == 'de'
      ? '$guidesBaseUrl/nutzungsbedingungen'
      : '$guidesBaseUrl/en/terms',
);

/// Whether the help and contact page is live on snacklist.app. Peter
/// approved its text on 2026-10-30, so `site/content/legal/support.md` and
/// `support-en.md` are no longer drafts (docs/NEEDS_PETER.md, Job 24).
/// Taking the page down again means setting this back to false together
/// with `draft: true` there and `supportPublished` in `site/config.json`.
const supportPagePublished = true;

/// More shows "Hilfe & Kontakt" once the page is published, and before
/// that only where drafts are wanted ([Environment.legalDrafts]).
const supportLinkShown = supportPagePublished || Environment.legalDrafts;

/// The help and contact page on snacklist.app, German or English.
Uri supportUrl(String languageCode) => Uri.parse(
  languageCode == 'de' ? '$guidesBaseUrl/support' : '$guidesBaseUrl/en/support',
);

/// The public changelog on snacklist.app at [version]'s entry (job 268),
/// German or English: `1.4.1` is the anchor `v1-4-1`.
Uri changelogUrl(String languageCode, String version) => Uri.parse(
  '$guidesBaseUrl/${languageCode == 'de' ? 'de' : 'en'}/changelog'
  '#v${version.replaceAll('.', '-')}',
);
