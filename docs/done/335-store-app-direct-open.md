# Job 335: chain apps open directly on iPhone

Peter (build 1439): EDEKA and Lidl opened the App Store page although both apps were installed.
The iPhone app now opens the chain's app directly for 63 of the 68 app rows (21 before).

## What changed

- **iOS plan** (`app/lib/list/store_app.dart`, `storeAppPlan`): universal link (app only), then the
  bare root of the app's URL scheme (`edeka://`, `LaunchMode.externalApplication`), then the App
  Store. Nothing is sent with the scheme (Legal N-296). Android and the web app are unchanged.
  Info.plist and the native projects are unchanged.
- **Registry** (`supabase/retailers/retailers.json`): a `scheme` per app (null where no evidence),
  14 more first-party universal links (OS2), sources in each entry's `note` and `sources`. New
  migration `supabase/migrations/20261121063121_retailers_data.sql`, app copy
  `app/lib/list/retailer_registry.g.dart`, per-app table `supabase/retailers/coverage.md`
  (`scripts/retailers.ts --coverage`; `--check` keeps it current).
- **Evidence tool**: `tool/retailers/app_schemes.py` reads the schemes from each app's current
  APK manifest (apkpure, else Aptoide; nothing from the APK runs).
- **Analytics (OS3)**: `store_app_opened` already carries the context's `platform` (`ios`,
  `android`, `web`), so no new property; the insight query is
  `analytics/queries/store_app_opens.sql`. A test now fails when an event's rules name a context
  key (review 0: an event-level `platform` would have been overwritten by the context's). The runner's PostHog key
  cannot create insights, so the Lead creates it (NEEDS_LEAD).

## Coverage

| | App rows (68) | Apps (59) |
| --- | --- | --- |
| Before | 21 (universal link) | 21 |
| After, universal link | 43 | 35 |
| After, scheme only | 20 | 19 |
| After, neither | 5 | 5: E.Leclerc, Dirk, Biedronka, Żabka Jush, Esselunga |

EDEKA: `edeka://` (Android manifest). Lidl Plus: `https://app.lidlplus.com/`, then `lidlplus://`.
Kaufland: `com.kaufland.iosapp://`. 3 schemes have iOS-side evidence (Jumbo, dm, Dia); the others
come from the Android app, so whether the iOS app registers the same scheme is unproven until a
phone tries it. A wrong scheme falls through to the App Store.

## Verification

- iOS Simulator probe (iOS 18.6 and 27.2, the app's url_launcher versions, no
  LSApplicationQueriesSchemes): an installed third-party app's scheme opens it and `launchUrl`
  answers true; a missing app answers false and nothing shows; `externalNonBrowserApplication`
  refuses custom schemes. Runs https://github.com/trost-systems/snacklist/actions/runs/44876062114
  and https://github.com/trost-systems/snacklist/actions/runs/44874758450, screenshots in
  `docs/screenshots/335/`, probe source in `docs/screenshots/335/probe/`. iOS 17: no runner has it.
- `scripts/retailers.ts --verify` (online, all countries): 68 apps verified, 0 failed.
- Unit tests: `app/test/list/store_app_test.dart` (the iOS plan with a scheme, both, neither; the
  run falls through; a dotted scheme), `retailer_test.dart`,
  `events_test.dart`, `scripts/retailers_test.ts`.
- Not done: no phone. Which screen each link or scheme opens, and the 20 Android-sourced schemes on
  iOS, need a tester's iPhone (Peter: EDEKA, Lidl on TestFlight).

## Ship

Flag `open-store-app` (on for internal testers). Expected in the first green main TestFlight build
after the merge (above 1439).

## Review 0

- Must fix: `store_app_opened`'s own `platform` was overwritten by the context's `platform` on every
  event (`Analytics.track` sends `{...properties, ...context}`), so `iphone_browser`/`other` never
  arrived. Removed; the guard test in `app/test/analytics/events_test.dart` ("no event names a
  context key") fails on that mutation (checked by putting the rule back).
- Nice to have, done: dotted-scheme test, "certificate subject" wording, README known gaps (short
  schemes, unverified certificate subjects) and the shared-scheme rule worded to match Carrefour PL.
