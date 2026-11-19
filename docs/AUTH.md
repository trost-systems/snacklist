# Sign-in

The app offers four ways in: Google, Apple, email and password, and a magic
link. All of them end in the same Supabase Auth user. After the first sign-in,
the user creates or joins a household as before.

| Method | iOS | Android | Web |
| --- | --- | --- | --- |
| Google | native (GoogleSignIn SDK) → `signInWithIdToken` | native (Credential Manager) → `signInWithIdToken` | OAuth redirect (PKCE) |
| Apple | native (AuthenticationServices) → `signInWithIdToken` | OAuth redirect in the browser, back via deep link | OAuth redirect (PKCE) |
| Email and password, magic link | yes | yes | yes |

A provider's button appears only when the build has its public client
configuration (see "Configuration"). Otherwise the screen shows only email
sign-in.

Research was done on 2026-10-22 against Supabase CLI 2.121.0, GoTrue
v2.197.0, google_sign_in 7.2 (platform interface 3.1), sign_in_with_apple
8.2.0 and supabase_flutter 2.18.3.

## Sources

- Supabase, Login with Google: https://supabase.com/docs/guides/auth/social-login/auth-google
- Supabase, Login with Apple: https://supabase.com/docs/guides/auth/social-login/auth-apple
- Supabase, Identity linking: https://supabase.com/docs/guides/auth/auth-identity-linking
- Supabase, Native mobile deep linking: https://supabase.com/docs/guides/auth/native-mobile-deep-linking
- Supabase, Redirect URLs: https://supabase.com/docs/guides/auth/redirect-urls
- Supabase CLI config reference: https://supabase.com/docs/guides/local-development/cli/config
- GoTrue source, `internal/api/token_oidc.go` and `internal/models/linking.go` at tag v2.197.0: https://github.com/supabase/auth
- Google branding guidelines: https://developers.google.com/identity/branding-guidelines
- Apple Human Interface Guidelines, Sign in with Apple: https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple

## How each flow works

### Native ID token (Google on iOS and Android, Apple on iOS)

1. The app creates a random raw nonce and gives the provider its SHA-256 hex
   digest.
2. The provider's own dialog returns an ID token whose `nonce` claim is that
   digest.
3. The app calls `supabase.auth.signInWithIdToken(provider, idToken, nonce: raw)`.
   GoTrue checks that `sha256(raw)` equals the claim, that `aud` is one of
   the provider's configured client IDs, and the issuer's signature.

Google's plugin takes its nonce in `initialize`, which may run only once per
app process. Google therefore uses one nonce per app run, and Apple uses a
fresh nonce per attempt (`SocialSignIn` in `app/lib/session/social_sign_in.dart`).
The nonce check stays on (`skip_nonce_check = false`). Supabase's docs
suggest skipping it for Google on iOS only because their sample passes no
nonce. We pass one.

The app does not request a Google access token. GoTrue verifies the ID token
alone and checks `at_hash` only when an access token is sent. Skipping it
avoids a second consent sheet.

### OAuth redirect (web, and Apple on Android)

`signInWithOAuth` opens
`https://<project>.supabase.co/auth/v1/authorize?provider=google|apple&redirect_to=<return>&code_challenge=…&code_challenge_method=s256`.
The provider sends the user to Supabase's callback
`https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/callback`. Supabase then
redirects to `redirect_to` with `?code=…`, and supabase_flutter exchanges the
code with the PKCE verifier it stored.

- Web: `redirect_to` is the current origin plus the screen's return path, so
  `/join/<code>` survives the round trip.
- Android: `redirect_to` is `com.snacklist.app://login-callback`,
  registered in `AndroidManifest.xml` and `Info.plist`. Magic links on the
  phones use the same deep link. Hummlist builds use
  `com.hummlist.app://login-callback`, builds from before the Hummlist rename
  (job 20) `com.petertrost.familygroceries://login-callback`, so all three
  stay in the redirect allow list.
- Errors come back as `?error=…&error_description=…`. `access_denied` shows
  "Anmeldung abgebrochen"; anything else shows "Anmeldung fehlgeschlagen: …".
  gotrue's auth stream replays the error, so `SessionCubit` turns it into
  `SignedOut(error)` and the sign-in panel shows it once.

The web app cannot use Google's native flow. google_sign_in on web returns an
ID token only from Google's own rendered button, and `authenticate()` throws.

