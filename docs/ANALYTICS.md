# Analytics, error tracking and feature flags (jobs 19 and 44)

Hummlist measures its DACH kill gates and lifetime value in PostHog, reports app and
edge-function errors there, and takes its runtime toggles from PostHog feature flags. PostHog is
the only vendor for all three (Peter, 2026-10-31). Spec #1 "Kill-gate and LTV analytics";
decisions in [DECISIONS.md](DECISIONS.md), "Job 19" and "Job 44"; open steps in
[NEEDS_PETER.md](NEEDS_PETER.md), "Job 19", and [NEEDS_LEAD.md](NEEDS_LEAD.md), "Job 44".

| Metric | Question | Query |
| --- | --- | --- |
| Day-35 unlock share | Which share of an install-week cohort bought the lifetime unlock within 35 days of `first_open`? | [`analytics/queries/unlock_d35.sql`](../analytics/queries/unlock_d35.sql) |
| WAH | How many households added or ticked at least once in a week (Mon-Sun, Europe/Berlin)? | [`wah.sql`](../analytics/queries/wah.sql) |
| Paying share of WAH (kill gate, jobs 43 and 49) | Which share of a week's active households has Hummlist Premium (Yearly or Lifetime) that week? | [`paying_share_wah.sql`](../analytics/queries/paying_share_wah.sql) |
| Paying households by day 35 (jobs 43 and 49) | Which share of a household-start-week cohort bought Hummlist Premium (Yearly or Lifetime) within 35 days of its first event? | [`paying_households_d35.sql`](../analytics/queries/paying_households_d35.sql) |
| Net unlock revenue | Revenue per month after VAT and store fee, refunds subtracted, restores zero | [`revenue_monthly.sql`](../analytics/queries/revenue_monthly.sql) |
| Household retention | Share of an install-week cohort still adding or ticking in week 1-12 and month 1-11 | [`retention_weekly.sql`](../analytics/queries/retention_weekly.sql), [`retention_monthly.sql`](../analytics/queries/retention_monthly.sql) |
| Manual reorders | Category (route order, store layout) and store reorders per household | [`reorders.sql`](../analytics/queries/reorders.sql) |
| Locked integrations (job 50) | How many households did Siri, MCP or the API (job 73) refuse per week (Alexa until job 72) (each integration too), and how many of them bought Hummlist Premium within 14 days? | [`integration_blocked_weekly.sql`](../analytics/queries/integration_blocked_weekly.sql) |
| Internal filter | Installs and households excluded from every query above | [`internal.sql`](../analytics/queries/internal.sql) |
| Privacy scan (AC4) | No item names, list text, e-mails, IPs or GeoIP in the project | [`privacy_scan.sql`](../analytics/queries/privacy_scan.sql) |

## Where the data goes

- **PostHog EU Cloud**, organization and project "Einkauf", project id **319492**, ingestion host
  `https://eu.i.posthog.com`. The app and the edge functions accept that host and nothing else
  (the e2e build's stand-in `https://posthog.invalid` aside, which cannot leave the machine). No
  fallback key or host is in the code: without `POSTHOG_PROJECT_API_KEY` and `POSTHOG_HOST`
  analytics and error tracking are off.
- The **project key** (`phc_…`) is public by design but never committed. Builds get it from their
  environment: Vercel (`scripts/vercel.sh`), the release workflow (`release.yml` → fastlane,
  `--dart-define`), and Supabase function secrets for the edge functions. CI builds never have it:
  `no_posthog_in_ci` in `scripts/lib.sh` fails the e2e, web-prod and flutter gates otherwise.
- **Free tier only.** No group analytics, cohorts, dashboards or add-ons were created. Person
  profiles are off (`$process_person_profile: false`), so events stay personless and cheap.
- Project-side settings Peter set (IP anonymization, no autocapture, replay, surveys, heatmaps,
  web vitals; exception autocapture; Europe/Berlin; EUR; test-account filter) are a second line.
  The app enforces its own rules regardless: it switches every SDK feature it does not use off
  in its own config, and on the web the browser never loads the project's remote config (the
  CSP allows `https://eu.i.posthog.com` only, not `eu-assets.i.posthog.com`). The native SDKs
  do read it; only native exception autocapture depends on it (on in the project).

## How it is built

Since job 44 the app runs PostHog's official SDK, **posthog_flutter 5.58.3** (pinned), with
posthog-ios and posthog-android under it, and on the web **posthog-js 1.444.0**, served from the
app's own origin (`app/web/posthog/array.js`, `scripts/posthog-js.sh <version>` updates it).
Our guarantees sit on top of it (DECISIONS Job 44):

- **No yes, no SDK.** `Posthog().setup()` runs only once this install said yes; a no calls
  `close()`. The SDKs' own opt-out does not stop their remote-config and flag requests, so it
  is not used as the gate. Before the yes nothing at all is requested or stored by PostHog's
  code; on the web `posthog/array.js` is not even fetched. `AUTO_INIT` is false in the Android
  manifest and the iOS Info.plist.
- **Two allow-list checks.** `track` checks every event against `eventCatalog`; the SDK's
  `beforeSend` (`Analytics._admit`) checks it and the context again, drops it if analytics is
  no longer live, and removes `$screen_name`. Error reports are rebuilt there from the
  scrubbed type and message. On the web posthog-js' own `before_send` then drops every
  property outside `webEventKeys` (`events.dart`), its URL, referrer, user agent, session and
  device ids among them.
