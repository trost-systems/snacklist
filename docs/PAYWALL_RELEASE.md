# Paywall release: the go-live checklist

This is the ordered list of switches that put Snacklist Premium on sale and,
after that, lock AI assistants and the API behind it. Siri (job 184) and the
Alexa skill (Peter Q39, Legal Review N-27, job 72) stay free: the lock never
covers them. Every step names its
owner. A step marked **Peter's yes** waits for Peter to say yes in his own
words. Nothing here has been flipped yet (job 67, 2026-11-02). The behaviour
behind the switches is in [`PURCHASES.md`](PURCHASES.md). The old per-job
notes are in [`NEEDS_LEAD.md`](NEEDS_LEAD.md) (jobs 43, 47, 49 and 50) and
[`NEEDS_PETER.md`](NEEDS_PETER.md) (jobs 25 and 43). This file replaces them
as the order to follow.

Owners:

- **Peter**: decisions, legal sign-off, anything under his Apple, Google or
  bank identity.
- **Ops** (Snacklist Ops): App Store Connect, Play Console and RevenueCat
  dashboard work. Ops creates no product and changes no price without
  Peter's yes.
- **Lead** (snacklist-lead): repository PRs, repository variables and
  secrets, function secrets, SQL on the hosted project.
- **Legal** (Legal Review): legal texts and their publication.
- **PM** (Snacklist PM): user-facing copy that is still a placeholder.

## Product prerequisites (Peter, 11 Nov 2026)

Product work that bears on the sale, not switches. The decisions and their
status are in [`PRODUCT_FEATURE_MAP.md`](PRODUCT_FEATURE_MAP.md).

- **Differentiated Premium value** must exist before Premium goes on sale
  (step 5): insights, automation, the API and MCP, or conveniences with a
  real per-use cost (`premium-differentiation`, 20:42). Which slice the
  paid launch needs is open; the built public API and MCP are evaluated
  first. 1 Dec 2026 is a paid launch (`dec1-paid-launch`), so that slice
  is built before then.
- **Free price entry is not a sales gate.** Price entry, trip totals,
  unlimited barcode scanning and purchase recording are Free
  (`free-convenience-no-running-cost`, `barcode-free-limit`). Superseded:
  "Prices and trip total must ship before Premium goes on sale" (07:23).
- **Shelf-label scanning** must not delay the sale. It stays planned, is
  Free since 20:59, and ships later when it works well
  (`sales-prerequisite` in the map).
- **Household limit**: a user belongs to at most 20 households, on Free
  and on Premium. In the database since job 200 (`public.household_cap()`);
  the paywall and the terms do not name it yet (job 187).
- **Prices: yearly EUR 24.99 and Lifetime EUR 149.99**, both at the paid
  launch, no monthly or weekly plan (`yearly-plan`, `lifetime-plan`, 20:42).
  Approved, not in the stores yet: they still charge EUR 9.99 / EUR 29.99.
  `expectedPrices` holds the approved euro amounts and accepts the
  superseded ones with a note until then (job 184, step 2.3). Ops sets the stores, other currencies
  included, without a further yes from Peter; engineering does not touch the
  stores (`store-prices-ops`). Paywall and store copy read the price from
  StoreKit / Play Billing and never hardcode an amount. Superseded:
  EUR 9.99 / EUR 39.99 (11 Nov morning).
- **Lifetime** has the same features as yearly, with explicit allowances
  for costly processing and API use, not unlimited (`lifetime-allowances`;
  the numbers wait for a cost check).
- **Per-user Premium** is in the code since job 185 (RevenueCat App User
  ID = the Snacklist user id; docs/PURCHASES.md "Per-user Premium"). Step
  4.5 has to be done before 5.1 or 5.4.
- **Siri free under the lock** is built (job 184): the gate answers Siri
  open, as it does Alexa.

## The switches