The app depends on `google_sign_in_platform_interface` and the Android and
iOS implementations, not on the app-facing `google_sign_in` package. That
package also pulls in `google_sign_in_web`, which loads
`accounts.google.com/gsi/client` on every page view, a request to Google that
the web app never needs.

### Apple's name

Apple puts no name in the ID token. The native dialog returns the given and
family name only on the user's very first authorization. The app stores it at
once with `updateUser(data: {full_name, given_name, family_name})`. The
trigger `on_auth_user_metadata_updated` copies `full_name` into
`profiles.display_name`, unless the user already chose a different name.
Google's `full_name` arrives in the user metadata at sign-up and is used the
same way (migration `20261022190526_provider_display_names.sql`). The OAuth
redirect flow (Apple on web and Android) never sees the name, so those users
keep the name derived from their email address.

## Identity linking

Supabase links identities automatically: when a provider reports a
**verified** email that equals an existing user's email, the new identity is
added to that user. The user keeps their id, so they keep their household.
Read from GoTrue's `DetermineAccountLinking` and verified locally (see
"Tests"):

- Email and password first, then Google or Apple with the same address: the
  same user, two identities (`email`, `google`).
- Google or Apple first, then a magic link to the same address: the same
  user.
- Google today and Apple tomorrow with the same address: the same user.
- **Apple "Hide My Email".** Apple then reports `…@privaterelay.appleid.com`,
  which never matches another address. The result is a second, separate
  account. That person can join the household with an invite code, but their
  Google or email account stays separate. To avoid this, choose "Share My
  Email" in Apple's dialog.
- **Unconfirmed password accounts.** If someone registered with email and
  password but never confirmed the mail, a later Google or Apple sign-in with
  that address takes the account over and removes the unconfirmed password.
  This protects against pre-account takeover. Afterwards the user signs in
  with the provider or a magic link.
- Manual linking (`linkIdentity`) stays off (`enable_manual_linking = false`).
  No screen needs it.

The local stack confirms every email automatically, so locally every
provider address counts as verified. The hosted project requires
confirmation, which is the stricter case described above.

## Configuration

Client IDs are public; secrets are not.