- **One file talks to the SDK.** `app/lib/analytics/posthog_client.dart`; the ast-grep rule
  `posthog-flutter-only-in-posthog-client` fails any other import.

| Part | Where |
| --- | --- |
| Consent gate, install id, context, the SDK's `beforeSend` | `app/lib/analytics/analytics.dart` (`Analytics`, a cubit) |
| The SDK: setup, capture, flags, super properties | `app/lib/analytics/posthog_client.dart` (`PostHogClient`) |
| posthog-js on the web: loading, `init`, `before_send` | `app/lib/analytics/posthog_platform_web.dart` (`loadPostHogJs`), the pinned build in `app/web/posthog/` |
| Deleting the native SDK's files at an off | `app/lib/analytics/posthog_platform_io.dart` (`forgetPostHogState`), Android: `MainActivity.forgetPostHog` (`familygroceries/posthog`) |
| Event catalog and allow-list | `app/lib/analytics/events.dart` (`eventCatalog`, `checkEvent`, `contextKeys`, `webEventKeys`) |
| `is_internal` rules | `app/lib/analytics/internal.dart` (`isInternal`) |
| Error type names and the scrubber | `app/lib/analytics/exceptions.dart` (`errorType`, `scrubMessage`, `scrubException`) |
| Uncaught-error hooks, start-up from the build defines | `app/lib/analytics/setup.dart` (`reportUncaughtErrors`, `startAnalytics`, `allowedHost`); defines in `app/lib/app/environment.dart` |
| Feature flags | `app/lib/analytics/flags.dart` (`Flags`, read as `Analytics.flags`) |
| Consent screen | `app/lib/analytics/consent_screen.dart`, route `/analytics-consent` |
| More switch, internal install | `app/lib/more/more_screen.dart` (`more-analytics`, long press on `more-version`) |
| Edge-function error tracking | `supabase/functions/_shared/telemetry.ts` (`withTelemetry`, `Telemetry`); its own sender, not posthog-node (DECISIONS Job 44, item 16) |
| Purchase events | `supabase/functions/purchases/` (job 25), `supabase/functions/_shared/purchases.ts` |
| HogQL and its reference | `analytics/queries/*.sql`, `analytics/metrics.ts`, tests in `analytics/metrics_test.ts` |

## Consent

- **Opted out by default.** Nothing is captured, queued or sent until the user says yes on this
  install. A "no" is stored too and never asked again.
- **When it is asked:** right after the first sign-in on an install, before onboarding (create or
  join a household) and before the list (Peter, 2026-10-27). The router's only gate,
  `authRedirect`, sends a signed-in user to `/analytics-consent` while the install has not
  decided; an invite (`?invite=` or `/join/<code>`) rides along, so the link still ends on joining.
  A browser tab authorizing an MCP client (`next=/oauth/consent…`) is not interrupted; the app
  asks the next time it is opened. Signed out, nothing is captured, not even errors: the login
  screen sends nothing.
- **Per install**: a later sign-in on the same install (another account included) is not asked
  again. More → Nutzungsdaten switches it. Off stops the SDK at once and deletes the install id,
  ours and the SDK's: after `close()` the app deletes the native SDK's files (ids, queue, flags;
  DECISIONS Job 44, item 3), and a start with a stored no deletes them again. Nothing captured
  before a yes is ever sent later; an event handed to the SDK just before the off is sent if
  `close()` gets it out at once, else deleted. Nothing captured after the off is taken. At
  sign-out the SDK keeps running: what it holds is sent, nothing new is taken.
- **The install id exists only after a yes** (job 33b, legal review H-08, TDDDG §25): a yes
  makes and stores it, a no or off deletes it together with the `first_open` mark, and a later
  yes makes a new one. Without a yes the device holds only the decision (`analytics.consent`),
  never an id. An id an older build (job 19) stored without a yes is deleted at the next start;
  an id stored with a yes keeps working.
- **A build without a key** (CI, fg, local debug) never shows the screen: nothing could be sent.
- Peter approved the wording (DE and EN, the legal review's version) on 2026-10-30; job 33b
  removed the "ENTWURF" mark from the screen and from More. The current text, version
  2026-11-01, is Legal's 12:55 text with the buttons „Erlauben“ / „Nicht erlauben“ ("Allow" /
  "Don't allow"), equal weight, none pre-selected (approved by Peter 2026-11-01).
- **Consent text version** (Legal Review 2026-11-01, addendum 12:35; EDPB Guidelines 05/2020
  Rn. 108, 110): every decision is stored with the version of the text it was given under,
  `consentTextVersion` in `app/lib/analytics/consent_version.dart` (now `2026-11-01`). On the
  device it is `analytics.consent_text_version` next to `analytics.consent`; on the server
  `analytics_consents.consent_text_version` (`record_analytics_consent(p_install, p_consent,
  p_internal, p_answered, p_text_version)`). Each version's exact DE and EN text is kept in
  [`docs/consent/`](consent/README.md), the older ones (2026-10-30 and PR #165's, both stored
  without a version) included; `app/test/analytics/consent_version_test.dart` checks the app's
  strings against the current file and the functions' `CONSENT_TEXT_VERSION` against the app's.
  **A yes with no version or an older one counts as no decision**: at the start the app deletes
  it, the install id, the `first_open` mark and the SDK's data on the device, as on a no, sends
  nothing (no events, no errors, no `/flags`) and shows the consent screen again; only a new yes
  starts the SDK, with a new install id. A no stays a no whatever its version. The server does
  the same for its events (`analyticsSubject` in `supabase/functions/alexa/store.ts`): only a
  newest answer that is a yes to the current version counts, so a yes an older build recorded
  (the four-argument `record_analytics_consent`, kept for those builds, stores no version) sends
  nothing. Changing the text means a new version: a new file in `docs/consent/`, the new date in
  both constants, and everyone is asked again.