| Switch | Where | Off today | Turned on in step |
| --- | --- | --- | --- |
| `REVENUECAT_PURCHASES` | GitHub variable, `release` environment (store builds) | unset | 5.1 |
| `REVENUECAT_APPLE_API_KEY`, `REVENUECAT_GOOGLE_API_KEY` | GitHub secrets, `release` environment | unset | 5.1 |
| `app_switches.premium_offer` | hosted database | `false` | 5.4 |
| `premium-launch` | `releases/flags.json` hold | `released: false` | 5.6 |
| Job 329 PR (privacy section 5a, help answers, terms draft) | repository | open, not merged; its site texts wait for `premium-launch` | 4.1 |
| `app_switches.integration_lock` | hosted database | `false` | 6.4 |
| `INTEGRATION_LOCK` | GitHub variable, `release` environment, and the Vercel project's environment | unset | 6.5 |
| `integration-lock` | `releases/flags.json` hold | `released: false` | 6.5 |

Store builds read the four build switches through `app/fastlane/Fastfile`
(`PREMIUM_DEFINES`) and `.github/workflows/release.yml`. The web build reads
`INTEGRATION_LOCK` through `scripts/vercel.sh`. The web app never sells, so
it takes no purchase define. While a variable is unset the build sells
nothing and locks nothing.

The Home Screen widgets are not part of the lock. They show the list the
app already has and never call Siri's, Alexa's, the MCP or the API endpoint, so they
stay free with every switch on. Whether widgets should be Premium is
undecided (Peter). Locking them would be new work, not a switch.

## 1. Accounts and money (Peter)

1.1 **Peter**: App Store Connect → Business → Paid Apps agreement accepted,
bank account and tax forms done, status "Active". Without it Apple serves no
in-app product, not even in the sandbox (NEEDS_PETER "Job 25", item 1).

1.2 **Peter**: Play Console → Setup → Payments profile created and verified
(NEEDS_PETER "Job 25", item 2).

1.3 **Peter**: the App Store Small Business Program, and on Play the 15 %
service fee through an account group (NEEDS_PETER "Job 25", item 3). The
revenue estimate assumes 15 %.

1.4 **Peter's yes**: Google Play real-time notifications. They need a
Pub/Sub topic in a Google Cloud project with billing attached. The usage
stays inside the free tier. Without them a Play refund or renewal reaches
RevenueCat late (NEEDS_PETER "Job 43", item 3). Either answer works with the
code.

## 2. Store products (Ops, Peter's yes)

Hummlist's products exist (Ops, 2026-10-31). Since job 174 the app sells
Snacklist's: the App Store products below exist on the Snacklist app
(`6832756448`); the Play products go on the Snacklist Play app
(`com.snacklist.app`). Hummlist's (`com.hummlist.app.yearly`,
`com.hummlist.app.lifetime`) stay until Hummlist retires. This job created no
product and changed no price. Check each item and fix only what Peter
approves.