| Value | Public? | Where it goes |
| --- | --- | --- |
| Google Web client ID | yes | `app/config/auth.json` (`GOOGLE_WEB_CLIENT_ID`), Supabase Google provider (first client ID) |
| Google iOS client ID | yes | `app/config/auth.json` (`GOOGLE_IOS_CLIENT_ID`, Snacklist's `1001040145655-k035gko9uos1e0co15j71jr8tp18pek9` since job 174), reversed in `app/ios/Flutter/Auth.xcconfig`, Supabase (additional client ID). Hummlist's `1001040145655-q542vlf983lrhjc7oht2mvmcsp4fhie9` stays in Supabase until Hummlist retires |
| Google Android client IDs | yes | only Google Cloud and Supabase (additional client IDs); Android finds them by package name and SHA-1. Snacklist (`com.snacklist.app`): Play app signing `1001040145655-raog296lceu901h72e852e10kt75a7e2`, upload key `1001040145655-q9q9t08ugkv4fr117j01qck0ijobb3ck`, box debug `1001040145655-l88umh5facf1anqmqtpv7mtbtaukqe61`. Hummlist's clients stay |
| Google Web client secret | **no** | Supabase only (dashboard or `scripts/configure-social-auth.mjs`) |
| Apple Services ID | yes | Supabase Apple provider (first client ID) |
| Bundle ID `com.snacklist.app` | yes | Supabase Apple provider (in the client ID list; hosted since the Snacklist cut-over, S2, checked 2026-11-11 in job 183) |
| Bundle ID `com.hummlist.app` | yes | Supabase Apple provider (in the client ID list) until Hummlist retires |
| Old bundle ID `com.petertrost.familygroceries` | yes | Supabase Apple provider (in the client ID list) until the Hummlist build is verified (`NEEDS_PETER.md`, job 20) |
| Apple Team ID, Key ID | yes | inputs to the client secret |
| Apple Sign in with Apple key (`.p8`) | **no** | stays on Peter's machine; never in the repo |
| Apple client secret (JWT from the `.p8`) | **no** | Supabase only; expires after at most 6 months |
| `SIGN_IN_WITH_APPLE` | yes | `app/config/auth.json`, `"true"` once Apple is set up in Supabase |
| `APP_URL` | yes | `app/config/auth.json`, the web app origin for the phone apps' invite links: `https://app.snacklist.app` since job 174 (`https://app.hummlist.com` from job 20 on; `supabase/deploy/auth_urls.ts` allows both hosts) |

Release builds read the app values with
`flutter build … --dart-define-from-file=config/auth.json`. Only
`app/lib/core/environment.dart` reads them. An empty value hides the button.
A unit test (`test/core/auth_config_test.dart`) fails when `Auth.xcconfig`
does not hold the reversed `GOOGLE_IOS_CLIENT_ID`.

`supabase/config.toml` has `[auth.external.google]` and `[auth.external.apple]`
with `env(SUPABASE_AUTH_EXTERNAL_*)` references and `enabled = false`. To try
a real provider against the local stack, export the variables from
`.env.example` and set `enabled = true` locally.

The hosted project is configured with `scripts/configure-social-auth.mjs`.
`GOOGLE_IOS_CLIENT_ID` and `GOOGLE_ANDROID_CLIENT_ID` take comma lists:
while Hummlist and Snacklist both run (job 174), pass both apps' clients,
or the script drops the ones it isn't given.
It reads the values from the environment, enables a provider only when all of
its credentials are present, generates Apple's client secret from the `.p8`
key, and always makes sure the deep links of all three bundle IDs are in the
redirect allow list. Apple's client IDs go into `external_apple_client_id` as
one comma list, the Services ID first (the web flow signs in as the first
ID), then the bundle IDs; `external_apple_additional_client_ids` stays empty.
That is the hosted state since job 20. Since job 174 the hosted redirect allow
list also holds `com.snacklist.app://login-callback` and
`https://app.snacklist.app/**`, and the Google provider holds Snacklist's iOS
client (set by the lead on 2026-11-10). `com.snacklist.app` is in the
Apple client ID list (S2; read back from the hosted auth config on
2026-11-11, job 183). The hosted Site URL is
`https://app.snacklist.app` since 2026-11-10 (before that `https://app.hummlist.com`); the allow list also keeps
`https://family-groceries-pied.vercel.app/**` (the old Vercel URL, still an
alias) and the preview pattern, and neither script removes an entry.
On 2026-10-22 it ran once with no provider credentials. It added
`com.petertrost.familygroceries://login-callback` to the allow list; Google
and Apple stay disabled.

### Mail language

Supabase Auth sends the confirm, magic link, reset, email change, invite and
reauthentication mails from `"Peter · Snacklist" <hello@snacklist.app>`
(Auth SMTP through Resend). Each mail is German or English by the account's
`user_metadata.mail_locale`:

- The app saves `mail_locale` (`de` or `en`, the language it shows: the one
  picked under Einstellungen, else the device's, German for any other) with
  every sign-up and magic link (`signUp`/`signInWithOtp` `data`), so the
  first mail is already in that language. A magic link to an existing
  account doesn't change its saved language.
- `app/lib/session/mail_language.dart` keeps it in sync: on start (on the
  web, on load), on resume, on a sign-in and on a language pick it compares
  the language the app shows with the saved one and calls `updateUser` only
  when they differ. A failure is logged and retried at the next trigger; it
  never blocks the UI.
- `supabase/templates/*.html` and the `[auth.email.template.*]` subjects in
  `supabase/config.toml` branch on it: German when `mail_locale` is `de`,
  English otherwise (accounts from before 2026-11-10 until their app syncs,
  and accounts made outside the app). Subjects are Go templates with the
  same data as the body, so they branch too. The `with .Data` guard keeps an
  account without metadata on English instead of a template error.
  Both are built from `emails/` (`cd emails && npm run build`, docs/EMAIL.md):
  each language's mail in the Snacklist design, joined under this pick. Edit
  the words in `emails/src/emails/auth.tsx`, not in the built files.
- The local stack reads them from `config.toml`. Production gets them from
  `supabase/deploy/auth_mail.ts` (Management API, converges, `--dry-run`
  lists the keys that would change), with `SUPABASE_ACCESS_TOKEN` and
  `SUPABASE_PROJECT_REF` set:
  `deno run --allow-read --allow-env --allow-net --config supabase/deploy/deno.json supabase/deploy/auth_mail.ts`.
  Run it after a merge that changes a template; the deploy workflow doesn't.
  It refuses a template that still holds a draft line (`data-hl-draft`).
- Notification mails (password changed etc.) are off in production. Their
  built templates keep Supabase's English and add a German draft.

### Platform setup in the repo

- iOS: `Runner.entitlements` with `com.apple.developer.applesignin`
  (`CODE_SIGN_ENTITLEMENTS` in all three Runner configurations).
  `Info.plist` has two URL types, the auth deep link and
  `$(GOOGLE_REVERSED_CLIENT_ID)` from `Flutter/Auth.xcconfig`.
- Android: an intent filter for
  `com.snacklist.app://login-callback`. No SHA fingerprint is
  in code. Google matches the app by package name and the signing
  certificate's SHA-1 registered on the Android OAuth client (see
  `NEEDS_PETER.md`, section 4).

## Buttons

- Google: Google's light or dark theme (fill `#FFFFFF` / stroke `#747775` /
  text `#1F1F1F`, or `#131314` / `#8E918F` / `#E3E3E3`), pill shape, the
  standard "G" taken from Google's 2026 asset kit
  (`signin-assets.zip`, rendered to `app/assets/google_g.png` at 1x, 2x and
  3x), Google Sans Medium 14/20 with Roboto as the fallback font, label
  "Mit Google anmelden".
