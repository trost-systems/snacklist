# Sign-in

A user signs in with email and password, creates an account with "Registrieren", or asks for a sign-in link by email ("Anmeldelink per E-Mail senden"). A signed-out app opens on the start screen (`start-screen`: „Los geht's“, „Ich habe schon ein Konto“, and in fg's flag-off app „Einladung einfügen“); the login screen comes from „Ich habe schon ein Konto“, after a sign-out or an account deletion, and for an invite or a `next` link. Signing out from the More tab returns to the login screen.

## Sub-features

- `auth-password` signs in with email and password and lands on the list (or on the welcome screen without a household).
- `auth-wrong-password` keeps the user on the login screen with an error snackbar.
- `auth-signup` creates an account. Locally, email confirmation is off, so the user lands on the welcome screen.
- `auth-magic-send` sends a sign-in link and shows "Wir haben dir einen Anmeldelink geschickt. Öffne ihn auf diesem Gerät."
- `auth-magic-open` signs the user in when the link is opened on the device.
- `auth-signout` signs out from the More tab ("Mehr", then "Abmelden", key `more-sign-out`) or from the logout icon (tooltip "Abmelden") on the welcome screen and on the analytics question (builds with a PostHog key only).
- `auth-session` keeps the user signed in across an app restart.
- `auth-form-check` refuses to send an email without "@" ("Bitte eine gültige E-Mail-Adresse eingeben") or a password under 6 characters ("Mindestens 6 Zeichen"), under the fields.
- `auth-legal` shows "Impressum · Datenschutz" ("Imprint · Privacy" in English; keys `legal-imprint`, `legal-privacy`) at the bottom of the login screen, on screen without scrolling. Each opens snacklist.app (`/impressum`, `/datenschutz`; English `/en/imprint`, `/en/privacy`) in the browser, never inside the app.
- `auth-providers` shows "Mit Google anmelden" (key `sign-in-google`) and "Mit Apple anmelden" (key `sign-in-apple`) and "Weiter mit E-Mail" (key `sign-in-email`, opens the form under the divider "oder mit E-Mail") in builds that configure them; the linux build configures none and shows the form at once. No field is focused on open, and a provider tap closes the keyboard (job 70). They redirect to the provider and back to the page the user started from, link an existing account with the same email, and a cancel shows "Anmeldung abgebrochen".

## How to get to it (user POV)

