# Needs the Engineering Lead

Browser steps for the Engineering Lead, in the build box's browser, with
Peter only signing in. Everything around them is done from the box. Steps
that need Peter's own decision, money or identity are in
[`NEEDS_PETER.md`](NEEDS_PETER.md) instead.

## mcp.hummlist.com

Status: done. The Lead posted `Lead: mcp.hummlist.com live` (2026-10-28 15:44), and job 26's
`scripts/mcp-smoke.sh https://mcp.hummlist.com` passed. The steps below
stay as the record of the setup.

Job 26. Makes `https://mcp.hummlist.com` the public MCP URL
([`MCP.md`](MCP.md#public-url-mcphummlistcom)). Everything else is on
`main`: `mcp-proxy/vercel.json` and the function that advertises the public
URL. Nothing here costs money: a Hobby project, no env vars, no secrets.
DNS needs no change: hummlist.com is on Vercel's nameservers with a
wildcard, and `mcp.hummlist.com` answers `DEPLOYMENT_NOT_FOUND` today.

1. **Create the project** (Vercel connector or dashboard, team of the
   existing Hummlist projects):
   - Project name: `hummlist-mcp`.
   - Git repository: `trost-systems/family-groceries`, production branch
     `main`.
   - Root Directory: `mcp-proxy`.
   - Framework Preset: Other.
   - Build and Output Settings: leave every override off. `mcp-proxy/vercel.json`
     sets `installCommand`, `buildCommand` and `outputDirectory` to empty
     and `framework` to null, which skips the build (checked with
     `vercel build`: status `ok`, routes only).
   - Environment variables: none. Node.js version: any.
2. **Domain.** Add `mcp.hummlist.com` to `hummlist-mcp` as a production
   domain (no redirect). If Vercel says another project holds it, move it.
3. **Deployment Protection** (Settings, Deployment Protection):
   - Vercel Authentication: off, or Standard Protection. Standard covers
     only preview and generated URLs, never the production domain. Not "All
     Deployments".
   - Password Protection: off.
   - MCP clients must reach `https://mcp.hummlist.com` with no Vercel
     sign-in.
4. **Builds only for `mcp-proxy/` (optional).** Settings, Build and
   Deployment, Ignored Build Step: Behavior "Custom", command
   `git diff --quiet HEAD^ HEAD -- . || exit 1`. Vercel runs it in the Root
   Directory and skips the build when it exits 0: the newest commit on
   `main` (one per merged PR) left `mcp-proxy/` unchanged. Any other result,
   a missing `HEAD^` included, exits 1 and Vercel builds. Without this step
   every push to `main` redeploys the same two files, which is harmless.
   The Root Directory's "Skip deployment" switch does not apply: it needs
   JS workspaces, which this repo has none of.
5. **Verify** from the box, in the repo:

   ```bash
   scripts/mcp-smoke.sh https://mcp.hummlist.com
   ```

   Four lines start with `PASS`, one with `SKIP` (no token), and the last
   line reads `all checks passed against https://mcp.hummlist.com`. Then
   post on BOARD.md: `Lead: mcp.hummlist.com live`.

   If only the metadata check fails with a 404 from Vercel, Vercel refused
   the `/.well-known` rewrite: say so on the board; job 26 has a one-line
   fallback (`DECISIONS.md`, Job 26, item 8).

## Job 23: weekly release pipeline

Done from the box (job 23, 2026-10-27): the weekly Release workflow
([`RELEASE.md`](RELEASE.md)), the Android upload key and its two `release`
secrets, and the keyless Play service account
`play-release@family-groceries-ci.iam.gserviceaccount.com`. iOS ships
weekly without any step below. Android builds and signs weekly; it uploads
once L1 to L4 are done and `PLAY_RELEASE_STATUS` is set.

Status (2026-10-28): all done. Nothing is open for the Lead.

- L1 and L2: Play app "Hummlist", app ID `4972374295718364245`.
- L3: release 1003 (0.1.0) on internal testing, list "Familie", track
  active; Google-generated app signing key (fingerprints in
  `RELEASE.md`, "Android signing"); `PLAY_RELEASE_STATUS=completed`.
- L4: the service account has Hummlist only, "Release to testing tracks"
  and "View app information" (Play Console adds "View app quality
  information" by itself). The Release runs reach Play with it.
- L5: nothing to do for internal testing.
- L6: Associated Domains enabled; `renew_profile` made profile
  `5T4AGK7RF2` (ACTIVE, with associated domains, match repo `03f489d`).
- L7: Android clients "Hummlist upload key" and "Hummlist Play app signing"
  (SHA-1 `77:B6:9B:5E:8F:10:5D:3F:46:3C:62:C3:BC:BE:A8:3D:EA:10:08:53`) in
  `family-groceries-512507`.

The steps below stay as the record of what was done and for a re-setup.

Values used below (none is secret):

| What | Value |
| --- | --- |
| Package name | `com.hummlist.app` |
| App name | Hummlist |
| Upload key SHA-1 | `D4:9D:98:9E:AD:E3:2E:FE:D2:D3:A1:7A:71:B2:95:29:84:81:78:69` |
| Upload key SHA-256 | `2C:9B:48:6D:AF:1B:94:AB:3F:92:38:49:CC:0F:C3:42:EF:09:64:2C:32:40:74:97:69:25:61:74:0C:BA:84:F5` |
| Service account | `play-release@family-groceries-ci.iam.gserviceaccount.com` |

### L1: Play Console account

1. Open <https://play.google.com/console> and let Peter sign in with his
   Google account.
2. If Play Console shows the "All apps" list (with or without apps), a
   developer account exists. Note its name and whether it is a personal or
   an organization account, then go to L2.
3. If it asks to create a developer account (account type, USD 25 fee,
   identity verification): stop here. Do not create it and do not enter any
   payment or identity data. That is Peter's decision:
   `NEEDS_PETER.md`, "Job 23", item 1. Skip L2 to L5 and L7's Play part;
   iOS keeps shipping weekly.

Verify: the "All apps" page loads.

### L2: Create the app

Only if "Hummlist" is not in "All apps".

1. Select **Create app**.
2. App name: `Hummlist`. Default language: `German – de-DE`. App or game:
   **App**. Free or paid: **Free**.
3. Tick the declarations (Developer Program Policies, US export laws).
   Select **Create app**.

The package name is set by the first upload (L3) and cannot change after
that; the AAB carries `com.hummlist.app`.

Verify: Hummlist opens on its Dashboard.

### L3: Internal testing, first release, Play App Signing

1. Get the signed AAB. For the first upload: `~/groceries-ops/artifacts/app-release.aab`
   (built on the box, version code 1003, signer checked). Later: the newest
   Release run on `main` with an `android`
   job (Actions, Release, open the run, Artifacts,
   `hummlist-<build number>-aab`; artifacts are kept 7 days). Unzip it to
   get `app-release.aab`. If none is younger than 7 days, run
   `gh workflow run release.yml -f upload=false -f platform=android` and
   wait about 15 minutes.
2. Hummlist, **Test and release**, **Testing**, **Internal testing**,
   **Testers** tab: **Create email list**, name `Familie`, add Peter's Google
   account (the one he uses on his Android phone, if any). Do not add Lea
   until Peter says so. Save, tick the list, **Save**.
3. **Releases** tab, **Create new release**.
4. App integrity / Play App Signing: choose **Use Google-generated key**
   (Google creates and keeps the app signing key; our key stays the upload
   key). Select **Next** or **Save**.
5. **App bundles**, **Upload**: `app-release.aab`. Play shows version name
   `0.1.0` and the version code (the build number). Release name: leave
   Play's default. Release notes: leave empty.
6. **Next**, review the warnings (missing store listing or app content
   warnings do not block internal testing), **Save and publish** (or
   **Start rollout to Internal testing**).
7. **Test and release**, **Setup** (or **Release**, **Setup**), **App
   signing**: copy the **App signing key certificate** SHA-1 and SHA-256, and
   the **Upload key certificate** SHA-256. The upload key SHA-256 must equal
   the value in the table above; if it differs, the wrong AAB was uploaded.
8. Send the two app signing key fingerprints back (BOARD.md or the job
   brief). They go into `RELEASE.md`, table under "Android signing", row
   "Play app signing key", and into L7 and job 22's `assetlinks.json`.
9. Tell the box (BOARD.md) that L3 is done. The box then sets
   `gh variable set PLAY_RELEASE_STATUS --env release --body completed`
   (or `draft` if Play still calls the app a draft; see below) and dispatches
   one Release run. If you have `gh` at hand, you can run it yourself.

Verify: Internal testing shows the release as "Available to internal
testers"; the **Testers** tab shows the "Copy link" opt-in URL. If Play
says "Only releases with status draft may be created on draft app" in a
later run, set `PLAY_RELEASE_STATUS` to `draft` and roll that draft out by
hand once; after that, back to `completed`.

### L4: Grant the service account

1. Play Console (account level, not the app), **Users and permissions**,
   **Invite new users**.
2. Email address:
   `play-release@family-groceries-ci.iam.gserviceaccount.com`. This is the
   CI's API account, not a person; no email goes out.
3. **App permissions**, **Add app**: Hummlist only. Tick:
   - **Release to testing tracks** (under Releases)
   - **View app information (read-only)** (under App access)
   Leave everything else unticked, including account permissions.
4. **Apply**, **Invite user**, confirm.

Verify: the next Release run's `android` job, step `upload`, prints
"Play access works" (before `PLAY_RELEASE_STATUS` is set) or uploads to
internal testing (after). Until L4, it prints "Play refuses the service
account for com.hummlist.app (...)".

### L5: Policy items (App content)

Google's help: "You can start an internal test before completing app setup"
([Set up an open, closed, or internal test](https://support.google.com/googleplay/android-developer/answer/9845334)).
None of the items below blocks an internal testing upload or rollout. They
block closed testing, open testing and production, and the Dashboard lists
them under "Set up your app".

| Item (Policy, App content) | Blocks internal testing | Blocks closed/open/production | When |
| --- | --- | --- | --- |
| Privacy policy URL | No | Yes | After 33a's policy is on hummlist.com (https://hummlist.com/datenschutz). |
| App access (sign-in needed; reviewer credentials) | No | Yes (review) | With the production track. |
| Ads (no ads) | No | Yes | Any time: "No, my app does not contain ads". |
| Content rating (IARC questionnaire) | No | Yes | Any time; the answers are Peter's. |
| Target audience and content | No | Yes | Any time: 18+ suggested (household tool); Peter's call. |
| Data safety form | No | Yes | After 33a's policy; answers from `docs/PRIVACY_DATA_MAP.md` (job 14). |
| Government apps, financial features, health | No | Yes | Any time: "No" for each. |
| Store listing (descriptions, screenshots, icon) | No | Yes | Job 14 owns the metadata. |

A personal developer account created after 2023-11-13 also needs a closed
test with at least 12 testers opted in for 14 days before production. That
concerns production only.

### L6: Apple Developer, Associated Domains (job 22)

Weekly TestFlight builds do not need this (job 23 checked: the current
profile is `ACTIVE` and the build has no new entitlement). Job 22 needs it
for universal links (`applinks:app.hummlist.com`).

1. <https://developer.apple.com/account>, Peter signs in. **Certificates,
   Identifiers & Profiles**, **Identifiers**, `com.hummlist.app`.
2. Tick **Associated Domains**. Leave every other capability as it is.
   **Save**, confirm the dialog about invalidated profiles.
3. Do not touch **Certificates** or **Profiles** (no revoke, no new
   certificate). The profile "match AppStore com.hummlist.app" now shows
   "Invalid"; that is expected.
4. Post on BOARD.md that L6 is done. The box (job 22, or whoever is
   running) then runs `bundle exec fastlane ios renew_profile`
   (`RELEASE.md`, "Capabilities", step 2), which regenerates the profile
   with the existing certificate `GN85KDC962`.

Verify: Profiles shows "match AppStore com.hummlist.app" as Active with a
new expiry date, and the next Release run's `plan` passes "Check the
profile". Between step 2 and the box's `renew_profile`, a Release run fails
in `plan` with "Profile ... is INVALID"; that is the expected signal, not a
new problem.

### L7: Google sign-in on Play builds

Google Cloud Console, project `family-groceries-512507`, **Google Auth
Platform**, **Clients**, **Create client**, type **Android**:

1. Name `Hummlist upload key`, package `com.hummlist.app`, SHA-1
   `D4:9D:98:9E:AD:E3:2E:FE:D2:D3:A1:7A:71:B2:95:29:84:81:78:69`.
   **Create**. (Builds signed locally or by CI with the upload key.)
2. After L3: a second client, `Hummlist Play app signing`, package
   `com.hummlist.app`, SHA-1 = the app signing key SHA-1 from L3, step 7.
   This one makes Google sign-in work in builds installed from Play.

No client secret is created and nothing goes into the repo: the app never
sends an Android client ID; Google matches it by package and SHA-1.

Verify: both clients are listed with package `com.hummlist.app`. On a phone
with the internal testing build, "Mit Google anmelden" completes.

## Job 24: help page URLs (after Peter's publish OK)

Status: waiting for Peter's OK on the text (docs/NEEDS_PETER.md, Job 24).

1. Send Peter the hummlist-site preview of the PR's head: `/support` and `/en/support` on the
   preview deployment URL (BOARD.md line "24-privacy-page: PR …", or the PR's Vercel check).
2. After the publish PR is merged and https://hummlist.com/support answers 200:
   - App Store Connect → Apps → Hummlist → the app version (or App Information) → **Support
     URL**: `https://hummlist.com/support` (required for review). Marketing URL stays empty.
   - Play Console → Hummlist → Grow users → Store presence → Store settings → **Store listing
     contact details**: Email `support@hummlist.com`, Website `https://hummlist.com/support`,
     **Save**.
3. Check: `curl -sI https://hummlist.com/support | head -1` gives 200 and the page has no
   "ENTWURF" banner.

## Job 25: Hummlist Lifetime store setup (browser; Peter only signs in)

Order matters: items 1 and 5 wait for NEEDS_PETER Job 25 items 1 and 2. Nothing here submits
anything for review. Docs: `docs/PURCHASES.md`.

**Since job 43 (RevenueCat):** the steps below that set function secrets for our own Apple/Google
verification (`PURCHASES_ENVIRONMENTS`, `APPLE_IAP_*`, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`,
`PURCHASES_CRON_SECRET`) and point App Store Server Notifications at our function no longer apply;
those keys go to RevenueCat instead ("Job 43 – RevenueCat setup" below). Creating the products
(P1, the Play product) still does.

### P1: The product in App Store Connect (after the Paid Apps agreement, or try before)

On the box (the ASC key is there):
`ASC_KEY_ID=4J3N457M89 ASC_ISSUER_ID=<issuer> ASC_KEY_PATH=~/groceries-ops/AuthKey_4J3N457M89.p8 deno run --allow-env --allow-read --allow-net scripts/iap/apple_product.ts`
(dry run), then the same with `--apply`. Copy the printed "equalized price AUT/CHE" lines into
DECISIONS 25.1. If Apple refuses (for example because the agreement is not active), do it by hand:
App Store Connect → Apps → Hummlist → Monetization → In-App Purchases → "+": type
Non-Consumable, Reference Name `Hummlist Lifetime`, Product ID `com.hummlist.app.lifetime`;
Availability: all countries; Price Schedule: Germany, 9,99 €, keep the automatic prices; App
Store Localization: German and English (U.S.), display name `Hummlist Lifetime`, descriptions
from `scripts/iap/product.ts`; Family Sharing: leave off. Review information: no screenshot,
do not submit.

### P2: In-App Purchase key and function secrets

1. App Store Connect → Users and Access → Integrations → In-App Purchase → Generate In-App
   Purchase Key (name "Hummlist purchases"). Download the .p8 once to
   `~/groceries-ops/secrets/apple-iap/` (chmod 600). Note the Key ID and the Issuer ID shown there.
2. Set the hosted function secrets (you, not a job):
   `supabase secrets set --project-ref jdwqrallbpdbshrdhenk APPLE_IAP_KEY_ID=… APPLE_IAP_ISSUER_ID=… APPLE_IAP_PRIVATE_KEY="$(cat <file>.p8)" PURCHASES_ENVIRONMENTS=Sandbox PURCHASES_CRON_SECRET=<openssl rand -hex 32>`
   and the same cron value as repository secret: `gh secret set PURCHASES_CRON_SECRET`.
   `PURCHASES_ENVIRONMENTS=Sandbox` while TestFlight testers buy; switch to
   `Production,Sandbox` before the App Store review (App Review buys in the sandbox).
3. Check: `curl https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases` answers
   `{"configured":true,"environments":["Sandbox"]}`.

### P3: App Store Server Notifications V2

App Store Connect → Apps → Hummlist → App Information → App Store Server Notifications: Production
Server URL and Sandbox Server URL both
`https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases/apple/notifications`, Version 2.
Then send Apple's test notification ("Request a Test Notification", or the App Store Server API
`POST /inApps/v1/notifications/test` with the P2 key): the function answers 200 `ignored`.

### P4: Sandbox tester

App Store Connect → Users and Access → Sandbox → Test Accounts → "+": an address Peter chooses
(an alias on hummlist.com works; never a real person's Apple ID without his OK), region Germany.
On the test iPhone: Settings → App Store → Sandbox Account → sign in.

### P5: Google Play (after the payments profile)

1. Google Cloud project `family-groceries-ci`: a service account `play-purchases` with a JSON key
   (edge functions cannot use the keyless GitHub federation of `play-release`). Save the key to
   `~/groceries-ops/secrets/` (600), set it as function secret
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON="$(cat <key>.json)"`.
2. Play Console → Users and permissions → invite that service account for Hummlist with "View
   financial data", "Manage orders and subscriptions" and "Manage store presence".
3. The product: `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=<key> deno run --allow-env --allow-read --allow-net scripts/iap/google_product.ts`
   (dry run, prints Play's AT and CH prices for DECISIONS 25.1), then `--apply`. By hand
   instead: Play Console → Monetize with Play → Products → One-time products → Create:
   Product ID `com.hummlist.app.lifetime`, name and description DE and EN, purchase option `buy`,
   price 9,99 € in Germany, other countries from the converted prices, Activate.
4. Play Console → Settings → License testing: add the Google accounts Peter names, response
   LICENSED. Their purchases are test purchases (Sandbox) and never charged.
5. Check the poll: Actions → "Purchases voided poll" → Run workflow: green, log shows
   `{"checked":0,"revoked":0}`.

### P6: Device checklist (TestFlight build from release.yml, with Peter)

On the iPhone with the sandbox tester (and on Android with a license tester after P5):
1. More → Hummlist Lifetime shows "9,99 €" from the store; buy; "Freigeschaltet". The partner's
   phone shows "Freigeschaltet" without buying.
2. Kill the app right after confirming the purchase; open it again: unlocked.
3. Delete and reinstall; "Käufe wiederherstellen": unlocked.
4. Ask to Buy is not testable without a family; Play: buy with the license tester's "slow test
   card, approves after a few minutes": "Wartet auf Bestätigung", then unlocked.
5. Refund: App Store Connect sandbox → the tester → "Clear Purchase History" does not refund;
   use Play Console → Order management → refund (test order) for Google, and for Apple check
   P3's test notification. The next poll (or a REFUND notification) shows the household locked.
6. Report the result on BOARD.md.

## Job 43: Hummlist Lifetime, household-bound (2026-10-31)

### Steps

1. **Testers** (on the box, which has `SUPABASE_ACCESS_TOKEN`): `scripts/iap/testers.ts`
   (docs/PURCHASES.md "Testers"). Dry run first, then `--apply`:
   `deno run --allow-env --allow-net --allow-read scripts/iap/testers.ts add --email <e> [--grants n] [--note "TestFlight"]`;
   `set-grants --email <e> --grants n` raises a tester's count case by case; `list`, `remove`.
   It prints user ids, never keys. Keep notes free of names and e-mail addresses.
2. **PostHog insights** in project 319492 (read-only for jobs; you create them): paste
   `analytics/queries/paying_households_d35.sql` and `analytics/queries/paying_share_wah.sql` as
   HogQL insights. The kill gate is `paying_share_wah`'s `share_percent` ≥ 2 in the Berlin week
   that contains day 35 after launch (docs/ANALYTICS.md). No PostHog groups.
3. **No new analytics event is proposed.** The queries work on `purchase_completed`,
   `purchase_refunded`, `item_added` and `item_ticked` with their existing `household_id`; nothing
   waits for a privacy-policy section 9 change. `purchase_restored` is no longer sent (RevenueCat
   restores produce no event for us); its catalog entry stays.
4. **Archiving for real users** (after Legal Review): add `"HOUSEHOLD_ARCHIVE": "true"` to
   `app/config/auth.json`, which the store builds (fastlane) and the web build (`scripts/vercel.sh`)
   read. Until then it is on only in e2e builds (`app/config/e2e.json`).
5. **The purchase screen** (after Peter approves the legal texts, ADDENDUM 5): builds need
   `--dart-define=REVENUECAT_PURCHASES=true` plus the public SDK keys `REVENUECAT_APPLE_API_KEY` and
   `REVENUECAT_GOOGLE_API_KEY` (from `~/groceries-ops/env`). First only for Peter's own builds;
   then wire them into fastlane's defines (`app/fastlane/Fastfile`, like the analytics defines)
   for everyone.

### Job 43 – RevenueCat setup (Ops, not done by the job)

**Done by the Lead by 2026-10-31 14:56 (ADDENDUM 6):** project 9cb4a72e with entitlement
`lifetime`, offering `default`, package `$rc_lifetime`, product `com.hummlist.app.lifetime`
(non-consumable), and the function secrets `REVENUECAT_WEBHOOK_AUTH` (with `Bearer `),
`REVENUECAT_SECRET_KEY` (v2), `REVENUECAT_TOMBSTONE_HMAC_KEY`, `REVENUECAT_PROJECT_ID`. After this
PR lands: point the webhook at the URL in step 7 and send RevenueCat's test event (expect 200
`ignored`); check steps 3 to 6 and 9 below. The SDK key defines are `REVENUECAT_APPLE_API_KEY`
and `REVENUECAT_GOOGLE_API_KEY`.

1. RevenueCat account and project "Hummlist" (free up to USD 2,500 monthly tracked revenue, then
   1 %; confirm webhooks are included on the plan the dashboard shows). Accepting the terms
   accepts the DPA.
2. Apps: App Store (`com.hummlist.app`) and Play Store (`com.hummlist.app`). Public SDK keys into
   `~/groceries-ops/env` as `REVENUECAT_APPLE_API_KEY`, `REVENUECAT_GOOGLE_API_KEY`.
3. App Store Connect: an In-App Purchase key (Users and Access → Integrations → In-App Purchase),
   `.p8` and Issuer ID uploaded to RevenueCat; App Store Server Notifications V2, Production and
   Sandbox, set to the URL RevenueCat shows (replaces our function's URL there).
4. Google: a service account with Play access, its JSON key uploaded to RevenueCat (validation
   can take up to 36 h). Real-time developer notifications need a Pub/Sub topic, which needs a
   Google Cloud project with billing enabled; DECISIONS 25.8 avoided that ("not allowed"). Peter
   decides (NEEDS_PETER Job 43 item 3); until then RevenueCat learns of Play refunds without
   notifications only as RevenueCat documents it.
5. Products: import `com.hummlist.app.lifetime` for both stores, mark the Play product
   **NON-CONSUMABLE** (otherwise RevenueCat consumes it and Google sells it again), entitlement
   `lifetime` attached, an offering with a lifetime package.
6. Project settings → General → Restore behavior: **Keep with original App User ID**, production
   and sandbox alike. Leave "Track new purchases from server-to-server notifications" off. Leave
   RevenueCat's AI features off (Legal Review C4). No integrations, no data exports.
7. Webhook integration: URL
   `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases/revenuecat/webhook?forceFunctionRegion=eu-central-1`,
   an `Authorization` header value (a long random string), production and sandbox, all apps;
   optionally HMAC signing. Then set the function secrets `REVENUECAT_WEBHOOK_AUTH` (that header
   value), `REVENUECAT_WEBHOOK_HMAC_SECRET` (if signing is on) and `REVENUECAT_TOMBSTONE_HMAC_KEY`
   (a random 32-byte hex string, never rotated), e.g. `supabase secrets set --project-ref
   jdwqrallbpdbshrdhenk REVENUECAT_WEBHOOK_AUTH=…`. Send RevenueCat's test event: the function
   answers 200 `ignored`.
8. A v2 secret API key with `customer_information:customers:read_write` as the function secret
   `REVENUECAT_SECRET_KEY`, and `REVENUECAT_PROJECT_ID` (the daily workflow
   `revenuecat-delete.yml` only starts the function's deletion route).
9. Afterwards delete what job 43 removed: function secrets `PURCHASES_ENVIRONMENTS`,
   `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_PRIVATE_KEY`,
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `PURCHASES_CRON_SECRET`, and the repository secret
   `PURCHASES_CRON_SECRET`. Update the App Privacy and Data safety answers (Purchases, User ID)
   once Legal Review and Peter have decided the privacy text (RevenueCat as a new processor).

### Legal Review: draft 5a sentences this job affects

`site/content/legal/datenschutz-kaeufe.md`, `privacy-purchases.md`; not edited here.

- "Du kaufst im App Store von Apple oder bei Google Play. Apple bzw. Google wickeln die Zahlung
  ab …" / "You buy it in Apple's App Store or on Google Play …": RevenueCat, Inc. (USA) now sits
  between the app and the stores as our processor: the app's SDK sends it the household UUID as
  App User ID, transaction ids, product, price, currency, country, dates, environment, platform,
  app/SDK version, device locale and the IP address; RevenueCat checks with Apple and Google. US
  transfer under its DPA (SCCs module 2); its subprocessors are all in the USA.
- "Nach dem Kauf schickt die App den vom Store signierten Kaufbeleg an unseren Server … Wir
  prüfen ihn, bei Bedarf auch direkt bei Apple … bzw. Google …" / "After the purchase the app
  sends the receipt … We check it, where needed directly with Apple … or Google …": no longer
  true. RevenueCat checks; our server receives RevenueCat's webhook and, from the app, the buyer's
  claim (user id ↔ transaction id). What we store: store, product, the store's transaction id and
  an HMAC of it, whether it was a test purchase, purchase and refund time, price, currency,
  country, the buyer (from the claim), and the household it belongs to (kept after that household
  is deleted, for 30 days; then only the HMAC).
- "… welches Konto den Kauf zuerst bestätigt hat und welchen Haushalt er freischaltet." / "…
  which account confirmed the purchase first and which household it unlocks.": now "which member
  said they bought it (first claim)".
- "Alle Mitglieder deines Haushalts sehen, dass der Haushalt freigeschaltet ist." / "All members
  … see that the household is unlocked.": still true; members no longer see who paid (H-55). New:
  someone with a valid invite sees, before joining, whether the household has Hummlist Lifetime;
  the joining user's own recent purchase (30 days) is checked to offer the refund help (shown to
  no one else); members see when the household bought Lifetime more than once.
- "Rechtsgrundlage: … dass ein Kauf nicht mehrfach oder in fremden Haushalten verwendet wird." /
  "Legal basis: … not used twice or in other households.": now enforced also after the household
  is deleted (the kept household id for 30 days, then the HMAC tombstone, kept while Lifetime is
  sold or honoured, reviewed yearly).
- "Speicherdauer: Die Freischaltung bleibt beim Haushalt … Löschst du dein Konto, entfernen wir
  die Verbindung zwischen dem Kauf und deinem Konto; die Transaktion selbst bleibt ohne
  Personenbezug gespeichert, solange Hummlist betrieben wird … Wird der Haushalt gelöscht, endet
  seine Freischaltung." / "Retention: …": the transaction is no longer kept while Hummlist runs:
  30 days after the household's deletion it is deleted (only the HMAC stays) and RevenueCat is
  asked to delete the household's customer. Account deletion still only removes the buyer link.
  New: the last member may archive the household instead (once archiving is on), which keeps its
  data and unlock.
- Not in 5a yet, new processing: the tester list (user id, number of free unlocks, how many were
  used, a note, the date) and which households a tester's free unlock went to; analytics marks
  tester households internal (usage data section; nothing new is sent).
- Outside 5a: §14 Speicherdauer ("Bist du das letzte Mitglied eines Haushalts, wird der Haushalt
  mit allem gelöscht."), the support FAQ (`support.md`: "Bist du das letzte Mitglied, wird der
  ganze Haushalt gelöscht.") and `app/web/konto-loeschen.html` ("Du bist das letzte Mitglied")
  describe deletion on leaving; with archiving they need the archive case. Account deletion
  deletes the last member's household and the households they archived.

### Job 43 – privacy/retention notes (Legal Review H-49 to H-56, RevenueCat conditions)

Plain facts from the code; what the law requires is Legal Review's call.

- **H-49, the purchase record after the unlock ends.** While its household exists (archived
  included) a purchase row keeps: store, transaction id, latest transaction id, the HMAC, product,
  kind, environment, price, currency, country, purchase/verification/refund times, the bound
  household, and the buyer's user id until their account is deleted. 30 days after the household
  is deleted the row is deleted (`purge_purchases`, daily) and only the HMAC stays
  (`purchase_tombstones`, nothing attached; kept while Lifetime is sold or its unlocks are
  honoured, reviewed yearly). The financial records Apple and Google keep (8 years, archived by
  Ops) are the tax records; these rows are not.
- **H-50, archived households.** An archived household keeps all its data unchanged: name,
  categories, stores and layouts, items and their history (`item_events`), invites (unusable),
  entitlements, purchases. It has no members, so no client can read it (RLS) and its invites
  answer `invalid_invite`. It is kept until the archiving user re-enables it (Mehr → Archivierte
  Haushalte → Wieder aktivieren, `unarchive_household`) or deletes their account, which deletes
  it (`delete_account`); one whose archiver was deleted another way goes with the daily purge.
  Only that user (`households.archived_by`) can re-enable it. Inside it, other former members'
  rows keep pointing to them as before (e.g. `items.added_by`); their own account deletion nulls
  those links. There is no time limit: an archived household stays until re-enabled or account
  deletion. A limit (e.g. after N months, with notice) would be a product and legal decision.
- **H-51, testers.** (Superseded by 20261101150000_testers_via_revenuecat.sql: testers get a
  RevenueCat promotional grant for their household, docs/PURCHASES.md "Testers"; the list below
  is removed.) `public.lifetime_testers`: user id (cascade-deleted with the account),
  grants, used, a note (Lead's free text, no names or e-mail), added_at. Service connection only;
  the Lead's script resolves an e-mail to the id at run time and stores no e-mail. A used grant
  is an `entitlements` row (`source` tester, `tester` the user id, nulled when the account is
  deleted); it stays with the household like a purchase, also after launch (Peter, 2026-10-31).
  No tester data goes to RevenueCat (no promotional entitlements). Sandbox purchases stay after
  launch too (NEEDS_PETER Job 25 item 8). The store transaction id is kept in
  `purchases.transaction_id` while the row exists; analytics only ever gets a hash
  (`transaction_ref`).
- **H-53, recipients.** docs/PURCHASES.md "Who receives what": our server calls neither Apple nor
  Google; RevenueCat (US, DPA) receives the household UUID as App User ID and the purchase data
  listed there and talks to the stores; our one outbound call is RevenueCat's customer deletion.
- **H-54, region.** RevenueCat calls the webhook from the US, so the registered URL carries
  `?forceFunctionRegion=eu-central-1`; the app's claim call is pinned with `region:
  'eu-central-1'` (`app/lib/purchases/purchase_api.dart`); the function logs `SB_REGION`.
  Supabase "Regional Invocations" (https://supabase.com/docs/guides/functions/regional-invocation,
  read 2026-10-31).
- **H-55, the buyer.** RevenueCat knows only the household. The buyer is recorded from the
  member's claim (`purchase_claim`, through the function, first member wins). Members have
  column-level select on `entitlements` without `granted_by` and `tester`: migration
  `20261031123504_household_bound_lifetime.sql`; pgTAP `purchases.test.sql`,
  `household_bound.test.sql`; the function's integration test; Realtime to the partner checked by
  `e2e/tests/purchases.spec.ts`.
- **H-56, restore.** RevenueCat's "Keep with original App User ID" (Ops) plus the server:
  `purchase_record` unlocks only `purchases.bound_household` (also after archive and
  re-enabling), refuses every other household (`used_elsewhere`, `household_gone`), ids that are
  no household, and tombstoned transactions; a `TRANSFER` moves nothing. Purchases from before
  this migration that unlocked nothing are bound to the nil UUID. Tests: pgTAP,
  `supabase/functions/purchases/handler_test.ts`, `e2e/tests/household-bound.spec.ts`.
- **C3 (SDK data).** The SDK starts only on the purchase page of a household known to have no
  Lifetime, with the household id; no attributes, no device or ad ids, no `logOut`: lint rules
  `purchases-flutter-only-in-revenuecat-repository` and `no-revenuecat-customer-data` fail the build otherwise.
- **RevenueCat's retention** after a deletion request follows its DPA ("subject to standard data
  backup and archival practices"), RevenueCat's statement.

## Job 44: PostHog SDK, error tracking, feature flags (2026-10-31)

The app now runs PostHog's official SDK (posthog_flutter 5.58.3, posthog-js 1.444.0 on the web;
DECISIONS Job 44, ANALYTICS.md). Nothing changes before the analytics yes: no request, no file.
After the yes, more data goes to PostHog than the legal texts name. Legal texts are unchanged;
these are the sentences and steps for you.

### For the Legal Review (privacy policy, consent text, store labels)

1. **Device and app data on every event (iOS, Android).** Proposed policy sentence (DE): "Mit
   jedem Ereignis übermittelt das PostHog-SDK außerdem technische Angaben zum Gerät und zur App:
   App-Version und -Build, Gerätehersteller, -modell und -typ, Betriebssystem und Version,
   Bildschirmgröße, Sprache und Zeitzone, ob WLAN oder Mobilfunk genutzt wird (Android zusätzlich
   Bluetooth, den Namen des Mobilfunkanbieters und die technische Kennung des Systembrowsers) und
   eine zufällige Sitzungskennung, die nach 30 Minuten ohne Nutzung wechselt." EN: "With every
   event the PostHog SDK also sends technical details of the device and the app: app version and
   build, device maker, model and type, operating system and version, screen size, language and
   time zone, whether Wi-Fi or mobile data is used (on Android also Bluetooth, the mobile
   network's name and the system's HTTP user agent) and a random session id that changes after 30
   minutes without use." Web: "Im Browser: Browser und Betriebssystem mit Version, Gerätetyp,
   Bildschirm- und Fenstergröße, Sprache und Zeitzone; nie die aufgerufene Adresse, die
   verweisende Seite oder die vollständige Browserkennung." The consent screen says "zum
   Beispiel ... Plattform und App-Version": please judge whether "Geräte- und App-Angaben" must be
   named there.
2. **Crash reports from the phone's own code.** "Stürzt die App ab, sendet sie beim nächsten Start
   einen Absturzbericht (Fehlerart, Fehlermeldung des Systems, technische Aufrufliste) an
   PostHog." Unlike Dart errors these system messages are not scrubbed by the app (ANALYTICS.md,
   "Gaps"); they normally hold no user content. iOS keeps its crash handler after switching
   analytics off: a crash after the off is sent only after a new yes.
3. **Feature flags.** "Nach Ihrer Einwilligung fragt die App PostHog mit der zufälligen Kennung,
   welche Funktionen für Ihre Installation freigeschaltet sind." No new purpose beyond running the
   app; same consent, same id.
4. **Storage on the device (TDDDG §25).** With the yes the PostHog SDK stores the install id, a
   device id (the same random value), queued events and the flag answer on the device; switching
   off deletes them (the More text "Ausschalten löscht die Kennung auf diesem Gerät" stays true).
   The web stores nothing (no cookie, no localStorage).
5. **Store labels.** App Store "App Privacy" and Play "Data safety" (NEEDS_LEAD Job 14 row): add
   Crash data / Diagnostics and "Device or other IDs" (the random install id), linked to no
   identity, not used for tracking, collected only with consent. Answers in PRIVACY_DATA_MAP.md.

### Steps in PostHog project 319492 (read-only from here; never 262464)

1. When a feature needs a runtime toggle: create the flag (key as in the code,
   `Analytics.flags.isOn('<key>')`, default off), roll it out there, and set the same key in
   `releases/flags.json` (`off`/`partial`/`full`) for its changelog item. No flag exists yet.
2. After the first SDK events from a release: run `analytics/queries/privacy_scan.sql` (block 1
   now lists the SDK's keys; anything else is a finding) and check that `$lib` reads
   `posthog-flutter`, `posthog-ios` or `posthog-android`.
3. Error tracking: the first native crash report arrives at the launch after a crash; exception
   autocapture must stay on in the project settings. Symbol upload (iOS dSYMs, Android mappings)
   is not set up (ANALYTICS.md, "Gaps").

### Upstream issue drafts (not filed; Peter: contribute upstream rather than add a vendor)

**A. posthog_flutter: let `beforeSend` see and strip what the native SDKs add**
- Repro: posthog_flutter 5.58.3 on Android or iOS, `config.beforeSend = [(e) { e.properties?.remove(r'$network_carrier'); return e; }]`, capture any event.
- Expected: the event goes out without `$network_carrier` (and the app can drop `$device_model`,
  `$raw_user_agent`, `$session_id` ...).
- Actual: the Dart callback sees only the caller's properties; posthog-android and posthog-ios
  add device, app, network and session properties afterwards, and those are sent. Both native
  SDKs have a `beforeSend` that sees the final properties, but the plugin sets none.
- Proposed fix: a Dart-side `PostHogConfig.propertyDenylist` (or `systemPropertiesBeforeSend`)
  that the plugin applies in the native `beforeSend` it registers at setup, and in posthog-js'
  `property_denylist` on the web; exposing the full native property map to the Dart callback
  would be the general form.

**B. posthog-ios and posthog-android: opting out does not stop network or storage**
- Repro: `PostHogConfig(optOut: true)` (or `optOut()` after setup), fresh install, watch the
  network and the app's files.
- Expected: an opted-out SDK makes no request and writes no id, so it can be set up before the
  user's consent.
- Actual: setup fetches `/array/<token>/config` and `/flags` (posthog-ios
  `PostHogRemoteConfig.swift` 157-209, no opt-out check; posthog-android `PostHog.kt` 397-412),
  writes an anonymous id and a device id (`PostHogStorageManager.swift` 72-104, `PostHog.kt`
  363, 660-689), and already queued events still flush. `reset()` keeps the device id and
  requests `/flags` at once under a new id, so there is no way to delete the SDK's state on the
  device without deleting its files.
- Proposed fix: opt-out gates remote config, flags and queue flushes, and defers id creation
  until opt-in; plus a `wipe()` (or `reset(keepDeviceId: false, reloadFlags: false)`) that
  deletes ids, queue and caches without a request.

**C. posthog_flutter: exception types are minified on Flutter web release builds**
- Repro: a `flutter build web --release` (dart2js) app calls `Posthog().captureException(error: StateError('x'))`.
- Expected: `$exception_list[0].type` is `StateError`.
- Actual: `minified:hm` (`DartExceptionProcessor._getExceptionType` uses `runtimeType`), so
  PostHog groups issues by meaningless names.
- Proposed fix: map the core error and exception types by `is` checks before falling back to
  `runtimeType` (Hummlist's `errorType` in `app/lib/analytics/exceptions.dart` does this), and let
  the app add its own types.

## Job 47: purchase legal fixes, Legal Review K.11 (2026-10-31)

Nothing here is live for users: `REVENUECAT_PURCHASES` and `HOUSEHOLD_ARCHIVE` stay off, and the
new server switch is seeded off. Decisions: DECISIONS "Job 47". Behavior: docs/PURCHASES.md.

### Steps

1. **The deletions cron secret (must, or the daily workflow fails).** `POST
   /purchases/revenuecat/deletions` now needs `x-deletions-secret`; while the function secret is
   unset it answers 503 and `revenuecat-delete.yml` fails (and opens its issue "RevenueCat
   customer deletion failed") until both secrets below are set. Generate one value and set it in
   both places without printing it:
   ```
   v="$(openssl rand -hex 32)"
   printf '%s' "$v" | gh secret set REVENUECAT_DELETIONS_SECRET --repo trost-systems/family-groceries
   supabase secrets set --project-ref jdwqrallbpdbshrdhenk REVENUECAT_DELETIONS_SECRET="$v"
   unset v
   ```
   Then run the workflow by hand once (`gh workflow run revenuecat-delete.yml`); it should end
   green with `{"status":"not_configured"}` until `REVENUECAT_SECRET_KEY` is set, or the
   deletion counts after.
2. **Archiving for real users (H-70), when you and Peter decide to offer it** (the 24-month texts
   are live since #147).
   Two switches, both needed, in this order:
   - Server (the database, service role), in the SQL editor or with the Management API:
     ```sql
     update public.app_switches set enabled = true, changed_at = now() where key = 'household_archive';
     ```
     Off again: the same with `false`. While it is off, every archiving call
     (`leave_current_household(true)`, `accept_invite(code, true)`, `unarchive_household(id, true)`
     when it would archive the household left) fails with `archive_disabled` and changes nothing;
     re-enabling an archived household keeps working.
   - App: `"HOUSEHOLD_ARCHIVE": "true"` in `app/config/auth.json` (Job 43 step 4).
   Turn the server switch on first: an app with the define on and the switch off shows "Archivieren
   ist gerade nicht möglich. Dein Haushalt bleibt, wie er ist." on the archive choice.
3. **Migration `20261031194500_purchase_legal_fixes.sql`** deploys with the normal pipeline. It
   deletes the nil-bound `Sandbox` purchases from before job 43 (H-69). It does not touch a
   nil-bound `Production` row; there should be none (nothing was sold). Check after the deploy:
   `select environment, count(*) from public.purchases where bound_household = '00000000-0000-0000-0000-000000000000' group by 1;`
   should return no rows.

### For Legal Review (re-check against the texts #147 put live; this job did not edit them)

- **H-67, done.** The SDK starts only on "Weiter zum Kauf" or "Kauf wiederherstellen" (tests:
  `app/test/purchases/no_sdk_before_tap_test.dart` with the real repository over the SDK's mocked
  channel; the web e2e checks no request goes to RevenueCat). The page shows no price (option a;
  DECISIONS 47.1). One fact for 5a ("Erst wenn du … einen Kauf startest oder einen Kauf
  wiederherstellst, verbindet sich die App mit RevenueCat"): after that tap the SDK stays
  configured for the rest of that app run, and on each return to the foreground it refreshes the
  household's CustomerInfo and offerings from RevenueCat when its cache is older than 5 minutes
  (purchases-ios `applicationWillEnterForeground` → `updateAllCachesIfNeeded`). A later app start
  contacts RevenueCat only after the next tap.
- **H-68, verified, matches draft 5a.** From the source of purchases-ios 5.99.0 and
  purchases-android 11.0.0 (pinned by purchases_flutter 11.0.0; links in docs/PURCHASES.md "What
  Apple and Google receive"): Apple gets the household id with every purchase (StoreKit 2
  `appAccountToken`; StoreKit 1 on iOS 15 `applicationUsername`), Google gets
  Base64(SHA-256(household id)) as `obfuscatedAccountId`, never `obfuscatedProfileId`. Note: the
  hash is unsalted, so whoever knows the household id can compute it; the household id is a
  random UUID that only the household's members, our server and RevenueCat know.
- **H-73, device storage.** The data map has the row (iOS UserDefaults suite
  `com.revenuecat.user_defaults`, Android SharedPreferences `com_revenuecat_purchases_preferences`,
  contents, cache times). Decision 47.6: sign-out and account deletion leave it on the device; the
  SDK has no call to clear it except `logOut`, which creates an anonymous RevenueCat customer and
  contacts RevenueCat. It goes when the app is uninstalled, or is replaced at the next Buy or
  Restore for another household. Draft 5a says the library stores the household id and the unlock
  status once a purchase or restore starts; it does not say how long. Please decide whether 5a
  needs a sentence on that.
- **Android Auto Backup (new finding, app-wide).** `app/android/app/src/main/AndroidManifest.xml`
  sets no `android:allowBackup`, so Android's default (on) applies: Auto Backup may copy the app's
  SharedPreferences, RevenueCat's file included (and the app's own DeviceCache and the Supabase
  session), to the user's Google account backup and to a new phone. Not changed here (it is
  app-wide, not purchase-specific). Options: `android:allowBackup="false"`, or backup rules that
  exclude RevenueCat's file and the session. Your call; a small app PR either way.
- **H-50.** Archived households are deleted 24 months after archiving; "Archivierte Haushalte"
  shows "Wird am <Datum> gelöscht", and the join screen's archive offer names the 24 months. No
  reminder e-mail: Hummlist sends no e-mails of its own (DECISIONS 47.3). If the texts promise a
  reminder, that needs a mail sender first.
- **The buyer's claim (job 43 review).** It now names the purchase's household and counts for a
  member at the purchase time, also one who left within the hour. That needs a new, short-lived
  record: `household_departures` (household, user, joined, left), kept one hour, service only.
  Draft 5a does not mention it; it is in the data map. Please check whether 5a needs it.
- **H-72.** Removing a tester (`testers.ts remove`) or their account deletion now clears their
  mark on the households they unlocked (`entitlements.tester`), as 5a says.
- **H-74 (optional), not done.** A refunded transaction whose household is deleted still gets a
  tombstone after 30 days, like any purged purchase. Leaving refunds out needs a decision whether a
  refunded-then-reversed purchase may then bind elsewhere, so it waits for Legal Review.

## Job 51: native Siri (2026-10-31)

Nothing here blocks the merge. Native Siri reaches testers with the next TestFlight build after
the merge. The changelog item waits on the `native-siri` hold in `releases/flags.json`.

### 1. Device test on Peter's iPhone (internal TestFlight, after the merge)

Sign in to Hummlist on the TestFlight build, open the list once, then close the app. Set Siri to
English (Settings → Siri → Language) for lines 1 to 5, then to German for lines 6 to 9.

1. "Hey Siri, add to Hummlist" → "What should I add?" → "milk, eggs and bread" → Siri: "Added
   milk, eggs and bread to Hummlist." Lea's phone shows the three items within seconds.
2. "Hey Siri, add milk to Hummlist" (milk on the list before) → no follow-up question, "Already on
   the list: milk." or "Added milk …".
3. "Hey Siri, what's on my Hummlist?" → reads at most ten items, then "and N more".
4. Airplane mode on, then line 1 → Siri says nothing was added. No item appears after airplane
   mode goes off again.
5. HomePod (if one is paired, Personal Requests on): line 1 → the full sentence is spoken.
6. "Hey Siri, füge etwas zur Hummlist hinzu" → "Was soll auf die Liste?" → "Milch, Eier und Brot"
   → "Hinzugefügt: Milch, Eier, Brot." (German device: the checks in "Job 71" below.)
7. "Hey Siri, füge Milch zur Hummlist hinzu" → no follow-up question.
8. "Hey Siri, was steht auf meiner Hummlist?" → reads the list.
9. Mehr → Abmelden, then line 6 → "Öffne Hummlist und melde dich an …", nothing added.
10. The old Shortcut ("Hey Siri, Einkaufsliste") still answers as before.
10a. One-word items take the app's language when the word is too short to tell (DECISIONS "Job 51"
    item 13). With the iPhone in English and Siri in German, say "Füge etwas zu Hummlist hinzu" →
    "Milch". Note whether the answer comes in German or English. English there is a known
    limitation, not a failure; the item must still be added.
11. Later, with job 50's lock on and a locked household: line 6 → the Premium sentence, nothing
    added, the app stays closed.

If Siri doesn't hear the phrases at all (lines 1 and 6), do section 2 and test again.

### 2. Only if the device test needs it: the Siri capability

Apple requires `com.apple.developer.siri` for SiriKit Intents extensions, not for App Intents
(DECISIONS "Job 51" item 5). If voice invocation fails anyway:

1. Lead: developer.apple.com → Identifiers → `com.hummlist.app` → enable **Siri** → Save.
2. On the box, renew the App Store profile (docs/RELEASE.md "Capabilities"): `bundle exec fastlane
   ios renew_profile` with the env shown there.
3. A one-line PR adds `<key>com.apple.developer.siri</key><true/>` to
   `app/ios/Runner/Runner.entitlements`. Its CI `ios` job and the next Release run prove the
   profile matches.

No `NSSiriUsageDescription`: the app never calls `INPreferences.requestSiriAuthorization`.

### 3. Placeholder copy for Hummlist Launch (Spec #5)

- `premium_required` (voice, not reachable until job 50): de "Sprachbefehle sind Teil von
  Hummlist Premium. Du kannst es in der App freischalten. Ich habe nichts hinzugefügt." en "Voice
  commands are part of Hummlist Premium. You can unlock it in the app under More, Hummlist Premium.
  I didn't add anything." The iOS app has the same sentences as a fallback
  (`app/ios/Runner/AppIntents`).
- The guides' native Siri sections (`site/content/guides/de/siri-kurzbefehl.md` "Ohne
  Einrichtung", `en/siri-shortcut.md` "Siri without setup") carry a draft note. They show on
  production from version 1.0.0. The EN guide's title still says "German only for now". Launch
  rewrites it once native Siri is public.
- The Zugänge card text (`siriWorksWithoutSetup`, `siriOldShortcutHint` in `app/l10n/app_*.arb`).

### 4. Legal Review touchpoints (no legal text was edited)

- **New credential.** "Siri (dieses iPhone)" is a token stored hashed on our server and in plain
  form in the iPhone's Keychain. It is bound to the app session and ends with sign-out. The
  privacy policy's section on access tokens and voice should name it.
- **Item names on the device for Siri.** Up to 50 item names of the household go to the iOS App
  Shortcuts system so that "Add milk to Hummlist" works. Apple states it "may extract anonymized
  App Shortcuts data such as localized phrases, display representation values … Machine learning
  models use this data" (https://developer.apple.com/documentation/appintents/app-shortcuts). The
  display representation values are our item names. The privacy text should say so, or Launch
  drops the one-shot phrase.
- **Analytics.** `siri_add` and `siri_read` (docs/ANALYTICS.md) count Siri use per household under
  the existing consent. No text and no names.

### 5. Known gaps

- English "beer" is classified as produce (DECISIONS "Job 51" item 11). The household's category
  memory fixes it after one move.
- iOS 15 and 16 get no native Siri. The Shortcut recipe stays for them.


## Job 49: Hummlist Premium, yearly and Lifetime (2026-11-01)

The go-live order for jobs 43 to 50 is now [`PAYWALL_RELEASE.md`](PAYWALL_RELEASE.md) (job 67).

Nothing here is live for users: `REVENUECAT_PURCHASES` stays off (Peter turns it on, 20:35 CET),
and the new server switch `premium_offer` is seeded off. Nothing is gated (job 50). Decisions:
DECISIONS "Job 49". Behavior: docs/PURCHASES.md.

### Done by Ops already (ADDENDUM 2, A2-7), so not listed as steps

RevenueCat entitlement `premium` (`entl654efcfce4`) with all four products attached, offering
`default` with `$rc_annual` and `$rc_lifetime`, the Play base plan `yearly`, Play grace period
14 days and account hold 46 days, the App Store subscription group "Hummlist Premium"
(`22532621`) with `com.hummlist.app.yearly` (`6829293557`), the country prices (ADDENDUM 3).

### Steps

1. **Migration `20261031214500_premium_yearly.sql`** deploys with the normal pipeline, together
   with the `purchases` function (same push to main). In the minutes between the two, a webhook
   from the old function fails the new kind check (500) and RevenueCat retries; nothing is sold,
   so none is expected. After the deploy: `select kind, count(*) from public.entitlements group by 1;`
   shows only `premium`.
2. **The old `lifetime` entitlement at RevenueCat**: delete it only after every installed app is a
   job 49 build or later. The webhook reads the product, not `entitlement_ids`, so events naming
   either work meanwhile. An entitlement's identifier can't be changed through RevenueCat's API v2
   (only `display_name`; https://www.revenuecat.com/docs/api-v2/entitlement, read 2026-11-01),
   which is why a new one was created.
3. **Keep unchanged at RevenueCat:** restore behavior "Keep with original App User ID", "Track new
   purchases from server-to-server notifications" off, the webhook URL with
   `?forceFunctionRegion=eu-central-1`. Please confirm in the dashboard that the webhook sends
   subscription lifecycle events (RENEWAL, CANCELLATION, UNCANCELLATION, BILLING_ISSUE,
   EXPIRATION, SUBSCRIPTION_PAUSED, SUBSCRIPTION_EXTENDED) for both stores on the current plan,
   and that App Store Server Notifications V2 and Play RTDN reach RevenueCat for subscriptions.
4. **Offering the purchase (when Peter says so), in this order:**
   - The store prices must be confirmed first (launch gate): run the drift check (step 6) green,
     or the app shows no amount it didn't read from the store anyway; the check proves the stores
     sell at the planned prices.
   - Server switch, service role (SQL editor or Management API):
     ```sql
     update public.app_switches set enabled = true, changed_at = now() where key = 'premium_offer';
     ```
     Off again (also the one command on price drift): the same with `false`. Off: no card, no Buy,
     no store price query, on every build.
   - App: `REVENUECAT_PURCHASES=true` (Job 43/47 steps).
5. **Secrets for the price drift check** (`scripts/iap/price_drift.ts`, `.github/workflows/price-drift.yml`,
   daily 05:17 UTC; it fails with "SKIPPED: … missing (NEEDS_LEAD Job 49)" until they exist).
   Repository secrets, set without printing them:
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the `.p8` text): an App Store Connect API key;
     the check only reads (subscription prices, IAP price schedule, availability). The existing
     App Manager key works; a read-only role may suffice (not tested).
   - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: a service account with `androidpublisher` scope that can
     see the app's products in Play Console (Users and permissions).
   Not added on purpose: a service-role secret in CI that would turn `premium_offer` off by itself
   on drift. Propose it if you want automatic switching; today drift opens the issue "Store prices
   drifted from scripts/iap/product.ts" and a person runs step 4's `false`.
6. **First run of the drift check:** `deno run --allow-env --allow-net --allow-read scripts/iap/price_drift.ts`
   on the box (ASC key there), with the Play service account if available. It prints the BR, MX
   and IN yearly amounts; put them into `expectedPrices` in `scripts/iap/product.ts` (they are
   `null` now). The 20 euro storefronts all expect 9.99 / 29.99; if a store set one differently,
   the check says which.
7. **StoreKit configuration file:** `app/ios/Hummlist.storekit` was written by hand (Xcode format
   4) with the subscription group; open it once in Xcode on a Mac (or a StoreKit test run) and
   commit whatever Xcode rewrites.
8. **PostHog (319492 only):** update the two paying-household insights from
   `analytics/queries/paying_households_d35.sql` and `paying_share_wah.sql` (both products count;
   the WAH share counts a yearly purchase for 365 + 14 days). The HogQL was not run here.
9. **Proposed event (not shipped):** a `subscription_renewed` / `subscription_expired` server
   event would let the WAH share count active yearly households exactly instead of the 379-day
   approximation. It needs a privacy policy section 9 change through Legal Review first.

### For Legal Review (via the Lead; this job edited no legal text)

- **5a** (privacy policy): the subscription, its renewal and expiry processing; the new stored
  facts per household: plan (`yearly`/`lifetime`), the plan's end (`expires_at`), whether it
  renews (`auto_renew`), whether a billing problem is open (`billing_issue`, with the grace end),
  the time of the newest RevenueCat event (`state_at`); `premium_source` readable by members.
  `cancel_reason` and `expiration_reason` are not stored (H-87).
- **S-8** ("an expired yearly plan can be renewed there under the same transaction number"):
  Apple: confirmed, `originalTransactionId` stays across renewals and a lapsed resubscribe in the
  same group (Apple commerce engineer, https://developer.apple.com/forums/thread/732932; a 2025
  report of a changed id for a few accounts is unanswered). Google: renewals keep RevenueCat's
  `original_transaction_id` (RevenueCat staff, community answer 2023-08-08); a resubscribe after
  expiry creates a new purchase token (Google's subscription docs), so on Google an expired plan
  bought again is a new transaction (it still binds only to the same household's App User ID).
  The clause holds for Apple, not for Google.
- **Section 9**: the new `premium_source` property on `purchase_completed` / `purchase_refunded`;
  the proposed event in step 9.
- **§12 / §13**: unchanged by this job as far as the code goes; please confirm.
- **Support FAQ** (S-3, „Wie kündige ich das Jahresabo?“): the app links `/support` and
  `/en/support` (no anchor exists); the entry is Legal's.
- **H-76 strings name only Lifetime** (`refundHelpBody`, `refundHelpGoogle`, `refundHelpReason`,
  `lifetimeBoughtTwice`, `joinLifetimeEnds`): left word for word. The refund sheet now adds the
  placeholder `premiumRefundYearly` ("Für das Jahresabo gilt dasselbe. Eine Kündigung beendet nur
  die Verlängerung; das laufende Jahr wird nicht automatisch erstattet.") below them.
- **S-11**: the rename „Hummlist Lifetime“ → „Hummlist Premium“ in the 26 values of app_de.arb
  (and app_en.arb) was not applied (legal text change; Peter's approval).
- **Terms / EULA (H-20, H-93)**: no Hummlist terms exist. The Premium page links Apple's standard
  EULA on iOS (`appleEulaUrl`) and, as a placeholder, the support page on Android and the web
  (`termsUrl` in `app/lib/purchases/premium_server.dart`).
- **Kündigungsbutton (§ 312k BGB)**: built nothing beyond the store-management links
  ("Abo verwalten oder kündigen"); is that enough for subscriptions sold through Apple/Google?
- **Store privacy labels (C10)** for subscriptions.
- **app/web/konto-loeschen.html (S-5)**: not edited; the in-app deletion now warns the subscriber.
- **Static-price question (ADDENDUM 1)** is moot: the app shows only what the store returns
  (A2-5). Legal may still want to confirm § 25 TDDDG for the store price query on page open (a
  StoreKit / Play Billing call, no RevenueCat, no network to us).
- **Placeholder copy needing final text** (every `premium*` ARB key marked PLACEHOLDER in its
  description): the page intro, status lines, card titles and price lines, "Einmal zahlen, für
  immer: so viel wie drei Jahre.", the yearly disclosures (`premiumYearlyTerms`), Buy labels,
  "nicht verfügbar" / "bald verfügbar", the yearly-elsewhere hint, the two-plans note, the web
  note, the yearly refund note, and the Lead's generic H-85 line
  (`premiumBillingContinuesOther`: „Ein Jahresabo für diesen Haushalt läuft weiter, bis es
  gekündigt wird.“). The EN button "Buy anyway" is the Lead's wording.
- **Disclosure wording**: Apple's subscription page asks for name, duration, the full renewal
  price and restore on the sign-up screen and links to the terms and privacy policy; the "24
  hours" sentence comes from Apple's Media Services Terms. `premiumYearlyTerms` follows that;
  please confirm or replace.

## Job 50: integration lock (2026-11-01)

The go-live order is now [`PAYWALL_RELEASE.md`](PAYWALL_RELEASE.md), section 6 (job 67).

Nothing here is live: the server switch `app_switches.integration_lock` is seeded off and the app
define `INTEGRATION_LOCK` is off, so every integration works as before for every household.
Turning it on is Peter's go. Decisions: DECISIONS "Job 50". Behavior: docs/PURCHASES.md,
"Integration lock". This job changed nothing in any dashboard, console or hosted database.

### Go-live order and commands (each step after the one before)

1. Job 49's premium is live for buyers: products and RevenueCat ready, the webhook secrets set,
   `premium_offer` on (`update public.app_switches set enabled = true, changed_at = now() where key
   = 'premium_offer';`) and store builds with `REVENUECAT_PURCHASES=true`. Otherwise a locked
   household sees "Bald verfügbar" and cannot unlock.
2. Promotional grants for the households Peter wants to keep working (`scripts/iap/promotional.ts
   grant --household <uuid>`, a dry run by default; `--apply` writes; `testers.ts` is gone since
   #173). Spec #4 says no grandfathering: a beta household without a
   grant or purchase is locked.
3. The cut-over count, read-only, in the hosted project's SQL editor (the Lead runs it; this job
   never queried the hosted database): `scripts/iap/integration-cutover.sql`. It lists every
   household without premium that uses an integration now (ids and counts of Shortcut tokens,
   Siri iPhones, Alexa links, OAuth connections, last token use) and a total line (households,
   with premium, would be locked, locked with integrations). Run on the local stack after the
   e2e spec it printed 10 households, 4 with premium, 6 would be locked, all 6 with integrations.
4. Legal Review's changes below are live (privacy section 9 at least).
5. The server switch, service role: `update public.app_switches set enabled = true, changed_at =
   now() where key = 'integration_lock';` From that moment Siri, Alexa and MCP refuse households
   without premium. Off again: the same with `false`; everything opens at once and the app hides
   the card in every build.
6. The app define in the next store builds: `--dart-define=INTEGRATION_LOCK=true` (release
   workflow defines, like `REVENUECAT_PURCHASES`), and `releases/flags.json` hold
   `integration-lock` set to released in a PR with the changelog item.

### Legal Review touchpoints (no legal text was edited)

- Privacy policy section 9 lists the server events (purchases, Alexa's `item_added`) but not
  `integration_blocked` (integration, household id, install id, under the caller's analytics yes;
  at most once an hour per household and integration) nor `paywall_viewed` (entry point). Both
  only happen with the switches on; the server switch waits for this.
- Privacy section 7 ("Siri, Alexa und KI-Assistenten") describes the integrations without saying
  they need Hummlist Premium; the support FAQ (`site/content/legal/support.md`,
  `support-en.md`), the purchase privacy page (`datenschutz-kaeufe.md`, `privacy-purchases.md`)
  and the store listings may call them free or not name them as premium. Check before the switch.
- The new service-only table `integration_blocks` (household, integration, last report time) is
  in docs/PRIVACY_DATA_MAP.md; it cascades with the household.

### Hummlist Launch: placeholder copy

| Where | Key | Text (DE; EN in the same file) |
| --- | --- | --- |
| `supabase/functions/voice/copy.ts` | `failures.premium_required` | Sprachbefehle sind Teil von Hummlist Premium. Du kannst es in der App freischalten. Ich habe nichts hinzugefügt. |
| `app/ios/Runner/Localizable.xcstrings` (job 51, used only when the server sends no speech) | `siri.locked` | Sprachbefehle sind Teil von Hummlist Premium. Du kannst es in der App freischalten. |
| `supabase/functions/alexa/speech.ts` | `premiumAdd` | Hummlist nimmt für euren Haushalt gerade keine Sprachbefehle an. Ich habe nichts hinzugefügt. (job 69: Alexa is not Premium) |
| `supabase/functions/alexa/speech.ts` | `premium` (read, launch) | Hummlist nimmt für euren Haushalt gerade keine Sprachbefehle an. |
| `supabase/functions/mcp/tools.ts` | `premiumRequired.de` / `.en` | Dieser Haushalt braucht Hummlist Premium für den Zugang über KI-Assistenten. Schalte es in der Hummlist-App frei. Es wurde nichts gelesen oder geändert. |
| `app/l10n/app_de.arb` / `app_en.arb` | `integrationPremiumTitle`, `integrationPremiumBody`, `integrationPremiumSiri`, `integrationPremiumAlexa`, `integrationPremiumAi`, `integrationPremiumLater`, `integrationPremiumBuy`, `integrationPremiumSoon`, `integrationPaused` | the integration settings' card and the paused label (descriptions marked PLACEHOLDER) |

### Alexa

The skill's certification and store description: Amazon's "Policy requirements for an Alexa
skill" (https://developer.amazon.com/en-US/docs/alexa/custom-skills/policy-requirements-for-an-alexa-skill.html,
last updated 2024-05-01, read 2026-11-01), section 4 "Skill recommendations, compensation, and
purchasing": In-Skill Purchasing must be used if the skill lets users buy digital products
within the skill, and every skill that makes products available for purchase must meet Amazon's
published requirements. The skill sells nothing; it tells a locked household to unlock in the app
("Du kannst es in der App freischalten"). Whether that counts as pointing to a purchase outside
Alexa is Amazon's call: ask in the certification submission, or say only that the household needs
Hummlist Premium without naming a purchase. The "Requirements for account linking" page
(https://developer.amazon.com/en-US/docs/alexa/account-linking/requirements-account-linking.html,
modified 2026-09-29, read 2026-11-01) has no rule about the description. Recommended: the skill
description says that Siri, Alexa and AI assistants need Hummlist Premium for the household,
before the switch goes on. The certification test account needs premium (a tester grant), or the
certifier hears only the premium answer. No Alexa console change was made.

### MCP and docs for clients

`docs/MCP.md` has the engineering note. Client-facing texts that will need a premium note
(Hummlist Launch, not edited here): the site guides under `site/content/guides/` about connecting
Claude, ChatGPT, Codex, Siri and Alexa, and the app's own help links. `mcp-proxy/vercel.json`
needed no change.

### Not gated, on purpose

An OAuth access token used directly against Supabase's REST API (PostgREST) instead of the MCP
endpoint is not gated: it is a user token under the same RLS as the app, and the app's own access
must never be gated. No MCP client does this. Closing it would need a client-id check in every
RLS policy (DECISIONS 50.3).

### Analytics

`analytics/queries/integration_blocked_weekly.sql` (households refused per Berlin week, per
integration, and how many bought within 14 days), run against PostHog project 319492 once the
switch is on. Job 49 had no `paywall_viewed`; this job added it (DECISIONS 50.9).

### Secrets

None new.

## Job 54: demo videos for hummlist.com (2026-11-01)

- **Human gate: Peter watches each loop once on a phone.** Open the PR's Vercel preview (`/de` and
  `/en`, Vercel login) on a phone and on a laptop, let each of the three demo cards play once,
  and check: it reads, it loops without a jump, nothing looks drawn that should be the app. With
  reduced motion on (iOS: Settings › Accessibility › Motion), the cards show the still and a play
  button. Then approve together with job 53 (NEEDS_PETER "Job 53"); the videos go live only with
  53's merge.
- **Launch copy.** Every word on screen is a draft: `site/COPY_NEEDED.md`, section "Demo videos:
  words on screen" (`marketing/videos/copy.json`), plus the rewritten text alternatives
  `demo.add-tick`, `demo.household-sync`, `demo.mcp-chat`. A copy change needs only
  `node marketing/videos/build.mjs` (no new filming).
- **English mcp-chat shows a German list.** The brief allows only the test household "Sams
  Wohnung" (fixture `solo-long-list`, German item names) for the MCP video, so the English cut has
  Sam's German rows (Senf, Ketchup, Tee) around the new "Honey" and "Jam". If an English list reads
  better, allow an English copy of the fixture (or `demo-family-en`) for that cut; then rerun
  `capture/take.ts mcp-chat en` and the build.
- **Material Icons credit.** The hex glyphs in the captions and the chat's buttons come from the
  app's own icon font in the Flutter SDK, licensed CC BY 4.0 (Google), which asks for attribution.
  The app and job 53's posters use the same font. A credits line on the site (for example in the
  imprint or footer: "Icons: Material Icons by Google, CC BY 4.0") is a legal-text change, so not
  made here.
- **Job 53 needs a rebase onto main** (52 and 51 landed). Until then this PR's and 53's lint gate
  fail the schema check on main's two newer migrations. After 53 is rebased or merged, this branch
  follows (DECISIONS 54.1).
- **No retailer on screen.** The demo households carry no store tags, so dm, Lidl and Edeka (seeded
  in every household) never show in the videos.
- **App findings from the fresh-eye review (not changed: no app behaviour changes in this job).**
  The videos show the app as it is; these would make the app, and the next takes, look better:
  - English item names get the wrong emoji: "Honey", "Jam", "Pasta" and "Rice" show the tin can,
    "Eggs" a milk glass (`item_icon.dart` seems to key on German names; "Honig" gets the honey pot).
  - A ticked row leaves in one frame after its 260 ms fade and the rows below jump up; no collapse.
  - Closing the add sheet shows the empty white sheet surface for about 300 ms while it shrinks.
  - The add sheet's suggestion row trails the typed text by a letter or two (debounce plus
    server round trip), visible when typing at speed.
  - Your own additions (here through MCP) get no "new" highlight, unlike another member's mint
    row; the mcp-chat video adds a mint marker beside the phone to point at them.

## Job 68: account deletion and Hummlist Premium (2026-11-02, for Legal Review)

**Outcome (DECISIONS 68.1 to 68.3).** Deleting the account never archives a household:

- **Last member of a household with Premium** (Lifetime, a yearly plan or a promotional grant):
  the household is deleted with the account, its Premium ends. With `HOUSEHOLD_ARCHIVE` on, the
  dialog says so, explains that archiving isn't possible there and that inviting someone keeps the
  household, links the refund help, and Delete waits for the tick „Ich habe verstanden: Hummlist
  Premium endet und wird nicht automatisch erstattet.“ (EN "I understand: Hummlist Premium ends and
  isn't refunded automatically.").
- **Households the user archived** are deleted with the account (DECISIONS 43.11, unchanged;
  pgTAP `supabase/tests/leaves_unlocked.test.sql`). The dialog names them; one with Premium asks
  for the same tick. Their purchases keep naming the deleted household, so they never unlock
  another one; the purchase rows follow the normal 30-day deletion.
- **Why no archive:** only the archiving user can bring an archive back, and their account is what
  is being deleted, so the archive would be unreachable data kept for 24 months.

**For Legal Review:** the strings `accountDeletePremium`, `accountDeleteArchived`,
`accountDeleteArchivedPremium`, `accountDeletePremiumAck` in `app/l10n/app_de.arb` /
`app_en.arb`. They match `app/web/konto-loeschen.html` today (household deleted "mit … einer
Freischaltung mit Hummlist Lifetime", archived households deleted too), which job 68 did not
edit.

**Lead decision needed only if you disagree:** to make account deletion archive instead, someone
other than the deleted user would need a way back in (for example an invite into an archived
household), which job 43 rules out.

**When it shows:** with `HOUSEHOLD_ARCHIVE` (NEEDS_LEAD "Job 43", step 4) or as soon as the
`premium_offer` server switch opens the Premium sale, whichever comes first. Nothing to flip for
this job; Legal Review should approve the four strings before either happens.

## Job 71: German native Siri only opened the app (2026-11-02)

Nothing here blocks the merge. Lea's iPhone (German system and Siri language) opened Hummlist
for every German phrase of build 1097; English worked on Peter's iPhone. Root cause and fix:
DONE_SUMMARY.md "Job 71". Test with the first TestFlight build that contains this PR, on a phone
whose Siri language is German. Sign in, open the list once, close the app.

### 1. Is German active for Hummlist's Siri phrases?

German setting names differ between iOS versions, so the English ones are given.

1. Settings → Siri → Siri Responses → **Always Show Speech** on. Siri then shows what it heard.
2. Kurzbefehle app → Kurzbefehle → **Hummlist**: the tiles read „Zu Hummlist hinzufügen“ and
   „Meine Hummlist vorlesen“. English tiles mean the phone did not take the German phrases.
3. Turn on **Type to Siri** (Settings → Accessibility → Siri, or Settings → Siri), then type
   „Füge etwas zur Hummlist hinzu“. Siri asks „Was soll auf die Liste?“. Typing skips speech
   recognition, so this tests the phrase alone.

### 2. Spoken, German

4. „Hey Siri, füge etwas zur Hummlist hinzu“ → „Was soll auf die Liste?“ → „Milch, Eier und
   Brot“ → „Hinzugefügt: Milch, Eier, Brot.“ The app stays closed. Note the words Siri shows for
   the app name (Hummlist, Hummliste, Humm Liste, Hummelliste, or something else).
5. Also run the intent: „Füge etwas zu Hummlist hinzu“, „Setz etwas auf meine Hummlist“,
   „Füge Milch zur Hummlist hinzu“ (Milch was on the list before), „Was steht auf meiner
   Hummlist?“, „Lies die Hummlist vor“.
6. Lines 8 to 11 of "Job 51" section 1 (offline, signed out, old Shortcut, Premium lock).

### 3. What the results mean

- Step 3 works but step 4 opens the app: Siri hears the name as a word the app does not list.
  Send the word Siri showed. It goes into `app/ios/Runner/de.lproj/InfoPlist.strings` (at most
  three names) and the voice parser (`supabase/functions/voice/parse.ts`).
- Step 3 also opens the app, or step 2 shows English tiles: the phone does not use the German
  phrases. Do "Job 51" section 2 (the Siri capability and entitlement; Apple reads the
  alternative app names only with it, according to its documentation), then test again.
- Everything works: tell the lead. The `native-siri` hold stays until Hummlist Launch.

## Job 72: Alexa data cleanup and fact answers for Legal Review (2026-11-02)

**ADDENDUM 1 (Alexa free, N-27) is done in this job:** the alexa function never asks the
integration lock, `integration_gate` answers `alexa` open even with `integration_lock` on, the
app's Premium copy and card no longer name Alexa (section 7's exact ARB changes), and the Alexa
tile in Zugänge is never paused. Proved by pgTAP (`integration_lock.test.sql`), the functions'
database test (`premium_integration_test.ts`: Alexa adds with the switch on, before a plan and
after its lapse), app tests and `e2e/tests/integration-lock.spec.ts`. Nothing was flipped;
`integration_lock` stays off. Section 7's other points (speech strings, handler line) are in the
same change.

For Legal Review's handoff of 2026-11-02 (section 6 and "Open fact questions"). Variant A of
N-24 and the 12-month purge of N-28 are built: migration `20261102093000_alexa_cleanup.sql`,
tests in `supabase/tests/alexa.test.sql` and `e2e/tests/alexa.spec.ts`, the table in
`docs/ALEXA.md` ("What is kept, and for how long"). Nothing is applied to the hosted project
before the merge; `supabase-deploy.yml` applies it from main. The site's legal texts are not
changed here (Peter approves them).

What the texts may now say, as built:

- The counter: deleted with the user's last Alexa link right away; otherwise by the daily job
  (03:29 UTC) once its minute has passed, so none is older than a day ("spätestens nach einem
  Tag" holds). Stricter than the handoff's "older than 1 day", which would let a counter live
  almost two days between two runs.
- Disabling the skill: the link, the counter, the Hummlist session and the Zugänge entry go right
  away. Linking again: the older sessions and their links go right away.
- "Amazon Alexa trennen": the session, the link and the counter go right away; GoTrue keeps the
  revoked grant record, which the next daily run deletes, within 24 hours ("spätestens am
  folgenden Tag" holds).
- Unlinking only in the Alexa app: everything stays until the user removes it in Zugänge or the
  skill goes unused for 12 months; then the session, the link and the grant go.

Answers (evidence read 2026-11-02, read-only: Management API config, `database/query/read-only`
as `supabase_read_only_user`, and the logs endpoint):

3. **Region.** Amazon's requests run in **eu-west-1** (Ireland). The three real Alexa requests in
   the last 24 h (2026-11-02 07:16:21, 07:25:34, 07:25:41 UTC; client AS "Amazon Technologies
   Inc.", Cloudflare colo DUB, country IE, user agent Apache-HttpClient) show
   `x_sb_edge_region=eu-west-1` in `function_edge_logs`, and their Boot/Shutdown lines in
   `function_logs` show `region=eu-west-1` (execution ids b013a8b4, 959205fb, 36e75b23). The
   database is in eu-central-1 (Frankfurt). Unsigned probes from elsewhere (curl, US/MX/FI)
   ran in us-west-1, us-east-1, us-east-2 and eu-central-1: Supabase runs the function in the
   region nearest the caller. `?forceFunctionRegion=eu-central-1` would not break request
   verification: `supabase/functions/alexa/verify.ts` checks the `SignatureCertChainUrl` and
   `Signature-256` headers and the signature over the raw body (lines 3-6, 207-211), never the
   request URL. Supabase documents `forceFunctionRegion` as the query form of `x-region`
   (supabase.com/docs/guides/functions/regional-invocation). Not tested: whether the Alexa console
   accepts a query string in the endpoint URI (needs the ASK login, which only the box has). The
   endpoint is unchanged, as briefed.
4. **`last_seen`.** It moves on every request that carries a token Hummlist accepts:
   `linkedOrReply` (`supabase/functions/alexa/handler.ts` l.95-114) calls `alexa_remember`
   (l.112), whose upsert sets `last_seen = now()` (`20261030140000_alexa.sql` l.113-114). That
   covers LaunchRequest (l.196), AddItemIntent (l.158) and ReadListIntent, "what's on the list"
   (l.183), also when the household is locked (the update runs before the Premium check), and
   SkillAccountLinked (l.226-230). It does not move on AMAZON.HelpIntent, Stop, Cancel,
   NavigateHome or Fallback (l.207-215, no account lookup), on an AddItemIntent with nothing
   understood (l.153-157), on SessionEndedRequest, or when the token is refused. A failure of
   the update is reported, not spoken (`.catch`). Hosted: the one link's `last_seen` is
   2026-11-02 07:25:41 UTC, the moment of the last Alexa request in the edge logs. The 12-month
   purge also counts the session's `refreshed_at`: Alexa refreshes the token when it uses it.
5. **Grant after SkillDisabled.** Before this job: yes. `alexa_revoke` deleted the Hummlist
   sessions only (`20261030140000_alexa.sql`, function `alexa_revoke`); the
   `auth.oauth_consents` row stayed with `revoked_at` null, with no expiry, until the user
   removed it in Zugänge or deleted the account. Zugänge lists exactly those rows (GoTrue
   v2.197.0, `internal/api/oauthserver/handlers.go`, `UserListOAuthGrants`: "active (non-revoked)
   consents"), so "Amazon Alexa" stayed listed although it no longer worked; docs/ALEXA.md's
   device check 7 said otherwise. Now `alexa_revoke` deletes the grant in the same call once the
   user holds no other Alexa session; the e2e spec checks that Zugänge shows "Noch keine App
   verbunden." after SkillDisabled. "Trennen" in Zugänge: GoTrue sets `revoked_at` and keeps the
   row (`UserRevokeOAuthGrant`); the daily job now deletes revoked Alexa grants. Hosted today:
   one active Alexa grant, with its session; no revoked one.
6. **Refresh token lifetime.** Unlimited, locally and live. `supabase/config.toml` l.279 and
   l.281 leave `timebox` and `inactivity_timeout` commented out; the hosted project's auth config
   says `sessions_timebox: 0`, `sessions_inactivity_timeout: 0` (0 = off),
   `refresh_token_rotation_enabled: true`, `security_refresh_token_reuse_interval: 10`,
   `jwt_exp: 3600`. Each refresh rotates the refresh token, and the session lives until it is
   revoked. From this job on, an Alexa session also ends after 12 months without use
   (`purge_alexa`). A project-wide timebox would sign app users out too, so it stays off.
9. **Console values against skill.json.** Partly answered. The skill was created from
   `alexa/skill-package/skill.json` with `ask deploy --target skill-metadata` (job 31b,
   docs/ALEXA.md "Deploy" step 2), not typed into the console. Job 31b's manifest read
   (`docs/screenshots/31b/alexa-deploy-smoke.txt`) shows privacy URL
   `https://hummlist.com/datenschutz`, as in skill.json. The terms URL, the countries and the
   privacy answers were not read back then, and this runner has no ASK login. On the box, from
   the repo root:

   ```bash
   diff <(ask smapi get-skill-manifest -s "$ALEXA_SKILL_ID" -g development \
            | jq -S '.manifest | {privacyAndCompliance, countries: .publishingInformation.distributionCountries, mode: .publishingInformation.distributionMode}') \
        <(jq -S '.manifest | {privacyAndCompliance, countries: .publishingInformation.distributionCountries, mode: .publishingInformation.distributionMode}' alexa/skill-package/skill.json) \
     && echo "console matches skill.json"
   ```

   Run it against main's skill.json: job 69 changes skill.json (English locales), so a
   difference may be job 69's not yet deployed change rather than a hand edit.

## Job 73: the Hummlist API (2026-11-02)

The API (`docs/API.md`, `docs/api/openapi.yaml`) ships dark: the app shows the API section under
Mehr → Zugänge only while the PostHog flag `public-api` is on, and this job turned nothing on, in
no dashboard, console or hosted database. Merging deploys the `api` function and the migration
(`supabase-deploy.yml`) like any other.

### For the lead

1. **Create the flag** `public-api` in PostHog project 319492 (Hummlist; never emotely 262464),
   off. `releases/flags.json` has it as `"rollout": "off"`, so the changelog item waits for it.
2. **The function works without the flag.** `create_api_token` is an RPC any signed-in app session
   can call, so someone who knows it can make a key and use the API before the flag is on. It
   reaches only their own household, under RLS, the limits and (later) the Premium lock. If that
   is not acceptable, a server switch in `app_switches` checked by `create_api_token` is a small
   follow-up (DECISIONS "Job 73", 10). Done in job 75: the server switch `app_switches.public_api`
   (off) closes both, see "Job 75" below.
3. **The address throttle keys on the gateway's `X-Real-IP`** (checked on the hosted project
   before the deploy, DECISIONS "Job 73" 8: hosted Supabase passes `X-Forwarded-For` on as the
   client wrote it, `X-Real-IP` and `cf-connecting-ip` are the real address). Only unknown keys
   count and are blocked; valid, missing and ended keys never are (DECISIONS 14). Optional smoke
   after the deploy: `for i in $(seq 21); do curl -s -o /dev/null -w '%{http_code} ' -H
   "Authorization: Bearer fgp_x$i" -H 'X-Forwarded-For: 198.51.100.'$i
   https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/api/v1/items; done` ends in `429`
   despite the rotating `X-Forwarded-For`; that blocks only unknown keys from that address for
   10 minutes.
4. **The integration-lock card's copy** names Siri, Alexa and AI assistants
   (`integrationPremiumTitle`, `integrationPremiumBody` in `app/l10n/app_*.arb`) and the held
   changelog item for `integration-lock` too. Neither mentions the API; the API section has its own
   Premium line. Whether the card should name the API is copy for Hummlist Launch.
5. **The PostHog insight** "Locked integrations" (`analytics/queries/integration_blocked_weekly.sql`)
   gained an `api` column. If the insight in PostHog is a copy of the query, paste the new one.
6. **A public domain** (`api.hummlist.com`, a Vercel rewrite like `mcp-proxy/`) needs Peter's OK;
   the API is served under the Supabase functions URL meanwhile.

### Premium (Addendum 1, Q41 = PA2)

The API is behind the integration lock: `integration_gate(household, 'api')`, called by the
function after the rate limit and before any read or write (`supabase/functions/api/handler.ts`).
A household without Premium gets `402 premium_required` while `app_switches.integration_lock` is
on; while it is off (until the paywall release, `docs/PAYWALL_RELEASE.md` 6.4) every household may
use the API. Refusals report `integration_blocked` with `integration: api`, once an hour per
household, like the others. `docs/PAYWALL_RELEASE.md` section 6 says so.

### Legal Review: privacy facts

- **Per API key** (`public.personal_access_tokens`, kind `api`): the member who made it, the
  household, a name the user typed, the SHA-256 hash of the key, its last four characters, the
  scopes (`read`, or `read` and `write`), created, last used, revoked. The key itself is shown once
  and never stored. Retention as for every access key: 30 days after it ended, then deleted
  (`purge_access_tokens`, Legal N-4); at once with the account or the household. The data export
  (`export_my_data`) lists API keys among `access_tokens` (name, hint, dates), without scopes.
- **Rate counters** (service only, no client reads them): per key a fill level and its last time
  (`api_token_buckets`), per household a request count per UTC day (`api_household_days`). Deleted
  daily by `purge_api_rate` (pg_cron `purge-api-rate`, 03:41 UTC): days before yesterday, buckets
  unused for a day. Basis (f), abuse protection.
- **Failed authentications** (`api_auth_failures`): only for keys we never issued, the SHA-256 of
  the caller's IP address as the gateway saw it (`X-Real-IP`), never the address, a window start
  and a count; ended windows are deleted as new failures come and daily once a day old. A hash of an IPv4 address
  can be reversed by trying all addresses, so it is pseudonymous, not anonymous: kept at most about
  two days. Basis (f).
- **Idempotency records** (`api_idempotency`): the key, the client's Idempotency-Key, a hash of the
  request and the stored response, which contains item names; 24 hours, deleted daily, at once with
  the key, household or account.
- **Logs**: one line per request in the Supabase function logs (request id, method, route template,
  status, duration, the key's id); never a body, item name, header value or address. Errors go to
  PostHog error tracking with the template words only (`_shared/telemetry.ts`).
- `docs/PRIVACY_DATA_MAP.md` has the five rows. The privacy page (`site/`) is Legal's to change: it
  names MCP and Siri access keys but not the API.
- **Premium terms**: the terms draft (PR #153) lists what Premium includes (Siri, connections
  with AI assistants over MCP). With Q41 = PA2 it should name the Hummlist API too. Not changed here (legal text).

### Open questions

- **Webhooks** (outgoing events such as "item added") are the obvious v2, so automations need not
  poll. Not built (brief).
- **OAuth for third-party apps** (Zapier as a registered client with `read`/`write` scopes) is not in
  v1; the MCP's OAuth server could carry it.
- **A user guide** for hummlist.com (DE and EN, how to make a key and a first Shortcut) can follow
  once the flag rolls out.

## Job 75: the API's server switch (2026-11-02)

The PostHog flag `public-api` hides only the app's API section. Since job 75 the server has its
own switch, `public.app_switches` key `public_api`, seeded **off** by
`supabase/migrations/20261102200000_public_api_switch.sql`. While it is off:

- `create_api_token` refuses with `api_disabled` (SQLSTATE 42501); the app shows „Die API ist noch
  nicht freigeschaltet.“ (EN "The API isn't available yet.") if someone reaches the button.
- every request to the `api` function answers `404` with `{"error":{"code":"not_found",...}}`,
  exactly like an unknown path, without rate-limit headers, before any key lookup, counter or
  read. Keys made before stay listed in the app and can be revoked; they work again once the
  switch is on.
- MCP, Siri and Alexa do not read the switch and behave as before.

The deploy of this migration (`supabase-deploy.yml` after the merge) is the only production change.
Nothing else was switched.

### Turning the API on (when Hummlist Launch says so)

1. Server: in the SQL editor of project `jdwqrallbpdbshrdhenk` (or the Management API's
   `database/query`, service role):
   `update public.app_switches set enabled = true where key = 'public_api';`
   Check: `select public.app_switch('public_api');` is `true`, and
   `curl -s https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/api/v1/items` answers `401`
   `missing_token` instead of `404`.
2. App: roll out the PostHog flag `public-api` (project 319492) and set it in
   `releases/flags.json` in a PR, so the held changelog item goes out.
3. Off again: the same update with `false`. Requests answer 404 at once, keys stay.

Order: server first, then the flag, so nobody sees a button that answers „noch nicht
freigeschaltet“. Whether the integration lock (`integration_lock`, Premium) should be on before the
API opens is the paywall release's call (`docs/PAYWALL_RELEASE.md` 6.4); the API switch does not
depend on it.

## Job 78: list and stores management (2026-11-02)

Calls made without Peter (DECISIONS, Job 78); say if one should go the other way:

1. Trash on a category inside a store's details deletes the category for the whole household
   (categories are shared), after a dialog that says so. The alternative, hiding it in that store
   only, needs the list to honour the per-store `hidden` flag, which it does not today.
2. The pseudo-store is labelled „Ohne Laden“ / "No store", as on the list, not „Kein Laden“.
3. Store deletion keeps the confirm dialog and has no undo (there is no undo for it in the app).
4. Item drag to another store or category on the list is gone too, not only reordering; moving an
   item happens in its edit sheet.
5. The "automatic" mark on the add sheet's chips is a circled „A“, not a sparkle.
6. Store deletion has no undo: the server deletes the store and untags its items, so an undo would
   have to recreate the store, its layout and every tag. Kept as a confirm dialog; a real undo is
   its own job if wanted.
7. Please decide item 1 explicitly: a trash icon inside one store's details may read as "remove
   from this store". Keeping household-wide deletion needs no change; per-store hiding needs the
   list to honour the `hidden` flag (a follow-up job).
8. The store and category rows are raised hex pills as on the old screens; the reviewer found them
   heavier than Settings' rows. Say if they should become plain rows like Settings.
## Job 80: connected apps name their device (2026-11-02, for Legal Review)

Mehr › Zugänge no longer lists a connected app's scopes ("Deine Anmeldung bestätigen · Deine
E-Mail-Adresse · Dauerhaft angemeldet bleiben"). Each row now reads like
„Chrome · macOS · Verbunden am 2.11.2026 · Zuletzt aktiv 2.11.2026“, and a tap opens a sheet
that says in plain words what the app may do, with „Claude trennen“.

New personal data, kept minimal (`supabase/migrations/20261102213000_connected_app_devices.sql`):

- `public.oauth_app_devices`: per user and OAuth client one short label of the browser and
  system the user approved the connection in (`Chrome · macOS`, `Safari · iOS`, `iOS` in an
  app). The app derives it on the device (`app/lib/oauth/device_label.dart`) and sends only the
  label; the server refuses anything longer than 40 characters or outside letters, digits, space,
  `.()·-`, so a whole user agent cannot be stored. No IP address, no location, no user agent.
- Why not Supabase's own session data: the sessions of an OAuth client carry the client's HTTP
  library as user agent (in production today: `undici` for Cursor, `python-httpx/0.28.1` for
  Claude, `Apache-HttpClient` for Alexa, `codex-mcp-client` for Codex), which names no device.
- Retention: the label goes when the grant ends (Trennen, `alexa_revoke`, the Alexa purge: a
  trigger on `auth.oauth_consents`) and with the account. It is in the data export under
  `connected_apps[].device`. `docs/PRIVACY_DATA_MAP.md` has the row.
- „Zuletzt aktiv“ is read from `auth.sessions` (the newest token refresh of that client), which
  Supabase Auth already stores; nothing new is kept for it.

**For Legal Review:** the privacy policy's section on connected apps (MCP, Alexa) may need one
line, e.g. „Beim Verbinden speichern wir, in welchem Browser und auf welchem System du die
Verbindung freigegeben hast (z. B. „Chrome · macOS“), damit du deine Verbindungen unter Zugänge
unterscheiden kannst. Die Angabe wird gelöscht, sobald du die Verbindung trennst.“ I did not
change any legal text.

## Job 89: spoken quantity words (2026-11-03)

PR #215. Merges on lead review + green CI; the voice and
alexa functions deploy with the next `supabase-deploy.yml`/release run.

- **Alexa skill model: no change.** Nothing under `alexa/skill-package/` changed; no skill deploy
  and no certification step.
- **Behaviour change to confirm.** Spoken, any count after the item is the quantity again
  („Büroklammern hundert“ → 100 Büroklammern, „Eier dreißig“ → 30 Eier). Typed text keeps job 61's
  stricter rule. Say if speech should keep a cap (e.g. 1 to 30) instead.
- **Your call: typed „zwei Gurken“ offline.** The app's offline parser keeps „zwei Gurken“ as the
  name while the server reads Gurken ×2 (pre-existing, typed path, out of this job's scope). Porting
  the number words to `app/lib/list/entry.dart` would be a small follow-up job.

## Job 88: onboarding own store named like a chain (2026-11-03)

PR #214. No Legal items: nothing new is shown. One call made without Peter (DECISIONS, Job 88):
a typed „edeka“ is now stored as „EDEKA“, the chip's spelling, because it ticks that chip. The
server already allowed only one store per name key, so no server guard was added.

## Job 85: More menu M-P2 (2026-11-02, addendum 1 on 2026-11-03)

PR #211, rebased onto main after #207 merged; lands with `scripts/merge-pr.sh --wait 211` under
the merge lock after lead review.

Legal-relevant, for information; nothing waits on Legal:

1. Addendum 1 put the legal rows on More itself: Mehr → Impressum is two taps from the list
   (§5 DDG), with Datenschutzerklärung, „Nutzungsbedingungen (EULA)“ and Lizenzen next to it.
   The terms row uses the Premium page's placeholder label and link (`termsUrl`: Apple's EULA
   on iOS, the support page elsewhere; H-93, NEEDS_LEAD Job 49), so it changes when those do.
   „Datenschutz bei Käufen“ is not linked anywhere in the app today and has no row.
2. The usage-data switch is under Mehr → Nutzungsdaten again (a row of its own, page title
   „Nutzungsdaten“). The approved consent text (version 2026-11-01) and the privacy policy say
   exactly that path, so the wording issue raised in the first round is gone; no legal text
   changes.
3. The Premium row no longer shows „Freigeschaltet“ (M-P2 has no row hints); the Premium page
   still shows the household's status.

## Job 82: the hummlist.com waitlist (Spec #10), 2026-11-02

Everything is built and off. Production looks exactly as before until Peter turns three things
on (below). The design and every route are in [`WAITLIST.md`](WAITLIST.md).

### Not merged: Legal's "no copy may be merged"

PR #210 is green and invisible in production, so the PM's rule would allow a merge. The Legal
handoff also says "no copy may be merged or deployed, before Peter's approval in his own words",
and the PR carries Legal's draft texts (behind `⟦LEGAL …⟧` markers in the consent files, the
privacy-policy blocks and the mail templates). I left it open with its Vercel preview. Two ways
on, your call:

- Merge as is: production stays the old site (`site/scripts/classic-diff.mjs`), the edge function
  answers 404 without its secrets, and the drafts sit unpublished in the public repo.
- Wait for Peter's approval, replace the markers with the approved texts in this PR, then merge
  and switch on (NEEDS_PETER "Job 82").

Region proof (Addendum 4): the preview is behind Vercel login, so `curl -si -X POST
<preview>/api/waitlist` answers 401 from the edge (`x-vercel-id: arn1::…`) and never reaches the
function. `docs/legal/waitlist-region-proof.txt` is not written yet; it needs a logged-in or
bypass request once the Vercel env vars are set (NEEDS_PETER "Job 82", step 3).

### Data flow for Legal Review

| Step | Where | What is stored or seen | How long |
| --- | --- | --- | --- |
| Form | hummlist.com page, `fetch` to the same origin | nothing (no cookie, no storage, no analytics, no third-party resource) | |
| Vercel function `/api/waitlist*` | Vercel, `regions: ["fra1"]` in `site/vercel.json` | sees the IP and the body; logs only a fixed outcome code; sends on an HMAC of `<UTC date>\|<IP>` (keyed with the proxy secret), never the IP | Vercel's own request logs (path, no body) |
| Edge function `waitlist` | Supabase, `x-region: eu-central-1` | sees the body; logs only outcome codes | |
| `public.waitlist` | Supabase Postgres, Frankfurt | email, HMAC of the email, platform, locale, launch news, consent version, sign-up, confirm, invite, launch-mail and last-mail times, the SHA-256 of the confirm token and its expiry | unconfirmed 7 days; confirmed 3 months after the invite, with launch news 30 days after the launch mail; everything by 2027-12-31 (Berlin); unsubscribe deletes at once |
| `public.waitlist_consent_proof` | same | HMAC of the email, consent version, locale, launch news, the four times, end reason; never the address, never an IP | 3 years after the later of last mail and end |
| `public.waitlist_rate` | same | SHA-256 of the daily client key, the hour, a count | deleted after 2 hours |
| Resend | Resend (USA), domain hummlist.com in eu-west-1 | the mail (to, subject, body); no tags, no metadata; single sends with an idempotency key | Resend's 30 days |

Retention hook: `public.purge_waitlist(now)`, pg_cron `purge-waitlist` daily at 03:23 UTC, every
period tested to the minute in `supabase/tests/waitlist.test.sql`.

### What is still a placeholder

Every text not yet approved by Peter is behind a visible marker, and a production build or a mail
fails while one is left: `⟦LAUNCH COPY⟧` (landing, welcome and invite mails, confirmation pages),
`⟦LAUNCH COPY FAQ⟧` (FAQ, /support), `⟦LEGAL W2⟧` (consent line, checkbox, FAQ answer, the
privacy-policy redlines, the confirmation mail body), `⟦LEGAL FOOTER⟧` (mail footers),
`⟦LEGAL privacy.website⟧`, `⟦LEGAL W1⟧` (stated periods). The Legal drafts are used word for
word behind them. The policy line about Vercel uses the variant without „läuft in Frankfurt am
Main“, since the fra1 check (below) has not run.

### Ambiguous, decided, please confirm

1. **Rate limit storage.** Addendum 3 says "ephemeral keys that are never persisted", the handoff
   "a short-lived hashed counter (≤ 24 h)". In-memory counters don't hold across Vercel
   instances, so the counter lives in Postgres: SHA-256 of a daily-rotating HMAC of the IP,
   per hour, deleted after 2 hours. 10 sign-ups per key per hour (IPv6 clients keyed by their /64), 300 per hour in total.
2. **No `unsubscribed_at`.** Spec AC8 lists it; the Legal handoff (binding) says unsubscribe
   deletes the row. The column is not there.
3. **The 2027-12-31 cap applies to every row**, not only launch-news ones, so a confirmed address
   that is never invited doesn't stay forever.
4. **Sender name per language:** "Peter von Hummlist" in German mails, "Peter from Hummlist" in
   English ones (Legal handoff 2.5).
5. **Welcome mail** goes out automatically right after confirming (consent text names it). It is
   not an invite. Its text is a neutral draft behind `⟦LAUNCH COPY⟧`: Launch's draft 5b was not
   in the brief.
6. **Root `/`.** Live today it already redirects by language to `/de` or `/en` (307), the landing
   pages, not the browser app. Kept as it is (PM override 3).
7. **Backups.** The backup drill dumps every public table, so encrypted backups hold waitlist
   addresses for the backup retention. Legal should say whether its periods cover backups.
8. **Deletion request by mail** (`end_reason = deletion_request`) has no function yet; Peter
   handles it with the unsubscribe link of the address's mail, or by SQL (NEEDS_PETER).
9. **app.hummlist.com had no noindex** (AC15 assumed it). The app's `vercel.json` now sends
   `X-Robots-Tag: noindex`; it reaches app.hummlist.com with the next store release, or sooner if
   you move the `release` branch.
10. **Launch mail** is not built (later spec); `launch_mail_sent_at` exists for the purge.

### Invites (Addendum 2)

Nothing sends an invite by itself: no cron, trigger or webhook. Confirmed sign-ups fall into a
batch by the ISO week of `confirmed_at` (Europe/Berlin), for example `2026-W47`.
`scripts/waitlist/invite.ts --batch 2026-W47` prints counts only (confirmed, invited, to invite,
per platform and locale). `--batch 2026-W47 --confirm 2026-W47 --export-dir <dir>` sends the
invite mail to each uninvited row of that batch, sets `invite_sent_at`, and writes `ios.csv`
(TestFlight import) and `android.csv` (Play email list). It prints counts only. Peter runs it
himself; no agent runs `--confirm`.

### W4: Android tester limit

Checked 2026-11-02 in the Play Console help ("Set up an open, closed or internal test"): internal
testing allows up to 100 testers per app; closed testing takes email lists of up to 2,000 users
each (up to 200 lists, 50 per track). Past 100 Android sign-ups, move the beta to a closed track
with an email list (`android.csv` fits it).
