# Needs Peter

Steps that cannot be done from the build box. Everything around them is
implemented.

## Status (checked 2026-10-24, job 7b)

Done from the box (details in the sections below):

- Remote project `jdwqrallbpdbshrdhenk`: all migrations applied, edge
  functions `health`, `mcp` and `voice` deployed, Google and Apple sign-in
  enabled. The "Supabase deploy" workflow redeploys from every push to
  `main` over the Management API and fails red when a credential is
  missing (section 1).
- Web app on Vercel at `https://app.snacklist.app` (job 174; `https://app.hummlist.com`
  since job 20 and `https://family-groceries-pied.vercel.app` still serve it as aliases), moved
  only by a store release since 2026-10-29; `main` is on
  `https://preview.app.hummlist.com` behind Vercel login (section "Job 7: web
  hosting on Vercel", `DEPLOY.md` section "Web app"). Site URL,
  redirect URLs and the OAuth consent path point at it (section 2).
- `app/config/auth.json` and `app/ios/Flutter/Auth.xcconfig` carry the real
  client IDs and the app URL (section 4, step 15).

Still yours:

- Section 4, step 7: done for Snacklist. `com.snacklist.app` has Android
  OAuth clients for the Play app signing key, the upload key and the box's
  debug key (`AUTH.md`, "Configuration", 2026-11-10). Still yours: try
  "Mit Google anmelden" in the Play internal build on a phone; no test on
  this side reaches the Play-signed app (job 183, 2026-11-11).
- Section 4, step 13: renew the Apple client secret before it expires
  (set up on 2026-10-23 per the board, valid 180 days, so renew by
  2027-04-21 at the latest).
- Section 4, steps 16 and 18: the Xcode capability check and trying
  sign-in on your phones.
- Section 5, step 1: one MCP connect and disconnect against production.
- "Job 4: Siri", step 2. Releases (jobs 23, 30): every green merge to `main`
  goes to TestFlight group "Familie" and to the Play internal track (list
  "Familie") by itself.
  Yours: "Job 23" below. Also "Job 5: Android verification run".
- "Job 13: database backups": done (job 13b). Copy the backup private key
  from the build box to your own computer and password manager (section
  "Job 13: database backups").
  Also watch the repository's issues (Watch, Custom, Issues): a failed
  daily keepalive opens one there (docs/DEPLOY.md, "Keepalive").

None of the steps below changes the hosted Site URL or removes a redirect
URL. Only `supabase/deploy/auth_urls.ts` sets the Site URL (section 2).

## 1. Remote Supabase deploy (job 1)

Done (job 7). The repo has the secret `SUPABASE_ACCESS_TOKEN` and the
variable `SUPABASE_PROJECT_REF`. The workflow applies migrations through
the Management API (`supabase/deploy/migrate.ts`), deploys the functions
with `supabase functions deploy --use-api` and smoke-tests them; it needs
no database password and no direct Postgres connection. From any machine:

```bash
set -a; source ~/groceries-ops/env; set +a
export SUPABASE_PROJECT_REF=jdwqrallbpdbshrdhenk
deno run --allow-read --allow-env --allow-net --config supabase/deploy/deno.json supabase/deploy/migrate.ts
supabase functions deploy --use-api --project-ref "$SUPABASE_PROJECT_REF"
```

## 2. Auth URLs on the hosted project

Done (job 7, 2026-10-23, Management API via `supabase/deploy/auth_urls.ts`):

- Site URL: `https://app.snacklist.app` (set on 2026-11-10, job 174; it was
  `https://app.hummlist.com` from 2026-10-25, job 20, and before that
  `https://family-groceries-pied.vercel.app`).
- Redirect URLs: `https://app.snacklist.app` and `https://app.snacklist.app/**`,
  `https://app.hummlist.com` and `https://app.hummlist.com/**` (kept until R1),
  `https://family-groceries-pied.vercel.app/**`,
  `https://family-groceries-*-peter-trost.vercel.app/**` (Vercel previews
  of this team), `com.snacklist.app://login-callback`,
  `com.hummlist.app://login-callback` (Hummlist builds, until R1) and
  `com.petertrost.familygroceries://login-callback` (builds from before
  job 20). No localhost entries on production (DECISIONS 7.9).
- OAuth server: enabled, authorization path `/oauth/consent`, so MCP
  clients land on `https://app.snacklist.app/oauth/consent`.

To change the URL later, rerun
`deno run --allow-env --allow-net supabase/deploy/auth_urls.ts <new-url> --preview <pattern>`
with `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` set, and change
`APP_URL` in `app/config/auth.json` (the invite links of the phone apps).

Magic links and sign-up confirmation mails redirect there. Email
confirmation is on by default for hosted projects: new users confirm their
address before the first sign-in, and the app tells them so.

## 4. Sign in with Google and Apple (job 1b)

The app, the Supabase config and a configuration script are ready. Both
providers stay hidden in the app and disabled on Supabase until these
steps give them credentials. Background: `docs/AUTH.md`.

Collect the values in `~/groceries-ops/env` (outside the repo) as you go.
The variable names are in `.env.example`.

### Google Cloud Console (https://console.cloud.google.com)

1. Create a project, or pick an existing one, for example "Family Groceries".
2. Go to **Google Auth Platform → Branding** (formerly "OAuth consent
   screen"). Enter the app name "Einkauf", your support email and the
   developer contact. Under **Authorized domains**, add `supabase.co`.
3. Under **Audience**, choose **External**. While the app is in "Testing",
   add your Google address and Lea's under **Test users**. Alternatively,
   press **Publish app**. Only the non-sensitive scopes `openid`, `email` and
   `profile` are used, so publishing needs no Google verification.
4. Under **Data Access**, add the scopes `openid`,
   `.../auth/userinfo.email` and `.../auth/userinfo.profile`.
5. Under **Clients → Create client → Web application**, name it
   "Einkauf Web (Supabase)". Add
   **Authorized redirect URI** `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/callback`.
   No JavaScript origin is needed: the web app signs in through Supabase's
   redirect, which works on production (job 7). Copy the **Client ID**
   (`GOOGLE_WEB_CLIENT_ID`) and the **Client secret**
   (`GOOGLE_WEB_CLIENT_SECRET`, a secret).
6. Under **Clients → Create client → iOS**, set the bundle ID to
   `com.petertrost.familygroceries`. Copy the **Client ID**
   (`GOOGLE_IOS_CLIENT_ID`).
7. Under **Clients → Create client → Android**, set the package name to
   `com.petertrost.familygroceries` and enter the SHA-1 fingerprint of a
   signing certificate. Create one Android client per certificate:
   - This build box's debug keystore (`~/.android/debug.keystore`):
     `4B:41:A1:23:70:B5:26:8F:01:53:98:97:C7:B5:28:79:FA:07:EB:F1`
   - Your Mac's debug keystore, if you build debug APKs there:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   - The release keystore from job 4:
     `keytool -list -v -keystore <release.jks> -alias <alias>`
   - If the app ever ships through Google Play with Play App Signing, add
     the **App signing key certificate** SHA-1 from Play Console → Test and
     release → App integrity.

   Copy one Android client ID as `GOOGLE_ANDROID_CLIENT_ID`. The app never
   uses it; Google matches the app by package name and SHA-1.

### Apple Developer (https://developer.apple.com/account, team of peter@petertrost.com)

8. Go to **Certificates, Identifiers & Profiles → Identifiers → App IDs**,
   then to `com.petertrost.familygroceries`, or register that ID. Tick
   **Sign in with Apple** (as a primary App ID) and save. Note the **Team ID**
   (top right, `APPLE_TEAM_ID`).
9. Go to **Identifiers → + → Services IDs**. Use description "Einkauf Web"
   and identifier `com.petertrost.familygroceries.web` (`APPLE_SERVICES_ID`).
   Enable **Sign in with Apple → Configure**. Set the primary App ID to
   `com.petertrost.familygroceries`, the domain to
   `jdwqrallbpdbshrdhenk.supabase.co`, and the return URL to
   `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/callback`.
10. Go to **Keys → +**. Name it "Einkauf Sign in with Apple", tick **Sign in
    with Apple**, configure it with the primary App ID, register it and
    download `AuthKey_<KEYID>.p8` **once**. Keep it outside the repo, for
    example `~/groceries-ops/AuthKey_<KEYID>.p8`. Note the **Key ID**
    (`APPLE_KEY_ID`) and set `APPLE_PRIVATE_KEY_FILE` to the file's path.
11. Optional: under **Services → Sign in with Apple for Email
    Communication**, register `jdwqrallbpdbshrdhenk.supabase.co`. Only needed
    if mails ever go to private relay addresses.

### Supabase (from this box or your Mac)

12. With the values in the environment, run:

    ```bash
    set -a; source ~/groceries-ops/env; set +a
    node scripts/configure-social-auth.mjs --dry-run   # shows what changes, secrets redacted
    node scripts/configure-social-auth.mjs
    ```

    The script enables Google once `GOOGLE_WEB_CLIENT_ID` and
    `GOOGLE_WEB_CLIENT_SECRET` are set. The client ID list is web first, then
    iOS and Android. It enables Apple once the Services ID, Team ID, Key ID
    and `.p8` file are set. The client ID list is the Services ID, then the
    old and the new bundle ID (job 20), and the client secret is generated from the `.p8`. To do the
    same by hand, use Dashboard → Authentication → Sign In / Providers →
    Google / Apple, with the same values in the same order. Leave "Skip
    nonce check" off.
13. **Every 5 months**, rerun step 12 for Apple: the Apple client secret
    expires after 6 months, and web and Android Apple sign-in stop working
    then. The script prints the expiry date. Native iOS sign-in keeps
    working without it.
14. Done (job 7, job 20): the redirect URLs list the web app and both deep
    links, `com.snacklist.app://login-callback`, `com.hummlist.app://login-callback` (until R1) and the pre-rename
    `com.petertrost.familygroceries://login-callback` (section 2).

### The app

15. Put the public values into `app/config/auth.json` and commit them
    (client IDs are public):

    ```json
    { "GOOGLE_WEB_CLIENT_ID": "<web client id>",
      "GOOGLE_IOS_CLIENT_ID": "<ios client id>",
      "SIGN_IN_WITH_APPLE": "true",
      "APP_URL": "https://app.snacklist.app" }
    ```

    In `app/ios/Flutter/Auth.xcconfig`, set `GOOGLE_REVERSED_CLIENT_ID` to
    the iOS client ID with its dot-separated parts reversed. For
    `123-abc.apps.googleusercontent.com`, that is
    `com.googleusercontent.apps.123-abc`. `flutter test` fails if the two
    files disagree.
16. In Xcode, check that the Runner target shows the **Sign in with Apple**
    capability. It comes from `Runner/Runner.entitlements`. Automatic signing
    regenerates the provisioning profile with it.
17. GitHub: nothing is needed for sign-in. Client IDs live in
    `app/config/auth.json`; secrets live only in Supabase. Job 4's release
    workflow builds with `--dart-define-from-file=config/auth.json`.
18. Try it once: Google and Apple on the iPhone, Google and Apple on an
    Android phone, and both on the web app. Then sign in with the same email
    by password or magic link and check that you land in the same household.

## 5. MCP server on the hosted project (job 3)

Done from the box through the Management API on 2026-10-22: OAuth 2.1 server
enabled, dynamic client registration enabled, authorization path
`/oauth/consent`. JWT signing already used an ES256 key (`in_use`).

Done since: migrations and `mcp` deployed (section 1), web app hosted and
Site URL set (section 2); an MCP client registered by DCR reaches
`https://family-groceries-pied.vercel.app/oauth/consent` (job 7), since
job 20 `https://app.hummlist.com/oauth/consent`, since job 174
`https://app.snacklist.app/oauth/consent`.

Still yours:

1. **Connect and disconnect once** (job 3b): connect Claude or ChatGPT to
   `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp`, then
   disconnect it under Mehr → Zugänge. Its next MCP call must get `401`.
   The function reads `auth.sessions` through `SUPABASE_DB_URL` for this; a
   `500` instead would mean the hosted database role lacks that read. Not
   run on production yet: it needs your Google or Apple account.
2. **Optional:** if a browser-based MCP client on another site should connect,
   set the edge function secret `MCP_ALLOWED_ORIGIN_HOSTS` to its hostname(s),
   comma-separated (`supabase secrets set MCP_ALLOWED_ORIGIN_HOSTS=…`).

## Job 4: Siri

1. Done (job 7): `voice` is deployed (section 1). `supabase/config.toml` sets
   `verify_jwt = false` for it, because Siri sends a personal access token,
   not a JWT. Check it with:

   ```bash
   curl -s -X POST 'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/voice?format=text' \
     -H 'Authorization: Bearer nope' -d 'Milch'
   # -> Der Zugriffstoken fehlt oder ist ungültig. …
   ```

2. On your iPhone, follow `docs/SIRI_SHORTCUT.md` (German): create a token
   in the app under Mehr → Zugänge, then build the three-action Shortcut
   "Einkaufsliste". Lea does the same on her phone with her own token.

The Shortcut itself needs no Apple account setting, but creating the token
needs a running app on the hosted project: the TestFlight or Play build
(job 4 release section below) or the web app at
`https://app.snacklist.app`.

## Job 4b: the microphone on a real phone

This box has no iOS device and no Android emulator (KVM is locked), so the
on-device check ran only in unit and widget tests and through the iOS and
Android compile jobs in CI. On the first build on your phone:

1. Tap the microphone next to "Was fehlt?", allow microphone and speech
   recognition, and say "Milch, zwei Gurken und Klopapier". Expect the
   words in the field, then "Hinzugefügt: Milch, 2 Gurken, Klopapier."
2. If instead you see "Diktieren geht nur offline … fehlt hier die deutsche
   Offline-Spracherkennung …", the phone has no offline German model.
   iPhone: Einstellungen › Allgemein › Tastatur › Diktieren on, with German
   among the keyboards (iOS downloads the model). Android: Einstellungen ›
   System › Sprachen › Spracheingabe (Google) › Offline-Spracherkennung ›
   Deutsch. Then try again.
3. Which phones can dictate: iPhones with iOS 13 or later and the German
   model; Android 12 (API 31) or later with Google's on-device recognizer.
   Android 11 and older always show the message above, because they have
   no on-device recognizer the app can require. On Android 12 the app can't
   ask for the language in advance, so a phone without offline German shows
   the message once you start speaking; please try that too if you have
   such a phone.

## Job 4: release

The Release workflow and the fastlane lanes are in place
([`RELEASE.md`](RELEASE.md)). Until the secrets below exist, the workflow
skips both platforms and stays green. All secrets and variables go into one
GitHub environment.

### Status (2026-10-27, job 23)

Superseded by the weekly pipeline: [`RELEASE.md`](RELEASE.md) and
[`NEEDS_LEAD.md`](NEEDS_LEAD.md). What still holds from job 4:

- Environment `release` (deployments from `main` only) holds variables
  `APPLE_TEAM_ID` (`VCZSHMZY25`) and `MATCH_GIT_URL`, secrets
  `MATCH_DEPLOY_KEY`, `MATCH_PASSWORD`, the three `APP_STORE_CONNECT_*`
  (API key `family-groceries-ci`, key ID `4J3N457M89`, Admin) and, since
  job 23, `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEY_PROPERTIES`. The match
  deploy key pair is `~/groceries-ops/match-deploy-key` (+ `.pub`) and
  `MATCH_PASSWORD` is in `~/groceries-ops/env` on the build box. Copy both
  to your password manager. Without the passphrase the match repo is
  unreadable.
- Certificates run
  [40224053069](https://github.com/trost-systems/family-groceries/actions/runs/40224053069)
  created Apple Distribution certificate `GN85KDC962` (expires 2027-10-25)
  and the profile now named "match AppStore com.hummlist.app". The team has
  three distribution certificates; none was revoked. Don't rerun
  Certificates unless the certificate needs renewing.
- The App Store Connect app "Hummlist" (Apple ID `6826922741`) exists, with
  the internal group "Familie" (all builds, you are in it). Release run
  [40229901781](https://github.com/trost-systems/family-groceries/actions/runs/40229901781)
  uploaded 0.1.0 (1002). Apple expired it, and every other build of the
  team, on 2026-10-26 (`RELEASE.md`, "TestFlight builds expired"); the
  next merge uploads a new one.
- Steps 1 to 7 below are done for iOS (Lea's App Store Connect invitation is
  pending; the Lead follows it up). The Android steps are replaced by
  `NEEDS_LEAD.md`.

### iOS

1. **Agreement and bundle ID.** App Store Connect, Business (or the banner
   on the home page): accept the current Apple Developer Program License
   Agreement; TestFlight uploads fail until it is accepted. The App ID
   `com.petertrost.familygroceries` should already exist from Sign in with
   Apple (section 4, step 8); if not, register it in developer.apple.com,
   Certificates, Identifiers & Profiles, Identifiers, description "Einkauf".
2. **Create the app record.** App Store Connect, Apps, New App: platform iOS,
   name "Einkauf" (the name must be unique on the App Store; pick a variant
   such as "Einkauf Familie" if it is taken, the home-screen name stays
   "Einkauf"), primary language German, bundle ID
   `com.petertrost.familygroceries`, SKU `family-groceries`.
3. **Team ID.** Done: `APPLE_TEAM_ID=VCZSHMZY25` in `release`.
4. **App Store Connect API key.** App Store Connect, Users and Access,
   Integrations, App Store Connect API, Team Keys, generate a key with the
   Admin role (match needs it to create the certificate). Download
   `AuthKey_<KEY_ID>.p8`; Apple offers the download once. Then, from a clone
   of the repo:

   ```bash
   gh secret set APP_STORE_CONNECT_API_KEY_ID --env release --body <KEY_ID>
   gh secret set APP_STORE_CONNECT_ISSUER_ID --env release --body <ISSUER_ID>
   gh secret set APP_STORE_CONNECT_API_KEY_P8 --env release < AuthKey_<KEY_ID>.p8
   ```

5. **match repo and deploy key.** Secrets and variable done. Left: as an
   owner of `trost-systems`, create the repo and add the public key, which
   is on the build box at `~/groceries-ops/match-deploy-key.pub`:

   ```bash
   gh repo create trost-systems/family-groceries-certificates --private --add-readme
   gh repo deploy-key add ~/groceries-ops/match-deploy-key.pub --allow-write \
     --repo trost-systems/family-groceries-certificates --title release-ci
   ```

   Or ask the box to do it after giving `petertrost-bot` permission to create
   repositories in the organization. Write access lets step 6 push the
   certificates with the same key; the Release workflow only reads.
6. **Create the certificate and profile once.** After the PR that adds
   `certificates.yml` is merged: Actions, Certificates, Run workflow on
   `main`, type `create`. It fails early, naming what is missing, if a
   secret from steps 4 or 5 is not set. Apple allows only a few
   distribution certificates per team. If the lane reports the limit,
   revoke an unused one in the developer portal and rerun. On a Mac the
   same works by hand with `bundle exec fastlane ios certificates` in `app/`
   and the six values in the environment.
7. **First release and testers.** Run the Release workflow with
   `platform: ios`. The build shows up in TestFlight after Apple's
   processing (10 to 30 minutes). In App Store Connect, TestFlight, create
   an internal group and add yourself and Lea. Lea must first be a user of
   your team (Users and Access, invite her, any role such as Customer
   Support or Developer); she then installs the TestFlight app and accepts
   the invitation.

### Android

Replaced by job 23. The upload keystore exists (created on the build box,
`~/groceries-ops/secrets/android/`), its secrets are set, and Play access is
keyless (no `PLAY_SERVICE_ACCOUNT_JSON`). The Play Console steps are the
Lead's: [`NEEDS_LEAD.md`](NEEDS_LEAD.md), L1 to L5.

## Job 5: Android verification run

1. **Run the Android surface once on a machine where the emulator works**
   (your Mac, or a Linux host with working KVM). The build box cannot: a
   KVM guest there crashes the host kernel (see DECISIONS 5.1), so `fg`
   drives the Linux desktop build instead. On that machine:
   `scripts/fg setup --surface android`, then
   `FG_SURFACE=android scripts/fg up --clients peter,lea`, `scripts/fg doctor`
   and `.cursor/skills/verify-family-groceries/journeys/quick-add-live-sync.sh`.
   Those steps have never run end to end (SKILL.md, section "Android").
2. **Optional, for whoever runs the VM host:** nested KVM on this box oopses
   in `vmx_vcpu_create` (dmesg, 2026-10-23 05:53–06:03). Once the host is
   fixed, delete `~/.config/fg/kvm-broken` on the box to re-enable the
   emulator.

## Job 7: web hosting on Vercel

Done. The Vercel project `peter-trost/family-groceries` (created by
Engineering Lead on 2026-10-23) is linked to this repo and builds every
push from `vercel.json`:

- Production: `https://app.snacklist.app` (custom domain since job 174), also
  reachable as `https://app.hummlist.com` (job 20) and
  `https://family-groceries-pied.vercel.app`. Since 2026-10-29
  the production branch is `release`, which `release.yml` moves when it ships
  a store build; `main` is on `https://preview.app.hummlist.com` behind
  Vercel Authentication (`DEPLOY.md`, section "Web app").
  The plain `family-groceries.vercel.app` belongs to someone else.
- Previews: `https://family-groceries-git-<branch>-peter-trost.vercel.app`,
  behind Vercel Authentication (team default, unchanged).
- Project settings: root directory empty (repo root), framework "Other",
  no install, build or output overrides, Node 22.x. Environment variables
  for Production and Preview, both public values:
  `SUPABASE_URL=https://jdwqrallbpdbshrdhenk.supabase.co` and
  `SUPABASE_PUBLISHABLE_KEY=sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5`.
  The build fails if either is missing or the key is not a publishable key.
- Check a deployment with `node e2e/web-smoke.mjs <url> <screenshot-dir>`
  (after `cd e2e && npm ci`): SPA routes, cache headers, and the Google and
  Apple buttons reaching the providers' sign-in pages.

Nothing is needed from you here. The custom domain `app.snacklist.app` is
attached (job 174, next to `app.hummlist.com` from job 20); for another one, rerun `auth_urls.ts` with it (section 2)
and change `APP_URL` in `app/config/auth.json`.

## Job 9: account deletion and data export

In-app deletion and export are built and tested (`docs/ACCOUNT_DELETION.md`).
Three things need you.

### Approve the drafts (ENTWURF, nicht veröffentlicht: Freigabe durch Peter)

1. `app/web/konto-loeschen.html`: the public "Konto und Daten löschen"
   page Google Play asks for. After the merge it is served at
   `https://app.snacklist.app/konto-loeschen.html` with
   `noindex` and a red ENTWURF banner. Check the wording, the developer
   name ("Peter Trost", which must match the Play listing), the support
   address `peter@petertrost.com` and the promise "innerhalb von 30 Tagen"
   for requests from people who can no longer sign in. To publish it, delete
   the `<p class="draft">` line and the `noindex` meta tag, then enter the
   URL in Play Console under App content › Data safety › Data deletion.
2. `docs/ACCOUNT_DELETION.md`, sections "What is deleted" and "What stays,
   and for how long": these are the facts for the App Store privacy label
   and the Play Data safety form (job 14 drafts those).

### Sign in with Apple token revocation on the hosted project

Apple wants the app to revoke Sign in with Apple tokens when a user deletes
their account. The `account` function does that on iPhones, but only when
it has the Sign in with Apple key. The function deploys with every merge to
`main`. Until the secrets below exist, it deletes accounts without revoking,
and the app tells Apple users to remove "Snacklist" in their Apple ID
settings (Apple's documented fallback, TN3194).

3. Set the function secrets once, from your Mac or the build box (the key
   file and IDs are the ones from section 4, step 10; this prints nothing):

   ```bash
   source ~/groceries-ops/env
   supabase secrets set --project-ref jdwqrallbpdbshrdhenk \
     APPLE_TEAM_ID="$APPLE_TEAM_ID" APPLE_KEY_ID="$APPLE_KEY_ID" \
     APPLE_PRIVATE_KEY="$(cat "$APPLE_PRIVATE_KEY_FILE")"
   supabase secrets list --project-ref jdwqrallbpdbshrdhenk | grep APPLE_
   ```

   The function tries the bundle IDs `com.hummlist.app`, `com.snacklist.app` and
   `com.petertrost.familygroceries` in turn (job 20, job 174), so the key must cover
   all three App IDs (job 20, step 3). An `APPLE_BUNDLE_ID` secret from before
   job 20 is ignored; remove it with `supabase secrets unset`. Unlike
   the Supabase Apple client secret, nothing here expires: the function
   signs a fresh 5-minute client secret per deletion.
4. Check it once on your iPhone with a throwaway Apple account (never with
   your or Lea's real account). Sign in with Apple, then Konto › Konto
   löschen. The success message must not show the "Apple-ID-Einstellungen"
   hint, and the function log must show `apple: revoked`.

## Job 13: database backups (decision for Peter)

**DONE (job 13b, 2026-10-25).** Peter said yes on 2026-10-25, with three
changes to the proposal below: nightly instead of weekly, 90 days of
retention, and `auth.users` plus `auth.identities` included. Runbook,
restore steps and key rotation: [`BACKUP.md`](BACKUP.md).

- **Live:** `.github/workflows/backup.yml`, every night at 02:30 UTC and
  on demand. A failed run opens the issue "Database backup failed".
- **Key pair:** created by the Engineering Lead. The public key is
  `supabase/backup/recipient.txt`. The private key is on the build box at
  `~/groceries-ops/backup-age-key.txt`. **Still yours:** copy it to your
  own computer and your password manager. Without it no backup can be read.
- **Database password:** the repository secret `SUPABASE_DB_PASSWORD`, set
  by the Engineering Lead on 2026-10-25 from the existing value (not
  rotated). Engineering Lead: update this line if you rotate it through
  the Management API.
- "What you would do" below is superseded: steps 1 and 2 were done by the
  Engineering Lead, step 3 became a repository secret (DECISIONS 13b.3),
  step 4 is answered (auth tables included).

The original proposal follows for the record.

### What exists today

- **The free plan has no backups.** Supabase backs up Pro, Team and
  Enterprise projects daily; for free projects it recommends regular
  exports with `supabase db dump` kept off-site
  (https://supabase.com/docs/guides/platform/backups). Point-in-time
  recovery is a paid add-on. So if a migration or a bug destroys data,
  there is nothing to restore from.
- **A GitHub runner can reach the database, but only through the pooler.**
  Measured on 2026-10-24 with a throwaway workflow on `ubuntu-latest`, without
  any credential (log: `docs/screenshots/13/runner-pooler-probe.txt`):
  - `db.jdwqrallbpdbshrdhenk.supabase.co` has only an IPv6 address, and
    the runner has no IPv6 route ("Network is unreachable"). The IPv4
    add-on for direct connections is paid.
  - The session pooler `aws-1-eu-central-1.pooler.supabase.com:5432`
    (user `postgres.jdwqrallbpdbshrdhenk`) is reachable. `psql` with a
    wrong password got "password authentication failed", so the pooler
    routes to this project. Supabase documents the shared pooler as
    IPv4 on every plan
    (https://supabase.com/docs/guides/database/connecting-to-postgres).
  - The server runs Postgres 17, so the runner needs `pg_dump` 17
    (`postgresql-client-17`, or `supabase db dump`, which brings a matching
    one).
- **The build box can't reach Postgres at all.** Its DNS points every
  database host at a local proxy, so a backup must run on GitHub.
- **The repo has no database password secret.** Job 7b deleted the unused
  `SUPABASE_DB_PASSWORD` secret; deploys need only the access token.

### Proposal

A weekly workflow, `backup.yml` (Sunday night and on demand):

1. Install `pg_dump` 17 and `age`.
2. Dump the data of `public` through the session pooler:
   `pg_dump --data-only --schema=public` (schema comes from the
   migrations). Optionally add `auth.users` and `auth.identities`, so a
   restore keeps everyone's sign-in and household membership. Without
   them, the restored rows point at user IDs that no longer exist.
3. Encrypt the dump with `age -r <your public key>` and stream it straight
   into the file. Nothing unencrypted touches the disk or the log.
4. Check that the file starts with the `age-encryption.org/v1` header.
   Upload nothing if it doesn't.
5. Upload it as a workflow artifact with 90 days of retention, the maximum
   for a public repo, so about 13 weekly copies exist.

The repo is public, so anyone can download the artifacts: encryption is
mandatory. Only the public key would be committed. Without your private
key the file is useless, and only you can restore it with
`age -d -i key.txt dump.sql.age | psql ...`.

### What you would do (superseded, see above)

1. Create the key pair on your Mac: `age-keygen -o ~/family-groceries-backup.key`.
   Keep the file in your password manager. It prints the public key
   (`age1...`). If you lose the private key, every backup is unreadable.
2. Give the public key to the next job (paste it on the board or in the job
   brief). It goes into the repo as `supabase/backup/recipient.txt`.
3. Add the database password as a secret for the workflow only:
   Settings, Environments, New environment `backup`, add secret
   `SUPABASE_DB_PASSWORD` (dashboard, Project Settings, Database).
   Alternative: a read-only role just for backups, if you'd rather not
   hand the workflow the `postgres` password.
4. Say yes or no to including `auth.users` and `auth.identities` (step 2
   of the proposal).

A cheaper variant without a database password: the workflow could read the
tables as JSON through the Management API with the existing
`SUPABASE_ACCESS_TOKEN`. The restore would then need a small loader script
instead of `psql`, and it reads with the most powerful credential the repo
has. I'd pick `pg_dump` through the pooler.

## Job 20: the app is now "Hummlist" (`com.hummlist.app`)

The repo builds the app as "Hummlist" with bundle ID and Android package
`com.hummlist.app` and the deep link `com.hummlist.app://login-callback`.
Already done by the Engineering Lead: the App ID `com.hummlist.app` (Sign in
with Apple, In-App Purchase), the hosted Supabase Apple client IDs
(`com.petertrost.familygroceries.web,com.petertrost.familygroceries,com.hummlist.app`)
and both deep links in the redirect allow list. The match profile is the
Lead's step. Yours, in this order:

1. **App Store Connect app record.** Done (2026-10-25): "Hummlist", Apple
   ID `6826922741`, with the internal group "Familie". The old app record
   (`6826907810`) gets no new builds.
2. **Google sign-in** (Google Cloud project `family-groceries-512507`,
   Google Auth Platform, Clients). Without this, Google sign-in fails on the
   new builds.
   - Open the iOS client `1001040145655-q542…` and change its bundle ID to
     `com.hummlist.app`. The client ID stays, so `app/config/auth.json`,
     `Auth.xcconfig` (the reversed client ID URL scheme) and Supabase need no
     change. The TestFlight build 0.1.0 (1001) of the old bundle ID can lose
     Google sign-in after this; Apple, email and magic link still work there.
   - Create an Android client with package name `com.hummlist.app` for each
     SHA-1 of section 4, step 7 (build box debug keystore
     `4B:41:A1:23:70:B5:26:8F:01:53:98:97:C7:B5:28:79:FA:07:EB:F1`, your Mac's
     debug keystore, the upload keystore and, once on Play, the app signing
     key). The app never sends an Android client ID; Google matches it by
     package name and SHA-1.
   - Branding: change the app name "Einkauf" to "Hummlist", so the Google
     consent screen names the app.
3. **Sign in with Apple key for account deletion** (developer.apple.com,
   Certificates, Identifiers & Profiles). The `account` function revokes
   Apple tokens with the key `APPLE_KEY_ID`, signing as the bundle ID the
   code was issued to. The key was configured with the primary App ID
   `com.petertrost.familygroceries`; `com.hummlist.app` is a primary App ID
   of its own. Until the key covers it, deleting an account from a Hummlist
   iPhone build deletes it but cannot revoke, and the app shows the hint to
   remove "Hummlist" by hand (nothing else breaks). Fix: under Identifiers,
   group `com.petertrost.familygroceries` and the Services ID
   `com.petertrost.familygroceries.web` under the primary App ID
   `com.hummlist.app`, then under Keys edit the Sign in with Apple key to
   the primary App ID `com.hummlist.app`. Then rerun section 4, step 12 (the
   Apple client secret is signed with this key) and check the web Apple
   sign-in once. Apple changes the grouping on its side; this is inferred
   from Apple's docs, not tried from the box. While there, change the
   Services ID's description "Einkauf Web" to "Hummlist": Apple's web
   sign-in page shows it to the user.
4. **Play Console.** Done by job 23 up to the browser: the Lead creates
   the Play app "Hummlist" (`NEEDS_LEAD.md`, L1 to L4). Nothing of a
   `com.petertrost.familygroceries` Play app carries over.
5. **Retire the old bundle ID** only after a Hummlist build is verified on
   your iPhone (Apple, Google, magic link) and Lea has moved to it: remove
   `com.petertrost.familygroceries` from the Supabase Apple client ID list
   (Dashboard, Authentication, Sign In / Providers, Apple, or drop it from
   `bundleIds` in `scripts/configure-social-auth.mjs` and rerun step 12).
   A job can then drop it from `appleBundleIds` in
   `supabase/functions/account/apple.ts`. Keep its deep link in the redirect allow list; it costs nothing.

## Job 23: weekly releases

The Release workflow ships every green merge to `main` (job 30; until then
Mondays): TestFlight group "Familie" and the Play internal track
([`RELEASE.md`](RELEASE.md)). The Play Console and Apple Developer browser
steps are the Lead's, with you only signing in
([`NEEDS_LEAD.md`](NEEDS_LEAD.md)). Yours:

1. **Google Play developer account:** nothing to do. It exists; the Lead
   created the app "Hummlist" in it on 2026-10-27.
2. **Copy the Android upload key to your password manager.** Both files are
   on the build box in `~/groceries-ops/secrets/android/`:
   `upload-keystore.jks` and `key.properties` (its two passwords). Google can
   reset a lost upload key only through Play Console support, so keep a copy
   outside the box.
3. **Watch the repository's issues** (Watch, Custom, Issues) if you haven't:
   a failed automatic release opens "Internal release failed" there.
4. **If a new TestFlight build comes out already expired** (the run fails
   with "VALID but already expired"; `RELEASE.md`, "TestFlight builds
   expired"): as the account holder, open a case at
   <https://developer.apple.com/contact/> (TestFlight) naming the build
   number. Apple expired all of the team's builds at once on 2026-10-26 and
   has acknowledged the same problem for other teams; nothing in the account
   settings or the repo fixes it.
5. **Flight mode, once per platform (jobs 166, 166b).** On the next
   TestFlight build and the next Play internal build, open the list and
   turn flight mode on: „Offline“ shows without a tap. Turn it off: it
   goes within about 3 s, also without a tap. The runner has no phone, so
   only the web build proves this today.


## Job 24a: guides on snacklist.app

The guides site is `site/` on `main`. The Lead creates its Vercel project
(Root Directory `site`, everything else from `site/vercel.json`) and
attaches the domain and www (snacklist.app since job 174; hummlist.com redirects
there). Yours:

1. **Remove noindex at the beta launch.** Every page carries
   `X-Robots-Tag: noindex` so search engines skip it while the pages change.
   At launch, delete that header entry from `site/vercel.json` (or ask a
   job to).
2. **The support@snacklist.app mailbox must receive mail** before the site
   goes live: the Impressum lists it as the contact address.

## Job 16: the design H list

Nothing blocks. Two things to look at, both reversible:

- **Removed the store filter chips because H folds stores; say if you miss
  them.** The "Alle / dm / Lidl / Edeka" chips above the list are gone. Each
  store is a section in its own walk order; fold the ones you are not in.
  With the chips went two side effects of "the store I'm in": an add no
  longer lands in the viewed store (the add sheet's store chip in job 17 does
  that), and ticking an item without a store no longer tags it to that store.
  Tag items by dragging them onto a store or with the edit sheet's store
  chip. The per-store "gibt es bei …" switches went from the store layout
  screen too, since nothing is hidden any more (DECISIONS, Job 16, 1 and 2).
- ~~**Empty stores show as "Edeka 0 Artikel" dividers**~~ Done (job 17b,
  2026-10-29): you answered "we don't want to show stores that have 0
  articles on the list". Empty stores are hidden and show only while an item
  is dragged, as drop targets (DECISIONS, Job 17b).

## web-release-align: production branch `release` (2026-10-29, done)

Done on 2026-10-29 at about 18:20 CET. You authorized the Vercel CLI on the
box, and the agent made the change with it:

- Production branch (Settings, Environments, Production, Branch Tracking):
  `main` -> `release`, through `PATCH /v9/projects/{id}/branch`.
- Auto-assignment of production domains is back on
  (`autoAssignCustomDomains: true`).
- `preview.app.hummlist.com` is a domain on the `main` branch, behind Vercel
  Authentication (deployment protection unchanged).
- `app.hummlist.com` stayed on the 5b6659d build (`dpl_AiSL9Jf7`) and moves
  with the next store release (`DEPLOY.md`, section "Web app").

## Job 17: legal pages and the guides site

- **Datenschutz.** Done in job 33b: More → Datenschutz, the login footer
  and the consent screen open https://snacklist.app/datenschutz (English:
  /en/privacy), the pages job 33a publishes.
- **Impressum.** More → Impressum opens https://snacklist.app/impressum
  (English: /en/imprint), the page job 24a wrote in `site/`. On 2026-10-29
  hummlist.com answered 404 for every path, so the site is not deployed
  yet. Deploying it (docs/DEPLOY.md, the site's Vercel project) makes the
  link work; nothing changes in the app.

## Job 28: WebAssembly web build (2026-10-29)

- **Check the preview once (1 min).** `#95` merged as `64f8444`, and its
  Vercel deployment (`4HMwTh7VUENcuSFL4FubLunMfhXF`) is Ready. The job could
  not open it: preview.app.hummlist.com is behind Vercel Authentication, and
  the Mac runner has no Vercel token. Open https://preview.app.hummlist.com in
  desktop Chrome, signed in to Vercel. DevTools → Network should show
  `main.dart.wasm` (type `wasm`, `application/wasm`), not `main.dart.js`.
  Or run `node e2e/web-smoke.mjs '<preview URL>/?_vercel_share=<link>'`:
  every line `ok`, including `/main.dart.wasm` and "Chromium runs the wasm
  build".
- **Your iPhone stays on the JS build** (Safari and every iOS browser, by
  Flutter's default; DECISIONS job 28.2), so it should feel the same as
  before. The double tap: one tap focuses the field correctly in our tests
  (DECISIONS 28.5). If the keyboard still needs two taps on the preview, it
  is Flutter's or Safari's behaviour, not our code. Nothing for you to do
  unless you want to report it upstream.

## Job 19: analytics and error tracking (PostHog EU)

Built and tested, but **off** until you set the keys below; nothing is sent today. Details in
[ANALYTICS.md](ANALYTICS.md). Please do the steps in this order: the wording first, because the
keys make the consent screen appear for everyone.

1. **Done 2026-10-30: consent wording approved** (job 33b applied the legal review's version and
   removed the chip). Was: approve the consent wording (ENTWURF). The screen after the first sign-in and the
   switch under Mehr → Nutzungsdaten, German and English, in `app/l10n/app_de.arb` /
   `app_en.arb`: `analyticsConsentTitle`, `analyticsConsentBody`, `analyticsAccept`,
   `analyticsDecline`, `analyticsSection`, `analyticsToggle`, `analyticsToggleHint`. Both show the
   chip "ENTWURF: Freigabe durch Peter" (`analyticsDraftNote`); once you approve (or edit) the
   text, the chip goes (one small PR). Screenshots: `docs/screenshots/19/`.
2. **Privacy policy entry for PostHog.** Name PostHog Inc. as processor (EU Cloud, data in
   Frankfurt), what is sent (a random installation id, the household id, app version, platform,
   which action happened: add, tick, reorder, household created, invite accepted; scrubbed error
   reports), what never is (item names, list text, names, e-mail, IP, location), the legal basis
   (consent, Art. 6(1)(a) GDPR, withdrawable under Mehr → Nutzungsdaten), retention, and the
   edge-function error reports (no user data; legitimate interest). The privacy page isn't live
   yet (Job 17 item above).
3. **DPA with PostHog**: accept PostHog's data processing agreement in the organization settings
   of "Einkauf".
4. **Data retention.** The free plan keeps 1 year; the spec's month-12 retention needs about 14
   months. You said you'll upgrade before year end; until then the queries go to month 11.
5. **Group analytics yes/no.** It is a paid add-on. The app can also send the `household` group
   (`ANALYTICS_HOUSEHOLD_GROUPS=true` as a build define); off now, the household metrics use the
   `household_id` property.
6. **Turn it on** (the lead or you; no agent changes these):
   - Vercel project `family-groceries`, environment **Production** (and Preview if you want data
     from preview.app.hummlist.com, marked internal by your household id):
     `POSTHOG_PROJECT_API_KEY` = the Einkauf project key (`phc_…`),
     `POSTHOG_HOST` = `https://eu.i.posthog.com`,
     `ANALYTICS_INTERNAL_HOUSEHOLDS` = your household id
     (`select id from households where name = '<your household>'` in the SQL editor).
   - Readable web stack traces (optional, Production only): `POSTHOG_PERSONAL_API_KEY` (the
     error-tracking key) and `POSTHOG_PROJECT_ID` = `319492` in the same Vercel project.
     `scripts/vercel.sh` uploads the source map and deletes it from the deployment. A GitHub
     secret `POSTHOG_PERSONAL_API_KEY` is not used (the web app is built by Vercel; DECISIONS Job
     19.15); you can delete it if you created it.
   - GitHub (environment `release`): secret `POSTHOG_PROJECT_API_KEY`, variables `POSTHOG_HOST`
     and `ANALYTICS_INTERNAL_HOUSEHOLDS`. The next TestFlight and Play builds then ask for
     consent after sign-in.
   - Supabase function secrets on the hosted project: `POSTHOG_PROJECT_API_KEY` and
     `POSTHOG_HOST` (error tracking for mcp, voice, account, health). Do not set
     `ANALYTICS_INTERNAL` there.
7. **Store credentials for purchase verification** (the in-app purchase job): an App Store
   Connect In-App Purchase key (issuer id, key id, `.p8`) and the App Store Server Notifications v2
   URL; a Google Play service account with the Play Developer API and Orders API, and a Pub/Sub
   topic with a push subscription for Real-time Developer Notifications.
8. **Optional:** in PostHog project settings, the internal/test-account filter can use the
   event property `is_internal = true`; the delivered queries filter it themselves anyway.

What the proofs left in project 319492 (all internal): 3 error-tracking issues, 1 symbol set, the
release `hummlist-web@job19-proof` and 2 events from `proof-ac11@fg.test` (DECISIONS Job 19.19).

## Job 29c: swipe left edits (2026-10-30)

- **Try it on your phone once (2 min), optional.** No real phone was
  available. The e2e specs drive Chrome as an Android phone (real touch
  events) and WebKit as an iPhone. On https://preview.app.hummlist.com
  (Vercel login), in Safari on your iPhone:
  1. Swipe an item to the left. The edit sheet should open and the row stay.
     Löschen in the sheet deletes, with Rückgängig.
  2. Hold an item still for about a second and let go. The edit sheet should
     open, not a move. If a still hold still turns into a move, tell the next
     job: the drift tolerance (18 px for a finger, DECISIONS 29c 4) wasn't the
     cause. The swipe works either way.

## Job 21: in-app feedback

Live with the next release; nothing to switch on. Details in [FEEDBACK.md](FEEDBACK.md).

1. **Privacy policy entry for in-app feedback** (with the Job 17 and Job 19 items). Suggested
   content: under Mehr → "Feedback senden" a user can send a note to the developer. Stored with
   it: the text, an optional kind (Bug, Idee, Sonstiges), whether they agree to be contacted, the
   app version and build, platform and OS version (on the web the browser family and OS), the
   app language, the name of the screen they came from, their account id and household id. No
   list items, no screenshots, no device model; the e-mail is not copied. Stored at Supabase
   (EU, Frankfurt), readable only by Peter Trost. Deleted 12 months after sending
   (daily cleanup), at once when the account is deleted; the encrypted nightly backups keep a
   deleted note up to 90 more days. Contact happens only by Peter and only when the user ticked
   "Peter darf mich dazu kontaktieren". Legal basis: the user sends it on purpose (Art. 6(1)(b)
   or (f) GDPR; your lawyer's call). Notes are part of "Meine Daten exportieren".
2. **Your household as internal.** Notes from your family count as internal only through the
   `ANALYTICS_INTERNAL_HOUSEHOLDS` build define (Job 19, item 6). Until it is set in the release
   and Vercel builds, your own notes show in the Monday summary's external part (debug builds and
   test accounts are internal regardless).
3. **After the deploy (lead)**: check the cleanup is scheduled on the hosted project:
   `select jobname, schedule, active from cron.job where jobname = 'purge-old-feedback';` should
   return one active row with `17 3 * * *`.

## Job 22: onboarding and invites

Live with the next release. Invite links open the installed apps only once app.snacklist.app
serves `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json`, that is
after the next *dispatched* Release run (the web follows the store release). Check them with
`node e2e/web-smoke.mjs https://app.snacklist.app`. The Apple and Play steps for the domains were
already done (NEEDS_LEAD L3 and L6).

1. **Device check, iPhone and Android** (no simulator or emulator on the build machines). On
   each phone, with the TestFlight / Play internal build installed and signed out:
   1. On a second device, create a household, tap "Partner einladen" and send the link to the
      phone (e.g. by a message to yourself).
   2. Tap the link on the phone: the Snacklist app opens (not the browser) on the sign-in screen.
      If the browser opens instead, long-press the link and choose "In Snacklist öffnen", and
      tell the lead (the domain files are not live yet).
   3. Sign in with Apple. After the consent screen comes the join screen with the household's
      name and "Haushalt beitreten". Join: the shared list appears; an item added on the other
      device shows up within seconds.
   4. Repeat with a new invite and an account that signs in with Google, then with a magic link
      (the mail's link opens the app; the join screen must still come, without tapping the
      invite link again), then with email and password.
   5. Kill the app between tapping the invite link and signing in (swipe it away), open it
      again and sign in: the join screen still comes.
   6. Open the same link again once joined: the list opens, nothing else happens.
   7. On a phone already in a household, open an invite link: "Du bist schon in einem Haushalt"
      with Abbrechen (prominent) and Haushalt beitreten.
   8. In Mehr, "Partner einladen": "Neue Einladung" opens the share sheet; the text reads "Komm
      in unseren Snacklist-Haushalt: https://app.snacklist.app/join/… · Code: …". Widerrufen
      removes it; its link then says "Dieser Code ist ungültig oder abgelaufen."
   9. With the phone set to English, the same screens are in English.
2. **Country-specific store sets for Austria and Switzerland later?** Today everyone gets dm,
   Lidl and Edeka (Edeka exists only in Germany; Austrians and Swiss can delete it or tap
   "Überspringen"). Say if you want e.g. Billa/Spar (AT) or Migros/Coop (CH) sets.
3. **Privacy policy entry for invites** (with the Job 17, 19 and 21 items). Suggested
   content: a member can create invite links/codes for their household. Stored per invite: the
   code, who created it, when, when it expires (7 days), whether and when it was used and by
   whom, and when it was revoked. Failed code entries are logged with the account id and time
   for one day, to rate-limit guessing (10 per hour). Invites are part of "Meine Daten
   exportieren" for the person who created them. Nothing is sent by Snacklist; the user shares
   the link themselves.

## Job 33b: legal fixes in the app

You approved the wording on 2026-10-30 (07:51). PR #107 carries it, with the
ENTWURF chip removed, and waits ready for the lead, who merges it together with
33a's privacy pages so the links never point at a 404 in a shipped build (a
merge ships the internal TestFlight and Play builds). The PR description lists
every changed text in German and English under "Wording (approved by Peter
2026-10-30)".

1. **Nothing to approve any more.** Before a public release, enter
   https://snacklist.app/datenschutz as the privacy policy URL in Play Console
   and App Store Connect (review H-01).
2. **Optional (H-21): split usage data and error reports into two
   switches. Not built; say if you want it.
3. Still yours from the review, outside the app: H-11 (where the backups
   live), H-14 (the Play payments profile address 7 → 5).

## Job 33a: privacy policy and deletion page (2026-10-30)

PR: see BOARD.md (`33a-legal-site`). Nothing is live until the PR merges, and
snacklist.app's production build fails while a `[PETER: …]` is left.

- Wording approved 2026-10-30 07:51. The deletion page is published with
  the next web release (no ENTWURF banner, no noindex).
- **Fill the placeholders** (listed with their questions in the PR body,
  "Peter must fill before merge"; Vercel address, Vercel log retention and
  the auth mailer were filled by the lead, DECISIONS 33a 9): AI support
  assistant provider and location, whether you send every support reply
  yourself, support mail deletion period, and the transfer basis for the AI
  support provider. (Job 33d filled the Google Workspace contracting entity
  and the transfer basis for Supabase, Vercel, GitHub, PostHog and Google;
  DECISIONS "Job 33d". Job 33e filled your answers of 2026-10-30 14:21 and the
  provider Anysphere, Inc., USA; DECISIONS "Job 33e".) **One left: the
  transfer basis for Anysphere** (section 13). Anysphere is not
  DPF-certified, and its DPA with SCCs covers Teams/Enterprise contracts
  (MSA), not an individual subscription. Pick the basis, e.g. a plan with
  the DPA, then tell the lead the exact wording. snacklist.app publishes the policy only once all are
  filled (Vercel's production build refuses otherwise); merging alone does
  not.
- **Google Play payments profile:** change the address from Yalovastraße 7
  to Yalovastraße 5 (H-14).
- **USt-IdNr:** do you have one? Then the Impressum needs it (DDG §5 Nr. 6).
- **After merge:** enter https://snacklist.app/datenschutz in Play Console
  (App content, Privacy policy) and App Store Connect (Privacy Policy URL);
  https://snacklist.app/datenschutz#rechte is the User Privacy Choices URL.
- **Follow-ups, your decisions:** move the backups off the public repo (H-11:
  make the repo private, or private EU storage); a retention period and cron
  for the list history `item_events` (H-12); pin the edge functions to
  eu-central-1 (`x-region` / `forceFunctionRegion`) if you want "EU only";
  the MCP consent text naming the AI provider (H-17, job 33b or a
  follow-up).

## Job 31: Alexa skill "Hummlist"

Everything on our side is built and tested on the CI stack ([ALEXA.md](ALEXA.md)). These steps
need you or Snacklist Ops at Amazon; nothing was done there.

1. **Amazon Developer account on hello@hummlist.com** (decided). You create it and do the
   sign-in and 2FA once; Snacklist Ops takes over the console after that.
2. **Create and deploy the skill (Snacklist Ops, after 1).** The exact commands are in
   [ALEXA.md, "Deploy"](ALEXA.md#deploy-after-peters-amazon-developer-sign-in): `ask configure`,
   `ask deploy --target skill-metadata` from `alexa/`, `scripts/alexa-oauth-client.sh <vendor id>`
   (registers the account-linking client; prints its secret once, straight into the Alexa
   console), `ask smapi update-account-linking-info` with PKCE on, then the lead sets the skill id
   for the function: `supabase secrets set ALEXA_SKILL_ID=<skill id> --project-ref
   jdwqrallbpdbshrdhenk`. Until that secret is set, the deployed function refuses every request
   (400), which is safe.
3. **Beta invites: Peter, Lea, Max and Barbie first (needs your yes).** Console → Distribution →
   Beta Test, up to 500 testers by e-mail, no certification needed. Then the beta checklist in
   [ALEXA.md, "Beta and certification"](ALEXA.md#beta-and-certification) on a real Echo: AC1
   (Milch visible in the app within 5 s), AC3 (spoken read-back), AC12 (the four of you use it
   through the invite).
4. **Certification (needs your yes, and the public privacy policy naming the skill).** Job 24's
   privacy page must say: the Alexa skill "Snacklist" sends what you say to Amazon, which turns it
   into text; Snacklist receives only that text for the items to add or the request to read the
   list, from the account you linked, and stores the items like any others; the link can be
   removed in the Alexa app or under Mehr → Zugänge; with analytics consent in the app, an add
   over Alexa is counted without its content. Snacklist Ops prepares the certification form
   (privacy URL, testing instructions draft in ALEXA.md, a test account) as a draft for your
   review. Amazon may ask why the invocation name is one word: "Snacklist" is the app's brand.
5. **Approve the skill name and invocation name "Snacklist"** (`snacklist`), as in
   `alexa/skill-package/skill.json` and `interactionModels/custom/de-DE.json`, and the example
   phrases "Alexa, sag Snacklist, füg Milch und Eier hinzu", "Alexa, frag Snacklist, was auf der
   Liste steht", "Alexa, öffne Snacklist".

## Job 31b: Alexa skill deployed (2026-10-30)

Job 31's steps 1, 2 and 5 are done: the skill "Hummlist" (invocation `hummlist`, de-DE) is on
your Amazon Developer account in the development stage, account linking and development testing
are on, the function has the skill id, and a beta test is running with no testers
([done/31b-alexa-deploy.md](done/31b-alexa-deploy.md)). Still open:

1. **Check the Test tab once (you, in the browser).** developer.amazon.com → Alexa → Hummlist →
   Test → "Skill testing is enabled in: Development", language Deutsch, type "öffne hummlist".
   Expected: "Bitte verknüpfe zuerst dein Hummlist-Konto …" (you have not linked yet). From the
   CLI, the simulation API (`ask dialog`, `simulate-skill`) answers "This utterance did not
   resolve to any intent in your skill": Alexa recognises the launch but never calls the
   skill, while Amazon-signed requests through `invoke-skill-end-point` reach it and pass. If
   the console says the same, your amazon.com account probably has no Alexa setup yet: sign in
   once in the Alexa app (or alexa.amazon.com) with that account, then try again.
2. **Beta invites** stay with Snacklist Ops (job 31 step 3), after your yes to the tester list.
3. **Certification** stays off until you say yes (job 31 step 4).

## Job 24: help and contact page (2026-10-30)

Not legal advice. The privacy policy itself is job 33a's (#105); this is the help page and the
data map behind the store forms.

- ~~**Approve the text** of the help page, German and English~~ **Done 2026-10-30, 15:40
  CET:** Peter approved `site/content/legal/support.md` and `support-en.md` ("support page
  approved.").
- **Support address:** the page uses support@snacklist.app, as the Impressum does. Keep it, or
  name another (hello@ / feedback@ exist per 33a's policy). No placeholder is left on the page.
- ~~**OK to publish**~~ **Done 2026-10-30 (Job 24 publish PR):** both files are `draft: false`,
  the footer links the page (`supportPublished` in `site/config.json`), and
  `supportPagePublished = true` in `app/lib/app/guides.dart`, so More shows "Hilfe & Kontakt" in
  release builds. snacklist.app/support and /en/support are live (still noindex, like every page).
- **Data map:** `docs/PRIVACY_DATA_MAP.md` collects what is stored where, why and how long. Job
  14 fills the App Store privacy label and Play's data safety form from it. It has no open
  `[PETER: …]` items.
- Optional: have a lawyer or a generator check the policy and this page.

## Job 25: Snacklist Lifetime (in-app purchase, sandbox)

Everything that needs no money, contract or identity is built (docs/PURCHASES.md). Until the items
below are done the purchase flow is inert: the app says "not available yet", the server answers
503. Nothing is sold, nothing is charged.

1. **Paid Applications agreement, banking, tax** (App Store Connect, Business). Without it Apple
   loads no in-app product, not even in the sandbox. App Store Connect → Business → "Paid Apps":
   View and Agree to Terms; add the bank account (account holder, IBAN, bank); complete the tax
   forms (for a German seller: the US form W-8BEN or W-8BEN-E, and the German tax details Apple
   asks for); add the contacts. Apple reviews it, usually within a day; the status turns
   "Active". Tell the Lead.
2. **Google Play payments profile** (merchant account). Play Console → Setup → Payments profile →
   Create payments profile: legal name, address, bank account; verify it. Play only lets the
   app sell in-app products after this. Tell the Lead.
3. **15 % store fee.** Apple: enroll in the App Store Small Business Program
   (developer.apple.com/app-store/small-business-program, needs item 1 active). Google: 15 % on
   the first USD 1M a year once the developer account is in an account group (Play Console →
   Settings → Account groups). The revenue estimate assumes 15 % (docs/ANALYTICS.md).
4. **Confirm or change the product decisions** (DECISIONS 25.1 to 25.5):
   - 25.1 One non-consumable, id `com.snacklist.app.lifetime` on both stores (Hummlist builds:
     `com.hummlist.app.lifetime` until R1), name "Snacklist Lifetime" (DE and EN), EUR 9.99 with Germany as base; other countries from Apple's and
     Google's automatic prices (AT and CH are printed by the setup scripts once they can run).
   - 25.2 The unlock is the household's (both partners) and stays with the household where it
     was bought, also when the buyer leaves or deletes the account. **Answered by Peter
     2026-10-31 (model A, job 43):** household-bound only; a purchase never unlocks another
     household, also not after its own is gone (DECISIONS 43.1).
   - 25.3 Apple Family Sharing for the purchase: off (Apple never lets it be turned off again).
   - 25.4 Nothing is behind the unlock yet. **Which features need it, or a free limit?**
   - 25.5 Web: no buying; More shows that it is in the iOS and Android app, and the unlocked state.
5. **Approve the privacy text** for purchases, German and English: draft section 5a in
   `site/content/legal/datenschutz-kaeufe.md` and `privacy-purchases.md` (preview only, banner
   "ENTWURF"). It says the anonymous transaction record is kept while Snacklist runs (against
   double use and to match refunds); confirm that period or name one. Then a small PR moves the
   text into the policy. Not legal advice; Apple sells as commissionaire and Google as merchant
   of record, so we keep no tax records about buyers (DECISIONS 25.9). Your tax adviser may want
   to confirm that for your bookkeeping of the store payouts.
6. **Say yes to the store screen copy** (draft): "Ein Kauf, für euren ganzen Haushalt …" on the
   Snacklist Lifetime page (`app/l10n/app_de.arb`, keys `lifetime…`), and the store description
   "Ein Kauf für den ganzen Haushalt." / "One purchase for the whole household."
   (`scripts/iap/product.ts`).
7. **Sandbox purchase on a device** (with the Lead, after NEEDS_LEAD Job 25): a TestFlight
   build, signed in to the App Store with the sandbox tester account; checklist in NEEDS_LEAD.
8. **Tester unlocks after launch.** TestFlight testers, App Review and Play license testers unlock
   their households with sandbox purchases, which cost nothing. Keep those unlocks after the
   public launch, or drop them then (DECISIONS 25.27, one database statement by the Lead)?

## Job 40: approve the 1.0 launch "What's new" (2026-10-31)

1. Read `releases/changelog/1.0.0.override.md`. It holds the German and English texts for Play (500 characters max) and the App Store. The full text is also in `docs/done/40-changelog-flags.md`.
2. Change the wording in a PR if you like. `node scripts/release/changelog.mjs drafts` checks the limits.
3. To approve it, delete the first line (`status: draft — pending Peter's review`) in that PR. Until then, `record.mjs add` refuses to record 1.0.0 as a public release.
4. When the Alexa skill is certified, set `"released": true` for `alexa-certification` in `releases/flags.json`. The next release draft then takes the held Alexa items.

   **Answered by Peter 2026-10-31:** keep them; testers also get free grants that stay with their
   households (DECISIONS 43.12, 43.13).

## Job 43: Snacklist Lifetime, household-bound (model A)

Built as decided on 2026-10-31 (DECISIONS "Job 43"), on RevenueCat. Four calls are left for you:

1. **Google buyers after 48 hours.** Google's general refund rule: within 48 hours the buyer asks
   Google Play; after that Google sends them to the developer
   (https://support.google.com/googleplay/answer/15574908). In the EEA and the UK, Google's page
   offers its own request form for in-app purchases without a deadline
   (https://support.google.com/googleplay/answer/15575720), so German buyers have a route. Outside
   the EEA after 48 hours, only the developer can refund (Play Console → Order management).
   The app's refund help says "we can't refund; Apple and Google decide", as you asked. **Do you
   want to answer such requests (refund in Play Console), or keep "we never refund"?** Nothing to
   change if you keep it.
2. **Turn on archiving for real users** once the legal texts say it (NEEDS_LEAD Job 43). Until
   then the last member of an unlocked household who joins another sees "deleted, not refunded"
   and "Trotzdem beitreten"; the archive choice exists on the server and in e2e builds only.
3. **Google refund notifications need a billed Cloud project.** RevenueCat learns of Play
   purchases and refunds in real time through a Pub/Sub topic (NEEDS_LEAD "Job 43 – RevenueCat
   setup", step 4). Pub/Sub needs a Google Cloud project with billing enabled, which job 25 avoided
   (DECISIONS 25.8: no paid resources). At Snacklist's volume it stays inside Pub/Sub's free tier,
   but a billing account has to be attached. **Allow it, or launch on Android without real-time
   notifications** (a Play refund then reaches us only as RevenueCat finds it)?
4. **Approve the new purchase legal texts, then the purchase screen goes on.** Every build hides
   Buy and Restore (`REVENUECAT_PURCHASES` off) until you approve Legal Review's text for
   RevenueCat (NEEDS_LEAD Job 43 lists the affected sentences). Then the Lead turns it on, first in
   your own build.


## Job 52: the new design (6b Hex Frische, app icon #5)

1. **Check the new look in TestFlight.** The merge ships the build to internal TestFlight as
   usual. Open it in light and dark (Einstellungen → Darstellung): the list, the add sheet, an
   item's edit sheet, Mehr and the settings, and press a yellow button to feel it sink. Check the
   home-screen icon in light, dark and tinted (long-press the home screen → Bearbeiten →
   Anpassen) and the launch screen. The changelog note "Neues Design …" stays out of the public
   changelog until you say it's good: then the Lead sets `new-design` to `"released": true` in
   `releases/flags.json`.
2. **The Widgetbook** (the component catalogue) is not on snacklist.app. Open the latest
   `widgetbook` artifact of the "Widgetbook" workflow on GitHub Actions (docs/DESIGN.md,
   "Widgetbook"), unzip it and serve it, or ask the Lead for a link.
## Job 53: approve the first homepage (2026-11-01)

PR #157 adds the landing pages `/de` and `/en` and points `/` at them. It is not merged: every
push to `main` goes live on snacklist.app.

1. **Look at the preview** (Vercel login):
   https://hummlist-site-git-job-53-homepage-v1-peter-trost.vercel.app/de and `/en`, in light and
   dark mode, on the phone and the desktop. The guides, the changelog and the legal pages now
   share the new header and footer; their texts are unchanged.
2. **Copy is a draft.** `site/COPY_NEEDED.md` lists every new or changed string (DE and EN) for
   Snacklist Launch. Approve them as they are, or have Launch change them in
   `site/content/landing/copy.yml`. The Siri card says „Bald“ / "Coming soon" until native Siri
   (job 51) is in the stores.
3. **Merge** when you're happy: on the box, under the merge lock,
   `~/groceries-ops/bin/merge-lock bash -c 'scripts/push-pr.sh && scripts/merge-pr.sh --wait 157'`.
   The production build then serves `/de` and `/en`, and `/` redirects there. `noindex` stays on
   every response until you decide on the beta launch.
4. **Job 54's demo videos** drop into the three slots without a code change
   (`site/public/media/README.md`); until then the slots show stills.

## Job 57: two looks on a phone, and four design calls (2026-11-01)

1. **Sign in with Apple on an iPhone.** The login draws Apple's button itself now (the package's
   Apple logo, black in light and white in dark, 15 px label, 48 px), so it matches Google's.
   Open the next TestFlight build signed out and check it looks like Apple's own button. If not,
   say so and it goes back to the package's button with its larger label.
2. **Retailer logos in the store badge.** Your calls on job 56 items 31 to 34 (15:17) are built.
   The badge shows the store's name in a hex until the Legal Review clears retailer logos; then
   `StoreBadgeStyle.logo` takes the logo files (DECISIONS job 57 addendum 5).
3. **The household name over the list (job 56 item 6).** The site's app header shows the household
   name in caps, the open-item count and the members as hex initials. You took name and count out
   in job 29a. Say if you want the site's header in the app after all; it is built and was left
   out only because of your 29a call (DECISIONS job 57, 16).

## Job 63: Home Screen widgets (2026-11-01)

The iOS widget is an app extension, `com.snacklist.app.HomeWidget`, that
reads the list from the App Group `group.com.snacklist.app` (Hummlist builds:
`com.hummlist.app.HomeWidget` and `group.com.hummlist.app`, which the steps below
registered on 2026-11-01). The App Store
Connect API key can register an App ID but cannot create an App Group or
assign one to an App ID, so these steps are in the browser. Until they are
done and the profiles are renewed, the iOS release on `main` fails in
`preflight` ("Profile ... is missing"), so job 63's PR must not merge
before step 7.

1. <https://developer.apple.com/account>, Peter signs in. **Certificates,
   Identifiers & Profiles**, **Identifiers**, the **+** button, **App
   Groups**, **Continue**. Description `Hummlist`, identifier
   `group.com.hummlist.app`. **Continue**, **Register**.
2. **Identifiers**, **+**, **App IDs**, **App**, **Continue**. Description
   `Hummlist Home Widget`, **Explicit** Bundle ID
   `com.hummlist.app.HomeWidget`. Under Capabilities tick **App Groups** only.
   **Continue**, **Register**.
3. Open `com.hummlist.app.HomeWidget` again, **App Groups**, **Configure**,
   tick `group.com.hummlist.app`, **Continue**, **Save**.
4. Open `com.hummlist.app`, tick **App Groups** (leave every other
   capability as it is), **Configure**, tick `group.com.hummlist.app`,
   **Continue**, **Save**, confirm the dialog about invalidated profiles.
5. Do not touch **Certificates** or **Profiles**: no revoke, no new
   certificate. "match AppStore com.hummlist.app" now shows "Invalid"; that
   is expected.
6. Post on BOARD.md that job 63's portal steps are done. Then, on the box, in
   `app/` of a checkout of the job 63 branch (its Matchfile names both
   identifiers), run `bundle exec fastlane ios renew_profile` exactly as
   docs/RELEASE.md, "Capabilities", step 2 shows. match regenerates the app's
   profile and creates "match AppStore com.hummlist.app.HomeWidget", both
   with the existing certificate `GN85KDC962`; it creates and revokes no
   certificate. `MATCH_FORCE=false` afterwards checks without changing
   anything.
7. `bundle exec fastlane ios preflight` (same environment, plus
   `TESTFLIGHT_JSON=/tmp/tf.json`) passes for both profiles. Now the PR may
   merge.

Then the device test, on an iPhone (TestFlight build) and an Android phone:

- [ ] Add the small and the medium widget (iPhone: Bearbeiten → Widget
  hinzufügen → Snacklist; Android: Widgets → Snacklist, 2x2 and 4x2).
- [ ] Both show the open count and the next items; medium shows the store
  pills with the store's full name and the Add button.
- [ ] Add and tick in the app: the count and rows follow within a second or
  two.
- [ ] Airplane mode, reopen the app: the widget still shows the last list.
- [ ] Add opens the app with the add sheet and the keyboard; a tap anywhere
  else opens the list (also from the More tab, and with the app closed).
- [ ] Sign out: the widget asks to sign in; a tap opens sign-in.
- [ ] German and English phone language; light and dark mode.
- [ ] If all is well, set `home-widgets` to `"released": true` in
  `releases/flags.json` and remove `draft: true` from both widget guides.

## Job 66: deep links (app.snacklist.app opens the app)

Nothing to set up: Associated Domains is on for `com.hummlist.app` (L6, again confirmed by Ops on
2026-11-02 for job 63) and Google already verifies app.hummlist.com for the Play signing key
(Hummlist builds; the old invite links on app.hummlist.com keep working until R1). The
new paths open the iPhone app once app.snacklist.app serves the new
`/.well-known/apple-app-site-association`, that is with the next *dispatched* Release run (the
web follows the store release), and Apple's CDN has fetched it (up to a day). Android needs only
the new build. Route table: `docs/DEEP_LINKS.md`.

1. **Device check, iPhone and Android** (no simulator or emulator on the build machines), with
   the TestFlight / Play internal build of this release installed. Send yourself these links in
   a message (Notes or Mail work too; typing them into Safari does not trigger the app):
   `https://app.snacklist.app/more/invites`, `https://app.snacklist.app/add`,
   `https://app.snacklist.app/more/settings`, `https://app.snacklist.app/list`,
   `https://app.snacklist.app/irgendwas` and `https://app.snacklist.app/stores/<id>` (the id of one
   of your stores: `select id, name from stores` in the SQL editor, or ask the lead).
   1. Signed in: each link opens the Snacklist app (not the browser). `/more/invites` shows
      „Einladungen“, `/add` the list with the add field open, `/more/settings` „Einstellungen“,
      `/list` and `/irgendwas` the list, `/stores/<id>` the list at that store.
   2. Signed out (Mehr → Konto → „Abmelden“): tap `/more/invites`. The app opens on „Anmelden“;
      sign in with Apple or Google: „Einladungen“ opens.
   3. If the browser opens instead: long-press the link, choose „In Snacklist öffnen“, and tell the
      lead which link and phone (the domain file is not live yet, or Apple has not fetched it).
   4. Invite links (`/join/<code>`) and sign-in by email link still work as before (job 22 list).

   Not checked on a device yet: the Associated Domains entitlement (`applinks:app.snacklist.app` and
   `applinks:app.hummlist.com` in `Runner.entitlements`) and the Android filter were checked by reading the files and by
   `deep_links_config_test.dart`; the routing itself by the web build (`e2e/tests/deep-links.spec.ts`).
## Job 67: the paywall release (2026-11-02)

Everything is ready for the switches. Nothing is on yet. [`PAYWALL_RELEASE.md`](PAYWALL_RELEASE.md) lists them in order. Your yes is needed for these steps:

1. Google Play real-time notifications. They need a Google Cloud project with billing attached and stay inside the free tier (step 1.4).
2. The store prices, and any change to the products (step 2.3).
3. The legal texts: PR #153 with section 5a, and later the terms of use (steps 4.1 and 4.2).
4. The sandbox run on your phones (step 5.3), then opening the sale (step 5.4).
5. The App Store review submission and the Play production release (step 5.5).
6. Which beta households keep Siri, Alexa and AI assistants free, then the integration lock (steps 6.1 and 6.4).
7. Whether the Home Screen widgets should become Premium. Today they stay free. Making them Premium would be new work.

## Job 69: „Alexa, öffne Hummlist“ answered „Ich weiß nicht“ (2026-11-02)

The logs say the request never reached Hummlist (inferred from timestamps; the simulator run
that would reproduce it needs the box, docs/ALEXA_CERTIFICATION.md "Results"). The function's logs on 2026-11-02 show four requests to
`alexa`: 07:38 CET (the deploy's unsigned smoke check, refused on purpose), then 08:16, 08:25:34
and 08:25:41, which match the skill being linked, disabled and linked again. Nothing came after
08:25:41, and the one link Hummlist holds was last used at 08:25:41. So for „öffne Hummlist“
Alexa did not call the skill at all. Two causes fit, and only your account can tell them apart:

1. **Alexa misheard the name.** Alexa app → **Mehr** → **Einstellungen** → **Alexa-Datenschutz**
   → **Sprachaufnahmen-Verlauf**: the entry for that request shows what Alexa heard. „öffne
   homelist“ or „öffne hamlist“ means speech recognition. The guide now says to say
   „Humm-list“ in two syllables, or „Alexa, öffne Hummlist“ first.
2. **The Echo isn't on the account with the skill.** The skill was enabled and linked on Lea's
   account. If the Echo is registered to your account, or Alexa takes your voice profile, Alexa
   looks for the skill in your account and doesn't find it. Check in the Alexa app of the
   account the Echo belongs to (**Geräte** → the Echo → **Registriert für**), and enable and link
   the skill there (the beta invitation has to go to that account's e-mail).

**Simulator result (box, 2026-11-02 ~11:00 CET):** typed „öffne hummlist“ does **not** reach the
skill either, in any of the six locales, for the developer account (p.trost93@gmail.com). So
cause 1 is ruled out as the only cause. Amazon's validation passes and the endpoint answers when
it is called directly. Please open the developer console (developer.amazon.com → Hummlist →
**Test**), check that testing is set to „Development“, and type „öffne hummlist“ in the simulator
there. Then check which Amazon country the developer account and Lea's account use (Alexa app →
Einstellungen → Info/Über: Host Name alexa.amazon.de). Details in docs/ALEXA_CERTIFICATION.md
„Results“.

## Job 91: Alexa „Verbindungsproblem“, what only your accounts can show (2026-11-03)

This morning's attempts never reached Hummlist. Linking at 08:21 worked, but no „öffne Hummlist“
or „sag Hummlist …“ request has ever arrived at the skill. So Alexa stopped them on Amazon's
side. These five checks tell us where. `scripts/alexa/diagnose.sh` (docs/ALEXA.md
„Troubleshooting“) shows whether a request arrived; the lead can run it for you.

1. **What Alexa heard.** Alexa app → **Mehr** → **Aktivität** → **Sprachverlauf**: for this
   morning's attempts, note the exact words Alexa heard and the answer or card she gave.
2. **Which account the Echo belongs to.** Alexa app → **Geräte** → the Echo → **Registriert
   für**: which Amazon account? It must be the beta-invited account that linked Hummlist at
   08:21 this morning. If it is another account, invite that account's e-mail address to the
   beta, then enable and link the skill there.
3. **Alexa+.** Is this Echo on Alexa+ (Early Access)? Alexa+ may treat beta skills differently.
4. **The console test.** developer.amazon.com → Hummlist → **Test** tab: set it to
   „Entwicklung“, choose Deutsch (Deutschland), and type „öffne Hummlist“. Note the time, so
   the lead can check in diagnose.sh whether a LaunchRequest arrived.
5. **The second beta tester.** Distribution → Beta Test: one tester is still NOT_ACCEPTED. Resend
   the invitation, or remove the tester if they are not testing.

The linked half of `scripts/alexa/smoke.sh` also needs the certification test account
(docs/ALEXA_CERTIFICATION.md „Left for the console“, item 1) and an access token of it. Until then only the unlinked half runs.
## Job 92: German Siri routing (2026-11-03)

PRs #221 (profiles, Siri entitlement) and #222 (phrases, spoken names, SiriKit Lists). Ops
enabled the SiriKit capability on `com.hummlist.app`; CI regenerated the App Store profiles with
the existing certificate. On an iPhone with Siri set to Deutsch (Deutschland):

1. **Transcripts on build 1119.** Einstellungen › Siri › Antworten › „Transkription immer
   anzeigen“ on. Say each phrase of docs/SIRI_SHORTCUT.md „Gerätetest Deutsch“ and screenshot
   what Siri wrote. The three German spoken names (today „Humm Liste“, „Hummliste“, „Ham Liste“)
   are picked from what Siri writes; send the screenshots to the lead.
2. **Kurzbefehle app.** Does a Hummlist section with „Zu Hummlist hinzufügen“ and „Meine
   Hummlist vorlesen“ appear?
3. **Siri for Hummlist.** Einstellungen › Apps › Hummlist › Siri: „Mit Siri verwenden“ and „Von
   dieser App lernen“ on. On the build with job 92, the app asks once after sign-in whether
   Hummlist may use Siri: allow it.
4. **SiriKit capability.** Done by Ops on 2026-11-03 (App ID `com.hummlist.app`, team
   VCZSHMZY25). CI renewed the App Store profile the same evening (Certificates run 41733197123:
   `match AppStore com.hummlist.app` INVALID before, ACTIVE after, certificate `GN85KDC962`
   unchanged). Nothing left here.
5. **German retest** on the first TestFlight build that contains #222, by the protocol in
   docs/SIRI_SHORTCUT.md „Gerätetest Deutsch“, before the `native-siri` hold ends. Record build
   number, transcript and outcome per phrase.

## Job 97: Siri fix-now and iOS 17 (2026-11-04)

Everything is built and checked on CI; only an iPhone can show what Siri hears. On the first
TestFlight build that contains job 97 (it reaches TestFlight through the normal release pipeline
after the lead merges; nothing was uploaded by this job):

1. **Device test, German and English.** Run the table in docs/SIRI_SHORTCUT.md „Gerätetest (job
   97)“ with Siri in Deutsch (Deutschland), then in English. Record build number, transcript
   screenshot and outcome per phrase. Note especially how Siri writes the name: the German
   alternative names (Humlist, Hamlist, Homlist) are educated guesses, and the lead swaps them
   for what Siri actually writes, as long as it does not end in „Liste“.
2. **Kurzbefehle app.** The Hummlist tile should list three actions now: „Zu Hummlist
   hinzufügen“, „Meine Hummlist vorlesen“, „Hummlist öffnen“.
3. **iPhones on iOS 15 or 16** no longer get updates. Nothing to do; they keep the last build and
   the Shortcut recipe.
## Job 82: the snacklist.app waitlist (2026-11-02)

Built and off (`docs/WAITLIST.md`). Three steps turn it on, in this order. Nothing here costs
money. Keep every secret out of the repo, PR texts and chats.

1. **Resend key** (only you can make it): in Resend, domain snacklist.app, create an API key with
   "Sending access" for that domain. Check that open and click tracking are off for the domain.
2. **Supabase secrets** (project `jdwqrallbpdbshrdhenk`, Edge Functions › Secrets, or
   `supabase secrets set --project-ref jdwqrallbpdbshrdhenk ...`):
   - `RESEND_API_KEY`: the key from step 1.
   - `WAITLIST_PROXY_SECRET`: a new random value (`openssl rand -hex 32`); the same value goes
     into Vercel in step 3.
   - `WAITLIST_HMAC_SECRET`: another random value. Never change it later: it signs every
     unsubscribe link and the proof records.
   - Leave `WAITLIST_MAIL_ALLOW` unset while testing: then only `test@snacklist.app`, `test+…@snacklist.app`
     and (until after the weekend) `hello+…@hummlist.com` addresses are stored and mailed. Set it to `*` on the day the waitlist goes public.
3. **Vercel** (project of snacklist.app, `hummlist-site`, Settings › Environment Variables), first for **Preview**
   only:
   - `WAITLIST_UPSTREAM_URL` = `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/waitlist`
   - `WAITLIST_PROXY_SECRET` = the value from step 2.
   Then sign up on the PR's preview with a `test+waitlisttest…@snacklist.app` address, confirm,
   and unsubscribe. Region proof: `curl -si -X POST <preview>/api/waitlist ...` with your Vercel
   login's bypass, and check that `x-vercel-id` contains `::fra1::`; save the output to
   `docs/legal/waitlist-region-proof.txt` (Addendum 4).
4. **Going live** (after your OK of the copy and Legal's texts in your own words): set the two
   variables from step 3 for **Production** too and `WAITLIST_MAIL_ALLOW=*` in Supabase, then merge
   PR #210. The merge itself publishes the waitlist: there is no separate site switch any more
   (Addendum 8: the stage is `site/config/stage.ts`, `waitlist`). Merging before the variables are
   set shows the form, but every sign-up then answers "Das hat gerade nicht geklappt".

Off again: unset `WAITLIST_PROXY_SECRET` in Supabase (every request 404 at once, the form says it
didn't work); taking the form off the page is a PR (revert, or another stage).

Requests by mail: an unsubscribe or deletion request at support@snacklist.app is yours the same day
(Legal). Without the person's link, delete by SQL in the SQL editor (this writes the proof
record for a confirmed row):
`select public.waitlist_unsubscribe(id, now()) from public.waitlist where lower(email) = lower('<address>');`

## Job 101: one unintended write to the hosted auth config (2026-11-05)

While checking a lint fix, a job 101 subagent ran `node scripts/configure-social-auth.mjs` without
`--dry-run`, with `SUPABASE_ACCESS_TOKEN` in its shell (about 07:15 CET). The script reads the
hosted project's auth config and PATCHes it. A dry run afterwards showed what that PATCH holds when
no Google or Apple credentials are in the environment: only `uri_allow_list`, set to the current
list, trimmed and deduplicated, plus `com.petertrost.familygroceries://login-callback` and
`com.hummlist.app://login-callback`, which were both already in it. Google and Apple were left
alone. So the write most likely changed nothing, or at most removed duplicates or spaces. That is
an inference, because the list from before the run was not recorded.

The lead checked read-only at 07:41: the redirect list had its 7 entries intact, and Google and
Apple sign-in were still enabled.

- [ ] Optional: in the Supabase dashboard (Authentication, URL Configuration), confirm the
  redirect URLs are the ones you expect.

The job now tells its subagents never to run a script against a hosted service.

- [ ] Follow-up: the strict TypeScript pack (`tool/lint/ts/pack.ts`) still excludes the Alexa,
  Siri and IAP code, which the hill-climb brief froze. Queue a normal job, owned by whoever owns
  those areas, that removes those exclusions and fixes the findings.
- [ ] Follow-up: `tool/hillclimb/hc-backend-perf/bench.ts` (job 106's measurement harness, 32
  findings) is excluded from the pack because the hill-climb protocol freezes it. Fix it when job
  106's goal is next re-baselined.

## Job 155: the store rating prompt waits for the public release build (2026-11-06)

iPhone: nothing to do. The build the testers had is the one to submit; StoreKit never shows the
prompt in TestFlight, so testers are not asked and App Store users are. Android: when the public
release step exists (its own job, your go), its Play production AAB is the tested commit built
once more with `--dart-define=STORE_RELEASE=true`; internal-track builds never pass it
(docs/RELEASE.md, "Public releases"). If you would rather promote the internal AAB unchanged,
say so: then Android never asks, which is safe. Before launch, check the native dialog once on a
phone:
`flutter run --dart-define=REVIEW_PROMPT_FORCE=true`, tick off a list, wait 3 s (iOS shows it in
debug builds; Android only for an app installed from Play).

## Job 149: deleting single items, after the edit sheet lost Löschen (2026-11-06)

The edit sheet has no Löschen any more (your call, t612u). The public deletion page
`app.snacklist.app/konto-loeschen.html#einzelne-daten` (Legal N-11, approved Nov 1) said „Tippe auf
Löschen“ in that sheet. It now says: tick an item to take it off the list; with a screen reader
each item has the action Löschen (with Rückgängig); single items and history entries are deleted
on request by email. A ticked item stays under „Zuletzt verwendet“, so on the web a sighted user
can no longer delete one item themselves.

- [ ] Check the new wording of „Einträge und Verlauf“ on that page (and with Legal, if the Play
  Data safety form says users can delete single data in the app).
- [ ] If single items should stay deletable for everyone, say where (for example in „Zuletzt
  verwendet“); this job adds no new delete path, as the brief asked.

## Job 170: Siri and Alexa test session (2026-11-08, 16:00)

Everything that needs your iPhone or Echo is in `docs/voice/TEST-SESSION-2026-11-08.md`, in
order, with the expected answer and a fix for each failure. It replaces the open device steps of
„Job 69“, „Job 91“, „Job 92“ and „Job 97“ above.

- [ ] Run the session; send the lead the failed rows with their times, the transcript
  screenshots, the iOS version, Alexa+ yes or no, and the account Alexa names („Alexa, welches
  Konto ist das?“).
- [ ] If the Echo's account isn't the Alexa developer account: accept the skill's beta
  invitation on that account first (the lead sends the link from the console's Beta-Test page).

## Job 172: „26 Artikel auf deiner Einkaufsliste“ was Alexa's own list (2026-11-08)

The answer you heard at about 14:35 did not come from Hummlist: no read request reached the skill
after your add at 14:33, and the skill never says „Artikel“ (it said „Auf der Hummlist stehen 3
Sachen: …“, now „Auf der Snacklist stehen …“). Alexa's built-in shopping list answered. Snacklist's read-back (Alexa, Siri, the AI
assistants) counts only open items; a test now holds that with ticked items present.

- [ ] Optional: Alexa app › Listen › Einkaufsliste. If it holds 26 old entries, clear them, so
  a misheard „humm list“ doesn't read them out.
- [ ] Ask again with „Alexa, öffne humm list“ (Humm-list in two syllables), then „Was steht auf
  der Liste?“ (rows A8 and X9a in `docs/voice/TEST-SESSION-2026-11-08.md`).

## Job 169b: households, invite loop and club features (2026-11-08)

Built and merged (#327, #332, #333). What only Peter can do:

1. **Legal review of the privacy text and the club data processing agreement.** Draft PR #328
   (do not merge) changes `site/content/legal/datenschutz.md` and `privacy.md` and adds draft
   `avv.md` / `dpa.md` (hidden in production builds). 27 open questions are in
   `docs/legal/169b-privacy-draft.md` on that branch, among them: the legal basis for showing the
   inviter's first name on the signed-out join page (Art. 6(1)(f)?), the hourly salted IP hash,
   the Play Install Referrer and the tap-to-paste clipboard read under § 25 TDDDG, removal
   records (30 days), and whether a club needs an AVV at all. Merge the policy only after Legal
   approves. **Urgent: the features are already live.** Each merge shipped by the release workflow
   (web app.hummlist.com, TestFlight, Play internal): wave 1 (several households) on 2026-11-08
   at about 21:14 CET, wave 2 (join page, group links, removal) on 2026-11-09 at about 00:01
   CET, wave 3 (lists, claims, join approval) at about 01:12 CET (release runs 42517677040,
   42531652600, 42537666564). Until #328
   lands, the published policy contradicts them: it says invite links last 7 days and work once
   (group links: 30 days, 50 people) and doesn't mention the signed-out join page showing the
   inviter's first name, its salted IP hash or the removal records. Options while Legal reviews:
   merge #328 as is, or hide group links behind a flag (Peter's call).
2. **Store listings and the join page.** When the App Store and Play listings are public, set
   `storeListings` in `app/web/join/join.js` (both) so `/join/<code>` shows "App laden" and the
   Smart App Banner (`app-id=6826922741`), and fill `site/config/stores.mjs`.
3. ~~**Play Console "Data safety".**~~ Obsolete (job 178, Legal N-111): the app no longer reads
   the Play Install Referrer and the Play link carries no invite code.
4. **Decide later (product):** a removed member can be re-invited by any member after 30 days
   (removal records are purged for privacy; DECISIONS 169b W2 item 10); a club has no signal for
   open join requests outside More → household; any member can rename or delete a list or rename
   the household, also in clubs; when the default household is left or someone is removed from it,
   Siri, Alexa and AI assistants move to the oldest other membership without asking; "Neuer
   Haushalt" in the switcher asks for no kind, so a club made there gets no club share text and no
   approval default (job 168's onboarding sets the kind). All deliberate for now.

## Job 168c: guided start and join approval (2026-11-09)

1. **Decide whether to backfill join approval.** #331 (guided start) created club households
   with „Beitritte bestätigen“ off, against the W3 rule that a new club starts with it on; #336
   fixes new ones. Clubs made in between keep it off. To see how many there are, in the SQL
   editor: `select count(*) from households where kind = 'club' and join_approval = false and
   created_at >= '2026-11-09 03:00+01';`. A club the buggy build created but whose kind was
   written only after the fix (an app killed mid-setup) also keeps approval off; the query finds
   it too. If any, decide: leave them (owners can switch it on under Mehr → household; some may
   have chosen off), or switch them on with an `update` limited to those rows. Nothing was
   changed in production by the job.
2. **Join requests have no signal on the guided start's invite step.** Since #336 every club made
   in the guided start has join approval on, so a member who accepts an invite from its invite
   step becomes a join request: the step's card stays unchanged (no „beigetreten“), and the
   request waits on Mehr → the household. This is 169b's item 4 gap („no signal for open join
   requests outside More → household“), now on the main club path. Decide together with that
   item whether the invite step should show waiting requests (a later job; copy and UX).
3. **Later copy job: the invite entry on a club's Mehr menu.** On a club, Mehr still says
   „Partner einladen“ (169b W2's generic entry), while the guided start says „Mitglieder
   einladen“. Left unchanged here (no copy changes in a landing job); a copy job should decide
   the wording per household kind.

## Job 173: partner news on phones, the household cap on joins (2026-11-09)

1. **Where „1 neu von Lea“ sits on a phone (design call, works either way).** Since the
   household chip came (#327), the bar has no room on a phone for the chip, the news line and
   „Anpassen“ side by side: at 390 px the chip and the line share 212 px, and the line alone
   needs 124. The line now shows whole right below the household chip, floating over the top of
   the list like the sync card, until the adds are seen; on a tablet and the web it stays in the
   bar. „Seen“ means each new row has been on screen for 3 s, and new adds often sort below the
   fold, so the line can stay until the user scrolls down to them: in the post-merge review it
   still showed after 60 s. For that whole time it covers the left part of whatever is under it:
   at the top of the list the first store divider's badge and name („Ohne Laden“ in the demo),
   and once scrolled, the names of the top rows passing under it (for example „Obst & Gemüse“
   and „Bananen“). It ends before the column under „Anpassen“, so a divider's count and fold
   key stay usable. Taps on it do nothing, which also means a tap on a row's name under it
   doesn't tick that row until the line clears. A long partner name takes a second line before
   it ellipsizes. Screenshots: `docs/screenshots/173/`. Other options,
   if you prefer one: push the list down by the line's height while it shows (the rows jump
   twice, once when a partner adds and again when it clears); shorten the line to „1 neu“ in
   the bar on phones (who added only for screen readers); or give „Anpassen“ an icon on phones
   to make room. Decide in a later design job; nothing to do now.
2. **Users above 10 households.** Joins were not capped until this job. Anyone who joined an
   11th or more keeps those households (nothing was removed); they can't join or create more
   until they are below 10. To see whether anyone is affected, in the SQL editor:
   `select user_id, count(*) from household_members group by user_id having count(*) > 10;`.
3. **Copy: a join request that can't be granted any more.** If someone asks to join a household
   with approval on and then reaches 10 households before an admin decides, „Aufnehmen“ closes
   the request instead of letting them in (they would be in 11). The admin's row just goes
   away, and the requester reads „Deine Anfrage für „…“ wurde nicht angenommen.“, which sounds
   like a decline. A copy job could give both sides their own words („… ist schon in 10
   Haushalten“). Rare: it needs a join elsewhere while the request waits. On the oldest builds
   (`join_household`), asking at 10 into such a household now files no request and looks like
   an invalid code, where before a request was filed that an approval would close anyway.
   Restoring an archived household at 10 shows the cap text, which says „anlegst oder
   beitrittst“ and doesn't name a restore; the same copy job could cover it.
4. **Copy items from the verification run of 2026-11-09 (vmaint-20261109, gaps 3-6).** Found
   in its summary, not changed here (copy is Peter's call); a copy job can take them together:
   - **The consent page promises Alexa a choice it can't make.** For a user in several
     households, the AI-assistant consent page says „Arbeitet in deinem Standard-Haushalt „X“.
     Nennst du einen anderen deiner Haushalte, auch dort.“ to every app, Alexa included. Alexa
     always uses the default household and has no way to name another.
     `app/lib/oauth/consent_screen.dart:318` (`consentDefaultHousehold`).
   - **The AI tip mentions the API.** „Noch besser mit KI & Automatisierung“ says „… oder nutze
     die API, um Automatisierungen zu erstellen.“ (`hintAssistantBody`, `app/l10n/app_de.arb:1096`,
     shown by `app/lib/tips/hints.dart:230`), also on the web Tipps page, while API keys stay
     behind the off `public-api` flag.
   - **„Zugangs-Tokens“ in the deletion dialog.** „Konto löschen“ says „deine Zugangs-Tokens“
     (`accountDeleteWhat`, `app_de.arb:230`); everywhere else users see „Zugriffstoken“.
   - **German admin text wrong after an owner handover.** `householdNotOwner` reads „Admins
     ernennt nur, wer den Haushalt angelegt hat.“ (`app_de.arb:995`). Since the owner role passes
     on when the creator leaves, the person who may name admins is the owner, not necessarily
     the creator. The English text ("Only the household's owner names admins.") is right.

## Job 174: Snacklist rename, code and copy (2026-11-10)

1. **Mail addresses stay @hummlist.com.** The app, the legal pages, the support pages and the
   consent texts still name support@, hello@ and feedback@hummlist.com: the snacklist.app
   mailboxes don't exist yet. When they do (S3: Workspace secondary domain, Resend), say which
   addresses Snacklist uses; one PR then swaps them together with the privacy and imprint pages.
   Done the same day: the mailboxes exist, mail goes out from hello@snacklist.app (#356 to #358),
   and the final sweep put support@, hello@ and feedback@snacklist.app in the app, the legal and
   support pages.
2. **Siri's alternative names, on your iPhone.** Siri gets „Snacklist“ as the spoken name and,
   for what it may write instead, de „Snack List“, „Snäcklist“, „Snecklist“ and en „Snack List“,
   „Snack-list“, „Snack Lists“. The brief also listed „Snacklist“ itself; the repo's Siri checks
   refuse an alternative that repeats the app name (it costs one of the three slots and matches
   nothing new), so „Snecklist“ and „Snack Lists“ took its place. On the first Snacklist
   TestFlight build: say „Füge Milch zu Snacklist hinzu“ and „Was steht auf Snacklist?“ a few
   times; if Siri writes the name another way, that spelling should replace one of these.
3. **The waitlist pages mix both names until S3.** The sign-up and confirmation pages say
   Snacklist („Snacklist-Beta“), but the consent texts right below them
   (`site/content/legal/consent/waitlist-*`) and the waitlist mails still say Hummlist („Peter
   Trost (Hummlist)“, sender „Peter von Hummlist“). Those consent texts are versioned records the
   waitlist function checks, so a Snacklist version goes in together with the new mail sender
   (S3). Say if the waitlist should rather stay all-Hummlist until then.
   Done the same day: the sender is „Peter · Snacklist“ (#357), and the final sweep added new
   consent text versions (`waitlist-*-v3`, `waitlist-confirm-*-v2`) with only the name and
   address swapped.
4. **Apple's sign-in list may still say Hummlist.** After an account deletion the app tells
   Apple users to remove „Snacklist“ under „Mit Apple anmelden“. Apple shows the name of the
   primary App ID or Services ID the user signed in with; Snacklist's App ID is grouped under
   Hummlist's, so users may see „Hummlist“ there. Worth a look in the Apple Developer portal at
   S3 (the Services ID description is already „Snacklist“).

## Job 94: MCP 2026-07-28 and Client ID Metadata Documents (2026-11-04)

PR #231. Nothing blocks the merge; two optional checks after the deploy, both on production:

1. **One hosted sign-in through the CIMD front (optional).** The front's fetch, DNS and the
   admin API's secret key on the hosted project are proven locally only. To prove them on
   production, open this URL in a browser while signed in to Snacklist and stop at the consent
   page (do not press Erlauben):
   `https://mcp.snacklist.app/oauth/authorize?response_type=code&client_id=https%3A%2F%2Fclaude.ai%2Foauth%2Fmcp-oauth-client-metadata&redirect_uri=https%3A%2F%2Fclaude.ai%2Fapi%2Fmcp%2Fauth_callback&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=check`.
   It shows „Zugriff erlauben?“ with „Claude“ and https://claude.ai. This registers one Supabase
   OAuth client named „Claude“ for Claude's document, the one a real Claude on 2026-07-28 would
   use anyway. The smoke does not do this on its own (DECISIONS, job 94).
2. **The client address behind the proxy.** After the first token request through
   mcp.snacklist.app/oauth/token, the hosted edge logs of `mcp` should show requests with the
   header `x-vercel-forwarded-for`. If it is missing, the per-address token limit is one
   bucket for everyone on the proxy; tell the lead.

## Job 177: Snacklist mail design, before it goes live (Peter, after review)

The PR restyles every mail Supabase Auth can send (German and English, AL4's wording) and the
onboarding and notice mails. Nothing is live, nothing was sent, the hosted project is unchanged.

1. **Review** (done: Peter, 2026-11-10, "362 looks good, go ahead") every mail, German and English: the review page
   `~/groceries-ops/jobs/177-mail-design-snacklist/previews/index.html` (PNGs, HTML and plain text
   per mail; on the box under the same jobs path), or render it yourself:
   `cd emails && npm ci && flock /tmp/fg-e2e.lock npm run preview -- --out /tmp/mails`.
2. **Approve the Legal footer texts** (N-15 a and b, `emails/src/components/Footer.tsx`): Legal's
   words with Snacklist's name, domain and addresses swapped in.
3. **Merge** (done: job 179, 2026-11-10). Merging changes nothing on the hosted project; the site
   deploy puts the logo at `https://snacklist.app/email/snacklist-icon-96.png`.
4. **Approve or rewrite the draft reason lines** (the grey "Du bekommst diese E-Mail, weil …" line)
   of confirmation, recovery, email change, invite and reauthentication, DE and EN, in
   `emails/src/emails/auth.tsx` (`draft` becomes `confirmed`, then `cd emails && npm run build`).
   The deploy refuses a template with a draft line, so until then the hosted project keeps AL4's
   plain mails.
5. **Put the templates live** from a checkout of `main` with a personal access token:

   ```sh
   export SUPABASE_ACCESS_TOKEN=... SUPABASE_PROJECT_REF=jdwqrallbpdbshrdhenk
   deno run --allow-read --allow-env --allow-net --config supabase/deploy/deno.json \
     supabase/deploy/auth_mail.ts --dry-run   # lists the six mailer_templates_*_content keys
   deno run --allow-read --allow-env --allow-net --config supabase/deploy/deno.json \
     supabase/deploy/auth_mail.ts
   ```

   Then send yourself a sign-in link from the app in each language. To go back, run the same
   script from a checkout of `0873093e` (AL4's plain templates).

## Job 195: validation events and PostHog's test-account filter (2026-11-12)

1. **Check cohort 293017** in PostHog (project Snacklist, Settings → Product analytics →
   "Filter out internal and test users"). The repository's key cannot read cohorts or project
   settings (error-tracking scope only), so job 195 could not look. The app and the functions send
   every event without a person profile (`$process_person_profile: false`), and a cohort holds
   persons, so by PostHog's documented behaviour the cohort filter keeps every event, internal ones
   included (`docs/ANALYTICS.md`, `is_internal`).
2. **If you want the default filter to drop internal events**, add the event-property filter
   `is_internal` · `is not` · `true` next to the cohort there. Nothing in the repository depends on
   it: the gate queries filter through `analytics/queries/internal.sql` already, which also drops
   an install's events from before it was marked internal. Job 195 changed no project setting and
   created no person profiles.
3. **Set the pass bars** for F2, F3 and F5. The events are in the catalog; `mcp_tool_call` and
   `api_key_used` are sent from the next functions deploy on, the F2 and F3 events once the prices
   and scanner UIs ship behind their flags.

## Job 185: per-user Premium, before sales go on (2026-11-13)

Per-user Premium is in the code and dark: the app would send the Snacklist user id to RevenueCat
as the App User ID, but only after a tap that needs `REVENUECAT_PURCHASES` and `premium_offer`,
both off. Before either goes on:

1. **Legal: the purchase privacy texts.** `site/content/legal/datenschutz-kaeufe.md`,
   `privacy-purchases.md` and `privacy.md` (§5, §12, §14) say RevenueCat receives the household's
   id, "nicht deine Konto-ID", and that the store links the purchase to the household. With
   per-user Premium RevenueCat receives the account id (and Apple gets it as `appAccountToken`,
   Google a hash of it), the purchase belongs to the account, and an account deletion deletes the
   RevenueCat customer 30 days later if the id ever reached RevenueCat. Job 185 changed no legal
   text (brief). The App Store privacy label and Play Data safety form (PAYWALL_RELEASE 4.4) need
   the same change.
2. **Peter and Legal: a deleted account's Lifetime.** Like a deleted household's, a deleted
   account's purchases are purged to tombstones after 30 days, so a person who deletes their
   account and signs up again cannot restore Lifetime onto the new account. Say if that should
   change.
3. **Copy, through the prototype gate (t777u).** These strings promise the household, not the
   buyer: `premiumHeroBody` („Snacklist Premium gilt für euren ganzen Haushalt, auch für alle, die
   später dazukommen.“, on screen today), `premiumHeroTitle` („Einer kauft. Alle haben es.“),
   `lifetimeWeb`, `premiumHousehold`, `lifetimeUnlockedBody`, `accountDeletePremium`,
   `accountDeletePremiumLastMember`, `premiumChecking`, `premiumLifetimeWhileYearly`,
   `premiumLifetimeWhileYearlySubscriber` („Euer Haushalt hat schon ein Jahresabo …“, now also for
   the buyer's own plan) and `lifetimeUsedElsewhere` („Dieser Kauf gehört zu einem
   anderen, früheren Haushalt …“). The Premium page also draws three members and a plus in a one-person
   household. The subscriber of their own yearly plan now also gets the "your plan keeps billing"
   dialog when leaving or joining any household (the text stays true); say whether it should show
   there. Rewrite them once `shared-views` is decided.
4. **Ops: nothing in RevenueCat changes.** Keep "Keep with original App User ID". Testers keep
   household grants (`scripts/iap/promotional.ts`) until the privacy text describes user grants.

## Job 201: Play uploads and web production stopped at the repo rename (2026-11-13)

Every `release.yml` run since the repository became `trost-systems/snacklist` (2026-11-12 21:50)
fails in the Android job at `google-github-actions/auth`: "The given credential is rejected by the
attribute condition" (runs 43345705603, 43351664814, 43357310646). The AAB builds, but nothing
reaches Play, and the jobs after it ("Uploaded", "Web production") are skipped. So
`app.snacklist.app` still serves the build from before Flutter 3.50 and the Wasm opt-in for
Safari and Firefox (#381). iOS uploads are not affected (build 1265 reached App Store Connect).

GitHub now signs the release job's token with the subject
`repo:trost-systems@267752722/snacklist@1429864759:environment:release` (the repo id 1429864759
and owner id 267752722 did not change; only the name did). Google Cloud still expects
`family-groceries`. Two places in the Google Cloud console, project `family-groceries-ci`
(number 1023711338330):

1. **IAM & Admin → Workload Identity Federation → pool `github` → provider `family-groceries`
   → Edit → Attribute condition.** Replace `family-groceries` with `snacklist` in it, or, so the
   next rename cannot break it, set it to `assertion.repository_id == '1429864759'`. Save.
   Equivalent command:

   ```
   gcloud iam workload-identity-pools providers update-oidc family-groceries \
     --project=family-groceries-ci --location=global --workload-identity-pool=github \
     --attribute-condition="assertion.repository_id == '1429864759'"
   ```

2. **IAM & Admin → Service accounts → `play-release@family-groceries-ci.iam.gserviceaccount.com`
   → Principals with access.** Remove the `roles/iam.workloadIdentityUser` principal ending in
   `subject/repo:trost-systems@267752722/family-groceries@1429864759:environment:release` and add
   the same role for the new subject:

   ```
   gcloud iam service-accounts add-iam-policy-binding \
     play-release@family-groceries-ci.iam.gserviceaccount.com --project=family-groceries-ci \
     --role=roles/iam.workloadIdentityUser \
     --member="principal://iam.googleapis.com/projects/1023711338330/locations/global/workloadIdentityPools/github/subject/repo:trost-systems@267752722/snacklist@1429864759:environment:release"
   ```

Then rerun the latest `release.yml` run on `main` (Actions → Release → Re-run all jobs). Done when
the Android job uploads and "Web production" runs, and `https://app.snacklist.app/flutter_bootstrap.js`
contains `const wasmAllowList = { blink: true, webkit: true, gecko: true };` and engine
`371f77202a73e8dff57a8b3bff75bca55c090aee`. The workflow's provider path keeps its id
`family-groceries`; nothing in the repo changes.

## Job 199: grocery log behind `grocery-log` (2026-11-13)

The Verlauf tab, the trip sheet and the list's trip card ship behind the PostHog flag
`grocery-log`, off for everyone (`releases/flags.json` rollout `off`). Nothing waits on you to
merge; these are the steps to see it and the one open legal question.

1. **Lead or Peter: create the flag for your TestFlight install only (t834u).** In PostHog
   (project 319492), Feature flags, New: key `grocery-log`, release condition "Users" with the
   person property `is_internal` equals `true`, rollout 100 %, everyone else off. The app sends
   `is_internal` only with the flag request (no person profile is created; docs/ANALYTICS.md,
   "Feature flags"). On the phone: the analytics yes must be given (More → Nutzungsdaten), and
   the install must be internal: long-press the version line under More until "Interne
   Installation" shows (or the household is in `ANALYTICS_INTERNAL_HOUSEHOLDS`); then restart the
   app. The next green `main` build after this merge carries the code to
   TestFlight (`release.yml`). Lea's install sees it too if it is internal; for you alone, add a
   second condition on the install's distinct id instead (PostHog → Activity, your events).
2. **Answered by Legal (N-167 ADJUST+DEFER, 14 Nov 2026; no Peter decision needed): manual
   logging of a pharmacy trip stays the user's choice. GL-2 (job 234): pharmacy stores raise no
   trip question and no „Einkauf eintragen?“ card (`Store.isPharmacy`).** Original question:
   **Legal: drugstore lines in a manual purchase log (Art. 9).** The log stores what a household
   member typed or ticked, for example "Schwangerschaftstest" or "Insulin-Pen-Nadeln" bought at dm,
   with the day and the store. N-127 treats pharmacy lines on receipts as Art. 9 health data and
   asks for explicit consent and a pharmacy discard. Question for Legal: does a log the user
   writes themselves (no receipt, no OCR, items the user chose to keep, visible to the household
   members, kept until the user, the household or the account deletes it, in the GDPR export)
   need Art. 9(2)(a) consent, a drugstore filter, a notice in the sheet, or nothing beyond the
   existing privacy text? Until the answer, the flag stays off for the public; the flagged merge
   did not wait for it (brief).
3. **Copy check before a public rollout.** The locked-history row reads "Ältere Einkäufe siehst
   du mit Snacklist Premium" / "See older trips with Snacklist Premium". It reuses the Premium
   naming of existing hints and adds no pricing copy. Say if you want different words before the
   flag goes beyond internal installs.
## Job 190: prices and trip total on your TestFlight phone only (2026-11-13)

Prices, the list total and the store subtotals ship behind the PostHog flag
`prices-and-trip-total`, off for everyone. To review them on TestFlight (t834u), turn it on for
your install only. Flags load only after the analytics yes, so:

1. On the TestFlight build that carries this change (the first green `main` build after it
   merges), say yes to Nutzungsdaten (More → Nutzungsdaten) if you have not.
2. More → long press the version line at the bottom → "Interne Installation" appears. Tap
   "Installations-ID kopieren: …" and send the id to the lead (it is the PostHog distinct id of
   this install, not your account; a reinstall makes a new one).
3. Lead, in PostHog (project 319492): create the flag `prices-and-trip-total` if it does not
   exist, release condition "Person property `distinct_id` equals <that id>", 100 %, no other
   condition. Save. The app picks it up on the next start or flag refresh.
   PostHog documents this condition for `distinct_id`; it has not been tried on this project
   yet, where person profiles are off. If the phone still shows no "+ Preis" chip after a
   restart, use the flag's "Overrides" with the same id instead, and tell the lead.
   It targets the phone, not the account: a reinstall makes a new id.
4. To turn it off again, remove the condition. Lea's phone stays off unless her install id is
   added the same way.

Two calls to confirm while you try it (both are easy to change):

- **Units.** You wrote "per g, per ml etc." The editor offers pro Stück, pro kg and pro l: an item
  in g reads per kg and one in ml per litre, the Grundpreis units on shelf labels, because per
  gram shows amounts like 0,002 €. "3 Packungen" is priced pro Stück. Say if you want per g,
  per 100 g or pro Packung instead.
- **Today's prices only.** A price counts for the total on the day it was saved. Example: you
  price Milch at 1,19 € on Monday and leave it on the list; on Tuesday its row shows "+ Preis"
  again, the total leaves it out, and the editor says "0,30 € teurer als zuletzt" when you type
  1,49. A shop across midnight splits into two totals. The alternative is a total that keeps
  every price on the list until the item is ticked and cleared. Say which you want.

Before the flag goes on for everyone: the privacy policy's section 5 lists what an entry holds
and does not name prices or the household currency yet (`docs/PRIVACY_DATA_MAP.md`, differences
to the policy). That text needs your approval first.

## Job 209: recommended GitHub token for the site's deploy gate

The gate works without it. The site's build asks GitHub's public API whether **Supabase deploy**
has finished, without a token (60 requests per hour per address). Vercel's build machines share
addresses with other customers, so that limit can be spent by others; the build then sleeps
until the reset or ends in ERROR after 25 minutes, and the new site silently stays unpublished
(the build log says `GitHub answered 403 (rate limit remaining 0, ...)`). A token avoids that:

1. GitHub, Settings, Developer settings, Fine-grained tokens: a token for
   `trost-systems/snacklist` with **Actions: Read-only** and nothing else.
2. Vercel project `hummlist-site`, Settings, Environment Variables: add
   `GITHUB_ACTIONS_READ_TOKEN` with that token for **Production**, marked Sensitive.
3. If a deployment already ended in ERROR this way, Redeploy it (keep "Use project's Ignore
   Build Step" on).

The dashboard's old Ignored Build Step can stay as it is: `site/vercel.json`'s `ignoreCommand`
overrides it.

## Job 211: RevenueCat household customers with an ended grant (2026-11-13)

Since job 211 a deleted household's RevenueCat customer is deleted only if RevenueCat reported a
purchase or a promotional grant under the household id (`revenuecat_households`). The migration
noted every household with a purchase or a promotional row on the day it ran. A household whose
promotional grant had already ended by then has no row, so it is not noted: if it is deleted later,
its RevenueCat customer stays. Before sales go on, **Ops** (one look, no code):

1. In RevenueCat → Customers, filter for customers with an expired promotional entitlement whose
   App User ID is a household id (test and beta households from `scripts/iap/promotional.ts`).
2. For each one, either grant again and revoke at once (the two events note the household), or
   delete the customer in RevenueCat by hand if the household is gone.

## Job 207: default list for Siri, Alexa & KI, and Alexa's named-list sentences (2026-11-13)

The picker "Liste für Siri, Alexa & KI" (household page) and "Liste: …" (household sheet) ship
behind the PostHog flag `default-list-voice-target`, off for everyone. The server side is live
with the merge: a named list in a Siri or Alexa sentence works for everyone, and unnamed adds go
to the first list until someone picks another.

1. **See the picker on TestFlight.** Same steps as "Job 190" above, with the flag
   `default-list-voice-target` (create it in PostHog project 319492 if it does not exist,
   release condition `distinct_id` equals your install id, 100 %). Your household needs two lists
   or more, else the row stays hidden.
2. **Alexa's new sentences reach the development skill only after a dev deploy.** The model
   (new `AddToListIntent` with `{items}` and `{list}`) is on `main`, but the ASK CLI is signed in
   only on the box, not on the Hetzner runner. Where it is signed in, from a checkout of `main`:

   ```bash
   ALEXA_SKILL_ID=amzn1.ask.skill.ad766331-e979-4a6e-95f1-30198b0a34cb scripts/alexa-deploy-dev.sh
   ```

   It writes the development stage only (no certification, no publishing, no testers). Then in
   the Alexa app on your account: "Alexa, öffne Snacklist und füge Luftballons zur Geburtstag
   Liste hinzu". Before that deploy the old model should still get there for a list that
   exists: Alexa puts "Luftballons zur Geburtstag Liste" (or "Luftballons zur Geburtstag") into
   the items and the server takes the list phrase off. Untested on a device; a name that matches
   no list can then end up as an item, which the new intent avoids.

## Job 225: daily feedback digest, switch on after Legal GO (2026-11-14)

The digest is merged and off (docs/FEEDBACK.md, "Daily digest"): no cron job, switch off. Only
after the Legal Review GO, in this order:

1. Make one secret value and set it as the function secret:
   ```sh
   v="$(openssl rand -hex 32)"
   supabase secrets set --project-ref jdwqrallbpdbshrdhenk FEEDBACK_DIGEST_SECRET="$v"
   ```
   The digest sends with the waitlist's function secret `RESEND_API_KEY`; check that
   `supabase secrets list --project-ref jdwqrallbpdbshrdhenk` lists it (without it every run with
   notes answers 503 `mail_not_configured`).
2. Store the same value in the vault (dashboard, SQL editor, as postgres):
   ```sql
   select vault.create_secret('<the value of $v>', 'feedback_digest_secret');
   ```
3. Resend → Domains → `snacklist.app`: open tracking and click tracking must both be off
   (open tracking would add a pixel to the digest and record every opening). Do not switch the
   digest on while either is on.
4. Privacy policy first: once the digest is on, each note and, when the sender allowed a reply,
   their address go through Resend (USA) into the `hello@snacklist.app` mailbox. Update the
   feedback paragraphs of `site/content/legal/datenschutz.md` and `privacy.md` with Legal, and
   let them go live, before the next step.
5. Switch it on (SQL editor):
   ```sql
   select public.feedback_digest_set(true, 'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/feedback-digest');
   ```
   Notes from this moment on go into the next 08:00 mail; older notes are never mailed.

Switch it off: `select public.feedback_digest_set(false);` (removes the cron job; switching on
again later mails the notes from the pause too).

Check the runs: `cron.job_run_details` for the job `feedback-digest`, `net._http_response` for
the function's answers (`{"status":"sent","count":N}`, `empty`, `failed`), and
`https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/feedback-digest/status`
(`{"enabled":true,"healthy":true}`). The workflow "Feedback digest watch" checks that URL daily
and opens the issue "Feedback digest failed" when a run fails. The queries are in
docs/FEEDBACK.md.

## Job 220: repository settings that close what the security review found (2026-11-13)

Job 220's code is merged and changes nothing by itself here: the scheduled jobs name the
environment `ops`, but their secrets are still repository secrets. A repository secret is
readable by a workflow file on any pushed branch (a branch copy of `backup.yml` with a `push`
trigger once ran a full production dump that way, harmlessly, on `job/13b-db-backups`). An
environment limited to `main` is not. Nothing indicates misuse, so no value needs rotating for
this. Steps 1 to 3 are the ones that matter; the Engineering Lead can do them from the box (it
has the database password). Details and evidence: `docs/done/220-security-hardening.md`.

1. **Limit the environment `ops` to `main`.** It exists already (empty, no rules). GitHub,
   Settings, Environments, `ops`, "Deployment branches and tags": "Selected branches and tags",
   add `main`. No required reviewers: the jobs run on a schedule.
2. **Move the two secrets into it,** environment first, then delete the repository one (the
   environment's value wins while both exist):
   ```
   gh secret set SUPABASE_DB_PASSWORD --env ops -R trost-systems/snacklist      # asks for the value
   gh secret delete SUPABASE_DB_PASSWORD -R trost-systems/snacklist
   v="$(openssl rand -hex 32)"
   printf '%s' "$v" | gh secret set REVENUECAT_DELETIONS_SECRET --env ops -R trost-systems/snacklist
   supabase secrets set --project-ref jdwqrallbpdbshrdhenk REVENUECAT_DELETIONS_SECRET="$v"
   unset v
   gh secret delete REVENUECAT_DELETIONS_SECRET -R trost-systems/snacklist
   ```
   The deletions secret gets a new value because neither GitHub nor Supabase shows the old one.
   Then run both once from `main`: `gh workflow run backup.yml` and
   `gh workflow run revenuecat-delete.yml`. Both should end green; a failure opens the usual
   issue. A copy of the old deletions secret kept elsewhere for `scripts/iap/promotional.ts`
   (`reconcile --apply`, `grant --apply`) stops working with the new value: store the new one
   there before `unset v`. Running the block again later, without the last line, is harmless.
   Also delete `POSTHOG_PERSONAL_API_KEY` at repository level
   (`gh secret delete POSTHOG_PERSONAL_API_KEY -R trost-systems/snacklist`): no workflow reads it
   (the web build reads its own from the Vercel project).
3. **The price drift check's secrets go into `ops` too.** `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_KEY_P8` and `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` exist nowhere yet, which is why the daily
   `price-drift.yml` run fails. When you create them (NEEDS_LEAD "Job 49", step 5), use
   `gh secret set <NAME> --env ops`, not a repository secret. `SUPABASE_ACCESS_TOKEN` stays a
   repository secret for now: `supabase-deploy.yml` names no environment yet (another job's
   file; the follow-up is in `docs/done/220-security-hardening.md`, "In files other jobs own").
4. **A ruleset for `main`** (Settings, Rules, Rulesets). `main` has no protection today: a
   direct push skips `ci-ok` and deploys migrations and functions to production. Require a pull
   request (0 approvals), require the status check `ci-ok`, block force pushes, restrict
   deletions. Bypass list: the GitHub Actions app, because `public-release-record.yml` pushes the
   release record straight to `main` with the workflow's token. Whether the settings page offers
   that app as a bypass actor is not confirmed from here. If it does not, enforce only the
   force-push and deletion rules, leave the pull request and status check rules off until the
   record has another way in (a deploy key on the bypass list, or the record through a PR), and
   tell the Engineering Lead. A dry run of `public-release-record.yml` does not test the bypass:
   it stops before the push. The first real record after a public release does. If `main`
   refuses it, the run fails with "the token may not be allowed to push to main"; the stores
   already have the build by then, and the site shows the release once the rule is fixed and the
   workflow has run again. `scripts/merge-pr.sh` keeps working: it rebase-merges a PR whose head
   has `ci-ok`. The bot account is a repository admin and could edit a ruleset, and with the
   Actions app on the bypass list a workflow whose token may write contents can still push to
   `main`. So this stops mistakes and tokens that cannot push workflow files, not that token.
   No ruleset for `release`: `release.yml` pushes that branch with the workflow's token, the
   runbook pushes it by hand to recover, and `docs/DEPLOY.md` ("Web app") says why nothing may
   cover it.
5. **Secret scanning and alerts** (Settings, Advanced Security; free for a public repository):
   turn on Secret Protection with push protection, Dependabot alerts and private vulnerability
   reporting. Today a secret that gitleaks' rules miss is public before anything objects, and no
   advisory for a dependency reaches anyone. Alerts are enough: "Dependabot security updates"
   would also open a PR, with a full CI run, for each advisory, including the ones in build
   tooling that this review looked at and left (`docs/done/220-security-hardening.md`).
6. **Actions settings** (Settings, Actions, General): "Require approval for all external
   contributors" for fork pull requests. Optionally allow only GitHub's own actions plus
   `subosito/flutter-action@*`, `ruby/setup-ruby@*`, `supabase/setup-cli@*`,
   `oven-sh/setup-bun@*` (setup-cli calls it), `denoland/setup-deno@*`,
   `webfactory/ssh-agent@*` and `google-github-actions/auth@*`. The CI run of a PR that changes
   `app/` or `supabase/` shows whether the first five are right (a docs-only PR skips the jobs
   that use setup-cli). The last two are used only by `release.yml` and `certificates.yml`:
   check them with `gh workflow run release.yml -f upload=false` (builds, signs and validates,
   uploads nothing; if the plan says blocked because CI on `main` is still running, run it
   again) before the next green CI on `main` starts a real release.
   **Leave "Require actions to be pinned to a full-length commit SHA" off for now.** Every
   `uses:` in this repo's files is pinned and the lint gate keeps it so, but the setting also
   covers the actions an action calls, and `subosito/flutter-action` (9 uses) calls
   `actions/cache@v5` by tag. With the setting on, those jobs would most likely be refused and
   `ci-ok` would go red (GitHub's documentation says so; not tried on this repo).
7. **Not a step, a warning: no required reviewer on the environment `release` as the workflow
   stands.** `release.yml`'s `plan` job is in that environment too, and it runs after every green
   CI on `main` (34 green release runs on 13 and 14 November up to 11:00 on the 14th, 17 of
   which built for a store).
   Each run would wait for your approval at `plan` and again at `ios` and `android`, and
   TestFlight, Play internal and the web production push would stop being automatic. The same
   holds for `ops`: a click per nightly run. A reviewer becomes worth it only once `plan` no
   longer needs the environment.
8. **One read-only look, now that #416 is deployed** (Supabase SQL editor). The migration sets
   default privileges for the role that runs migrations. Locally that role owns every table; this
   checks the same for production:
   ```sql
   select defaclrole::regrole, defaclobjtype, defaclacl
   from pg_default_acl where defaclnamespace = 'public'::regnamespace;
   select relowner::regrole, relkind, count(*)
   from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r', 'S') group by 1, 2;
   ```
   The second result names the owner of the tables (locally `postgres`; 54 tables and 3
   sequences on #416's branch). In the first, that role's rows for tables (`r`) and sequences
   (`S`) should list only itself and `service_role`, as they do locally:
   `{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}` for tables and
   `{postgres=rwU/postgres,service_role=rwU/postgres}` for sequences. The `supabase_admin` rows still
   name `anon` and `authenticated`; they apply to tables that role creates, which migrations do
   not. If the owner's rows still name `anon` or `authenticated`, tell the next job: a new table
   would again start with every privilege granted, and only its own `revoke` (the convention)
   would close it.

## Job 234: trip mode, flag targeting and open questions (2026-11-14)

Trip mode is merged behind the PostHog flag `trip-mode` (off for everyone). To see it on
TestFlight:

1. PostHog → Feature flags → `trip-mode` (the lead creates it): release condition
   `is_internal = true` (the person property job 199 added for flags), or "`distinct_id` equals
   <your install id>" (More → long press on the version → „Installations-ID kopieren“).
   Everyone else stays off.
2. The summary's lines (planned, extra, prices) need Premium; the stopwatch, the question and
   the Free card work without. The prices in the summary need `prices-and-trip-total` on too, the
   Verlauf entries `grocery-log`. Keep all three internal until Legal's N-163 to N-168 land.

Open questions, answered for now as in DECISIONS "Job 234" (say if any should change):

- **TQ1, where a running trip lives.** On the device only. A server-side trip would let Lea see
  „Peter kauft gerade ein“ and stop her app asking.
- **TQ2, two shoppers.** Lea's ticks during Peter's trip count as bought on his trip; her own
  ticks still ask her.
- **TQ4, a forgotten trip.** It pauses itself after 45 minutes and ends at the last tick after 4
  hours (TM2's timings). No notification.
- **TQ6, others' additions nobody bought.** Shown under „Seit dem Start dazugekommen“ as „nicht
  gekauft · von Lea“.
- **TQ7, early own additions.** Not treated as planned; „War geplant“ fixes them.
- **TQ11, the strip and the price total.** The strip sits above the list total; it does not
  carry the total.

## Job 237: the totals block, two answers before `list-declutter` widens (2026-11-14)

The totals block (ST3) is on main behind `list-declutter`; it needs `prices-and-trip-total` on too, and `trip-mode` for the bought/open split.

1. **ST-Q4, „≈ until it is weighed“: the build differs from your answer.** The app does not store whether a weight came from the scale: saving a price writes the weight into the quantity either way. Job 237 decided on its own: a price per kg or l typed per kg or l reads „≈“ while the item is open; the label's total („Gesamt“ in the price editor) or a tick makes it exact. So a weight you type at the scale still shows „≈“ until you tick the item, and an item ticked without weighing counts as exact. Making it exact needs a new `price_weighed` column (a migration, the price write, the data export). Answer: keep the current rule, or build the column.
2. **ST-Q6, count wording under Gesamt.** Without a trip Gesamt says „6 mit Preis · 1 offen“ while the store line above says „1 ohne Preis“ for the same item, and a fully priced list reads „2 mit Preis · 0 offen“ although 2 items are open. During a trip Gesamt already says „ohne Preis“. Answer: keep „offen“, or say „1 ohne Preis“ under Gesamt too.