- Apple: sign_in_with_apple's `SignInWithAppleButton`, which draws Apple's
  logo and sizes the title to Apple's 43 % rule. Black on light, white on
  dark, same height (44) and pill radius as the Google button, label
  "Mit Apple anmelden".
- Google's German guideline page prefers „Über Google anmelden“. The brief
  asked for „Mit Google anmelden“, which Google's guidelines allow as a
  localization, so the app uses that.
- App Store guideline 4.8 requires Sign in with Apple whenever Google
  sign-in is offered on iOS. Configure both before an iOS release.

## Reusable sign-in panel (job 3)

`SignInPanel(returnPath: …)` in `app/lib/session/login_screen.dart` contains
every method: the Google and Apple buttons, email and password, and the magic
link. `LoginScreen` is just an app bar around it. **The MCP OAuth consent page
(job 3) must embed `SignInPanel`** with `returnPath` set to the consent URL
including its query (for example `/oauth/consent?authorization_id=…`), so that
a Google or Apple redirect or a magic link lands back on the consent screen.
It needs the `SessionCubit` and `SocialSignIn` providers that `App` already
supplies. Add the consent origin to the hosted redirect allow list together
with the web app URL.

## Tests

- Unit tests (`app/test/session/social_sign_in_test.dart`): which flow each
  platform gets, and no button when unconfigured. The provider gets
  `sha256(raw)` and `signInWithIdToken` gets `raw` with the right provider.
  Google keeps its nonce and Apple's changes. Apple's name is stored once.
  Cancel and errors propagate. The redirect flow launches with the return URL.
- Widget tests (`app/test/session/login_screen_test.dart`): the buttons shown
  for each configuration, sign-in through each button, and the German cancel
  and error messages, including errors from a redirect return.
- pgTAP (`supabase/tests/profiles.test.sql`): display names from Google and
  Apple metadata, and a chosen name surviving.
- Integration against the local stack (`e2e/tests/id-token.spec.ts`).
  GoTrue's Google and Apple issuers are hard-coded, so no local test can
  present a real Google or Apple token. Its `keycloak` provider accepts any
  issuer and runs the same ID-token grant: signature, audience, nonce and
  account linking. `e2e/fake-oidc.mjs` is that issuer (discovery, JWKS,
  authorize, token, userinfo, plus `POST /mint` for test tokens). Its key
  comes from a fixed seed, so every copy is interchangeable.
  `supabase/config.toml` enables `[auth.external.keycloak]` pointing at it
  through `host.docker.internal:54399`. Playwright starts the fake on the
  port in that URL (`e2e/stack.ts`), so a checkout on another port block
  sets it to `<prefix>99`. **Never enable this provider on the
  hosted project.** The tests cover a matching nonce, a wrong or missing
  nonce, a foreign audience, linking to an existing password account with its
  household, provider first then magic link, and two provider sign-ins with
  one email.
- Playwright on Flutter web (`e2e/tests/social-sign-in.spec.ts`): all methods
  are shown. Each button starts the PKCE redirect to
  `/auth/v1/authorize?provider=google|apple` with the right `redirect_to`,
  and an invite path survives it. A full redirect round trip runs with only
  the provider name swapped to the fake at the network edge: a new user goes
  through household onboarding, the same email lands in the existing
  household, and canceling shows "Anmeldung abgebrochen".
- Manual, once the credentials exist: real Google and Apple on an iPhone, an
  Android phone and the hosted web app (`NEEDS_PETER.md`, section 4, last
  step).