2.1 **Ops**: App Store Connect, subscription group "Snacklist Premium"
(`22562774`). `com.snacklist.app.yearly` (Apple ID `6832759834`, 1 year) and
the non-consumable `com.snacklist.app.lifetime` (`6832759640`) each have a
German and an English display name and description, a review screenshot and
review notes, and the status "Ready to Submit". Family Sharing is off for
both, and Apple never lets it be turned off again once on.
The review screenshot comes from the iOS simulator: run the workflow
"Paywall screenshot" (`paywall-shot.yml`, `scripts/ios-paywall-shot.sh`) and
take `paywall-ios-de.png` (yearly picked) and `paywall-ios-de-lifetime.png`
(Lifetime picked), 1290x2796, German, light, from its artifact. They show
the German storefront's prices; StoreKit's own answer on the runner
(the sandbox's US storefront) is in the artifact's `ready-yearly` (DECISIONS,
job 86).

2.2 **Ops**: Play Console. The subscription `com.snacklist.app.yearly` with
base plan `yearly` (auto-renewing, 1 year, grace period 14 days, account
hold 46 days, **no free trial or introductory offer**). The one-time product
`com.snacklist.app.lifetime` is active. Since job 67 the app buys the base
plan itself. An offer added later would not be charged without an app
change, which keeps the shown price the charged price (Legal Review A2-5).

2.3 **Ops**: the prices. Peter approved EUR 24.99 a year and EUR 149.99
Lifetime (11 Nov 2026); Ops sets the other currencies accordingly without a
further yes (`store-prices-ops` in the map). Not set yet: the stores still
charge the superseded amounts. `expectedPrices` in `scripts/iap/product.ts`
holds the approved euro amounts (job 184), and the drift check in 2.4
accepts the superseded EUR 9.99 / 29.99 with a note until Ops moves the
stores; a PR then deletes the superseded amounts. US $9.99 / $29.99, UK
£8.99 / £24.99 and CH CHF 10 / CHF 30 are today's store prices, recorded
anew once Ops sets them. Brazil, Mexico and India get yearly only.
EUR 9.99 / 29.99 / 39.99 are historical.

2.4 **Lead**: the price drift check. Set the repository secrets `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8` and `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Then
run `deno run --allow-env --allow-net --allow-read scripts/iap/price_drift.ts`
once on the box, fill in the printed BR, MX and IN yearly amounts in
`expectedPrices` in a PR, and confirm that `price-drift.yml` is green
(NEEDS_LEAD "Job 49", steps 5 and 6). This is the launch gate for prices.

## 3. RevenueCat and the server (Ops, Lead)

3.1 **Ops**: RevenueCat project `9cb4a72e`, in the dashboard. Snacklist has
its own apps there (iOS `app762918886a`, Android `appcec7ffa3d1`); Hummlist's
(`app508ff9066c`, `app44e3fb2d11`) stay until Hummlist retires.

- Entitlement `premium` (`entl654efcfce4`) holds Hummlist's four products.
  Attach Snacklist's four next to them: App Store yearly and Lifetime, Play
  `com.snacklist.app.yearly:yearly` and `com.snacklist.app.lifetime`. Nobody
  has confirmed them in RevenueCat yet (job 174). The Play Lifetime products
  are marked **non-consumable**.
- Offering `default` with `$rc_annual` and `$rc_lifetime`. The app loads
  products by id, so the offering is only for the dashboard.
- Restore behavior **Keep with original App User ID**, production and
  sandbox. "Track new purchases from server-to-server notifications" off,
  AI features off, no other integrations.
- App Store Server Notifications V2 (production and sandbox) point to
  RevenueCat's URL. The In-App Purchase key is uploaded. The Play service
  account is uploaded, plus Pub/Sub if 1.4 said yes.
- The webhook integration:
  `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases/revenuecat/webhook?forceFunctionRegion=eu-central-1`,
  production and sandbox, all apps, all event types, and the `Authorization`
  value the function expects.

3.2 **Lead**: the function secrets on the hosted project are set (names only,
never print values): `REVENUECAT_WEBHOOK_AUTH`,
`REVENUECAT_TOMBSTONE_HMAC_KEY`, `REVENUECAT_SECRET_KEY`,
`REVENUECAT_PROJECT_ID`, `REVENUECAT_DELETIONS_SECRET`, and
`REVENUECAT_WEBHOOK_HMAC_SECRET` if signing is on. The repository secret
`REVENUECAT_DELETIONS_SECRET` holds the same value (NEEDS_LEAD "Job 47",
step 1). Check:

- `supabase secrets list --project-ref jdwqrallbpdbshrdhenk` names them all.
- `curl -s https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/purchases`
  answers `{"configured":true}`.
- RevenueCat's "Send test event" gets 200 `ignored`.
- `revenuecat-delete.yml`, run by hand once, is green.

3.3 **Lead**: the hosted database has every migration of main up to and
including `20261102001623_premium_grace_kept.sql` (job 67), deployed by
`supabase-deploy.yml`. Read-only checks in the SQL editor:

```sql
select key, enabled from public.app_switches order by key;  -- premium_offer, integration_lock: false
select kind, premium_source, source, count(*) from public.entitlements group by 1, 2, 3;
```

3.4 **Lead**: delete the old RevenueCat entitlement `lifetime` only after
every installed app is a job 49 build or later (NEEDS_LEAD "Job 49",
step 2). The launch does not wait for it.

## 4. Legal texts (Legal, Peter's yes)

The open gaps between the drafts and what the app does are listed in the
job 67 PR ("For Legal Review"). Each one is either closed or accepted by
Legal before 4.1.

4.1 **Legal, Peter's yes**: the job 329 PR (#580), which replaces PR #153.
It puts section 5a (yearly plan and Lifetime, per-user since job 185) into
the privacy policy, the help page's answers on cancelling, leaving a
household, a lapse and refunds, the Premium page's per-user lines (the
yearly terms, `premiumOwner` under the plans, the web note `premiumWeb`)
and the account-deletion page's Premium lines. It deletes the draft
purchase pages. The site parts sit in `::: once premium-launch` blocks (the
old answers in `::: until premium-launch`), so the PR can merge after
Legal's GO without going live: production renders them only once the hold
is released (5.6, `site/test/gates.test.mjs`). The app strings show only
with `REVENUECAT_PURCHASES` and `premium_offer` on. The account-deletion
page (`app/web/konto-loeschen.html`, `delete-account.html`) and the §12/§13
RevenueCat lines are worded to be true before and after the sale and go
live with the next web release. Still household-worded on the Premium
page: the hero („Einer kauft. Alle haben es.“, „… für euren ganzen
Haushalt …“), job 327's (#579; the Lead's override of 20 Nov has #579 leave the
11 household-wording keys out (N-308) and keeps `paywall-cs1` off). Before 5.4 the hero must stop
promising the household and the page must say, without a further tap,
that the free list needs no Premium (N-129), and the 20-household cap must
stand on the page (N-128): open for the Lead, NEEDS_LEAD "Job 329".

4.2 **Legal, Peter's yes; blocker for 5.4**: the terms of use
(`nutzungsbedingungen.md`, `terms.md`, job 329; Legal's K.13.S rewritten
per-user). Legal N-129 and K.13.R R.6 want them live and linked before a
yearly plan is sold. They stay `draft: true` (404 in production) until
Legal's GO; then a PR drops `draft`, sets the date line, and points
`termsUrl` (`app/lib/purchases/premium_server.dart`) at
`/nutzungsbedingungen` and `/en/terms` on Android and the web, before 5.4.
Apple's EULA can stay on iOS, or the terms page can replace it there too
(Legal decides). Also before 5.4 (N-128): numbered limits for any per-use
cost feature that is offered, in the terms (section 8) and on the Premium
page; today only the API has numbers (section 8 names them), MCP has none,
and Lifetime's allowances (`lifetime-allowances`) are open for Peter.

4.3 **Legal**: privacy section 9 names `paywall_viewed` and
`integration_blocked` (and the Siri events), and section 7 says that AI
assistants need Snacklist Premium (not Siri or Alexa, which stay free). This is needed before 6.4,
not before the sale.

4.4 **Ops, after Legal**: the App Store privacy label and the Play Data
safety form list purchases (RevenueCat as processor, the account id as
user id since job 185).

4.5 **Legal, Peter's yes**: the purchase privacy texts describe per-user
Premium (job 185): RevenueCat and through it Apple and Google receive the
account id, the purchase belongs to the account, and the RevenueCat
customer is deleted 30 days after the account. Drafted in job 329 (4.1). The Premium page copy that
promises the household changes through the prototype gate. Both lists are
in NEEDS_PETER "Job 185".

## 5. The sale

5.1 **Lead**: the store build switches. Set the `release` environment
secrets `REVENUECAT_APPLE_API_KEY` (`appl_…`) and `REVENUECAT_GOOGLE_API_KEY`
(`goog_…`), both from `~/groceries-ops/env`, and the variable
`REVENUECAT_PURCHASES=true`. Nothing is sold yet: while `premium_offer` is
off every build says "Snacklist Premium ist bald verfügbar.". Check: the
next Release run's `fastlane ios beta` and `fastlane android build` log
lines show `--dart-define=REVENUECAT_PURCHASES=true`. The key values are
masked.

5.2 **Lead**: for the sandbox run in 5.3, turn `premium_offer` on for a
short window with the statement in 5.4, then off again. Every installed
build with the define then sells. TestFlight builds buy only in the sandbox.
**Play internal testers who are not license testers pay real money**, so
only Play license testers (Play Console → Setup → License testing) take part
on Android.

5.3 **Peter and Lead**: the sandbox run on real phones (TestFlight with a
sandbox Apple ID, Play internal with a license tester). Peter and Lea's
household, or a fresh test household without a promotional grant:

- Mehr → Snacklist Premium shows both cards, yearly first, with the store's
  price and "inkl. MwSt.".
- Buy yearly. The page says "Wird freigeschaltet …", then „Snacklist Premium
  aktiv (jährlich, verlängert sich am …)“. The partner's phone shows the same
  within seconds without a reload.
- Restore on the partner's phone: nothing to buy, nothing to restore.
- Buy Lifetime while yearly runs. The warning appears first, then
  „Snacklist Premium Lifetime“ with the note that the plan keeps billing.
- „Abo verwalten oder kündigen“ opens Apple's or Google's subscription page.
  Cancel there. The status says „läuft am … aus“. The sandbox year lasts one
  hour on Apple and 30 minutes for Play license testers. After the end the
  household is back to both cards (a household without Lifetime).
- A household with a promotional grant (`scripts/iap/promotional.ts grant`)
  shows „Snacklist Premium geschenkt“ and no Buy.
- The webhook rows: `select event_type, count(*) from public.revenuecat_events group by 1;`
  in the SQL editor.

Turn `premium_offer` off again when the run ends.

5.4 **Lead, Peter's yes**: the sale opens, together with 4.1:

```sql
update public.app_switches set enabled = true, changed_at = now() where key = 'premium_offer';
```

5.5 **Peter's yes, Ops**: App Store review. The app has no public release
path yet ([`RELEASE.md`](RELEASE.md), "Public releases"). The store
submission is its own job and needs Peter's go. For the paywall it must
attach both in-app purchases to the app version ("In-App Purchases and
Subscriptions" on the version page), since Apple reviews a first purchase
only with a version. The review notes name a reviewer account whose
household has no promotional grant, so the reviewer can buy in the sandbox
(the App Review household from "Testers" in `PURCHASES.md` has a grant and
shows no Buy). Play: the production track, with its own release job as on
Apple.

5.6 **Lead**: the changelog and the sale's legal texts. A PR sets `"released": true` for
`premium-launch` in `releases/flags.json`, as part of the release whose
store build first sells, and merges no later than 5.4 turns the sale on:
it publishes privacy section 5a and the help page's Premium answers (4.1).
The same PR sets `updated:` and the „Stand“ / "Last updated" line of
`datenschutz.md`, `privacy.md`, `support.md` and `support-en.md` to its date. The next `changelog.mjs draft` then takes the held
Premium items: job 49's ("Snacklist Premium gibt es jetzt jährlich oder als
Lifetime …") and job 67's. Whoever owns the release checks the "What's new"
texts against the 500-character limit (`node scripts/release/changelog.mjs drafts`).

5.7 **Snacklist PM, Peter's yes**: the placeholder copy. Every `premium*` key
marked PLACEHOLDER in `app/l10n/app_de.arb` and `app_en.arb`, and the rename
„Snacklist Lifetime“ → „Snacklist Premium“ in the older strings (S-11, about
45 lines; for example `joinTargetUnlocked` "Dieser Haushalt hat Snacklist
Lifetime" also shows for yearly and granted households). The guides on
snacklist.app that call the integrations free. Snacklist PM can do this before 5.4.
A sale with the placeholder copy is possible but not recommended.

## 6. The integration lock (after the sale is live)

Alexa certification (job 69): the reviewer's household relies on the lock being off. Don't turn
`integration_lock` on while the skill is in certification, or grant the reviewer account Premium
first (6.2, needs Peter). Job 72 takes Alexa out of the lock (Alexa is free, Legal N-27); once
that is on main this note no longer applies.

6.1 **Peter's yes**: the households that keep the integrations for free
(beta households). Spec #4 says no grandfathering.

6.2 **Lead**: a promotional grant for each of them, a dry run first:
`deno run --allow-env --allow-net scripts/iap/promotional.ts grant --household <uuid>`,
then with `--apply`. The Alexa certification account and the App Review and
Play Review households need a grant too, or they hear only the Premium
answer.

6.3 **Lead**: the cut-over count, read-only, in the SQL editor:
`scripts/iap/integration-cutover.sql`. It lists every household without
Premium that uses an integration now. Peter sees the numbers before 6.4.

6.4 **Lead, Peter's yes**, after 4.3:

```sql
update public.app_switches set enabled = true, changed_at = now() where key = 'integration_lock';
```

From this moment MCP tool calls and the Snacklist API (job 73,
`docs/API.md`) refuse households without Premium: MCP with the Premium
sentence, the API with `402 premium_required`. Siri (Shortcut and native,
job 184) and Alexa (add, read, launch, job 72) stay open. Nothing is deleted
or disconnected. The API's keys keep working once the household unlocks;
the API section under Mehr › Zugänge shows a Premium line while the lock is
shown.

6.5 **Lead**: the app side. Set the variable `INTEGRATION_LOCK=true` in the
`release` environment and in the Vercel project's environment (production
and preview). The next store builds and the next web deploy then show the
Premium card under Mehr › Zugänge. A PR sets `"released": true` for
`integration-lock` in `releases/flags.json`. The held item then reaches
the next release. Its commit's text named Siri, which stays free (job 184).
`releases/changelog/rewords.json` (job 213, docs/CHANGELOG.md, "Rewording an
item on main") replaces it, so the draft says only "Der Zugang für
KI-Assistenten gehört jetzt zu Snacklist Premium; dein Haushalt schaltet ihn
mit einem Kauf für alle frei." Check that line in the next draft before
releasing the hold.

## 7. After each step: what to watch

- The `purchases` function logs in the Supabase dashboard. A 401 means a
  wrong `REVENUECAT_WEBHOOK_AUTH`. A 503 `not_recorded_yet` means a lifecycle
  event arrived before its purchase, and RevenueCat retries it. A 5xx means a
  database failure, and RevenueCat retries 5 times over about 80 minutes.
- `price-drift.yml` (daily) stays green.
- PostHog project 319492: `purchase_completed`, `paywall_viewed` and, after
  6.4, `integration_blocked`.

## Rollback

| What went wrong | Do this | Effect |
| --- | --- | --- |
| Anything with the sale (wrong price, store problem, a bug) | `update public.app_switches set enabled = false, changed_at = now() where key = 'premium_offer';` | At once, on every build: no card, no Buy, no store price query. What was bought stays unlocked |
| A price drifted | The same statement, then fix the price (Ops, Peter's yes) | As above |
| The integration lock refuses the wrong households | `update public.app_switches set enabled = false, changed_at = now() where key = 'integration_lock';` | At once: every integration open for every household, and the app hides the card in every build (it reads the switch) |
| A build should not sell at all | Unset `REVENUECAT_PURCHASES` (and `INTEGRATION_LOCK`), and let the next Release run ship | The next builds show "bald verfügbar". Installed builds follow the server switch |
| The privacy text must come back | Revert the #153 commit on main in a PR | snacklist.app redeploys from main |
| A webhook secret leaked | Rotate `REVENUECAT_WEBHOOK_AUTH` in RevenueCat and the function secrets together. Never rotate `REVENUECAT_TOMBSTONE_HMAC_KEY` | Deliveries between the two changes fail and are retried |
| A single purchase is wrong | Refunds go through Apple or Google (the refund help, `PURCHASES.md` "Refunds when something is off"). RevenueCat's refund event locks that purchase | Snacklist never refunds itself |

Purchases cannot be taken back by a switch. Once something is sold, the
buyer's household keeps it (model A), whatever is turned off later.