- **`first_open`** is sent at the moment of consent on the first sign-in of an install, once per
  install id, not at process start. Install-week cohorts therefore start at the first consented
  open. Someone who said no and later switches it on under More sends `first_open` then, and so
  does someone who switched it off and on again: that is a new install id.

## Event catalog

Every event carries `install_id` (a random UUID made at the yes, also the event's
`distinct_id`; new on a reinstall or after switching off and on; never an e-mail or name, no
`identify`), `household_id` (absent before joining), `platform` (`ios`, `android`, `web`),
`app_version` (`0.1.0+1023`), `is_internal`, `$geoip_disable: true`,
`$process_person_profile: false`. PostHog's `uuid` comes from the SDK, which sends it again on a
retry, so a retried batch is not counted twice. No `$ip`. With `ANALYTICS_HOUSEHOLD_GROUPS=true`
(off; group analytics is paid) it also sends `$groups: {household: <id>}`. The SDK adds its own
properties (next section). Until job 44 events also carried `event_id`, `distinct_id` as a
property and `$lib: hummlist-app`; no query reads them.

| Event | When | Properties |
| --- | --- | --- |
| `first_open` | the first yes on an install | none |
| `household_created` | the server created the household; once, also when a retry finds the household a lost answer made (job 22) | `store_count` (0 to 50: how many stores were picked or typed in onboarding, job 58; never their names); `default_stores` from builds before job 58 (true: dm, Lidl and Edeka; false: Skip); `context` (job 169b: `onboarding`, or `switcher` for the switcher's "Neuer Haushalt"; missing from builds before it). A retry with the same request id answers the same household, which is counted once |
| `household_switched` | job 169b: the user picked another of their households in the switcher sheet; not for the switch that follows a create or a join (those send `household_created` and `invite_accepted`) | none; the household switched to rides along as `household_id` |
| `invite_accepted` | the server confirmed a new membership from an invite (`accept_invite` answered `joined`; not when the user was a member already, except as the answer to a try whose answer was lost) | `method`: `link` (the code came from `/join/<code>`, `?invite=` or the pending invite kept on the device, and was not edited), `code` (typed), `referrer` (job 169b W2: from the Play Store's install referrer, read once on the first start) or `paste` (job 169b W2: the start screens' "Einladung einfügen") |
| `invite_sent` | job 22: an invite was handed out: the share sheet opened, or its link or code was copied; once per tap | `channel` (`share_sheet`, `copy_link`, `copy_code`), `context` (`onboarding`: Step 3 after creating; `settings`: More, Einladungen; `switcher`: the invite sheet from a household's row in the switcher; `household`: the invite sheet from the household page; the last two job 169b W2), `kind` (`person`: one person, 7 days; `group`: the group link, up to 50 people, 30 days; job 169b W2). Never the code, the link or the household's name |
| `member_removed` | job 169b W2: the owner or an admin removed a member from the household on the household page and the server confirmed it | none; never who was removed or their name |
| `list_created` | job 169b K: the user added a list to the household (the tabs' "+" or the household page's "Neue Liste") and the server confirmed it | none; never the list's name |
| `list_switched` | job 169b K: the user picked another list in the list tabs; not for the switch to a list they just created (that is `list_created`) | none; never the list's name or id |
| `item_claimed` | job 169b L: the user said "Ich bringe das" on an item they had not claimed; once per claim, never for a changed amount, a retry or an undo | `actor_role`, `household_size`; never the item, the amount or who else brings it |
| `join_requested` | job 169b W3 M: the user accepted an invite to a household that confirms joins (`accept_invite` answered `requested`); the request waits for an owner or admin | none; the user's own household rides along as `household_id`, never the one asked to join or its name |
| `join_request_decided` | job 169b W3 M: an owner or admin let someone in or turned them away on the household page and the server confirmed it | `approved`: `true` or `false`; never who asked or their name |
| `item_added` | the user added an item | `source`: `typed` (taken as typed), `spoken` (in-app dictation), `suggestion` (any other row of the add sheet, a due usual, a re-add from "Zuletzt verwendet" more than 10 minutes after the tick), `alexa` (server only, job 31: added through the Alexa skill, sent by the `alexa` function); `actor_role` (`owner`, `admin` since job 169b, `member`; the `alexa` function reports an admin as `member`); `household_size` |
| `item_ticked` | the user ticked an item off | `actor_role`, `household_size` |
| `category_reordered` | a new category order reached the server | `scope`: `default` (route order) or `store` (a store's layout) |
| `store_reordered` | a new store order reached the server | none |
| `feedback_submitted` | the server stored a feedback note (job 21, docs/FEEDBACK.md); once per note, also after a Retry whose first answer was lost | `category` (`bug`, `idea`, `other`, `none`), `entry_point` (`settings`; More is the only entry), `screen` (a name from `screenNames` in `router.dart`, e.g. `list`; `stores` for the List tab's Anpassen pages, never a store's id, job 78), `contact_ok` (true, false). Never the note's text |
| `item_categorized` | the server confirmed an add from the app (job 32a); once per added item, also after a retry whose first answer was lost; not for a restored deletion | `via`: how the server chose the category (`items.categorized_via`): `household` (a correction of this household, also for the item's spelling variants and synonyms), `exact` (the dictionary, also after folding spelling: Karrotten), `synonym` (Paradeiser), `fuzzy` (a typo: Schokolde), `fallback` (Sonstiges), `picked` (the add brought another category than the guess). Never the name or the canonical key |
| `dedupe_hint_shown`, `dedupe_hint_merged`, `dedupe_hint_ignored` | job 32b's duplicate hint ("Möhren steht schon auf der Liste"): `shown` when the snackbar shows, then once either `merged` (Zusammenführen) or `ignored` (any other close); the merge's undo sends nothing. Listed by 32a, sent by `ListCubit` since 32b | `actor_role`, `household_size`. Never the item names |
| `purchase_completed`, `purchase_refunded` | server only, after store verification (see Purchases) | `product_id` (`com.hummlist.app.yearly`, `com.hummlist.app.lifetime`), `premium_source` (`yearly`, `lifetime`; job 49, absent on earlier events, which are all Lifetime), `price`, `currency`, `app_store` (`apple`, `google`), `country`, `net_amount` when known, `transaction_ref` |
| `purchase_restored` | server only | `product_id`, `app_store` |
| `siri_add` | server only (job 51): a Siri add reached the `voice` function, signed in with the app's Siri credential or a Shortcut's PAT; once per request, after authentication, for a user whose newest consent answer is yes (the Alexa lookup) | `result` (`success`, `fail`), `reason` (`added`, `nothing_added`, `no_text`, `too_long`, `nothing_understood`, `server`, `premium_required` (job 50: the household is locked); `no_household` is allowed but not sent yet), `language` (`en`, `de`), `source` (`native`: the Siri credential, `shortcut`: a PAT), `count` (items understood, 0 to 30). Never a name or the text |
| `siri_read` | server only (job 51): "What's on my Hummlist?" (`mode: read`) through the `voice` function, same rules as `siri_add` | `result`, `reason` (`read`, `server`, `premium_required` (job 50); `no_household` allowed, not sent yet), `language`, `source`, `count` (open items). Never a name |
| `integration_blocked` | server only (job 50): a household without Hummlist Premium used Siri, MCP or the API (job 73) while the server's `integration_lock` switch is on and was refused; at most once an hour per household and integration (`integration_blocks`), for a caller whose newest consent answer is yes (the Alexa lookup). Off while the switch is off | `integration` (`siri`, `mcp`, `api`; Alexa stays free since job 72, so `alexa` is refused) and the household id. Never what was said, a tool name or its arguments |
| `paywall_viewed` | job 50: the Premium page showed a plan with its store price to a household that can buy it; once per visit. Never with the switch `premium_offer` or `REVENUECAT_PURCHASES` off (the page offers nothing then) | `entry_point` (`more`: More's row, `integrations`: the integration settings' Buy) |
| `review_prompt_requested` | job 155: the app asked the store for its rating prompt (`ReviewPrompt.requestIfDue`) after a completed trip in a public store build, every gate passed (`app/lib/review/review_gates.dart`) and the store had a prompt; at most twice per version, three times a year. The store decides whether it shows and never says, so this counts requests, not prompts shown. iPhone release builds count as store builds, so TestFlight installs send it too, although Apple shows nothing there (their counters also start the 120-day cooldown, which carries over when a tester installs the App Store build); filter internal installs before reading it. More's "Hummlist bewerten" opens the store listing and sends nothing | none |

Rules that keep it one event per user action (AC3, AC9):

- Events fire where the user acts (`ListCubit.tick`, `addParsed`, `readd`, the reorder methods,
  `SessionCubit.createHousehold` and `join`), never where ops are sent. An op retried after a
  reconnect, a realtime echo, or a resync sends nothing.
- Undo sends nothing: the tick has no snackbar since job 29b, and a tap on the item under "Zuletzt
  verwendet" within 10 minutes of the tick (`ListCubit.undoWindow`, the window in which
  `suggest_items` drops the purchase too) is its undo, no `item_added`; the add sheet's undo deletes, a
  restored deletion re-inserts; none is an event. Ticking again after an undo is a new action and
  sends a new `item_ticked`.
- A tick of an item that is not on the list, an add of something already on it, a reorder that
  leaves the order as it was, one refused offline, or one the server rejected: nothing.
- Hiding a category in a store's layout is not a reorder.
- MCP and Siri adds and ticks are not counted (PM, 2026-10-25): the app only. Alexa adds are
  (Spec #7, job 31): see "Alexa" below.
- `item_categorized` is the one list event sent on the server's answer, not on the tap: only the
  server knows how it categorized. An op is acknowledged once, so it is still one event per add.

Adding an event (jobs 21 and 22): add it to `eventCatalog` with a rule per property, a case to
`app/test/analytics/events_test.dart`, and a row here. Free text can't be added by accident: a
property needs an explicit rule (`OneOf`, `IntIn`, `IsBool`), and `checkContext` refuses any other
key. Server events: `serverEventCatalog` in `telemetry.ts`.

## What the SDKs add (job 44)

The SDK adds properties after our `beforeSend`, so the allow-list does not cover them:

- **Web (posthog-js)**: only what `webEventKeys` admits: `$os`, `$os_version`, `$browser`,
  `$browser_version`, `$browser_language`, `$device_type`, `$screen_height`, `$screen_width`,
  `$viewport_height`, `$viewport_width`, `$timezone`, `$lib` (`posthog-flutter`),
  `$lib_version`, `token`, `distinct_id`. Never the URL, path, referrer, user agent, session
  or device id. posthog-js keeps everything in memory: no cookie, no localStorage.
- **iOS (posthog-ios)**: `$app_name`, `$app_version`, `$app_build`, `$app_namespace`,
  `$is_testflight`, `$is_sideloaded`, `$device_manufacturer`, `$device_model`, `$device_name`
  (the model, such as "iPhone", not the name the user gave the phone), `$device_type`,
  `$is_emulator`, `$os_name`, `$os_version`, `$screen_width`, `$screen_height`, `$locale`,
  `$timezone`, `$network_wifi`, `$network_cellular`, `$lib`, `$lib_version`, `$session_id`
  (random, in memory, new after 30 minutes idle), `$is_identified`, debug counters.
- **Android (posthog-android)**: the same app, device, OS and screen properties plus
  `$screen_density`, `$network_bluetooth`, `$network_carrier` (the mobile network's name) and
  `$user_agent`/`$raw_user_agent` (the system HTTP agent: Android version and device model).
- **Linux desktop** (fg only): app name and version, OS, screen, time zone, session id.

Neither native SDK lets Dart strip these (the plugin passes no native `beforeSend`), which is
the upstream issue drafted in NEEDS_LEAD "Job 44". The flag request (`/flags`) carries the install
id, the SDK's device id (the same id), the time zone and the SDK's name and version.
`privacy_scan.sql` lists all of them, so anything else that shows up is a finding. The context
is also registered as super properties, so what the native SDKs build themselves (crash
reports) carries `install_id`, `household_id`, `is_internal` and `$geoip_disable: true` too.

## Alexa (job 31)

An item added through the Alexa skill is `item_added` with `source: alexa`, `actor_role` and
`household_size`, sent by the `alexa` edge function (`serverEventCatalog` in `telemetry.ts`, which
allows nothing else), once per item that was not on the list yet.

Consent is per install and lives on the device, so the app tells the server each install's answer
(`record_analytics_consent(p_install, p_consent, p_internal, p_answered, p_text_version)`, table
`analytics_consents`, no client may read it): when the user answers, switches it under More, marks the install internal,
or signs in (an account new on an install that already answered). A no is recorded under the
install id it had before job 33b's no deletes it, or, for an install that never had one, under the
nil UUID. An answer the user gives is always their newest; a start or sign-in only records a new or
changed answer, so it never outranks a newer answer on another device. The function
counts an Alexa add only while the user's newest answer is a yes to the current consent text
version (above), with that install as
`distinct_id` and its internal mark as `is_internal`; otherwise nothing is sent. A build without a
key never records an answer, so its users' Alexa adds are never counted. Item names, the
utterance, Alexa's user id and tokens are never sent.

## Never sent

Item names, quantities, brands, details, category or store names, household names, display
names, e-mail addresses, invite codes, tokens, request bodies, IP addresses, GeoIP. The allow-list
makes them impossible as event properties; `privacy_scan.sql` checks the project after real data
arrives (AC4, the lead runs it).

## `is_internal`

True when any of these holds (`isInternal`, `app/lib/analytics/internal.dart`):

- a debug or profile build, or a Vercel preview deployment (`ANALYTICS_INTERNAL_BUILD`, set by
  `scripts/vercel.sh` for every deployment but production);
- the install is marked internal: a long press on the version line under More (a snackbar says
  so; "Interne Installation" shows below it, with a "Testfehler senden" button for error
  tracking);
- the household is in `ANALYTICS_INTERNAL_HOUSEHOLDS` (Peter's family; a build define, not in
  code);
- the user's e-mail domain is a reserved test domain (`.test`, `.invalid`, `.example`,
  `.localhost`, `example.com/.net/.org`: the fixtures' `fg.test` and `fg-test.invalid`, e2e's
  `example.test`) or in `ANALYTICS_INTERNAL_EMAIL_DOMAINS`. The e-mail is read on the device only.

Server events take it from the `ANALYTICS_INTERNAL` function secret (true only for local proofs).
Every gate query drops every event of an install or household that **ever** sent
`is_internal = true` (`internal.sql`, AC10), so a phone marked internal late, or a tester in a
household, leaves no trace. PostHog cohorts need person profiles, which the app does not create,
so the filter is this pair of lists in each query rather than a saved cohort.

## Error tracking

- **App, Dart:** `reportUncaughtErrors` hooks `FlutterError.onError` (still presented as before)
  and `PlatformDispatcher.instance.onError`, and `main` runs in a zone; all three hand uncaught
  errors to `Analytics.captureException`, under the same rules as events (consent, signed in,
  `is_internal`). It hands the error to posthog_flutter's `captureException`, which builds
  `$exception_list` (type, value, mechanism, raw frames; on the web each frame's `chunk_id`);
  `beforeSend` then puts our readable type and scrubbed message into the first item, gives every
  cause `<redacted>`, keeps code locations only in frames, and drops the rest (the SDK's
  `flutter_error_details` included). The SDK's own Dart error hooks stay off: they would hand
  `beforeSend` strings, and the scrubber needs the error. An `AsyncError` is unwrapped.
- **App, native:** `captureNativeExceptions` and `captureNativeCrashes` are on. iOS: uncaught
  NSExceptions, Mach exceptions and signals through PLCrashReporter (experimental at PostHog),
  sent at the next launch. Android: uncaught JVM exceptions, and from Android 12 native (NDK)
  crashes read from the system's exit records at the next launch. Both need the project's
  exception autocapture setting (on since job 19).
- **Scrubbing** (`scrubMessage`): errors the Dart runtime and Flutter raise themselves (type,
  range, null-check, state, layout errors) keep the shape of their message's first line, at most
  120 characters: anything quoted, e-mail addresses, URLs, UUIDs and numbers are replaced, and
  every word outside the runtime's and Flutter's own error templates becomes `<w>`, so
  `StateError('cannot parse Hafermilch 2 Liter')` reads `Bad state: cannot <w> <n> <w>`. The
  word list is the edge functions' (`telemetry.ts`) plus Dart's and Flutter's. Every other error (a Postgres
  error echoing a value, a format error quoting its input, the app's own exceptions) keeps only a
  code that looks like one (`23505`, `invalid_invite`) or `<redacted>`. Frames carry code
  locations only; a device path keeps its file name.
- **Readable traces.** iOS and Android release builds are not obfuscated (no `--obfuscate`, no
  `--split-debug-info`), so Dart frames name their functions and files. On the web, Safari and
  other non-Chromium browsers run `main.dart.js`: with `POSTHOG_PERSONAL_API_KEY` and
  `POSTHOG_PROJECT_ID` in the Vercel project, `scripts/vercel.sh` builds with `--source-maps`, runs
  `posthog-cli sourcemap process` (chunk ids into `main.dart.js`, the map uploaded, then deleted
  from the deployment), and posthog_flutter sends each frame's `chunk_id`, so PostHog maps it
  back to Dart. Chromium runs the wasm build (job 28): its frames name Dart functions but carry
  no lines, and PostHog has no wasm symbolication.
- **Gaps** (job 44), what the SDKs do not cover or what we cannot shape:
  - **Native crash reports are not scrubbed.** They are built natively and never pass the Dart
    `beforeSend`: an NSException reason or a Java exception message goes as the platform wrote
    it. The app's own native code is two small speech checks; plugin crashes carry technical
    messages. Upstream draft in NEEDS_LEAD "Job 44".
  - **iOS keeps its crash handler after an off.** PLCrashReporter's signal handler cannot be
    removed once installed, so a crash after switching off is written to disk and sent if the
    user says yes again later (read in posthog-ios, not observed). Android does not install its
    handlers while the SDK is off; a native crash from that time is read from the system's exit
    records after a later yes (inferred).
  - **Native symbols.** iOS dSYMs and Android mapping or `.so` symbols are not uploaded (no
    obfuscation, so Dart frames read; native frames of a native crash stay addresses). The
    upload needs PostHog's Xcode build phase and Gradle plugin with the personal key on CI, a
    release-pipeline change left for a later job.
  - **No isolate hook.** The app spawns no isolate; errors in the main isolate reach the zone or
    `PlatformDispatcher`.
  - **Web:** `PlatformDispatcher.onError` does not exist there, so uncaught async errors arrive
    through the zone only; release builds minify type names, so types outside `errorType`'s list
    read as `minified:…` (upstream draft in NEEDS_LEAD).
  - **Linux and Windows:** no native crash capture (fg's Linux app only).
- **Edge functions:** every function is wrapped in `withTelemetry(<name>, handler)`: an uncaught
  exception is reported (tagged `function_name`) and answered with 500, and the voice and account
  functions also report the failures they catch and answer with 500. The event is sent before the
  response returns (3 s cap) and never carries the request, headers, tokens or item text. Its
  `distinct_id` is `edge-function-<name>`: no user, so no consent is involved (DECISIONS Job 19).
  It stays on its own sender (DECISIONS Job 44, item 16).

## Feature flags (job 44)

Runtime toggles are PostHog feature flags, read in one place: `Analytics.flags.isOn('<key>')`
(`Flags`, a cubit, so a widget can `select` it). Nothing else in the app reads PostHog flags.

- **Off unless PostHog said on.** `isOn` is false for an unknown key, before the yes (the SDK
  does not run, so no flag request is made), after a no (every flag back to off at once), in a
  build without a project key (CI, fg, local debug), and offline until a first answer. After
  the first answer the SDK serves what it received last, also offline and at the next start
  (native SDKs keep it on disk; posthog-js asks again at every page load).
- **Only installs that said yes to the current consent text get flags.** The flag request
  carries the install id, so a rollout through a flag never reaches users who declined, nor an
  install whose yes was given under an older text (no `/flags` until the new yes; Peter kept the
  flag lookups on 2026-11-01 instead of PR #164, which stays unmerged). A change that must reach everyone
  ships without a flag.
- **Forcing a flag locally.** `--dart-define=FLAGS_ON=public-api` (comma-separated keys,
  `Environment.flagsOn`) turns flags on whatever PostHog serves, only in a build whose
  `POSTHOG_HOST` is not PostHog EU (local, fg, e2e and verify-hummlist builds); store and
  Vercel builds ignore it (`startAnalytics`, `Flags.forced`).
- **Reading a flag sends nothing** (`sendFeatureFlagEvent` off, no `$feature_flag_called`).
  Flags are read with `getAllFeatureFlags()` after the SDK starts and whenever it reports new
  ones.
- **Keys and rollouts live in PostHog** (project 319492); the Lead creates them. No flag exists
  yet. A flag gates code paths only; it never gates consent, data or legal texts.
- **`releases/flags.json` is not this.** It only says which changelog items wait for a rollout
  or a hold (job 40, docs/CHANGELOG.md, "Gated items"). A feature behind a PostHog flag gets its
  key there too (`"rollout": "off"`, `partial`, `full`), set by hand when the PostHog rollout
  changes, so its changelog item goes public once everyone has it.

## Configuration

| Name | Where | What |
| --- | --- | --- |
| `POSTHOG_PROJECT_API_KEY` | app define (Vercel env, release secret), function secret | the `phc_` key; empty = off |
| `POSTHOG_HOST` | app define (Vercel env, release variable), function secret | `https://eu.i.posthog.com` |
| `ANALYTICS_INTERNAL_HOUSEHOLDS` | app define (Vercel env, release variable) | Peter's household id(s), comma-separated |
| `ANALYTICS_INTERNAL_EMAIL_DOMAINS` | app define (optional) | more internal e-mail domains |
| `ANALYTICS_INTERNAL_BUILD` | app define (set by `scripts/vercel.sh` outside production) | every event internal |
| `ANALYTICS_HOUSEHOLD_GROUPS` | app define | `true` sends `$groups`; off until Peter buys group analytics |
| `ANALYTICS_INTERNAL` | function secret | `true` marks server events internal |
| `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_PROJECT_ID` | Vercel env (production) | source-map upload; error-tracking write scope, Einkauf only |

## The insights (AC4-AC10)

The HogQL lives in `analytics/queries/`; the Engineering Lead creates the insights from it in
project 319492 through the PostHog connector and runs `privacy_scan.sql` after the first real
events. The two job 43 paying queries are not created yet; the Lead adds them there too.
`analytics/metrics.ts` computes the same metrics in TypeScript, step by step like the
SQL, and `analytics/metrics_test.ts` checks them on `analytics/fixtures.ts`: Berlin week edges
(Sunday 23:30 UTC is Monday in Berlin), a purchase after day 35, a refund in the next month, a
restore, an install marked internal late, a test account and Peter's household; for job 43
(`payingEvents`) a household with two purchases, a refunded one, a tester household, a purchase
on day 40, one at 23:30 UTC on a Sunday and a buyer without consent; for job 49
(`premiumEvents`) Yearly only, Lifetime only, both in one household, a refunded Lifetime next to a
kept Yearly, a refunded only purchase, a Sandbox Yearly, a purchase without `premium_source` and
the yearly `product_id` without it, a year on inside and past the 379 days. It also checks
that every gate query carries the internal filter. The functions gate runs it.

Definitions:

- **Weeks** are Monday to Sunday in Europe/Berlin (`toStartOfWeek(…, 1)` on Berlin time);
  months are Berlin calendar months.
- **Install week** is the Berlin week of an install's `first_open` (its first consented sign-in).
- **Day 35** is 35 × 24 h after `first_open`. A purchase refunded since (same `transaction_ref`)
  does not count.
- **Household retention:** a household starts with its first event (`household_created`,
  `invite_accepted`, an add or a tick); its cohort is that Berlin week. It is active in period k
  when it added or ticked between start + k·7 days (weeks) or start + k·30 days (months) and the
  next period. Fixed-length months give every cohort the same windows. Weeks 0-12, months 0-11:
  the free plan keeps a year of data (Peter's override, 2026-10-25); month 12 and beyond need the
  paid retention Peter plans to buy before year end.
- **Paying household** (jobs 43 and 49): a household with a `purchase_completed` of either
  Premium product (`com.hummlist.app.yearly`, `com.hummlist.app.lifetime`, one entitlement) the
  store has not refunded since (same `transaction_ref`; a refund at any time takes it back, also
  for the weeks before it). A refund takes back only its own purchase: the household's other
  purchases still count. Premium unlocks the whole household (model A), so several purchases in
  the same household count once. `paying_households_d35.sql` counts a household when its first
  such purchase came within 35 × 24 h of the household's start (as in household retention).
  `paying_share_wah.sql` counts a household as paying in a week when one such purchase covers
  it:
  - **Lifetime** (`premium_source` `lifetime`, or no `premium_source` and not the yearly
    `product_id`: every purchase before job 49) covers every week from the Berlin week of the
    purchase.
  - **Yearly** (`premium_source` `yearly`, or the yearly `product_id`) covers the Berlin weeks
    from the purchase's week through the week that contains the purchase + 379 days (365 days
    and 14 days' grace for a late renewal).
- **The Yearly window is an approximation** (job 49). A renewal sends no event and there is no
  expiry event (a new event would need a privacy-policy change), so the query cannot see whether
  a subscription is still running. It errs both ways: a household that renews is undercounted
  from week 380 days after its first purchase on, and a household that cancels within its first
  year (no refund) is overcounted until that year and the grace end. Before the first renewals
  are due (a year after launch) only the overcount applies. PostHog's free plan keeps a year of
  events, so a purchase older than that drops out of both queries anyway, Lifetime included.
- **Kill gate** (Peter, 2026-10-31, model A): in the Berlin week that contains day 35 after
  launch, `paying_share_wah`'s `share_percent` is at least 2. `paying_households_d35` is the
  cohort view of the same question.
- **Net revenue:** completed minus refunded `net_amount`, in the month each happened; restores
  add nothing. Gross (`price`) the same way.

## Purchases (AC8)

Hummlist Lifetime is sold since job 25 (sandbox until Peter's store setup, docs/PURCHASES.md);
since job 43 RevenueCat verifies it and calls our `purchases` function. Since job 49 Hummlist
Premium Yearly is sold next to it under the same entitlement; `premium_source` on the purchase
events says which product granted it. Revenue reaches PostHog only from
that function, after RevenueCat confirmed the purchase:

- **Who.** The app sends no install id or price. The function sends an event only for a buyer
  whose newest analytics answer in the app is yes (`analytics_consents`, job 31), under that
  install id, with the household the purchase unlocks. No answer or a no: no event.
- **Which.** `purchase_completed` once per store transaction, when both RevenueCat's webhook
  record and the buyer's claim from the app are in (whichever arrives second; without a claim the
  buyer is unknown and nothing is sent); `purchase_refunded` once, when RevenueCat reports the
  refund (`CANCELLATION`) of a purchase with a known buyer. `purchase_restored` is no longer sent
  (a RevenueCat restore produces no event for us); it stays in the catalog. Properties as
  in the table above (`sendPurchaseEvent` in `_shared/purchases.ts`, allow-listed in
  `telemetry.ts`); `transaction_ref` is a hash, never the store's id.
- **Sandbox is never revenue.** A Sandbox transaction (TestFlight, Apple sandbox testers, App
  Review, Play license testers) is sent with `is_internal: true`. The internal filter then drops
  that whole household from every gate insight (`analytics/fixtures.ts` H8).
- **Amounts.** RevenueCat's event carries the price in the purchase currency, the currency and the
  country code; no tax, so `net_amount` uses the country's VAT rate.
- **Net amount** (`netAmount`): the store-reported tax (Google's Orders API) or else the country's
  VAT rate (DE 19 %, AT 20 %, CH/LI 8.1 %), then the store fee (15 %, both stores' small-business
  rate; 30 % above $1M). Unknown country and no tax: no `net_amount`. It is an estimate; the real
  proceeds are in App Store Connect's and Play Console's monthly financial reports, to reconcile
  monthly.
- **Paying households undercount** (job 43). A buyer who declined analytics, or whose claim never
  reached us (app killed right after the purchase), sends no `purchase_completed`, so their
  household never counts as paying, even when another member said yes. Both paying queries are a
  lower bound (`analytics/fixtures.ts` H15).
- **Tester households** (job 43; since 20261101150000 a RevenueCat promotional grant for the
  household, docs/PURCHASES.md "Testers"). A purchase in a household with a promotional grant
  (testers, App and Play Review) is sent with `is_internal: true` too (`household_internal`). The
  app sends every event of a household whose rows include a promotional grant with
  `is_internal: true`, so the internal filter drops the household from both the numerator
  and the denominator of the paying queries (`analytics/fixtures.ts` H12).
- `recordPurchase` and `FakePurchaseVerifier` remain job 19's harness for the same mapping.

## Verifying

- `flutter test app/test/analytics` (events, consent gate, the SDK set up only after the yes and
  closed at a no, the setup arguments, payload, internal rules, scrubber and error reports
  through the SDK, the uncaught-error hooks, flags, list and session events, consent flow, More
  switch). The tests run the real `Posthog()` facade and its `beforeSend` against a recorded
  method channel (`NativePostHog` in `fakes.dart`): what they see is what iOS and Android would
  receive. `deno test` in `supabase/functions` (`telemetry_test.ts`, `purchases_test.ts`, voice
  reporting) and in `analytics/`.
- `e2e/tests/analytics.spec.ts` drives the web build against the local stack with a fake
  collector on the PostHog host that speaks posthog-js' wire format (`/e/`, `/flags/`; remote
  config refused as the CSP refuses it): sign-in → consent → onboarding or list (with
  screenshots), zero requests and posthog-js not even fetched before consent and after
  declining, nothing after switching off, one event per action, only allow-listed keys, no
  PostHog cookie or storage, no list text or invite code in any request. Every other spec
  answers the consent through `signUp` or `answerConsent` (declined).
- Native: fg's Linux app with `FG_POSTHOG_HOST` against `cli/posthog_collector.ts`
  (`.cursor/skills/verify-family-groceries/features/analytics.md`); job 44's run is in
  `docs/screenshots/44/native-linux-collector.txt`.
- Manual proofs against project 319492 (never from CI): `e2e/analytics-proof.mjs` (AC11, a local
  release web build raising the internal test error) and `analytics/proofs/edge_exception.ts`
  (AC12). Steps in `.cursor/skills/verify-family-groceries/features/analytics.md`; evidence in
  `docs/screenshots/19/`.
