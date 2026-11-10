# Analytics consent

Builds that carry an analytics key (the web app, TestFlight and Play builds) ask once per install: as the first step of the guided start (after „Los geht's“ on the start screen, before the account), or, for someone who signs in without it, right after the first sign-in and before onboarding or the list: „Darf Snacklist Nutzungsdaten erfassen?“ / "May Snacklist collect usage data?" Two equal buttons answer it. A no sends nothing and stores no analytics ID on the device; a yes sends pseudonymous usage data and error reports to PostHog (EU servers). The answer can be changed any time under More → Nutzungsdaten.

## Sub-features

- `guided-start-step` signed out, „Los geht's“ opens the question as step 1 of the guided start (`/start/usage`; its title bar shows only the counter „Schritt 1 von 7“, no title „Nutzungsdaten“), the same words and buttons as below (`ConsentQuestion`), with the guided start's X instead of the logout icon. The answer is stored on the device at once and moves on to „Mit wem kaufst du ein?“; the server learns it at the sign-in, and after a yes `first_open` goes at the sign-in too. Nothing else is sent before the account. An install that already answered skips the step.
- `ask` the consent screen (`/analytics-consent`, for a sign-in that did not pass the guided start; app bar title „Nutzungsdaten“ / "Usage data", logout icon with tooltip „Abmelden“): heading „Darf Snacklist Nutzungsdaten erfassen?“ / "May Snacklist collect usage data?", the body below, a link „Datenschutzerklärung“ / "privacy policy" (opens the privacy page of snacklist.app in the app's language) and the two buttons „Nicht erlauben“ / "Don't allow" and „Erlauben“ / "Allow".
- `nothing-on-top` no snackbar shows over the question: a removed person's notice found at the same sign-in (household-invites `removed-notice`) waits until after the answer, so both answers stay uncovered (job 178, review 1).
- `decline` „Nicht erlauben“: no events, no error reports, no ID stored; onboarding or the list works the same.
- `accept` „Erlauben“: events and error reports go out; the decision is stored with the version of the text it was given under.
- `change-later` More tab → „Nutzungsdaten“ / "Usage data" (`/more/usage-data`, job 85), switch „Nutzungsdaten und Fehlerberichte senden“ / "Send usage data and error reports", hint „Pseudonym an PostHog (Server in der EU), ohne Listeninhalte. Gilt für dieses Gerät. Ausschalten löscht die Kennung auf diesem Gerät.“ / "Pseudonymous, to PostHog (servers in the EU), never list contents. Applies to this device. Turning it off deletes the ID on this device."
- `asked-again` a yes given under an older version of the text (or without a version, from an older build) counts as no decision: the app deletes the analytics ID, sends nothing and asks again (current version 2026-11-11, job 178: the 2026-11-10 text, itself the 2026-11-01 text with the name Snacklist, plus examples of the usage data; the server still counts a yes under 2026-11-10 and under 2026-11-01 from Hummlist builds for its own events, jobs 174 and 178). A no stays a no.
- `server-record` each install's answer and its text version are also stored on the server, so events the server sends (an add over Siri or Alexa, for example) follow the same answer.

## How to get to it (user POV)

- Signed out on a new device: „Los geht's“ on the start screen; the question is the first step.
- Or right after the first sign-in or sign-up on a device (from „Schon ein Konto? Anmelden“, an invite link or a link to a screen): the question appears before „Willkommen bei Snacklist“ and before the list.
- Later: tab „Mehr“ / "More" → „Nutzungsdaten“ / "Usage data" → the switch. This is the path the consent text names.
- The privacy page: the link „Datenschutzerklärung“ / "privacy policy" in the question, or More → „Datenschutzerklärung“ / "Privacy policy" (under the heading „Rechtliches“ / "Legal").

Exact text (DE, never paraphrase): „Snacklist (Anbieter: Peter Trost) möchte verstehen, welche Funktionen genutzt werden, Fehler finden, messen, ob sich Snacklist trägt, und neue Funktionen schrittweise freischalten. Dafür speichert Snacklist eine zufällige Kennung auf diesem Gerät und sendet damit pseudonyme Nutzungsdaten (etwa zu Einträgen, Haushalten und der Einrichtung und welche Tipps du siehst), Fehlerberichte, die Kennung deines Haushalts und technische Angaben zu Gerät oder Browser an unseren Dienstleister PostHog (Server in der EU). Listeninhalte, Namen und E-Mail-Adressen werden nie gesendet. Du kannst jederzeit unter Mehr → Nutzungsdaten widerrufen. Mehr in der Datenschutzerklärung.“

Exact text (EN): "Snacklist (run by Peter Trost) wants to see which features are used, find bugs, measure whether Snacklist pays for itself and switch new features on step by step. For that, Snacklist stores a random ID on this device and uses it to send pseudonymous usage data (for example about items, households and setup, and which tips you see), error reports, your household's ID and technical details of your device or browser to our service provider PostHog (servers in the EU). List contents, names and e-mail addresses are never sent. You can withdraw any time under More → Usage data. More in the privacy policy."

## Driving it with Playwright

Preconditions:

- Local stack and the verify-snacklist or e2e web build (both carry a stand-in analytics key, host `https://posthog.invalid`, so the question shows). The answer is stored per browser profile, not per account, and no seed records one: every new browser context is asked. The verify-snacklist `signIn` helper declines it; to stop on the question, sign in or sign up by hand.
- Fresh email via `newEmail(...)`.

- **See the question.** `signUp(page, email, '/', { consent: 'decline' })` ends by answering; to stop on the screen, do the sign-up steps by hand: `openEmailSignIn(page)`, `typeInto` the textboxes „E-Mail“ and „Passwort“, click button „Registrieren“. Observable result: URL `/analytics-consent`, `page.getByRole('heading', { name: 'Nutzungsdaten', exact: true })` (the bar title, also on More's page) and the question `page.getByText('Darf Snacklist Nutzungsdaten erfassen?')` visible, buttons `page.getByRole('button', { name: 'Nicht erlauben', exact: true })` and `{ name: 'Erlauben', exact: true }`.
- **See it in the guided start.** New context, `page.goto('/')`, `page.getByRole('button', { name: "Los geht's", exact: true }).click()`. Observable result: URL `/start/usage`, the bar's heading „Schritt 1 von 7“ (no heading „Nutzungsdaten“ here), the question „Darf Snacklist Nutzungsdaten erfassen?“, the same two buttons (wheel down on a short screen). „Nicht erlauben“ goes to `/start/who`; a later sign-up on the account step shows no `/analytics-consent`. `answerConsent` waits for `/analytics-consent`, so click the button directly here (`e2e/tests/guided-start.spec.ts`, `letsGo`).
- **Answer.** `answerConsent(page, 'decline' | 'accept')`; it scrolls on short screens and phones. Observable result: URL leaves `/analytics-consent`; on a no, no request reaches the collector and no install ID is stored (localStorage keeps only the no and its text version, and the server notes the no); on a yes, a `first_open` event reaches the fake collector (the spec captures it), and localStorage holds `analytics.consent = true` and `analytics.consent_text_version = "2026-11-10"` (2026-11-01 when driven on 2026-11-04 after a sign-up; job 174 moved it).
- **Asked again.** After a yes, set the localStorage value ending in `analytics.consent_text_version` to `"2026-10-30"` and reload. Observable result: URL `/analytics-consent` again, nothing sent to the collector before the new yes.
- **Change later.** `openMore(page, 'Nutzungsdaten')` (URL `/more/usage-data`), then the switch `page.getByRole('switch', { name: /^Nutzungsdaten und Fehlerberichte senden/ })` (the spec also accepts `getByRole('checkbox', ...)` for some engines). Observable result: turning it off stops sending at once.
- **Privacy link.** `page.getByRole('link', { name: 'Datenschutzerklärung', exact: true })` has href `https://snacklist.app/datenschutz` (EN „privacy policy“: `https://snacklist.app/en/privacy`) and opens in a new tab (driven 2026-11-06).
- Covered by `e2e/tests/analytics.spec.ts` (order sign-in, consent, onboarding; declined sends nothing; accepted sends `first_open` once; English text; older version or no version asked again; invite link through consent), `e2e/tests/onboarding.spec.ts`, `e2e/tests/alexa.spec.ts` ("the app records each install's analytics answer for server events (AC10)"). Run via `scripts/verify.sh --only e2e -- tests/analytics.spec.ts`.

## Gotchas

- The question appears only in builds with an analytics key. Local fg/Linux builds and builds without a key never ask and have no „Nutzungsdaten“ row on Mehr.
- One answer per install, wherever it was given: the guided start's step and the consent screen are the same question, so a device never sees both.
- Asked once per install: an existing user on a new install is asked once, then goes to the list (spec "a member with a household is asked once on a new install"). Sign-out keeps the answer on the device, so a second account signing in on an already answered install is not asked again (from code: sign-out leaves the `analytics.*` keys alone).
- A browser tab authorizing an AI assistant (MCP consent) is not interrupted by the question; the app asks the next time it opens.
- A yes under an older consent text version is treated as no decision (nothing is sent until the new yes). The current version is 2026-11-11 (job 178; 2026-11-10 since job 174).
- Legal text: quoted from the German and English ARB strings; do not edit or paraphrase.
- Analytics never carry list text, names or emails; the household's ID is sent after a yes.