- Open the app signed out: the start screen; tap „Ich habe schon ein Konto“ (`start-log-in`). The login screen opens on the Snacklist brand block (the app icon and the wordmark, no title bar since job 57) and shows email and password fields (hex fields since job 57; a focused field gets a cobalt contour and a ring) and, on Linux, the email form open at once with five buttons: „Anmelden“, „Registrieren“, „Anmeldelink per E-Mail senden“, „Neu bei Snacklist? Los geht's“ (`login-new`, without an invite or `next`) and „Einladung einfügen“ (`invite-paste`, fg's flag-off app); the provider buttons, both 48 px with 15 px labels, show only in builds with their defines. The legal footer is on the start screen and the guided start's account step too.
- Signed in: tap "Mehr" in the tab bar, scroll down and tap "Abmelden".
- Open the sign-in email on the phone and tap its link.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`. The lea client is signed out: `fg logout --client lea`.

- **Password sign-in.** Run `fg login lea`. It types into `login-email` and `login-password` and presses Enter. The result is `"screen": "list"` (the list names no household since job 29a; `fg db query "select h.name from household_members m join households h on h.id = m.household_id join auth.users u on u.id = m.user_id where u.email = 'lea@fg.test'"` returns "Familie Test").
- **Legal links.** Signed out, `fg find --key legal-imprint --client lea` and `fg find --key legal-privacy --client lea` each return one element; `fg screenshot --name auth-legal --client lea`. `fg tap --key legal-privacy --client lea` hands https://snacklist.app/datenschutz to the desktop (`pgrep -af snacklist.app/datenschutz`; stop that browser with `kill <pid>`), and the app stays on the login. On the web the e2e spec `e2e/tests/legal.spec.ts` checks the hrefs and the new tab.
- **Wrong password.** Sign out, then run `fg type --key login-email --input lea@fg.test --client lea`, `fg type --key login-password --input falsch123 --submit --client lea` and `fg wait --contains "Anmeldung fehlgeschlagen" --client lea`. `fg find --key login-email --client lea` still returns one element.
- **Form checks.** Signed out, run `fg type --key login-email --input foo --client lea` and `fg type --key login-password --input 123 --submit --client lea`. `fg screenshot --name auth-form-check --client lea` shows both messages under the fields, and the client stays on the login screen.
- **Sign-up.** Run `fg type --key login-email --input neu-$(date +%s)@fg.test --client lea`, `fg type --key login-password --input test-password-123 --client lea` and `fg tap --text Registrieren --client lea`. Then `fg wait --key welcome --client lea` succeeds: onboarding Step 1 of a user without a household (`features/onboarding.md`).
- **Magic link, send.** Sign out, then run `fg type --key login-email --input lea@fg.test --client lea` and `fg tap --text "Anmeldelink per E-Mail senden" --client lea`. `fg wait --contains "Anmeldelink geschickt" --client lea` succeeds. `fg mail --to lea --limit 1` shows the subject „Dein Anmeldelink für Snacklist“ (German account language, `user_metadata.mail_locale` `de`) or "Your Snacklist sign-in link" (otherwise) and one `/auth/v1/verify?...type=magiclink&redirect_to=com.snacklist.app://login-callback` link. The local allow list (`supabase/config.toml`) and the hosted one both hold that callback since job 174, so GoTrue keeps it.
- **Magic link, open.** Android only: run `adb -s <serial from fg env> shell am start -a android.intent.action.VIEW -d "<link with 127.0.0.1 replaced by 10.0.2.2>"`, then `fg wait --key add-item-field`. On linux, report `auth-magic-open` as not drivable (see Gotchas).
- **Sign-out.** Run `fg logout --client lea`: it taps `tab-more`, scrolls to `more-sign-out` and taps it. It waits for the start screen a sign-out lands on (`start-log-in`, job 486), taps „Ich habe schon ein Konto“ and returns `"screen": "login", "landedOn": "start"`. By hand: `fg tap --key tab-more --client lea`, `fg wait --key more-screen --client lea`, `fg marionette --client lea -- scroll-to --key more-sign-out`, `fg tap --key more-sign-out --client lea`, `fg wait --key start-log-in --client lea`. From the welcome screen (after **Sign-up**), run `fg tap --tooltip Abmelden --client lea` and `fg wait --key start-log-in --client lea`.
- **Session survives restart.** Sign in with `fg login lea`, then run `fg restart --client lea`, then `fg wait --key add-item-field --client lea`.
- **Provider buttons.** Not drivable with fg: every fg build leaves the provider defines unset, and the Linux app has no Google or Apple flow at all, so it never shows the buttons, defines or not. Run `scripts/gates/e2e.sh --workers=1 tests/social-sign-in.spec.ts` (it builds the web app with `app/config/e2e.json` and signs in through a fake OpenID provider). A real Google or Apple round trip needs a real account; `features/web-hosting.md` reaches the providers' pages from production.
- **Proof.** Take `fg screenshot --name auth-<sub-feature>` after each step, and record the mail with `fg mail --to lea > $(fg env | jq -r .evidenceDir)/auth-magic-mail.json`.

## Gotchas

- `fg find` and `fg wait` don't see the form's error messages under the fields. Prove them with a screenshot.
- Builds with a PostHog key (Vercel, the stores, the web e2e build) ask about analytics right after the first sign-in on a device, before onboarding or the list (`features/analytics.md`, `an-consent`). fg builds have no key and go straight on.
- Since job 57 the login screen has no "Anmelden" title, so `fg tap --text Anmelden` hits the button; Enter in the password field (`--submit`) or `fg login` work as before.
- `fg login` fails with `not_on_login` when the app is already signed in. Sign out first.
- The magic link redirects to `com.snacklist.app://login-callback` (job 174; Hummlist builds use `com.hummlist.app://login-callback`, builds from before the Hummlist rename use `com.petertrost.familygroceries://login-callback`; all three are in the local and the hosted allow list). The Linux desktop build registers no handler for that scheme, so opening the link cannot sign it in. Android handles the scheme (intent filter). The web build uses an http redirect instead: `e2e/tests/auth.spec.ts` "magic link signs in on this device" covers it in CI.
- The local stack's links point at `127.0.0.1:<prefix>21`. The emulator reaches that as `10.0.2.2:<prefix>21`.
- Sign-up users from these recipes stay in the database until `fg up --fresh`. They do not affect peter or lea.
- After `fg seed`, a running app keeps a session for a deleted user. The next `fg up` relaunches every app started before the seed, signed out; then `fg login` again.
