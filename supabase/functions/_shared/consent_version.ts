// The analytics consent text version the app shows now: the same value as consentTextVersion in
// app/lib/analytics/consent_version.dart (app/test/analytics/consent_version_test.dart checks it), the texts in
// docs/consent/<version>.md. A server event (Alexa add, purchase, voice, integration lock) goes
// out only while the user's newest answer is a yes to this version (Legal Review 2026-11-01,
// addendum 12:35; migration 20261101123500_consent_text_version.sql).
export const CONSENT_TEXT_VERSION = '2026-11-18';

/**
 * The versions a yes counts under for the server's own events: only the current one. The policy
 * promises to send nothing after a notice that names new data until the user answers again
 * (§9), so a yes under 2026-11-10 or Hummlist's 2026-11-01 no longer counts (job 178, Legal N-125),
 * nor one under 2026-11-11, which did not name the Siri events (Legal N-146), nor one under
 * 2026-11-14, which did not name connected apps, MCP or API keys (Legal N-251).
 */
export const CURRENT_CONSENT_TEXT_VERSIONS: readonly string[] = [CONSENT_TEXT_VERSION];
