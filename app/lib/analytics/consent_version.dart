/// The version of the analytics consent text the app shows now
/// (`analyticsConsentBody` and the buttons in `app/l10n/app_*.arb`). Every
/// decision is stored with it, on the device and on the server
/// (`analytics_consents.consent_text_version`), so we can show which text a
/// yes was given under (Art. 7(1) DSGVO). A yes under an older or no version
/// counts as no decision yet: nothing is sent and the app asks again.
///
/// Change the text, change this: a new date, the new DE and EN text in
/// `docs/consent/<version>.md`, and the same value in
/// `supabase/functions/_shared/consent_version.ts`
/// (`test/analytics/consent_version_test.dart` checks both match). Legal Review 2026-11-01,
/// addendum 12:35.
const consentTextVersion = '2026-11-11';
