# Needs the Engineering Lead

Browser steps for the Engineering Lead, in the build box's browser, with
Peter only signing in. Everything around them is done from the box. Steps
that need Peter's own decision, money or identity are in
[`NEEDS_PETER.md`](NEEDS_PETER.md) instead.

## mcp.snacklist.app (set up as mcp.hummlist.com)

Status: done. The public MCP URL is `https://mcp.snacklist.app`, a second production domain on
the same `hummlist-mcp` project (2026-11-10, #355); `mcp.hummlist.com` keeps serving for clients
set up before the rename and advertises its own host. The Lead posted `Lead: mcp.hummlist.com
live` (2026-10-28 15:44), and job 26's `scripts/mcp-smoke.sh https://mcp.hummlist.com` passed.
The steps below stay as the record of that setup; for the Snacklist host, read
`mcp.snacklist.app` for `mcp.hummlist.com` in steps 2, 3 and 5.

Job 26. Made `https://mcp.hummlist.com` the public MCP URL
([`MCP.md`](MCP.md#public-url-mcpsnacklistapp)). Everything else is on
`main`: `mcp-proxy/vercel.json` and the function that advertises the public
URL. Nothing here costs money: a Hobby project, no env vars, no secrets.
DNS needed no change: hummlist.com is on Vercel's nameservers with a
wildcard, and `mcp.hummlist.com` answered `DEPLOYMENT_NOT_FOUND` then.

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

The steps below stay as the record of what was done and for a re-setup. The status above is
the Hummlist app (`com.hummlist.app`, kept until R1 retires it); the steps name the Snacklist
app (`com.snacklist.app`), which the Release workflow builds and uploads now.

Values used below (none is secret):

| What | Value |
| --- | --- |
| Package name | `com.snacklist.app` |
| App name | Snacklist |
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

Only if "Snacklist" is not in "All apps".

1. Select **Create app**.
2. App name: `Snacklist`. Default language: `German – de-DE`. App or game:
   **App**. Free or paid: **Free**.
3. Tick the declarations (Developer Program Policies, US export laws).
   Select **Create app**.

The package name is set by the first upload (L3) and cannot change after
that; the AAB carries `com.snacklist.app`.

Verify: Snacklist opens on its Dashboard.

### L3: Internal testing, first release, Play App Signing

1. Get the signed AAB. For the first upload: `~/groceries-ops/artifacts/app-release.aab`
   (built on the box, version code 1003, signer checked). Later: the newest
   Release run on `main` with an `android`
   job (Actions, Release, open the run, Artifacts,
   `snacklist-<build number>-aab`; artifacts are kept 7 days). Unzip it to
   get `app-release.aab`. If none is younger than 7 days, run
   `gh workflow run release.yml -f upload=false -f platform=android` and
   wait about 15 minutes.
2. Snacklist, **Test and release**, **Testing**, **Internal testing**,
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
3. **App permissions**, **Add app**: Snacklist only. Tick:
   - **Release to testing tracks** (under Releases)
   - **View app information (read-only)** (under App access)
   Leave everything else unticked, including account permissions.
4. **Apply**, **Invite user**, confirm.

Verify: the next Release run's `android` job, step `upload`, prints
"Play access works" (before `PLAY_RELEASE_STATUS` is set) or uploads to
internal testing (after). Until L4, it prints "Play refuses the service
account for com.snacklist.app (...)".

### L5: Policy items (App content)

Google's help: "You can start an internal test before completing app setup"
([Set up an open, closed, or internal test](https://support.google.com/googleplay/android-developer/answer/9845334)).
None of the items below blocks an internal testing upload or rollout. They
block closed testing, open testing and production, and the Dashboard lists
them under "Set up your app".

| Item (Policy, App content) | Blocks internal testing | Blocks closed/open/production | When |
| --- | --- | --- | --- |
| Privacy policy URL | No | Yes | After 33a's policy is on snacklist.app (https://snacklist.app/datenschutz). |
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
for universal links (`applinks:app.snacklist.app`).

1. <https://developer.apple.com/account>, Peter signs in. **Certificates,
   Identifiers & Profiles**, **Identifiers**, `com.snacklist.app`.
2. Tick **Associated Domains**. Leave every other capability as it is.
   **Save**, confirm the dialog about invalidated profiles.
3. Do not touch **Certificates** or **Profiles** (no revoke, no new
   certificate). The profile "match AppStore com.snacklist.app" now shows
   "Invalid"; that is expected.
4. Post on BOARD.md that L6 is done. The box (job 22, or whoever is
   running) then runs `bundle exec fastlane ios renew_profile`
   (`RELEASE.md`, "Capabilities", step 2), which regenerates the profile
   with the existing certificate `GN85KDC962`.

Verify: Profiles shows "match AppStore com.snacklist.app" as Active with a
new expiry date, and the next Release run's `plan` passes "Check the
profile". Between step 2 and the box's `renew_profile`, a Release run fails
in `plan` with "Profile ... is INVALID"; that is the expected signal, not a
new problem.

### L7: Google sign-in on Play builds

Google Cloud Console, project `family-groceries-512507`, **Google Auth
Platform**, **Clients**, **Create client**, type **Android**:

1. Name `Snacklist upload key`, package `com.snacklist.app`, SHA-1
   `D4:9D:98:9E:AD:E3:2E:FE:D2:D3:A1:7A:71:B2:95:29:84:81:78:69`.
   **Create**. (Builds signed locally or by CI with the upload key.)
2. After L3: a second client, `Snacklist Play app signing`, package
   `com.snacklist.app`, SHA-1 = the app signing key SHA-1 from L3, step 7.
   This one makes Google sign-in work in builds installed from Play.

No client secret is created and nothing goes into the repo: the app never
sends an Android client ID; Google matches it by package and SHA-1.

Verify: both clients are listed with package `com.snacklist.app`. On a phone
with the internal testing build, "Mit Google anmelden" completes.

## Job 24: help page URLs (after Peter's publish OK)

Status: waiting for Peter's OK on the text (docs/NEEDS_PETER.md, Job 24).

1. Send Peter the hummlist-site preview of the PR's head: `/support` and `/en/support` on the
   preview deployment URL (BOARD.md line "24-privacy-page: PR …", or the PR's Vercel check).
2. After the publish PR is merged and https://snacklist.app/support answers 200:
   - App Store Connect → Apps → Snacklist → the app version (or App Information) → **Support
     URL**: `https://snacklist.app/support` (required for review). Marketing URL stays empty.
   - Play Console → Snacklist → Grow users → Store presence → Store settings → **Store listing
     contact details**: Email `support@snacklist.app`, Website `https://snacklist.app/support`,
     **Save**.
3. Check: `curl -sI https://snacklist.app/support | head -1` gives 200 and the page has no
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
(an alias on snacklist.app works; never a real person's Apple ID without his OK), region Germany.
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

## Job 43: Snacklist Lifetime, household-bound (2026-10-31)

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

1. RevenueCat account and project "Snacklist", named "Hummlist" until 2026-11-10 (free up to USD 2,500 monthly tracked revenue, then
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
  someone with a valid invite sees, before joining, whether the household has Snacklist Lifetime;
  the joining user's own recent purchase (30 days) is checked to offer the refund help (shown to
  no one else); members see when the household bought Lifetime more than once.
- "Rechtsgrundlage: … dass ein Kauf nicht mehrfach oder in fremden Haushalten verwendet wird." /
  "Legal basis: … not used twice or in other households.": now enforced also after the household
  is deleted (the kept household id for 30 days, then the HMAC tombstone, kept while Lifetime is
  sold or honoured, reviewed yearly).
- "Speicherdauer: Die Freischaltung bleibt beim Haushalt … Löschst du dein Konto, entfernen wir
  die Verbindung zwischen dem Kauf und deinem Konto; die Transaktion selbst bleibt ohne
  Personenbezug gespeichert, solange Snacklist betrieben wird … Wird der Haushalt gelöscht, endet
  seine Freischaltung." / "Retention: …": the transaction is no longer kept while Snacklist runs:
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
  `runtimeType` (Snacklist's `errorType` in `app/lib/analytics/exceptions.dart` does this), and let
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
  reminder e-mail: Snacklist sends no e-mails of its own (DECISIONS 47.3). If the texts promise a
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

Sign in to Snacklist on the TestFlight build, open the list once, then close the app. Set Siri to
English (Settings → Siri → Language) for lines 1 to 5, then to German for lines 6 to 9.

1. "Hey Siri, add to Snacklist" → "What should I add?" → "milk, eggs and bread" → Siri: "Added
   milk, eggs and bread to Snacklist." Lea's phone shows the three items within seconds.
2. "Hey Siri, add milk to Snacklist" (milk on the list before) → no follow-up question, "Already on
   the list: milk." or "Added milk …".
3. "Hey Siri, what's on my Snacklist?" → reads at most ten items, then "and N more".
4. Airplane mode on, then line 1 → Siri says nothing was added. No item appears after airplane
   mode goes off again.
5. HomePod (if one is paired, Personal Requests on): line 1 → the full sentence is spoken.
6. "Hey Siri, füge etwas zur Snacklist hinzu" → "Was soll auf die Liste?" → "Milch, Eier und Brot"
   → "Hinzugefügt: Milch, Eier, Brot." (German device: the checks in "Job 71" below.)
7. "Hey Siri, füge Milch zur Snacklist hinzu" → no follow-up question.
8. "Hey Siri, was steht auf meiner Snacklist?" → reads the list.
9. Mehr → Abmelden, then line 6 → "Öffne Snacklist und melde dich an …", nothing added.
10. The old Shortcut ("Hey Siri, Einkaufsliste") still answers as before.
10a. One-word items take the app's language when the word is too short to tell (DECISIONS "Job 51"
    item 13). With the iPhone in English and Siri in German, say "Füge etwas zu Snacklist hinzu" →
    "Milch". Note whether the answer comes in German or English. English there is a known
    limitation, not a failure; the item must still be added.
11. Later, with job 50's lock on and a locked household: line 6 → the Premium sentence, nothing
    added, the app stays closed.

If Siri doesn't hear the phrases at all (lines 1 and 6), do section 2 and test again.

### 2. Only if the device test needs it: the Siri capability

Apple requires `com.apple.developer.siri` for SiriKit Intents extensions, not for App Intents
(DECISIONS "Job 51" item 5). If voice invocation fails anyway:

1. Lead: developer.apple.com → Identifiers → `com.snacklist.app` → enable **Siri** → Save.
2. On the box, renew the App Store profile (docs/RELEASE.md "Capabilities"): `bundle exec fastlane
   ios renew_profile` with the env shown there.
3. A one-line PR adds `<key>com.apple.developer.siri</key><true/>` to
   `app/ios/Runner/Runner.entitlements`. Its CI `ios` job and the next Release run prove the
   profile matches.

No `NSSiriUsageDescription`: the app never calls `INPreferences.requestSiriAuthorization`.

### 3. Placeholder copy for Snacklist Launch (Spec #5)

- `premium_required` (voice, not reachable until job 50): de "Sprachbefehle sind Teil von
  Snacklist Premium. Du kannst es in der App freischalten. Ich habe nichts hinzugefügt." en "Voice
  commands are part of Snacklist Premium. You can unlock it in the app under More, Snacklist Premium.
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
  Shortcuts system so that "Add milk to Snacklist" works. Apple states it "may extract anonymized
  App Shortcuts data such as localized phrases, display representation values … Machine learning
  models use this data" (https://developer.apple.com/documentation/appintents/app-shortcuts). The
  display representation values are our item names. The privacy text should say so, or Launch
  drops the one-shot phrase.
- **Analytics.** `siri_add` and `siri_read` (docs/ANALYTICS.md) count Siri use per household under
  the existing consent. No text and no names.

### 5. Known gaps

- English "beer" is classified as produce (DECISIONS "Job 51" item 11). The household's category
  memory fixes it after one move.
- Since job 97 the app needs iOS 17, so every iPhone that gets updates has native Siri. iPhones
  on iOS 15 or 16 stay on the last build that supported them; the Shortcut recipe still works
  there because it needs only Apple's Shortcuts app and an access key.


## Job 49: Snacklist Premium, yearly and Lifetime (2026-11-01)

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
   Secrets of the environment `ops` (`gh secret set <NAME> --env ops`, not repository secrets:
   NEEDS_PETER, Job 220, step 3), set without printing them:
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
7. **StoreKit configuration file:** `app/ios/Snacklist.storekit` was written by hand (Xcode format
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
- **S-11**: the rename „Snacklist Lifetime“ → „Snacklist Premium“ in the 26 values of app_de.arb
  (and app_en.arb) was not applied (legal text change; Peter's approval).
- **Terms / EULA (H-20, H-93)**: no Snacklist terms exist. The Premium page links Apple's standard
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
  they need Snacklist Premium; the support FAQ (`site/content/legal/support.md`,
  `support-en.md`), the purchase privacy page (`datenschutz-kaeufe.md`, `privacy-purchases.md`)
  and the store listings may call them free or not name them as premium. Check before the switch.
- The new service-only table `integration_blocks` (household, integration, last report time) is
  in docs/PRIVACY_DATA_MAP.md; it cascades with the household.

### Snacklist Launch: placeholder copy

| Where | Key | Text (DE; EN in the same file) |
| --- | --- | --- |
| `supabase/functions/voice/copy.ts` | `failures.premium_required` | Sprachbefehle sind Teil von Snacklist Premium. Du kannst es in der App freischalten. Ich habe nichts hinzugefügt. |
| `app/ios/Runner/Localizable.xcstrings` (job 51, used only when the server sends no speech) | `siri.locked` | Sprachbefehle sind Teil von Snacklist Premium. Du kannst es in der App freischalten. |
| `supabase/functions/alexa/speech.ts` | `premiumAdd` | Snacklist nimmt für euren Haushalt gerade keine Sprachbefehle an. Ich habe nichts hinzugefügt. (job 69: Alexa is not Premium) |
| `supabase/functions/alexa/speech.ts` | `premium` (read, launch) | Snacklist nimmt für euren Haushalt gerade keine Sprachbefehle an. |
| `supabase/functions/mcp/tools.ts` | `premiumRequired.de` / `.en` | Dieser Haushalt braucht Snacklist Premium für den Zugang über KI-Assistenten. Schalte es in der Snacklist-App frei. Es wurde nichts gelesen oder geändert. |
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
Snacklist Premium without naming a purchase. The "Requirements for account linking" page
(https://developer.amazon.com/en-US/docs/alexa/account-linking/requirements-account-linking.html,
modified 2026-09-29, read 2026-11-01) has no rule about the description. Recommended: the skill
description says that Siri, Alexa and AI assistants need Snacklist Premium for the household,
before the switch goes on. The certification test account needs premium (a tester grant), or the
certifier hears only the premium answer. No Alexa console change was made.

### MCP and docs for clients

`docs/MCP.md` has the engineering note. Client-facing texts that will need a premium note
(Snacklist Launch, not edited here): the site guides under `site/content/guides/` about connecting
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

## Job 54: demo videos for snacklist.app (2026-11-01)

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

## Job 68: account deletion and Snacklist Premium (2026-11-02, for Legal Review)

**Outcome (DECISIONS 68.1 to 68.3).** Deleting the account never archives a household:

- **Last member of a household with Premium** (Lifetime, a yearly plan or a promotional grant):
  the household is deleted with the account, its Premium ends. With `HOUSEHOLD_ARCHIVE` on, the
  dialog says so, explains that archiving isn't possible there and that inviting someone keeps the
  household, links the refund help, and Delete waits for the tick „Ich habe verstanden: Snacklist
  Premium endet und wird nicht automatisch erstattet.“ (EN "I understand: Snacklist Premium ends and
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
Freischaltung mit Snacklist Lifetime", archived households deleted too), which job 68 did not
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
- Everything works: tell the lead. The `native-siri` hold stays until Snacklist Launch.

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
- Disabling the skill: the link, the counter, the Snacklist session and the Zugänge entry go right
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
4. **`last_seen`.** It moves on every request that carries a token Snacklist accepts:
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
5. **Grant after SkillDisabled.** Before this job: yes. `alexa_revoke` deleted the Snacklist
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
   `https://hummlist.com/datenschutz`, as skill.json said then (snacklist.app since #352). The terms URL, the countries and the
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

## Job 73: the Snacklist API (2026-11-02)

The API (`docs/API.md`, `docs/api/openapi.yaml`) ships dark: the app shows the API section under
Mehr → Zugänge only while the PostHog flag `public-api` is on, and this job turned nothing on, in
no dashboard, console or hosted database. Merging deploys the `api` function and the migration
(`supabase-deploy.yml`) like any other.

### For the lead

1. **Create the flag** `public-api` in PostHog project 319492 (Snacklist; never emotely 262464),
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
   Premium line. Whether the card should name the API is copy for Snacklist Launch.
5. **The PostHog insight** "Locked integrations" (`analytics/queries/integration_blocked_weekly.sql`)
   gained an `api` column. If the insight in PostHog is a copy of the query, paste the new one.
6. **A public domain** (`api.snacklist.app`, a Vercel rewrite like `mcp-proxy/`) needs Peter's OK;
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
  with AI assistants over MCP). With Q41 = PA2 it should name the Snacklist API too. Not changed here (legal text).

### Open questions

- **Webhooks** (outgoing events such as "item added") are the obvious v2, so automations need not
  poll. Not built (brief).
- **OAuth for third-party apps** (Zapier as a registered client with `read`/`write` scopes) is not in
  v1; the MCP's OAuth server could carry it.
- **A user guide** for snacklist.app (DE and EN, how to make a key and a first Shortcut) can follow
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

### Turning the API on (when Snacklist Launch says so)

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

## Job 93: agent-first site checks (2026-11-03)

1. Review and merge PR #223 (the brief asks for lead review before the merge). The land
   sequence is `scripts/push-pr.sh`, then `scripts/merge-pr.sh --wait 223` under the merge lock.
2. Copy Scout's `/workspace/hummlist/research/agent-first-website-2026-11.md` to hz, or compare
   it with `docs/AGENT_FIRST.md` "Needs a rule" yourself. The file never reached hz, so that
   checklist is the job's own reading.
3. Merge order with job 82 (#210). Both PRs add `site/config/stage.ts` with the same line, so
   the second one rebases. After job 82 is on main, the `site-agent` gate runs the waitlist
   form check (labels, no CAPTCHA, axe, consent byte for byte, pending confirmation). It passed
   on job 82's branch at e874cd3 (`site/checks/agent-forms.test.mjs` copied into a worktree of
   that commit, 12/12). After rebasing onto job 82, confirm that the `site-agent` log no longer
   says `# SKIP waits for job 82`.

## Job 91: Alexa dispatch diagnosis (2026-11-03)

- **PR:** #219 (changelog `none`; merges on your review + ci-ok).
- **Token lifetime:** compatible, no config change. Hosted: JWT 3600 s, rotation on, reuse
  interval 10 s, no timebox or inactivity timeout; the Alexa session uses v1 refresh tokens.
  Supabase accepts the direct parent of the current refresh token with no time limit (supabase/auth
  `internal/tokens/service.go` 382-391), so one lost refresh answer at Amazon is harmless. Only a
  token two rotations old after 10 s kills the link (`refresh_token_already_used`, shown by
  diagnose.sh). One mismatch we can't change: Supabase answers that with 400 + `error_code`, not
  OAuth's `invalid_grant`, so Alexa may show an error rather than the link card. DECISIONS
  „Job 91“.
- **diagnose.sh over 2026-11-03 07:00-12:00 CET:** two calls, both skill events (SkillDisabled
  08:20:56, SkillAccountLinked 08:21:17, 200); linking authorize → 403 `bad_jwt` (expired app
  sign-in) → authorize → consent approve → `authorization_code` 200 at 08:21:15; 1 link, 1 live
  session, 1 live refresh token. No spoken request. Full output:
  `docs/screenshots/91/diagnose-2026-11-03-0700-1200.txt`.
- **smoke.sh on the box (your run, 21:42, head 98ba10a):** `PASS unlinked` (LinkAccount card,
  438 ms at Amazon); diagnose.sh showed `alexa: LaunchRequest - de-DE linked=false -> link`.
  Linked half skipped: no `ALEXA_SMOKE_TOKEN` until the certification test account exists.
- **Vercel DPA (ADDENDUM 1):** committed as `docs/legal/dpas/vercel-dpa-2026-03-17.pdf`, a
  Chromium print of the public page (same version: last updated 2026-03-17, effective
  2026-03-31), because your box copy never reached hz. Provenance and checksums are in
  `docs/legal/dpas/README.md`. If you want Ops' exact download instead, replace the file and its
  checksum.
## Job 92: German Siri routing (2026-11-03)

- **PRs.** #221 (CI profile renewal lane, `com.apple.developer.siri` entitlement; landed first,
  addendum 1) and #222 (phrases, spoken names, launch registration, SiriKit Lists fallback).
  #222 merges on your review + green CI. Changelog `none` (`native-siri` held).
- **German spoken names (three, Apple's limit):** „Humm Liste“, „Hummliste“, „Ham Liste“, each
  with the pronunciation hint „humm liste“. „Hummelliste“ is dropped (no transcript showed it);
  „Home-Liste“ is not used (another app's name). Revisit when Peter's transcripts arrive
  (NEEDS_PETER „Job 92“ 1).
- **Part 2 is in #222, not split.** The capability exists and the profiles are renewed, so no
  build-setting gate: the entitlement is on main with #221.
- **`INPreferredForAppShortcuts`** from the brief is not an Apple key (the
  INAlternativeAppNames documentation lists only `INAlternativeAppName` and
  `INAlternativeAppNamePronunciationHint`); not added.
- **Siri permission prompt.** SiriKit routes only after the user allowed Siri for the app. The app
  asks once, right after it sets up the Siri credential (signed in, in a household). Say if you
  want it later, e.g. behind a button on Zugänge.
- **Profiles renewed** (Certificates runs 41733105879 `profiles`, 41733197123 `renew_profile`):
  `match AppStore com.hummlist.app` went INVALID to ACTIVE, the widget's stayed ACTIVE (renewed
  too), no certificate created; the match repo still holds only `GN85KDC962`.
- **Development and ad hoc profiles.** The portal has none for either App ID; the match repo has
  only the distribution certificate and App Store profiles. Development profiles are Xcode's (automatic signing) and renew themselves;
  match would have to create a development certificate, which the lane refuses.


## Job 87: PW-P4 „Haushalt“ as the real Premium page (2026-11-03)

**Needs Legal Review sign-off before merge.** Branch `job/87-paywall-pw-p4`, PR #217. CI and the
lead review are not enough on their own: the plan copy below is paywall copy. The beta strings are
Legal's final texts, approved by Peter on 2026-11-03 at 20:32 (handoff
`2026-11-03-pm-revenuecat-final.md`, section 4), used exactly as written.

Nothing about buying shows while the flags stay off (N-53). Beta builds keep `premium_offer` and
`REVENUECAT_PURCHASES` off, so no price, plan, Buy or Restore button renders, not even greyed out.
The widget tests „N-53: …“ in `app/test/purchases/premium_screen_test.dart` and
`e2e/tests/purchases.spec.ts` check this. Before sales start the page also hides
„… ist bald verfügbar.“, „Snacklist Premium kaufst du in der iPhone- oder Android-App …“ (on the
web too, for every household) and „… freigeschaltet. Danke!“. Two things are visible today:
- The hero without its slogan, for every household on the web and in the store builds: the member
  hexes, „Snacklist Premium gilt für euren ganzen Haushalt …“, the AI line, and the Siri line in
  the iPhone app only. The page is reachable only by its link, or from Mehr for households that
  have Premium.
- For households with a free unlock (promotional grant): the beta or tester title, the subtitle and
  the privacy link.

Since Legal Review's changes of 2026-11-04 (N-67 to N-71, below), the slogan „Einer kauft. Alle
haben es.“ and the refund link „Doppelt gekauft? …“ show only once sales are on.

### Every user-visible paywall string, verbatim

`{household}` is the household's name, `{date}` a date, `{code}` the store's error code,
`{period}` is `premiumPerYear` or `premiumOneTime`. The tile shows the store's price, then
„{period}, inkl. MwSt.“ under it (for example „9,99 €“ / „pro Jahr, inkl. MwSt.“, as in handoff
5(c)). Prices are never in the copy. The store formats them; the DE storefront gives „9,99 €“ and
„29,99 €“. No per-month figure. „inkl. MwSt.“ / "incl. VAT" shows only for a euro price, the English
UI included.

| Key | DE | EN |
| --- | --- | --- |
| `premiumTitle` | Snacklist Premium | Snacklist Premium |
| `premiumHeroTitle` (only while sales are on, N-68) | Einer kauft. Alle haben es. | One buys. Everyone has it. |
| `premiumHeroBody` | Snacklist Premium gilt für euren ganzen Haushalt, auch für alle, die später dazukommen. | Snacklist Premium covers your whole household, including everyone who joins later. |
| `premiumBenefitSiri` (iPhone app with `NATIVE_SIRI_LIVE` only, hidden today, N-71) | Per Siri auf die Liste, ohne die App zu öffnen | Add to the list with Siri, without opening the app |
| `premiumBenefitAi` (final, Legal N-67) | KI-Assistenten, die MCP unterstützen, mit eurer Liste verbinden | Connect AI assistants that support MCP to your list |
| `premiumBenefitApi` | Eigene Automationen mit der Snacklist API | Your own automations with the Snacklist API |
| `premiumStatusBeta` (final, Legal) | In der Beta kostenlos freigeschaltet, bis Snacklist Premium startet | Free in the beta, until Snacklist Premium launches |
| `premiumStatusFree` (final, Legal) | Kostenlos freigeschaltet (Test und App-Prüfung) | Unlocked free of charge (testing and app review) |
| `premiumBetaBody` (final, Legal) | Du zahlst nichts, und nichts verlängert sich automatisch. Bevor die kostenlose Freischaltung endet, sagen wir dir mindestens 4 Wochen vorher Bescheid. | You pay nothing, and nothing renews automatically. We'll let you know at least 4 weeks before the free unlock ends. |
| `premiumBetaPrivacyLink` (final, Legal) | Mehr dazu in der Datenschutzerklärung | More in the privacy policy |
| `premiumYearlyTitle` | Jährlich | Yearly |
| `premiumPerYear` | pro Jahr | per year |
| `premiumLifetimeTitle` | Lifetime | Lifetime |
| `premiumOneTime` | einmalig | one-time |
| `premiumWithVat` | {period}, inkl. MwSt. | {period}, incl. VAT |
| `premiumHousehold` | Premium gehört dann zum Haushalt „{household}“ und bleibt dort, auch wenn du den Haushalt später verlässt. | Premium then belongs to the household “{household}” and stays there, even if you leave it later. |
| `premiumBuyYearly` | Jährlich abschließen | Subscribe yearly |
| `premiumBuyLifetime` | Lifetime kaufen | Buy Lifetime |
| `premiumYearlyTerms` | Snacklist Premium jährlich, Laufzeit 1 Jahr. Das Abo verlängert sich automatisch um ein Jahr, wenn du es nicht mindestens 24 Stunden vor Ende der Laufzeit kündigst. Bezahlt wird über dein Apple- bzw. Google-Konto, bei der Bestätigung des Kaufs und bei jeder Verlängerung. Verwalten und kündigen kannst du das Abo in den Abo-Einstellungen des App Store bzw. von Google Play. | Snacklist Premium yearly, 1 year. The plan renews automatically for another year unless you cancel it at least 24 hours before the end of the period. Your Apple or Google account is charged when you confirm the purchase and at every renewal. You can manage and cancel the plan in the App Store's or Google Play's subscription settings. |
| `premiumLifetimeValue` | Einmal zahlen, für immer: so viel wie drei Jahre. | Pay once, for good: as much as three years. |
| `lifetimeRestore` | Kauf wiederherstellen | Restore purchase |
| `premiumTermsLink` | Nutzungsbedingungen (EULA) | Terms of Use (EULA) |
| `premiumPrivacyLink` | Datenschutzerklärung | Privacy policy |
| `lifetimeRefundLink` (once sales are on, or after buying twice, N-69) | Doppelt gekauft? So bekommst du dein Geld zurück | Bought it twice? How to get your money back |
| `premiumStatusLifetime` | Snacklist Premium Lifetime | Snacklist Premium Lifetime |
| `premiumStatusRenews` | Snacklist Premium aktiv (jährlich, verlängert sich am {date}) | Snacklist Premium active (yearly, renews on {date}) |
| `premiumStatusEnds` | Snacklist Premium aktiv (jährlich, läuft am {date} aus) | Snacklist Premium active (yearly, ends on {date}) |
| `premiumChecking` | Wir prüfen, ob euer Haushalt Snacklist Premium schon hat … | Checking whether your household already has Snacklist Premium … |
| `premiumUnavailable` | Snacklist Premium ist gerade nicht verfügbar. | Snacklist Premium is not available right now. |
| `premiumWeb` | Snacklist Premium kaufst du in der iPhone- oder Android-App. Danach ist es auch hier für deinen ganzen Haushalt freigeschaltet. | You can buy Snacklist Premium in the iPhone or Android app. It is then unlocked here too, for your whole household. |
| `lifetimeUnlocking` | Wird freigeschaltet … | Unlocking … |
| `lifetimePending` | Wartet auf Bestätigung | Waiting for approval |
| `lifetimePendingBody` | Snacklist Lifetime wird freigeschaltet, sobald der Kauf bestätigt ist. Das kann etwas dauern. | Snacklist Lifetime is unlocked as soon as the purchase is approved. This can take a while. |
| `lifetimeUnlockDelayed` | Dein Kauf ist angekommen, die Freischaltung dauert nur länger als sonst. Sie erscheint hier von selbst; bitte nicht noch einmal kaufen. | Your purchase went through; unlocking just takes longer than usual. It appears here by itself, so please don't buy again. |
| `lifetimeCanceled` | Kauf abgebrochen. | Purchase canceled. |
| `lifetimeStoreFailed` | Der Kauf hat nicht geklappt ({code}). | The purchase didn't go through ({code}). |
| `lifetimeStoreOffline` | Der Store ist gerade nicht erreichbar. Prüfe die Verbindung. | The store can't be reached right now. Check your connection. |
| `lifetimeUsedElsewhere` | Dieser Kauf gehört zu einem anderen, früheren Haushalt und bleibt dort. Hier schaltet er nichts frei. | This purchase belongs to another, earlier household and stays there. It unlocks nothing here. |
| `premiumUsedElsewhereYearly` | Dein Apple- bzw. Google-Konto zahlt schon ein Jahresabo für einen anderen Haushalt. Jemand anderes aus diesem Haushalt kann Snacklist Premium abschließen. | Your Apple or Google account already pays a yearly plan for another household. Someone else in this household can subscribe to Snacklist Premium. |
| `lifetimeNothingRestored` | Kein früherer Kauf gefunden. | No earlier purchase found. |
| `lifetimeBoughtTwice` | Euer Haushalt hat Snacklist Lifetime mehr als einmal gekauft. Einen der Käufe kannst du dir erstatten lassen. | Your household bought Snacklist Lifetime more than once. One of the purchases can be refunded. |
| `premiumTwoYearly` | Euer Haushalt hat zwei Jahresabos. Kündigen kann jedes nur, wer es abgeschlossen hat. | Your household has two yearly plans. Each can only be cancelled by whoever took it out. |
| `premiumBillingIssue` | Apple bzw. Google konnten dein Jahresabo nicht abbuchen. Premium läuft noch bis {date}. Prüfe deine Zahlungsmethode im Store. | Apple or Google couldn't charge your yearly plan. Premium keeps running until {date}. Check your payment method in the store. |
| `premiumLifetimeWhileYearly` | Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Kündigen kann nur, wer das Abo abgeschlossen hat, unter [Abos verwalten]. Snacklist kann das Abo nicht kündigen. | Your household already has a yearly plan. It keeps running and being billed after the one-time purchase until it is cancelled; the rest of the plan year isn't refunded automatically. Only the person who took out the plan can cancel it, in [Manage subscriptions]. Snacklist can't cancel it. |
| `premiumLifetimeWhileYearlySubscriber` | Euer Haushalt hat schon ein Jahresabo. Es läuft nach dem Einmalkauf weiter und wird weiter abgerechnet, bis es gekündigt wird; das restliche Abojahr wird nicht automatisch erstattet. Du kannst es unter [Abo verwalten] kündigen. Snacklist kann das Abo nicht kündigen. | Your household already has a yearly plan. It keeps running and being billed after the one-time purchase until it is cancelled; the rest of the plan year isn't refunded automatically. You can cancel it in [Manage subscription]. Snacklist can't cancel it. |
| `premiumBuyAnyway` | Trotzdem kaufen | Buy anyway |
| `cancel` | Abbrechen | Cancel |
| `premiumManage` | Abo verwalten oder kündigen | Manage or cancel subscription |
| `premiumManageWeb` | Dein Jahresabo verwaltest du im App Store oder bei Google Play. | You manage your yearly plan in the App Store or on Google Play. |
| `premiumManageApple` | App Store | App Store |
| `premiumManageGoogle` | Google Play | Google Play |

`premiumStatusGranted`, `premiumStatusGrantedUntil` („Snacklist Premium geschenkt (bis …)“),
`premiumUnlockedBody`, `premiumComingSoon` and `premiumVat` are deleted. The refund help page behind
`lifetimeRefundLink` (`refundHelp*`) and the dialogs before leaving or deleting with a running plan
(`premiumBillingContinues*`) are unchanged and not part of this page.

### Which free-unlock line shows when (Legal Review N-70)

The grant decides, not the switch:
- A promotional grant without end, or to 2100-01-01 or later, is a tester grant.
  `scripts/iap/promotional.ts grant` gives exactly that (`testerGrantEnd`). It shows
  „Kostenlos freigeschaltet (Test und App-Prüfung)“, before and after the launch.
- Any grant that ends earlier is a beta grant. It shows „In der Beta kostenlos freigeschaltet, bis
  Snacklist Premium startet“, also after `premium_offer` goes on.

Under both come the subtitle and the link to `/datenschutz#premium-beta` (EN
`/en/privacy#premium-beta`).

**Operational consequence, please confirm:** beta households must get a grant with a real end date
(RevenueCat dashboard, Grant with an end), not `promotional.ts grant`. Testers granted with
`promotional.ts` so far see the tester line today.

### Legal Review changes N-67 to N-71 (2026-11-04), done

- N-67: the AI line names no brand: „KI-Assistenten, die MCP unterstützen, mit eurer Liste
  verbinden“ / "Connect AI assistants that support MCP to your list". No assistant brand is
  anywhere on the page (widget test).
- N-68: „Einer kauft. Alle haben es.“ shows only when `premium_offer` is on and the build sells.
  It never shows on the web or in beta builds. The body and the benefits stay.
- N-69: the refund link shows only once `premium_offer` is on, or for a household that bought
  Lifetime twice.
- N-70: tester or beta line by the grant (above).
- N-71 (Addendum 3, 2026-11-04): the Siri line shows only when the build define `NATIVE_SIRI_LIVE`
  is on and this is the iPhone app. `Environment.nativeSiriLive` and the Fastfile's
  `HOLD_DEFINES` are identical to #224, so the two merge cleanly. Fastlane passes the define once
  `releases/flags.json` releases the `native-siri` hold. Today the hold is unreleased, so the line
  is hidden everywhere. Release the hold only after native Siri passes the TestFlight voice test
  (5a/5b).
- N-72 (optional) is not done. The screenshots in `docs/screenshots/87/` are developer docs with
  test data and fake store prices.

### Open questions for Legal Review

1. **Q1 preselection.** The yearly tile is picked when the page opens: honey fill, the button
   reads „Jährlich abschließen“, the yearly terms stand under it. Nothing says "recommended". Is a
   visible preselection of the subscription fine under UCPD / DSA Art. 25 when both prices are
   fully shown, or should nothing be picked until the user taps a tile? The second is a small
   change (the default of `PremiumPage.picked` in `app/lib/purchases/premium_page_cubit.dart`
   plus a disabled button).
2. **Q3 „Lifetime“ and „für immer“.** The Lifetime tile is titled „Lifetime“ and its line under
   the button reads „Einmal zahlen, für immer: so viel wie drei Jahre.“ (job 49 placeholder). Does
   „für immer“ need a definition (for example „solange es Snacklist gibt“), is „so viel wie drei
   Jahre“ an acceptable price comparison, and is „Lifetime“ fine as a German product name?
3. **Q4 withdrawal right.** The page adds no text about the right of withdrawal for digital
   content or the consent to start it; the App Store / Play purchase sheet handles the purchase.
   Does the page need a sentence?
4. **Q6 household binding wording.** Above the button: „Premium gehört dann zum Haushalt
   „{household}“ und bleibt dort, auch wenn du den Haushalt später verlässt.“ (EN „Premium then
   belongs to the household “{household}” and stays there, even if you leave it later.“). It is
   job 43's rule. Is this enough as pre-purchase information (UCPD Art. 7), and should it also
   say that a yearly plan keeps billing the buyer after they leave (today said only in the leave
   and delete dialogs, `premiumBillingContinues`)?
5. **Renewal price in the yearly terms.** `premiumYearlyTerms` says the plan renews automatically,
   but not at which price. The renewal price is the tile right above it („9,99 €“, „pro Jahr,
   inkl. MwSt.“). Is that enough, or should the terms take a `{price}` („… verlängert sich
   automatisch um ein Jahr zu {price} …“)?
6. **Restore only next to an offer.** „Kauf wiederherstellen“ shows only while a plan is offered,
   as on job 49's page. A household that already has Premium has nothing to restore here. Fine?
7. **Benefit wording.** „ChatGPT oder Claude schreiben mit (MCP)“ names two third-party products;
   „Eigene Automationen mit der Snacklist API“ shows only while the PostHog flag `public-api` is on.
   No retailer names, logos or colours anywhere on the page (N-23). No Alexa (N-27).

Resolved: the N-54 placeholder. Peter approved Legal's final beta texts (2026-11-03, 20:32). They are
in the app verbatim, and their ARB descriptions say „FINAL (Legal Review …)“.

### For the lead

- Job 86 (#213) recaptures the IAP review screenshot from this branch. `test_driver/paywall_review.dart`
  keeps working unchanged (same providers, `premium_offer` on in its fake). The page now has one
  Buy button for the picked plan: the default capture shows both tiles with DE prices and
  „Jährlich abschließen“; a Lifetime shot taps `premium-card-lifetime` first (button key becomes
  `premium-buy-lifetime`).
- PR #213 (job 86) is stacked on this branch and needs a rebase onto the new head of #217. The
  capture still works: its fake has `premium_offer` on and sells, so the slogan shows. The Siri line
  shows only if the capture build passes `--dart-define=NATIVE_SIRI_LIVE=true`.
- Changelog: one `new` item with `hold: premium-launch`, so it stays out of the public changelog
  until Premium is on sale.

## Job 86: the iOS paywall screenshots for the in-app purchase review (2026-11-03)

The screenshots show PW-P4, the Premium page of job 87, as merged on main (84e8da41, with Legal's
N-67..N-71). On the box (and on Hetzner) at the same path:

- `/workspace/hummlist/research/iap-check/paywall-ios-de.png`: yearly picked, "Jährlich
  abschließen". For `com.hummlist.app.yearly`.
- `/workspace/hummlist/research/iap-check/paywall-ios-de-lifetime.png`: Lifetime picked,
  "Lifetime kaufen". For `com.hummlist.app.lifetime`.

Both are 1290x2796, German, light, from the iOS simulator (iPhone 16 Plus), run 41792307363. Each
shows both products, "9,99 € pro Jahr, inkl. MwSt." and "29,99 € einmalig, inkl. MwSt.". PW-P4 has one Buy
button, for the picked plan, so each product gets its own screenshot with its own button. Copies
are in `docs/screenshots/86/` and `~/groceries-ops/jobs/86-iap-review-screenshot/`.

1. Ops: upload each as the review screenshot of its product in App Store Connect (an Apple
   account step; nothing was uploaded). The yearly file has no Lifetime button: the Lifetime slot
   needs `paywall-ios-de-lifetime.png`.
2. Know before uploading: the prices on them are set by the capture, not read from StoreKit. On
   GitHub's macOS runner StoreKit answers from the sandbox's US storefront ($9.99, $29.99, both
   products found; `paywall-ios-de.storekit.txt`), and StoreKit's local test store does not open
   there (DECISIONS, job 86). The amounts and format match the German storefront and App Store
   Connect's base prices. A capture with StoreKit's own German answer needs a Mac with Xcode and
   a German sandbox account: `scripts/ios-paywall-shot.sh` runs there unchanged.
3. #213 is rebased onto main (job 87 is in). Merge it after lead review: `scripts/merge-pr.sh
   --wait 213`. It holds the capture entrypoint, the script, `paywall-shot.yml` (by hand) and the
   Lifetime price fixed in `LifetimeStoreKitTests`.

## Job 104: gap fixes (2026-11-05)

PR "fix: rename dedupe, offline number words, last-member Premium warning". PR only: the lead
reviews and merges. Two new migrations deploy with the next `supabase-deploy.yml` run.

- **Copy.** Peter's plain-language texts (Addendum 5, Q73) replace `accountDeletePremiumLastMember`
  (new) and `accountDeletePremiumAck` (existing, also the archive build's tick box) in DE and EN.
  The card shows in every build, as Legal Review cleared (Addendum 4); the Legal re-check of the
  new copy is pending. The reused refund link „Erstattung bei Apple oder Google anfragen“ also
  shows for a gifted or tester unlock, where nobody paid; a gift-specific wording would be a new
  string.
- **Typed number words online (Addendum 3: fine, kept).** „Gurken zwei“, „two apples“ and
  „carrots two“ typed in the add sheet or sent through MCP now get a quantity online too, not
  only offline (DECISIONS 104.5). Before, the typed rule read only German words up front.
- **Follow-up, voice code (out of scope here).** The Siri, Alexa and dictation splitters
  (`voice/parse.ts`, `parse_en.ts`) don't read the new number-word names. Spoken „Drei Glocken
  Spaghetti“ gives 3 × Glocken Spaghetti, and „Seven Up“ gives 7 × Up. Reading
  `supabase/tests/number_words.tsv`'s `name` rows there would be a small job.
- **Rename merges only the same name (Addendum 3, done).** A synonym or a name whose open item
  has a brand („Butter“ next to „Butter“ Kerrygold) stays a second row and gets add's duplicate
  hint.
## Job 99: a delete wins over a replayed add (hc-sync)

Status: proposal, not applied. Changes an RPC, so it is the Lead's call (HC1 rule).

An add whose answer was lost is retried with the same id. If a partner deleted the item in
between, `put_item` inserts it again and the delete is undone on every phone. The sync fuzz
measures it with `FUZZ_STRICT=1`: 6 of seeds 1..1000 (seed 44 shrinks to three steps: Peter
adds Butter and loses the network before the answer, Lea deletes Butter, Peter's phone comes
back and the Butter is back). All phones still agree, so the scored oracle does not count it.
No client-side fix is safe: after reconnecting, the phone cannot tell "my add never landed"
from "it landed and was deleted". `item_events` can.

Proposal: [`docs/hillclimb/hc-sync-proposals/put_item_delete_wins.sql`](hillclimb/hc-sync-proposals/put_item_delete_wins.sql),
a `put_item` overload with a required `p_restored`. A plain add of a deleted id answers no
row, which the app already handles as "gone". The undo of a delete (`p_restored = true`)
inserts as before. Old apps keep the 11-argument function. The harness models it
(`FUZZ_PROPOSAL=delete-wins`, reading the op's `restored` flag): with `FUZZ_STRICT=1`, seeds
1..1000 go from 6 failures to 0, and convergence stays at 0.

To ship it:
1. Copy the file to `supabase/migrations/` with a new timestamp and add a pgTAP case: a plain
   add of a deleted id returns no row; a restored one returns the row. The SQL has not run
   against Postgres yet, because there is no Docker on the box.
2. In the same PR, send `'p_restored': op.restored` from `SupabaseListRepository._add`.
3. Don't let a store build carry the app change before the migration is deployed. The
   12-argument call fails with PGRST202 on an older database.

## Job 102: hc-ui-app (2026-11-05)

- **Apply attempt 4 or not.** The branch ships no app change: attempt 4 scored 7.0 with the
  judge inputs unchanged (6.5 + band, not kept). `tool/hillclimb/hc-ui-app/attempts/attempt-4.patch`
  holds it (regenerate goldens with `flutter test --update-goldens test/design/`). If applied:
  it makes „Ohne Laden“ a raised pill, reversing Job 78 item 16 (DECISIONS Job 102 item 7), it
  needs its own `dragHandle` e2e fix (in the patch), and its trash buttons need a 48 px minimum
  size on web.

## Job 125: account and auth flakes (#57 #58 #59 #60), 2026-11-05

- **Close #57, #58 and #59 as host-pause only, or keep them open.** The PR changes no code.
  With retries off, on main 1ba6dc51 the four tests passed 220 of 220 runs under one-CPU
  starvation and under runner, browser and stack pauses of 3, 8 and 9 s. On main 4a103f67 the
  same 8 s conditions went 59 of 60, and the one failure was #60's test (next bullet); #57, #58
  and #59 passed every run there too (DECISIONS Job 125). Failures start at 12 s
  pauses, and each one is a single 10 s `expect`, or from 25 s `typeInto`'s 20 s predicate (the
  issues' own signature), whose budget the pause used up. The page shows the step before, never
  an error. The issues' failures fell in named runner pauses of 189 to 2385 s and passed on the
  stall-only retry, which is the policy of DECISIONS 18.23. The brief leaves closing them to you.
- **#60 is not host-pause only: decide it knowing its second failure mode.** Its issue's own
  failure was a 316 s runner pause, like the others. But on main 4a103f67, auth.spec.ts:8 failed
  once (1 of 5) under an 8 s `docker pause` of the stack, which is under the failing wait's 10 s
  budget. `create_household` answered 500 (`57014`): the frozen database held the statement past
  the `authenticated` role's 8 s statement timeout. The budget that ran out is that server
  setting, which production uses too, not the test's wait. A real database stall of 8 s or more
  fails the request in production as well, and the app shows its error („Etwas ist
  schiefgelaufen: other“), which is correct for a server error, though the text says nothing
  useful. On the test side the condition, a stack frozen while the runner keeps running, comes
  only from the harness. Such a stall has no stall-detector line, so 18.23's retry would never
  cover it. Inferred, not measured: any test whose step calls PostgREST shares it, and #60's
  test met it first. A clearer message or a retry for a statement timeout would be new copy or
  app behaviour, outside this job (DECISIONS Job 125 item 5). The reviewer's 20 runs at the same
  condition did not hit it again, which fits a rare event.

## Job 82: the snacklist.app waitlist (Spec #10), 2026-11-02

Everything is built. Since the requeue of 2026-11-04 (Addenda 5 to 10) the merge of PR #210 is the
switch: it publishes the waitlist stage on snacklist.app. The secrets decide whether sign-ups work
(NEEDS_PETER "Job 82"). The design and every route are in [`WAITLIST.md`](WAITLIST.md).

### Not merged: Peter OKs the copy, Legal reviews

Per the lead (2026-11-04) PR #210 stays open: no merge before Peter approves the copy in his own
words and Legal has reviewed. There are no placeholder markers any more (Addendum 10: none may be
in the build, every build fails on one). Every text is the draft it would ship with: Legal's
versioned texts byte for byte, Launch's drafts for the rest, listed in the PR description. Merging
publishes the waitlist at once (Addendum 8: the stage file replaced the env switch).

Region proof (Addendum 4): the preview is behind Vercel login, so `curl -si -X POST
<preview>/api/waitlist` answers 401 from the edge (`x-vercel-id: arn1::…`) and never reaches the
function. `docs/legal/waitlist-region-proof.txt` is not written yet; it needs a logged-in or
bypass request once the Vercel env vars are set (NEEDS_PETER "Job 82", step 3).

### Data flow for Legal Review

| Step | Where | What is stored or seen | How long |
| --- | --- | --- | --- |
| Form | snacklist.app page, `fetch` to the same origin | nothing (no cookie, no storage, no analytics, no third-party resource) | |
| Vercel function `/api/waitlist*` | Vercel, `regions: ["fra1"]` in `site/vercel.json` | sees the IP and the body; logs only a fixed outcome code; sends on an HMAC of `<UTC date>\|<IP>` (keyed with the proxy secret), never the IP | Vercel's own request logs (path, no body) |
| Edge function `waitlist` | Supabase, `x-region: eu-central-1` | sees the body; logs only outcome codes | |
| `public.waitlist` | Supabase Postgres, Frankfurt | email, HMAC of the email, platform, locale, the form text version answered (`waitlist-*-v2`), the consent text version shown at the confirm press (`waitlist-confirm-*-v1`), launch news (set only by that press), sign-up, confirm, invite, launch-mail and last-mail times, the SHA-256 of the confirm token and its expiry; nothing about who or what submitted | unconfirmed 7 days; confirmed 3 months after the invite, with launch news 30 days after the launch mail; everything by 2027-12-31 (Berlin); unsubscribe deletes at once |
| `public.waitlist_consent_proof` | same | HMAC of the email, both text versions, locale, launch news, the four times, end reason; never the address, never an IP | 3 years after the later of last mail and end |
| `public.waitlist_rate` | same | SHA-256 of the daily client key, the hour, a count | deleted after 2 hours |
| Resend | Resend (USA), domain snacklist.app in eu-west-1 | the mail (to, subject, body); no tags, no metadata; single sends with an idempotency key | Resend's 30 days |

Retention hook: `public.purge_waitlist(now)`, pg_cron `purge-waitlist` daily at 03:23 UTC, every
period tested to the minute in `supabase/tests/waitlist.test.sql`.

### Addendum 10 (Legal N-73 to N-78), how it is built

- Consent is the person's click on the confirmation page: it shows `waitlist-confirm-<l>-v1`
  (C-1/C-2), the launch-news box unticked and the button; the press stores that version and the
  box (`confirm_text_version`, `launch_news`, migration `*_waitlist_confirm_consent.sql`).
- The form shows `waitlist-<l>-v2` (F-1/F-2) and has no launch-news box; a `launch_news` sent with a
  sign-up is ignored and stored false.
- Every sign-up answers the same `202 {"status":"ok"}`: new, known, dropped or rate-limited.
- Nothing logs who submitted (no address, IP, user agent, body, token owner); tests capture the
  logs.
- Confirmation mail M-1/M-2 (`doi-mail-*-v2`) word for word, without the launch sentence.
- `llms.txt` carries L-1 in the waitlist stage; `/api/waitlist` stays undocumented.
- Privacy §2a gets P-1/P-2 after the confirmation paragraph.
- No `⟦…⟧` placeholder can ship: every build fails on one, so the `site` CI gate is the check.

### Ambiguous, decided, please confirm

1. **Rate limit storage.** Addendum 3 says "ephemeral keys that are never persisted", the handoff
   "a short-lived hashed counter (≤ 24 h)". In-memory counters don't hold across Vercel
   instances, so the counter lives in Postgres: SHA-256 of a daily-rotating HMAC of the IP,
   per hour, deleted after 2 hours. 10 sign-ups per key per hour (IPv6 clients keyed by their /64), 300 per hour in total.
2. **No `unsubscribed_at`.** Spec AC8 lists it; the Legal handoff (binding) says unsubscribe
   deletes the row. The column is not there.
3. **The 2027-12-31 cap applies to every row**, not only launch-news ones, so a confirmed address
   that is never invited doesn't stay forever.
4. **Sender name:** "Peter · Snacklist" in German and English mails since #357 (2026-11-10);
   before, per language "Peter von Hummlist" and "Peter from Hummlist" (Legal handoff 2.5).
5. **Welcome mail** goes out automatically right after confirming (consent text names it). It is
   not an invite. Its text is a neutral draft (Launch's draft 5b was not in the brief), and with
   the markers gone it would go out as written once `WAITLIST_MAIL_ALLOW=*`; the same holds for
   the invite mail. Launch should approve both before.
6. **Root `/`.** Live today it already redirects by language to `/de` or `/en` (307), the landing
   pages, not the browser app. Kept as it is (PM override 3).
7. **Backups.** The backup drill dumps every public table, so encrypted backups hold waitlist
   addresses for the backup retention. Legal should say whether its periods cover backups.
8. **Deletion request by mail** (`end_reason = deletion_request`) has no function yet; Peter
   handles it with the unsubscribe link of the address's mail, or by SQL (NEEDS_PETER).
9. **app.snacklist.app had no noindex** (AC15 assumed it). The app's `vercel.json` now sends
   `X-Robots-Tag: noindex`; it reaches app.snacklist.app with the next store release, or sooner if
   you move the `release` branch.
10. **Launch mail** is not built (later spec); `launch_mail_sent_at` exists for the purge.
11. **A policy sentence names the browser app's URL as text.** In `/datenschutz` and
    `/en/privacy`, section 8 (account deletion) still ends in the plain text
    `https://app.snacklist.app/konto-loeschen.html`; §1 and the §3 heading name "app.snacklist.app".
    The link is gone (Addendum 1: link removal only, no legal wording changed), but the sentence
    points readers to the browser app. Legal should say whether it stays.
12. **Rate counters are a global lever.** Besides 10 per client key, all sign-ups share 300 per
    hour, so a botnet could close the form for an hour. Fine for the beta; raise or drop the global
    cap if it ever trips (`LIMITS` in `supabase/functions/waitlist/handler.ts`).
13. **The beta stage needs its own texts before it is switched on.** Legal's form text v2 names
    the button „Auf die Warteliste“ / "Join the waitlist", but the beta stage's button is „Zur
    Beta anmelden“ / "Join the beta"; the form intro and the thanks say "once the beta starts".
    Switching to `beta` needs a v3 form text from Legal and Launch's beta copy.
14. **L-1 sits in llms.txt's head, as a bold lead-in.** Legal wrote it as an `##` section, but
    llms.txt allows only link lists in `##` sections (job 93's check fails otherwise). The text is
    word for word; only „## Beta waitlist: signing up your human“ became
    „**Beta waitlist: signing up your human.**“.
15. **§2a still says the function runs in Frankfurt.** Legal's §2a „Dienstleister“ paragraph says
    „die Server-Funktion läuft in Frankfurt am Main“ while Legal's own rule keeps that claim out
    until the fra1 proof exists (the §2 line uses the variant without it). Legal should give the
    §2a wording until then, or the region proof lands first.
16. **Apple's German badge.** Only Apple's English "Download on the App Store" badge was reachable
    from the build box (tools.applemarketingtools.com does not resolve here); the launch stage
    uses it on both pages, with that alt text. Swap in the German badge before launch.
17. **Moved on /support:** the beta questions now open „Häufige Fragen“ / "Common questions"
    (job 93's FAQ JSON-LD covers only that section), with Legal's answer to „Was passiert mit
    meiner E-Mail-Adresse?“ first; the 7-day invite validity and the "first on 15 November" date
    are out (Addenda 5, 7).

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


## Job 114: a re-add from „Zuletzt verwendet“ while another phone opened the same item

Status: question, nothing changed. Found by the sync fuzz once it checked for two open rows with
one name (`FUZZ_STRICT=1`, seeds 1 to 1000: 27 seeds, for example 122 and 500; the other 5 strict failures are job 99's replayed adds).

Phone A, offline, taps Milch under „Zuletzt verwendet“ (an untick), while phone B adds Milch. After
the sync, two open Milch rows exist. In the app, one phone alone cannot do it, because the section
hides anything that is on the list. The public API can, with no race at all:
`POST /v1/items/{id}/untick` (`setItemStatus` in `supabase/functions/_shared/list.ts`) opens a
bought item while its twin is open (found in review 0). An offline add in the same race is folded into B's item
(`put_item`), but an untick is not: job 104's `items_rename_duplicate` checks only a changed name,
brand or details, and lets unticking through on purpose (pgTAP „unticking still passes“).

The question covers the whole untick class (the app's re-add, the API's untick): should an untick
onto an open copy fold into it, as an add does? If so, the server
would refuse it with 23505 and `ListCubit` would merge, as job 114 does for a refused rename. That
is roughly a day of work with tests. The fuzz already counts these cases (`FakeBackend.reopened`).

## Job 122: four flaky issues are host pauses only (#62, #64, #71, #72)

Status: left open for the lead to close. Evidence in DECISIONS (Job 122, items 3 and 4).

- **#62** edit-sheet "Abbrechen and an unchanged Fertig write nothing", **#64** list "edit
  changes name, quantity and category; delete can be undone", **#71** offline-start "a cold
  start without Supabase …", **#72** offline-start "signing out drops the cached list".
- On main with retries off, under SIGSTOP pauses of the runner and Chromium shorter than each
  test's budget, nothing failed. That is 25 of 25 on hz (4 s every 6 s), 30 of 30 on CI (2 s every
  3 s; the offline and sign-out tests) and 32 of 32 on CI (8 s every 6 s, all four tests).
  Traces of passing runs show no hidden wait.
- #62 failed with 262 s and 570 s host stalls. #64, #71 and #72 failed on 2026-10-25, before the
  stall detector, in the VM-pause days (DECISIONS 18.23).
- Closing them is the lead's call. If one fails again without a `[host-stall]` line, reopen it
  with the trace: `node e2e/trace-slow-steps.mjs <report>/data` lists its slow steps.
- #63 (edit-sheet "Fertig writes only what changed") was a real app bug and is fixed in this PR.
- **Your call: queued writes after a refused refresh.** If the server refuses the refresh token
  for good (revoked, account deleted), gotrue signs out and the device drops its list, queued
  offline changes included. This PR keeps that: without a session the writes cannot be sent,
  the next sign-in may be another user, and sign-out drops the list by design (#72). Keeping
  the queue for the same user's next sign-in would be a new feature.
- **Your call: a send that never answers stalls the offline queue.** `ListCubit` sends one op
  at a time and the app sets no HTTP timeout, so one hung request holds every later write until
  the list closes (an app restart clears it, and the ops are kept in the device cache). Not seen
  in any stressed run. A client timeout is not a safe fix: it stops the wait, not the request,
  and item writes are last-write-wins, so the late request overwrites ops sent after it (review
  1 proved a tick landing after the user's untick; the cubit test "a later op waits for a slow
  send, so the last change wins" fails with a timeout). Proposal: the server ignores a write
  older than the item's last applied op (a per-item op sequence or a client time guard in
  `put_item` and the item update path, one migration, old apps keep working). Then the app can
  time out and retry safely. Nothing of it is in this PR.
- **Your call: no hover hint on + and −.** The edit sheet's steppers lost their tooltips
  („Eins mehr“ / „Eins weniger“ on mouse hover). No string changed, and screen readers still
  get the names, but mouse users see no hint.
- **Follow-up: the same tooltip effect elsewhere.** Any Material `Tooltip` showing next to a
  focused text field on the web moves the DOM the same way. Candidates are the confirm and
  cancel buttons beside the store name field (`store_name_field.dart`) and the clear button
  beside the add field (`list_screen.dart`). The clear button was checked: text typed after it
  still lands in the field. The store name field was not checked. The widget test „hovering a
  stepper leaves the semantics tree as it is“ is the pattern to prove another case.

## Job 124: report the edge runtime's dropped answers upstream?

Status: open, the Lead's call (it posts to a public repository, so job 124 did not).

The local edge runtime sometimes throws away a function's finished answer and sends its own
empty 503 instead (`connection aborted` in its log). The cause is a race in edge-runtime itself
(DECISIONS, job 124, items 1 and 2). Job 124 cut it down with `policy = "per_worker"`, but a
retiring worker can still drop an answer (2 in 8000 under a pinned core). Upstream `main` has
the same code. A report to `supabase/edge-runtime` would need these parts: the mechanism
(item 2), `e2e/runtime-drop-probe.mjs` with the one-core pin, and the before and after table
(item 3). Nothing in this repo waits on it.

Two follow-ups outside job 124's scope:

- The e2e report action's "Edge runtime log" step prints only `tail -n 300`. For #265 the
  `connection aborted` line had scrolled out. Grepping the whole log for `connection
  aborted|already retired|soft limit` as well would keep the evidence. That is a workflow file,
  and #249 owns it now. Done by job 219 (#423): a failed e2e job keeps every container's log
  (the newest 50 MB of each), with timestamps, in its artifact (`docs/CI.md`, On-demand e2e).
- `timedFetch` in `e2e/tests/mcp-helpers.ts` retries every empty 502/503/504/546 once, POSTs
  included. Job 124 shows an empty 503 can come after the handler ran, so a retried MCP
  `tools/call` can write twice. Narrow the retry to bodiless calls once job 121's
  `mcp-helpers.ts` changes have landed.

## Job 121: mcp.spec.ts flakes #68, #69, #70 are host pauses (2026-11-05)

Status: your call. Close #68, #69 and #70, or keep them open as host-pause records.

All three timed out only inside VM holes (417 to 2754 s) and passed on the stall retry. With
retries off, on main's release web build, the three tests passed 90 of 90 stressed runs under
CPU load and runner or stack stalls up to 9 s. They fail only when one server round trip stalls
past 10 s, the `expect` budget. A 30 s budget passes those stalls, but it would only hide stalls
the stall retry is meant to see, so the budgets stay. #70's `AuthRetryableFetchError` is GoTrue's
504 "Processing this request timed out" at 10.0 s. It comes when the database stalls under a
running GoTrue, or when a host pause catches a request in flight. A whole-stack stall gives no
504. CI ran `mcp.spec.ts` 679 times from 2026-10-28 to 2026-11-05
without a flaky or failed test. Counts per arm are in DECISIONS "Job 121".

To rerun the edge, use the job's harness, where `--stack S/P` means stopped S s, then running
P s. It isn't committed; job 119's #261 tool counts its flags differently.
1. Run `scripts/verify.sh --only e2e -- tests/mcp.spec.ts` once. That starts the stack and
   builds the release web app.
2. Copy `~/groceries-ops/jobs/121-fix-mcp-spec-flakes/proof/e2e-stress-121.sh` to `scripts/`.
3. Run `flock /tmp/fg-e2e.lock scripts/e2e-stress-121.sh --stack 11/15 -- tests/mcp.spec.ts -g
   "another household" --workers=1 --retries=0 --repeat-each=5`. Then run it again with
   `--stack 9/12`. Between runs, wait until `docker ps` shows the db container healthy again.
   After several pauses it stays "unhealthy" for a while, and `supabase status` refuses until
   then.

Run on head a030ac03 (2026-11-06, under the lock): `--stack 11/15` gave 2 failed, 3 passed, both at `answerConsent`'s 10 s `toHaveURL`. `--stack 9/12` gave 5 passed. Logs: `proof/recipe-11-15.log`, `proof/recipe-9-12.log`.
## Job 126: classifier learning, RLS and due-again suggestions under load (2026-11-05)

PR "test(e2e): classifier learning, RLS and due-again suggestions hold under load". PR only: the
lead reviews and merges. No migration.

- **#61's `toBeNull` is open evidence.** Its first logged failure was an error from `add_items`, which this PR does not explain (DECISIONS 126.6). If it shows again, the assertion prints the error.
- **Issues closed by the PR.** #61, #73 and #77 each logged failures during host pauses, and none
  failed under load or under 3 to 8 s pauses (45 of 45 passed on main). Each test also had a race
  that fails it under one slow server answer (3 to 10 s, inside the 60 s budget), which is what
  the issues asked to look for, so the PR closes them (DECISIONS 126). Reopen one if it fails
  again without a stall line.
- **Follow-up, store guess (out of scope here).** The add sheet sends the store it guessed while
  the user typed. If the user moved the item to another store just before and that edit is still
  queued, the re-add carries the old store. `items_learn_insert` then counts it as a pick, which
  works against the correction in `item_store_memory`. The category had the same race and is
  fixed here by sending no category. For the store that is not enough: with no store, the insert
  trigger fills only `suggest_store` (memory), not `guess_store`'s brand and drugstore fallbacks
  (Balea → dm, Windeln → dm). The fix: in a migration, `items_before_write` fills
  `guess_store(household, name, brand, category)` for a missing store, and the app sends no store
  when the user did not pick one (`AddSheetState.store == null`). Then check that the Siri, Alexa
  and MCP adds (`add_item`, which already passes its parsed store) give the same stores.
- **Long specs under a busy runner (your call).** `classifier.spec.ts:5` takes 28.3 s of its 60 s
  on CI. On hz at loadavg 13 to 41 plus 12 CPU burners it timed out at its end 3 of 24 times on
  main and 5 of 24 with this PR (DECISIONS 126.4), which is within noise for the same cause. The
  budget stays (brief: no longer timeouts without a wrong budget). If such runs should count,
  `test.slow()` on the specs that use about half the budget on CI is the lever.
- **Two sibling specs, same test-wait shape (review 0, out of scope for #77).**
  `suggestions.spec.ts:13` and `:45` tick an item and type at once, expecting „Schon mal
  gekauft“. If the tick has not reached the server when the sheet asks for suggestions, there is
  no history row yet. The reviewer saw `:45` fail once under 8 s stack pauses (line 49, „6× Eier,
  Schon mal gekauft“ not found). The fix is the same poll as in `:68` before typing.
- **For job 120 (live sync).** After 8 s stack pauses, a row written through the API
  (`add_items`) sometimes never reached the open list over realtime: 1 of 12 on main and 1 of 12
  with this PR (`classifier.spec.ts:49` since the #237 rebase, „could not scroll … Hafermilch into view“; posted on BOARD for job 120 at 02:26 on 2026-11-06).

## Job 119: #74 and #75 are host pauses only (2026-11-05)

Status: open, for the lead to close or keep. Job 119 fixed #76 (STORE ORDERING: the reload outran
the drop's write) and could not make the other two stores.spec.ts tests fail without a host pause:

- #74 ("category and store layout changes sync live to the other member") and #75 ("categories:
  add, move an item there, rename, reorder, delete with reassignment") passed 24 of 24 runs each
  with retries off under `scripts/e2e-stress.sh`: runner, browser and stack pauses of 2 to 8 s,
  and the run pinned to one CPU (DECISIONS, job 119).
- Every failure recorded on the issues fell in a VM hole or mem-guard gap of 403 to 2613 s, far
  above both tests' budgets; #75's "while setting up page" is a browser context that such a hole
  timed out.

To decide: close both as host-pause only, or keep them open to collect a failure that has no
`[host-stall]` line. To rerun the evidence (stack paused 3 s of every 8 s), with the job's stack
and web build up: `flock /tmp/fg-e2e.lock scripts/e2e-stress.sh --target stack --on 3 --every 8
-- tests/stores.spec.ts -g 'sync live|categories:' --workers=1 --retries=0 --repeat-each=4`.

Also to decide (app, out of job 119's scope): a store or category reorder is written once, not
queued like item ops (`ListCubit._changeOrder`). A user who reloads the web app or closes the app
before the write answers loses the new order without a message, though it showed at once. Should
orders become queued ops (an `ItemOp`-like catalog op), or is a lost reorder acceptable?

## Job 120: live-sync.spec.ts flakes #65, #66, #67 are host pauses (2026-11-05)

Status: your call. Close #65, #66 and #67, or keep them open as host-pause records.

Each logged failure fell in a host pause. The stall detector measured 75 s and 505 s (#66) and
199 s (#67). #67's other failure is the verify loop's 1053 s mem-guard gap, which has no detector
line. #65's (2026-10-25) predates the detector, so its pause is inferred, with no direct record. It
needs about 50 s with no progress, while its setup took at most 0.59 s in every traced arm. CI never
failed it on main, and the box's VM was then being paused for minutes at a time. The BOARD's
mem-guard lines at 21:50 and 21:51 don't show it: mem-guard stopped job 15, not this run, for under a
minute.

The tests' budgets are 2 s (the `within` live windows), about 6.7 s (`reveal`'s scroll steps),
10 s (an `expect`), 20 s (`typeInto`) and 60 s (the test). With retries off, on the release web
build, they failed only when a stall outlasted the budget it landed in. Stalls of up to 9 s passed
the 10 s waits in all 184 of the builder's runs, and 12 s stalls failed them. The 2 s windows fail
whenever a stall longer than 2 s lands in one, whether of the runner, Chromium or the stack. Only
a runner stall gets the `[host-stall]` line and the retry. In review runs, Chromium alone paused
9 s failed 2 of 19, the stack alone paused 8 s failed 5 of 24 (all in a 2 s window), and 1 s
Chromium pauses passed 10 of 10. CI ran `live-sync.spec.ts` in 1,215 readable e2e logs from
2026-10-28 to 2026-11-05. It had no flaky test, and each of its five failures was caused by its own
branch. Counts per arm: DECISIONS "Job 120". The harness, the CI scan and rerun commands are in
`docs/done/120-fix-live-sync-flakes.md`.

Job 126's hand-off (a row from `add_items` that "never reached the open list" after 8 s stack
pauses) is a late row, not a lost one. In review 2's trace the stack paused 0.2 s after
`add_items` returned, and `reveal` gave up inside that pause. Every reconnect also resyncs the open
list. DECISIONS "Job 120" item 6 has the timings.

A possible follow-up, not this job: `within` (e2e `helpers.ts`) counts only the time the test
runner ran. It can't see a stall of Chromium or the stack alone, such as a starved renderer under
memory pressure while node keeps running, so such a stall uses up a 2 s live window with no
`[host-stall]` line and no retry. Polling a clock in the page as well would cover Chromium. It's
your call whether that is worth a job.
## Job 123: close #78 and #79 as host-pause only

Status: open, the lead's call. The job closes nothing by hand.

The two voice.spec.ts flakes ("a token only reaches its own household's list", #78; "a
dictated sentence lands in the open list, split and sorted", #79) did not reproduce under any
load or pause the stall detector cannot see. 90 of 90 runs passed under CPU load and
stack-only pauses of up to 8 s every 14 s, with retries off. They failed only while the runner
and Chromium were stopped for most of a 10 s wait. All 11 such attempts printed `[host-stall]`
(7 to 9 s), and the 18.23 policy retries those. Every recorded failure fell in a host pause of
177 to 1801 s. The counts and the method are in `DECISIONS.md` ("Job 123") and
`docs/done/123-fix-voice-spec-flakes.md`.

To close: close #78 and #79 with a link to the PR. If either one fails again without a
`[host-stall]` line in the failing attempt, reopen it with the run log.
## Job 150: site videos with the microphone (2026-11-06)

- **Phone check of the loops.** As for job 54: watch the four loops on a phone at real speed
  (landing page, both languages), especially the new voice-add card.
- **English video hears German (your call).** The app's dictation listens in German in every
  language, so the English voice-add cut shows the German sentence with "Snacklist listens in
  German." (DECISIONS "Job 150" 3). The other way is English dictation in the app (its own job),
  then a re-take with an English sentence.
- **Copy.** New strings are drafts in `site/COPY_NEEDED.md` (voice.app.*, demo.voice-add,
  voice-add.*) for Snacklist Launch; voice.siri.now lost its in-app sentence to the new card.


## Job 156: nexus.snacklist.app (ops dashboard), 2026-11-07

Status: done (2026-11-07, job 156 fix 4). The lead created the token. Job 156 ran steps 2 and 3:
project `hummlist-nexus` (not git-connected, Vercel Authentication on all deployments, no password
protection), domain `nexus.hummlist.com`, first production deploy. A logged-out request to the page
or to `/data/snapshot.json` gets a 302 to the Vercel login. The hz cron deploys every 10 minutes
once `nexus/` is on main. The steps stay below as the record. Since 2026-11-10 the domain is
`nexus.snacklist.app` on the same project; `nexus.hummlist.com` is a 308 redirect to it.

Nothing here costs money (cost table in [`nexus/README.md`](../nexus/README.md#cost)). Vercel
Authentication with the scope **All Deployments** is "Included" on Hobby and Pro since
2026-09-09
([changelog](https://vercel.com/changelog/protect-production-deployments-for-free-on-every-plan),
[pricing table](https://vercel.com/docs/deployment-protection/usage-and-pricing)). It now covers the
production custom domain too, so the `nexus-live` preview-branch workaround from Addendum 1 is
not needed. Do NOT turn on Password Protection: that one is $20 per project per month on Pro.

1. **Create a token** (Vercel dashboard, Account Settings, Tokens): name `hummlist-nexus-publisher`,
   scope the Hummlist team, expiry 90 days (see the note below). Put it on hz in `~/.config/agents/nexus.env` (mode 600):
   `VERCEL_TOKEN=...` and `VERCEL_ORG_ID=<team id>` (a token scoped to the team; never into the repo).
2. **Set the project up** on hz: `set -a; . ~/.config/agents/nexus.env; set +a;
   ~/nexus-publisher/nexus/scripts/setup-vercel.sh` (idempotent). It creates the project
   `hummlist-nexus` (not git-connected), adds `nexus.snacklist.app` (and keeps `nexus.hummlist.com` as a 308 redirect to it), sets Vercel Authentication to
   All Deployments and prints `VERCEL_PROJECT_ID`: add that line to `nexus.env`. With nothing
   deployed yet it says "no deployment yet" and exits 0. Then run
   `~/nexus-publisher/nexus/scripts/cron.sh` once (the first deploy) and rerun `setup-vercel.sh`:
   this time it ends with a logged-out `curl` of `https://nexus.snacklist.app` that must show 401 or a
   redirect to the Vercel login. DNS needs no change: snacklist.app is on Vercel's nameservers.
3. From then on the hz cron entry (installed by job 156, the line is in `nexus/README.md`) deploys
   every 10 minutes; its log is `~/nexus-publisher.log`.

Mind the token's reach (review 2). A Vercel token cannot be limited to one project: a team-scoped
token can also deploy to or delete `hummlist-site`, the app project and `hummlist-mcp`, and the hz
cron runs whatever `main` holds with it in its environment. Keep the expiry short (90 days, renew
in the dashboard), keep `nexus.env` mode 600 and outside every checkout, and revoke the token if
hz is ever shared beyond these jobs. A separate free Hobby team just for nexus would contain it
fully but is not needed at €0 either way; the lead's call.
   Send Peter `https://nexus.snacklist.app`; he signs in with his Vercel account.

## Job 218: a PR that conflicts only in the logs needs no rebase job (2026-11-13)

Status: open, the lead's call. No browser step: two notes for the watcher and the standing
instructions.

1. **GitHub still says CONFLICTING.** Since job 218, `scripts/push-pr.sh` rebases over sections
   other jobs appended to `docs/DECISIONS.md`, `docs/NEEDS_LEAD.md`, `docs/NEEDS_PETER.md` and
   `DONE_SUMMARY.md` without stopping (`scripts/merge-append-log.sh`, `docs/CI.md`, "Landing a
   PR"). GitHub runs no merge drivers, so the PR page shows such a PR as conflicting until that
   push. A green, reviewed PR whose only conflicts are these files can go straight to the land
   (`merge-lock bash -c 'scripts/push-pr.sh && scripts/merge-pr.sh --wait <n>'`); it needs no
   rebase job of its own, as `204b-rebase-merge-400` and `204c-land-400` were on 13 November.
   Each clone learns the driver at its first `push-pr.sh` from a branch that has job 218's
   commit; nothing to install on hz or the box.
2. **Optional: one decisions file per job.** The driver leaves the conflicts where a job edits
   old lines or adds a follow-up to an older section (18 of 256 in main's history). Writing each
   job's decisions to `docs/decisions/<job>.md` would end those too. It needs the standing
   instructions changed (where a job writes, how docs cite a decision) and is not worth it for
   that remainder alone; say so if it should be done.

## Job 218: lands after PR 3, and two things left for the lead (2026-11-14)

Status: open, the lead's call. No browser step. Numbers:
`docs/hillclimb/fable-improvement-2026-11.md`, PR 3.

1. **No sleep between push-pr.sh and merge-pr.sh.** merge-pr.sh now waits until GitHub's record
   of the PR names the pushed head (up to 2 min). Land scripts and the standing instructions
   can drop their `sleep 20`; a land is
   `merge-lock bash -c 'scripts/push-pr.sh && scripts/merge-pr.sh --wait <n>'` again.
2. **Optional: the lint gate's list of script tests.** `scripts/gates/lint.sh` names each
   script test in one header sentence and runs each on its own line; jobs that add a test
   conflict there (job 219 three times, job 218 once). A pattern, as the db gate has since
   job 218's PR 2, needs the tests renamed to one suffix first. PR #420 edited the file and
   was open until the morning of 14 November, so job 218 left it. Worth a small job now that
   #420 is in, if jobs keep adding script tests.
3. **For the record: the merge queue moves at one CI run per land.** In the night of 13 to 14
   November main took 17 commits a median 25 min apart while lands waited (job 218's first
   land: 2 h 31 min in the queue). The lock is held from the push to the merge, so through the
   CI run (median 23.8 min from creation to green). Nothing to do unless that wait starts to hurt; a change (CI before
   the lock, a merge queue on GitHub) is a design of its own.


## Job 220: what the security review leaves with other jobs (2026-11-14)

Status: open, the lead's call who takes each. No browser step here; Peter's part (repository
settings) is in `NEEDS_PETER.md`, "Job 220".

1. **`.github/workflows/supabase-deploy.yml` (job 209's file).** Its `deploy` job reads the
   Supabase access token from the job's `env:`, names no environment and runs a `bun` that
   `supabase/setup-cli` restores from the Actions cache. The lint check `workflow-hardening`
   excepts exactly these in `scripts/workflow-hardening.allow.json` (three entries) and fails on
   a stale entry. The fix, step by step: `docs/done/220-security-hardening.md`, "In files other
   jobs own". Until it lands, the token stays a repository secret (NEEDS_PETER, Job 220,
   step 3), which a workflow file on any pushed branch can read.
2. **Request bodies read before the caller is known.** `supabase/functions/voice/handler.ts`
   (jobs 207 and 213) and `supabase/functions/alexa/handler.ts` (PR #405) read the body without a
   size limit before the token or signature check. Small, and behind the gateway's own limit;
   recorded in the done doc, not changed here because both files were in flight.
3. **`scripts/merge-pr.sh --wait` gives up after 30 minutes; a green CI run took up to 33.8.**
   On 14 November one of this job's lands held the merge lock for 31 minutes and merged nothing
   (run 43570436349 took 33.5 minutes). The wait is `MERGE_WAIT_MINUTES` (default 30,
   `docs/CI.md`): a default of 40, or land scripts that set it, would keep such a hold from
   being wasted
   (`docs/hillclimb/fable-improvement-2026-11.md`, Job 220, the merge lock table).

## Job 219: what the verification job measured and did not fix (2026-11-14)

Status: open, the lead's call. No browser step. Each point is outside the job's reach or its
brief; the numbers are in `docs/hillclimb/fable-improvement-2026-11.md`, "Job 219".

1. **The merge lock is where the loop waits now.** In the baseline the merge lock took 55.8 h
   of the jobs' 602.4 h wall time (36 jobs), second to the wait for CI (172.7 h). In the night
   of 13 November and on 14 November the Mac lock was unavailable, and `merge-lock` waits for
   it at every acquisition before it falls back to the Hetzner lock (30 to 38 minutes at this
   job's turns, by the BOARD's warning lines). Each land then holds that lock for a push and
   one CI run, and the Hetzner lock is a plain `flock`, which hands the lock to any waiter and
   not to the first (job 218's point 3 above measures the one CI run per land). This job's 13 turns at the lock waited 17.6 h in sum,
   30 min to 2 h 48 min each. Two changes would cut that, both in
   `~/groceries-ops/bin/merge-lock` and so not a job's to make: remember for some minutes that
   the Mac lock was unavailable and skip the wait, and queue first-come.
2. **`merge-pr.sh --wait` gives up after 30 minutes; one run in five with the ios job takes
   longer.** 23 of the baseline's 110 green runs with the ios job took over 30 minutes to
   `ci-ok`, one over 45. A PR that touches `scripts/gates/` or `scripts/lib.sh` runs every CI
   job, ios included. It ended #420's first land: the run took 34.6 min (the ios job started
   4.7 min into the run and ran 28.9), and `ci-ok` turned green 2.6 min after merge-pr had given up.
   Job 218's #438 lost a land the same way at 09:40 on 14 November (its BOARD line of 09:41).
   The land then starts again with a new wait for the lock and, when main moved meanwhile, a
   new push and a new CI run. The setting exists and `docs/CI.md` named it; when to raise it
   was not written down. This job's last PR says so in `AGENTS.md` and `docs/CI.md`
   (`MERGE_WAIT_MINUTES=45` for such PRs). Job 220's point above proposes a default of 40. A default of 45 when the run has the ios job would not depend
   on a job reading that, at the price of a stuck run holding the lock 15 minutes longer: the
   lead's call.
3. **The hz-runner's BOARD line is early.** "WARNING <job> merged under the Hetzner-only merge
   lock" is posted when the wait for the Mac lock ends, before the job has the Hetzner lock and
   whether or not it merges. It named job 219 at 23:49 on 13 November, 2 h 18 min before its
   first merge (02:07), and three times at 09:42 on 14 November, 77 minutes before the next
   (10:59).
4. **A tick right before the page goes away can be lost (product, not changed).** In the one CI
   trace read (run 43503369675, WebKit) the app sent no write for a tick when the page reloaded
   within about half a second of the row leaving, and did not send it after the reload either.
   Locally an instant reload kept the tick in 20 of 20 tries. The e2e tests now wait for the
   write (#441). Whether a user who ticks and closes the tab at once can lose the tick is not
   measured; job 212 owns the list's write path.
5. **The hosted project and the early answer.** #440 fixed a local finding: the edge runtime
   drops a finished answer to a POST whose body nobody read (about a third of 150 requests on one
   core). Whether the hosted runtime does the same was not probed, since jobs do not load-test
   production. After #440 no function behind `withTelemetry` answers before it has read the
   body, so the question is open only for the others.
6. **Ten e2e tests cannot pass on the Hetzner runner.** The stack's containers cannot open a
   host port there, so the fake sign-in provider is out of reach (at least 20 of 199 jobs have
   these failures in their transcripts). The recipe names the cause and sends the tests to CI.
   Letting the Docker bridge reach the e2e port range on the host would make them pass
   locally; the firewall is not a job's to change.
7. **Left open in #442, each named in its PR.** The `docker exec` that reads the applied
   migrations has no timeout. Two checkouts with one `project_id` share a stack, and each resets
   it for its own migrations. `supabase db reset` restarts auth, realtime and storage, and the
   gate waits for nothing beyond the CLI's return (one passing run measured).
8. **The job's tests cost the lint gate 23 to 30 s** on the runner (79 to 86 s before, 108.5 s
   to 108.6 s after; three rounds each of `scripts/gates/lint.sh`). Most of it is
   `scripts/verify-test.sh` (28.9 to 29.0 s as merged), whose cases wait on real seconds for the
   lock-wait and left-over-server checks. Say so if that is too much for what it guards.
9. **Until #451, any fg-cli gate run ended a land waiting for CI on the same machine; what is left
   of it.** The gate's `cancel_test.ts` cleaned up with `pkill -f '^sleep 20$'` (since #35), and
   `merge-pr.sh --wait` polled with `sleep 20` under `set -e`: the land printed "Terminated",
   exited 143 and lost its turn at the lock. It ended #445's first land at 14:21:38 on 14 November,
   in the seconds job 215's fg-cli gate ran (the ledger: 7 s, done 14:21:41), and its second at
   15:05:49 (job 234's gate, 5 s, done 15:05:51). By 17:25 seven jobs' transcripts held such an
   end. Job 236's land of #453 is one: its wait ended before `ci-ok` on its head turned green at
   16:18:54, most likely at 16:17:00 in job 231's fg-cli gate (the ledger: 3 s, done 16:17:02),
   and it merged 48 minutes later. Job 229's ended between 16:41 and 17:00 (job 215's gate, done
   16:51:44, is the likely sender, not proven). A third end of this job's land's wait, at
   16:24:00, was this job's own doing: a review subagent ran an old checkout's fg-cli gate by
   mistake (a `cd` that went into the background with the list it led), which also ended two
   waiting loops of job 236's session, which went on; the land script started this job's wait
   again.
   #451 fixes both sides: the test ends its own process only, and `merge-pr.sh --wait` logs a sleep
   that a signal ended and waits on, up to 20 times per wait. A land runs `merge-pr.sh` from a
   checkout that `push-pr.sh` rebased, so lands are safe from the merge on. The worktrees of
   running jobs keep the old test until they rebase, and their fg-cli gate still ends every other
   `sleep 20` on the machine: a script that waits that way under `set -e` ends with "Terminated"
   (of the repo's scripts that wait only `scripts/voice/health.sh` has another `sleep 20`, without
   `set -e`; an agent's own loop may have one). Nothing to decide; a land that ended that way before #451 was this.
10. **A 502 from GitHub on the merge call loses a land's turn.** `merge-pr.sh` calls `gh pr merge`
    once. #445's third turn waited 71 minutes for the lock and 23 for CI, `ci-ok` turned green at
    16:39:59, and the merge call 20 s later came back "non-200 OK status code: 502 Bad Gateway":
    exit 1, the PR still open, the turn gone. Job 32b's transcript has the same end on 30 October;
    no other of the runner's transcripts has that line. Two lands in 16 days did not carry a PR of
    their own here. The fix would be small: when the merge call fails, read the PR's state, and
    call once more if it is still open and its head unchanged (`--match-head-commit` keeps a second
    call from merging anything else).

## Job 222: offline and sync gaps that need a decision (2026-11-14)

Status: open, the lead's call. Nothing here blocks the job's PR. The map and the reasons are in
`docs/done/222-robustness-offline-sync.md`.

1. **A write that never answers stalls the queue (server change).** Item writes have no HTTP
   timeout, and job 122 showed that one alone reorders last-write-wins writes. The safe fix is
   a stale-write guard on the server (a per-item op sequence or time check in `put_item` and the
   update path, a migration), then a timeout in `ListRepository`. Not built: a migration on the
   write path is more than a robustness test job should land between jobs 202 to 217.
2. **A forced sign-out drops queued changes (product).** A token refresh the server refuses
   signs the user out; sign-out forgets the device's data, queued adds and ticks included,
   without a word. Job 122 recorded it as intended. The options: keep the queue per user id and
   replay it when the same user signs in again, or say so on the sign-in screen. A user who
   signs out by hand with unsent changes is not warned either.
3. **Realtime channels other than the list's never rejoin after a server `phx_close`
   (purchases, household).** Read from the code and the library (`realtime_client` 2.13.2), not
   reproduced. Entitlements and invites re-read on a rejoin but a closed channel does not
   rejoin; the own and the household's join-request channels re-read nothing. Resume refreshes
   and the invites panel's 5 s poll hide most of it. Worst case: an owner with the approval
   section open misses a request until the section is rebuilt. The list's channel has its own
   resubscribe loop (`ListCubit`); the fix would give the four the same, in files jobs on
   purchases and the household own.
4. **A start read that never answers is never asked again.** `SessionCubit._load` has no
   timeout (the reason is in `docs/DECISIONS.md`, "Job 222"). If the lead wants one, it has to
   keep the slow answer: a timeout that only arms a second read and takes whichever answers.
5. **Job 219's point 4 (a tick right before the page goes away) is fixed** for the window it
   names: a row's tick now commits when the page is hidden, and `e2e/tests/tick-leave.spec.ts`
   drives a reload and a closed tab right after the click on three engines (3 of 18 passed on
   main, 30 of 30 on the branch). The CI trace of that point was not reproduced.
