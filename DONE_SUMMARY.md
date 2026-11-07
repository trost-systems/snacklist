# Done summary

- Job 1b, Sign in with Google and Apple: [docs/done/01b.md](docs/done/01b.md)
- Job 2, classifier and stores: [docs/done/02.md](docs/done/02.md)
- Job 3, MCP server, OAuth 2.1, personal access tokens: [docs/done/03-mcp-oauth-tokens.md](docs/done/03-mcp-oauth-tokens.md)
- Job 4, Siri endpoint, in-app dictation, release setup, final pass (whole-project overview and everything that needs Peter): [docs/done/04-voice-release.md](docs/done/04-voice-release.md)
- Job 5, verification skill and the fg CLI: [docs/done/05-verification-skill.md](docs/done/05-verification-skill.md)
- Job 3b, MCP follow-ups: [docs/done/03b.md](docs/done/03b.md)
- Job 2b, follow-ups to jobs 2 and 5 (finished and landed by 02c): [docs/done/02b.md](docs/done/02b.md)
- Job 8, who added it, new since you looked, usuals: [docs/done/08-who-added-usuals.md](docs/done/08-who-added-usuals.md)
- Job 4b, voice follow-ups (Linux relaunch session, on-device dictation, offline-start and social-sign-in flakes): [docs/done/04b-voice-followups.md](docs/done/04b-voice-followups.md)
- Job 7b, Vercel hosting loose ends (dotted deep links, APP_URL, NEEDS_PETER cleanup): [docs/done/07b-docs-followups.md](docs/done/07b-docs-followups.md)
- Job 12, structural lints and migration/RLS guards (`scripts/lint.sh`): [docs/done/12-lints-schema.md](docs/done/12-lints-schema.md)
- Job 9, in-app account deletion and data export: [docs/done/09-account-deletion.md](docs/done/09-account-deletion.md)
- Job 13, keepalive for the free Supabase project, deploy smoke test, edge-function rollback: [docs/done/13-ops-keepalive.md](docs/done/13-ops-keepalive.md)
- Job 11b, job 11's loose ends (PR description as landed body, model trailer from MODEL_CO_AUTHOR, MERGE_WAIT_MINUTES check, list.spec undo-snackbar flake): [docs/done/11b-ci-followups.md](docs/done/11b-ci-followups.md)
- Job 24a, guides site on hummlist.com (`site/`, its own Vercel project): [docs/done/24a-guides-site.md](docs/done/24a-guides-site.md)
- Job 17b, hide stores with no items on the list (they show only during an item drag, as drop targets): [docs/done/17b-hide-empty-stores.md](docs/done/17b-hide-empty-stores.md)
- Job 29c, swipe left opens edit instead of delete; no item action needs a hold; a finger hold tolerates 18 px of drift (plus the review follow-up: recipes and fg help): [docs/done/29c-swipe-edit.md](docs/done/29c-swipe-edit.md)
- Job 29b, no undo snackbar on a tick; "Zuletzt verwendet" shows the list's own rows, a tap puts an item back: [docs/done/29b-recently-used.md](docs/done/29b-recently-used.md)
- Job 29d, More: Zugänge (`/more/access`) and Konto (`/more/account`) on separate pages, old `/settings` links redirect: [docs/done/29d-more-access-account.md](docs/done/29d-more-access-account.md)
- Job 29a, fixed-height top bar (the sync icon no longer moves the list), no household name or item count on the list: [docs/done/29a-topbar-header.md](docs/done/29a-topbar-header.md)
- Job 32a, spelling variants, synonyms and typos in the classifier (Spec #8 Part A), `items.canonical_key` for 32b, `item_categorized` analytics: [docs/done/32a-synonyms-classifier.md](docs/done/32a-synonyms-classifier.md)
- Job 49, Hummlist Premium as a yearly plan and Lifetime under one entitlement (lifecycle webhook, `household_has_premium`, Premium page with the store's own prices, Legal Review K.13 must-fixes, price drift check): [docs/done/49-premium-yearly.md](docs/done/49-premium-yearly.md)
- Job 50, integration lock: Siri, Alexa and MCP need Hummlist Premium behind the server switch `integration_lock` and the app define `INTEGRATION_LOCK` (both off): [docs/done/50-integration-lock.md](docs/done/50-integration-lock.md)
- Job 63, Home Screen widgets on iPhone (WidgetKit) and Android (Glance) with home_widget, held (`home-widgets`) and waiting for Apple portal steps before merge: [docs/done/63-home-widgets.md](docs/done/63-home-widgets.md)
- Job 70, sign-in without autofocus; Google and Apple first, email behind „Weiter mit E-Mail“: [docs/done/70-login-no-autofocus.md](docs/done/70-login-no-autofocus.md)
- Job 74, one privacy-safe log line per Alexa request: [docs/done/74-alexa-request-log.md](docs/done/74-alexa-request-log.md)
- Job 76, the add-sheet.spec.ts:139 flake: Escape right after an add reopened the sheet on the web (app bug), plus a CI cache for WebKit's apt packages: [docs/done/76-add-sheet-flake.md](docs/done/76-add-sheet-flake.md)
- Job 78, stores and categories under Liste → Anpassen, nothing on the list drags, a compact add sheet, back from joining returns to More: [docs/done/78-list-manage-ux.md](docs/done/78-list-manage-ux.md)
- Job 92, German Siri routing: app-first phrases, spoken names with hints, the SiriKit Lists fallback for any item, and CI profile renewal after the Siri capability: [docs/done/92-siri-german-routing.md](docs/done/92-siri-german-routing.md)
- Job 106, hill climb hc-backend-perf: load harness over the app, MCP and voice hot paths; `suggest_items` keys each name once (list open about 1.5 s -> 0.6 s p95 on 300 open + 5,000 bought), PR DO NOT MERGE: [docs/done/106-hc-backend-perf.md](docs/done/106-hc-backend-perf.md)
- Job 149, item edit sheet: no title, hint or chip icons, Abbrechen instead of Löschen: [docs/done/149-item-edit-sheet-cleanup.md](docs/done/149-item-edit-sheet-cleanup.md)
- Job 151, Baumarkt: seven DIY categories, a Baumarkt store type, 251 DIY words: [docs/done/151-hardware-store-categories.md](docs/done/151-hardware-store-categories.md)
- Job 101, hill-climb hc-strictness: a strict TypeScript/JavaScript lint pack (`tool/lint/ts/`, every Deno lint rule and strict compiler option decided, 114 enforced in the lint gate), score 1030 -> 2 over 241 files, reviews 0 and 1: the type check fails closed, Deno is pinned in `.dvmrc`, every in-scope TS file is type-checked: [docs/done/101-hc-strictness.md](docs/done/101-hc-strictness.md)

## Job 1: foundation (2026-10-22)

PR: https://github.com/peter-trost/family-groceries/pull/1

### What was built

- **Toolchain.** `scripts/bootstrap.sh` installs Docker, the Supabase CLI
  2.121, Flutter 3.47.7 stable, Deno 2.9, gitleaks 8.30, Playwright with
  Chromium, and with `--android` the Android SDK. It also fixes this VM's
  stale `iptables-legacy` FORWARD DROP rule, which silently blocked traffic
  between Supabase containers. `scripts/dev.sh` starts the local stack and
  the web dev server; `scripts/verify.sh` runs every CI gate locally.
- **Schema and RLS** (`supabase/migrations/20261022150000_foundation.sql`).
  Tables: households, household_members (one household per user), invites
  (8-character codes, 14 days), profiles, categories (10 route categories
  plus the fallback "Sonstiges"), stores (dm, Lidl, Edeka) with
  store_category_order, items, item_events. Household creation seeds them.
  Every table is members-only. The RPCs are `create_household`,
  `create_invite`, `join_household` and `leave_current_household`. The
  classifier hook is `classify_item(household, name)`, a keyword stub that
  job 2 replaces. Realtime publishes items, categories, stores, store order
  and households.
- **App** (`app/`). Sign-in with email and password, or with a magic link.
  After sign-in the user creates a household or joins one with a code or a
  `/join/<code>` link. The list screen opens with the "Was fehlt?" field
  focused and the list beneath it. Enter adds an item and keeps focus.
  Items are grouped in route order. Ticking an item offers undo, and ticked
  items appear under "Zuletzt gekauft" for a one-tap re-add. Items can be
  edited (name, quantity, category) and deleted with undo. Duplicates are
  refused. Changes sync live through Realtime. Writes are optimistic,
  idempotent ops that are retried while offline, and the app resyncs on
  reconnect and on resume. All UI strings are German, in `app/l10n/app_de.arb`.
- **CI** (`.github/workflows/ci.yml`). The jobs are gitleaks (full history
  and working tree), Flutter (l10n check, format, analyze, test, web build),
  Deno (fmt, lint, test), pgTAP with `db lint`, and Playwright e2e on a
  local Supabase stack in CI. A `ci-ok` gate job sits on top.
  `supabase-deploy.yml` deploys from main (since job 7 over the Management API
  only, and it fails red without credentials).
- **Docs.** `docs/SPEC.md`, `docs/DECISIONS.md` (22 decisions),
  `docs/NEEDS_PETER.md`, `docs/REUSED_FROM_EMOTELY.md`, `AGENTS.md` (with a
  `CLAUDE.md` symlink) and `README.md`.
- **pstack.** `/setup-pstack` was run non-interactively and wrote
  `~/.cursor/rules/pstack-models.mdc`; see DECISIONS #19.

### How to verify

```bash
scripts/bootstrap.sh
scripts/verify.sh --screenshots docs/screenshots/job-1
```

### Test results (local `scripts/verify.sh`, and CI on PR #1)

| Suite | Result |
| --- | --- |
| gitleaks: full history and working tree | no leaks |
| pgTAP (`supabase/tests`) | 44/44, including the cross-household denial suite |
| `supabase db lint --fail-on warning` | no findings |
| Deno (`supabase/functions`) | 2/2 |
| Flutter analyze (flutter_agent_lints, experimental) | no issues |
| Flutter unit and widget tests | 45/45 |
| Playwright e2e on the Flutter web build and the local stack | 11/11 |

The Playwright tests cover:

- autofocus on open, with the list visible beneath the field;
- add, tick, undo, re-add from history, and persistence across a reload;
- grouping in route order;
- duplicates;
- edit and delete with undo;
- two-browser live sync between two users who share a household through an
  invite code: an add, tick, edit and delete each show up in the other
  browser within 2 s;
- joining through an invite link;
- an offline tick and add that sync after reconnecting;
- RLS across households through the UI, the REST API, RPCs and Realtime;
- sign-in with a password, with a wrong password, and with a magic link
  read from Mailpit.

`flutter build apk --release` works on this box and produced a 56.5 MB APK
signed with the debug key.

Screenshots are in `docs/screenshots/job-1/`.

### Found and fixed along the way

- Flutter web, with semantics on, blurred the add field on Enter. After
  that the field was dead: a second Enter did nothing. Experiments with
  three variants showed the fix: handle a hardware Enter in
  `Focus.onKeyEvent`.
- After a tick, the first tap on the add field took no text. The cause was
  that the focused checkbox element was removed with its row. Fix:
  `ExcludeFocus` around the checkbox.
- Deleting a household cascaded into history writes that pointed at the
  deleted household. Fix: the history trigger skips cascaded deletes.

- The first CI run on `main` failed in e2e: `address already in use` on
  port 54324. Supabase's 543xx ports sit inside the runner's ephemeral port
  range. The follow-up PR narrows that range before the stack starts
  (`job/1-foundation-ci-ports`).
- PR #1 was squash-merged at 18:03 UTC by another process on the
  `petertrost-bot` account (commit author `bot@petertrost.com`), before this
  job's own merge call. The merged tree is the verified head `96c1dc1`.

### Missing or blocked

- **Remote deploy.** `~/groceries-ops/env` is empty, so there is no
  `SUPABASE_ACCESS_TOKEN`. Migrations are not on `jdwqrallbpdbshrdhenk` yet.
  The deploy workflow is ready; the exact steps are in
  `docs/NEEDS_PETER.md`, sections 1 and 2.
- **Hosted Auth URLs and web hosting.** These wait for a public web URL;
  see `docs/NEEDS_PETER.md`, section 3.
- **Offline cold start.** Launching the app offline shows a spinner until
  the network returns; there is no local copy of the list yet. This is a
  deliberate scope call (DECISIONS #11), tracked in issue #3.
- **Repository moved.** The repo now lives at
  `peter-trost/family-groceries`; the GitHub redirect showed this on the
  first push. `~/groceries-ops/COMMON.md` still names `petertrost-bot`.

### Review 0 fixes (branch `job/1-foundation-review-fixes`)

Must fix:

1. **`classify_item` leaked across households.** Fixed by migration
   `20261022190000_classify_item_members_only.sql`: a signed-in caller who
   is not a member of the household gets `not_a_member` (42501). Service
   role and the database itself still classify (MCP and Siri in jobs 3–4),
   and member inserts are unaffected. New pgTAP cases: denied for another
   household, allowed for the own household, denied for anon, allowed
   without a user. Proven to catch the bug: with the fix migration removed,
   test 16 fails; with it, all pass. The Playwright RLS test also calls the
   RPC as the outsider and expects `not_a_member` with no data.
2. **Merge author email.** `main`'s squash commits `26e9d06` and `13dfe23`
   have `bot@petertrost.com`, the account's default email. History is not
   rewritten. GitHub refuses the noreply address as a squash-merge
   `--author-email` (tried: "Invalid email address"), so the new
   `scripts/merge-pr.sh` squashes the PR locally into one commit authored
   `341616691+petertrost-bot@users.noreply.github.com` with the trailers,
   and rebase-merges it once `ci-ok` passes, which keeps the author.
   AGENTS.md and COMMON.md point at it. PR #4 is landed with it. Recorded in
   DECISIONS #24.
   Slip: a failed branch checkout left the shell on `main`, and commit
   `008e2b0` (only `scripts/merge-pr.sh`) was pushed to `main` directly,
   bypassing a PR. It was a fast-forward, not a force-push; it is left in
   place and noted in DECISIONS #24.

Nice to have, also done:

- The add field caps names at 120 characters and the edit sheet caps the
  quantity at 40, so a long paste is trimmed instead of rejected. Covered by
  a widget test.
- pgTAP now covers `join_household`'s destructive path: a sole member who
  joins elsewhere loses their old household and its list, and a household
  with other members survives.
- Offline cold start is ticketed as issue #3.
- COMMON.md has a note about the repo's new owner.
- DECISIONS #26 records that the repo carries no pstack config.
- DECISIONS #27 explains why Node 20 stays on the box.

Results after the fixes (local `scripts/verify.sh`): pgTAP 54/54, Flutter
46/46, Playwright 11/11, gitleaks clean, `db lint` clean.

## Job 3: MCP server, OAuth 2.1, personal access tokens

See [docs/done/03-mcp-oauth-tokens.md](docs/done/03-mcp-oauth-tokens.md).

## Job 7: Vercel hosting, auth config, API-only deploy

See [docs/done/07-pages-auth-config.md](docs/done/07-pages-auth-config.md).

## Job 2b: follow-ups to jobs 2 and 5

See [docs/done/02b.md](docs/done/02b.md).

## Job 11: one CI run per merge, one gate definition, measured CI speedups

See [docs/done/11-ci-flow.md](docs/done/11-ci-flow.md).

## Job 12b: lint and schema-guard follow-ups

See [docs/done/12b-lints-followups.md](docs/done/12b-lints-followups.md).

## Job 13b: nightly encrypted database backups

See [docs/done/13b-db-backups.md](docs/done/13b-db-backups.md).

## Job 20: rename to Hummlist

See [docs/done/20-hummlist-rename.md](docs/done/20-hummlist-rename.md).

## Job 15: design H, part 1 (data, parser, edit sheet)

See [docs/done/15-design-data.md](docs/done/15-design-data.md).

## Job 18: test fixtures and multi-client sync capture

See [docs/done/18-test-fixtures-sync.md](docs/done/18-test-fixtures-sync.md).

## Job 23: weekly releases

See [docs/done/23-release-pipeline.md](docs/done/23-release-pipeline.md).

## Job 26: public MCP URL mcp.hummlist.com

See [docs/done/26-mcp-domain.md](docs/done/26-mcp-domain.md).

## Job 16: design H list

See [docs/done/16-design-list.md](docs/done/16-design-list.md).

## web-release-align: web production follows the store release

See [docs/done/web-release-align.md](docs/done/web-release-align.md).

## Job 27: on-demand e2e on GitHub Actions

See [docs/done/27-ci-e2e-on-demand.md](docs/done/27-ci-e2e-on-demand.md).

## Job 17: design H add sheet, app shell, English

See [docs/done/17-design-add-shell.md](docs/done/17-design-add-shell.md).

## Job 28: WebAssembly web build, iOS Safari tap focus

See [docs/done/28-web-wasm-ios.md](docs/done/28-web-wasm-ios.md).

## Job 19: kill-gate and LTV analytics, error tracking (PostHog EU)

See [docs/done/19-analytics-killgate.md](docs/done/19-analytics-killgate.md).

## Job 30: every green merge to main reaches the internal testers

See [docs/done/30-release-on-merge.md](docs/done/30-release-on-merge.md).

## Job 21: in-app feedback for beta testers

See [docs/done/21-feedback.md](docs/done/21-feedback.md).

## Job 29e: Einstellungen with light/dark/system theme and a language list

See [docs/done/29e-settings-theme.md](docs/done/29e-settings-theme.md).

## Job 32a: spelling variants and synonyms in the classifier

"Karrotten", "Paradeiser", "Schokolde" and "carrots" land with the word they mean on every add
path, through the one database classifier; text stays as typed; a household's correction holds
for the word's variants; `items.canonical_key` is ready for 32b's duplicate hint. Word list:
misspellings 94.2% right, false matches 0.48%; the classifier got faster (p95 about a third of
before). Details: [docs/done/32a-synonyms-classifier.md](docs/done/32a-synonyms-classifier.md).

## Job 22: onboarding: create or join a household, invite a partner (Spec #3)

See [docs/done/22-onboarding.md](docs/done/22-onboarding.md).

## Job 33b: legal fixes in the app

See [docs/done/33b-legal-app.md](docs/done/33b-legal-app.md).

- Job 33a, privacy policy on hummlist.com (/datenschutz, /en/privacy), corrected and published deletion page, error reports scrubbed to their shape (wording approved by Peter, lead merges): [docs/done/33a-legal-site.md](docs/done/33a-legal-site.md)

## Job 33c: self-host CanvasKit and fonts, nothing from gstatic.com

See [docs/done/33c-legal-canvaskit.md](docs/done/33c-legal-canvaskit.md).

## Job 31: Alexa skill "Hummlist" (Spec #7)

"Alexa, sag Hummlist, füg Milch und Eier hinzu" adds to the linked household, read back in German; ReadListIntent reads the list; account linking through Supabase's OAuth server (confidential client, PKCE). Live after the Amazon steps in NEEDS_PETER. Details: [docs/done/31-alexa.md](docs/done/31-alexa.md).
- Job 31b, Alexa skill deployed to the developer account (de-DE, beta running, no testers): [docs/done/31b-alexa-deploy.md](docs/done/31b-alexa-deploy.md)

## Job 24: help and contact page (draft) and the privacy data map

`/support` and `/en/support` on hummlist.com as drafts (banner and noindex on previews, 404 in
production until Peter's OK), More → "Hilfe & Kontakt" (debug/test builds only until then),
`docs/PRIVACY_DATA_MAP.md` for the store privacy forms, stale "Menü" directions fixed in the Siri
texts. The privacy policy itself is 33a's. See [docs/done/24-privacy-page.md](docs/done/24-privacy-page.md).
Fix 1 (review 0): the help page's deletion link now ends in `.html` (the bare path opened the app),
a site test checks app.hummlist.com links and pins the three publish switches together, the data
map follows 33b/33g, the FAQ covers Alexa; Lighthouse mobile 100/100/100 on the preview build.

## Job 32b: duplicate hint with one-tap merge (Spec #8 Part B)

"Karotten" with "Möhren" open is added and the list offers "Zusammenführen"; the merge runs on
the server in one transaction (500 g + 1 kg = 1,5 kg, else "1 Bund + 500 g") and Rückgängig
restores both items exactly. MCP and Siri report the similar item. Details:
[docs/done/32b-dedupe-hint.md](docs/done/32b-dedupe-hint.md).

## Job 34: the first key after a tap on a text field is kept

On the web a key typed right after tapping an unfocused text field was erased by the engine's late hand-over of the DOM input ("rot" for "Brot" in the add field after Schließen). `EarlyKeys` (app-wide, web only) types those keys through Flutter's key events. Before: 1/30 of the original test and 60/60 of the frame-held test failed; after: 0. Details: [docs/done/34-add-sheet-first-key.md](docs/done/34-add-sheet-first-key.md).

## Job 25: Hummlist Lifetime in-app purchase (sandbox)

One non-consumable (`com.hummlist.app.lifetime`, EUR 9.99 in Germany) that unlocks the buyer's
household, verified by the new `purchases` edge function (Apple JWS chain to the pinned Apple root,
App Store Server API with a key, Server Notifications V2; Google Play Developer API, Orders API,
daily voided poll) before `entitlements` unlocks it; More → Hummlist Lifetime in the iOS and
Android app, a note plus the unlock on the web. Inert until NEEDS_PETER/NEEDS_LEAD "Job 25" are
done. Details, tests, screenshots: `docs/done/25-iap-sandbox.md`; design: `docs/PURCHASES.md`.

## Job 25b: Hummlist Lifetime review follow-ups

A receipt the server refuses for good is finished with the store and shown once, not re-sent on every retry and launch. Production-only `PURCHASES_ENVIRONMENTS` is inert, so App Review's sandbox purchases wait instead of being refused. Apple notifications must carry a transaction from their own environment. `scripts/gates/e2e.sh -- <spec>` runs only that spec. Details: [docs/done/25b-iap-followups.md](docs/done/25b-iap-followups.md).

## Job 37: stale "Menü" directions, health comment, debug-entrypoint Zone mismatch

The debug app launches without Flutter's "Zone mismatch" EXCEPTION block, and a regression now fails the launch. The docs point to Mehr → Zugänge, the health comment no longer duplicates the response, and the unused `menu` string is gone. The voice 401 text was already right. Details: [docs/done/37-voice-error-copy.md](docs/done/37-voice-error-copy.md).

## Job 38: hummlist.com guides follow the live store version; public release record

Guides, sections and blocks tagged `since` an unreleased version stay off hummlist.com until a public release; preview shows them with a banner. `releases/releases.json` records public releases (empty today) with History-ready git stats; `public-release-record.yml` appends one and its push redeploys the site. Details: [docs/done/38-site-deploy-versioning.md](docs/done/38-site-deploy-versioning.md).

## Job 39: user-facing changelog (store "What's new" + hummlist.com/changelog) from PR notes

PRs carry a `## Changelog` note (de/en items or `none`), checked by push-pr.sh and the `changelog` CI gate. `scripts/release/changelog.mjs` collects the notes from main's commits into a reviewed draft with App Store and Play "What's new" texts. `record.mjs` moves the draft into the public release record, and hummlist.com/de/changelog and /en/changelog show recorded releases (empty state today). Details: [docs/done/39-changelog.md](docs/done/39-changelog.md).

## Job 40: flag/hold-gated changelog items, pending.json, 1.0 launch "What's new" override

PR notes may add `flag:` / `hold:` lines. `releases/flags.json` decides what is public, and the Alexa skill is held. Held items wait in `releases/changelog/pending.json` (written by `record.mjs`) until their gate opens. `releases/changelog/1.0.0.override.md` is the 1.0 launch "What's new", still a draft for Peter's review. Details: [docs/done/40-changelog-flags.md](docs/done/40-changelog-flags.md).

## Job 43: Hummlist Lifetime as a household-bound unlock (model A), on RevenueCat

A purchase belongs to the household it was bought in, for good: RevenueCat's App User ID is the household, and the server refuses it anywhere else, also after deletion (a tombstone stays 30 days after the purge of its rows). Our own Apple/Google verification is replaced by RevenueCat's webhook, and the SDK starts only on the purchase page with the household id. The purchase screen is off in every build until Peter approves the legal texts. Buy shows only when the household is known to have no Lifetime, and the join screen explains Lifetime around a join, with archiving behind the default-off `HOUSEHOLD_ARCHIVE`. There is DE/EN refund help, tester grants stay with households, members can't read who paid, and two paying-household queries back the kill gate. Details: [docs/done/43-iap-household-a.md](docs/done/43-iap-household-a.md).

## Job 44: all-in on PostHog: posthog_flutter SDK, error tracking, feature flags

The app's hand-written PostHog client is replaced by PostHog's SDK: posthog_flutter 5.58.3, and posthog-js 1.444.0 on the web, vendored and served from our origin. Our guarantees sit on top of it.
- **Consent.** The SDK is set up only after the yes, because native opt-out still makes requests and writes ids. A no closes it and deletes what the native SDK kept on the device.
- **Allow-list.** Every event is checked twice, the second time in the SDK's `beforeSend`, where errors are also re-scrubbed. On the web, posthog-js' own `before_send` strips URL, referrer, user agent, session and device ids.
- **Error tracking.** Native exception and crash capture are on. Gaps are documented.
- **Feature flags.** `Analytics.flags.isOn(key)` is the one place the app reads flags. `releases/flags.json` stays for the changelog.
- **Edge functions.** They keep their own sender; posthog-node was measured and rejected (DECISIONS 44.16).
- **Removed.** The sink, POST, chunk-id and frame-builder code. In `app/lib/analytics`, 383 lines went and 747 came; code and tests overall +1716 / −750.

**Verified.**
- `verify.sh --only gitleaks,lint,functions,fg-cli,flutter,web-prod` passed, flutter 1058 tests.
- Web: the analytics e2e passed 6/6 against a posthog-js collector.
- Native: the Linux app ran against a local collector (`docs/screenshots/44/`).
- iOS and Android: built in CI, not run.

**Open.**
- NEEDS_LEAD "Job 44": Legal Review sentences, store labels, three upstream issue drafts (none filed), flags to create in 319492.

Details: [docs/done/44-posthog-sdk.md](docs/done/44-posthog-sdk.md).

## Job 47: purchase legal fixes (Legal Review K.11) and job 43 review leftovers

RevenueCat's SDK starts only on a tap on "Weiter zum Kauf" or "Kauf wiederherstellen" (no price on the page; the store's sheet shows it). Archived households are deleted 24 months after archiving, with the date in "Archivierte Haushalte", and archiving needs a server switch that is seeded off. Nil-bound sandbox purchases are deleted. What Apple and Google receive and what the SDK keeps on the device were read from the pinned SDK sources and match draft 5a. The deletions route takes a cron secret, routes match exactly, the claim names the purchase's household, and removing a tester clears their mark. The refund help, the bought-twice note and the join warning use Legal Review's R-8 refund texts (H-76), with a link to the FAQ. Nothing is live for users. Details: [docs/done/47-purchase-legal-fixes.md](docs/done/47-purchase-legal-fixes.md).

## Job 51: native Siri (App Intents, English and German)

Siri adds items to the household's Hummlist on iOS 17+ without a Shortcut: "Add to Hummlist" / "Füge etwas zu Hummlist hinzu", then the items, read back only after the server confirmed; "What's on my Hummlist?" reads the list. A session-bound "Siri (dieses iPhone)" credential replaces token copying; the old Shortcut keeps working. Details: [docs/done/51-native-siri.md](docs/done/51-native-siri.md).

## Job 52: the design system (6b Hex Frische with option 6's yellow) in the app, app icon #5

The app wears the locked 6b Hex Frische design: one token source for app and site, cobalt, lemon and mint, Bricolage Grotesque over Inter, lemon hex buttons that sink into their edge when pressed, and app icon #5 Wabenstapel with splash screens on iOS (also as the iOS 26 layered icon), Android and web. A Widgetbook shows every component in every state. On the way it fixes main's flaky add-field tap on the web. The changelog note waits for Peter's TestFlight look (hold `new-design`). Details: [docs/done/52-design-6b-app.md](docs/done/52-design-6b-app.md).
## Job 53: first hummlist.com homepage (landing pages /de and /en), PR #157, not merged

German and English landing pages in the 6b Hex Frische design with design 6's yellow, built by the existing site generator from one copy file (`site/content/landing/copy.yml`), with filmed product stills and three demo-video slots for job 54. `/` now redirects to them by language. Every page shares the new header and footer. The noindex header, the legal texts and every old route are unchanged; there is no pricing and Siri is "coming soon". Checks: 96 site tests, axe 0 violations on 17 pages in 4 modes, contrast passes, Lighthouse accessibility 100. Peter approves and merges (NEEDS_PETER "Job 53"); Launch reviews `site/COPY_NEEDED.md`. Preview: https://hummlist-site-git-job-53-homepage-v1-peter-trost.vercel.app/ (Vercel login). Details: [docs/done/53-homepage-v1.md](docs/done/53-homepage-v1.md).
## Job 54: demo videos for hummlist.com, PR into job 53's branch, not merged

Three silent, captioned loops from the real Hummlist app fill job 53's video slots: adding and ticking off items, one household on three phones syncing live (real measured latency), and a generic AI chat adding and ticking items through the real MCP server. German and English, wide and compact, WebM and MP4 of 0.28 to 0.45 MB each, posters and captions. Made with a capture driver for the Linux build and HyperFrames (`marketing/videos/`). Site checks pass (97 tests, crawl, contrast, Lighthouse a11y 100, mobile perf 94–95). Review 0 fixed: the compact household-sync cut now shows both receiving phones; the English MCP cut's German list is the first item of Peter's check. Peter watches each loop on a phone and approves with job 53 (NEEDS_LEAD "Job 54"). Details: [docs/done/54-demo-videos.md](docs/done/54-demo-videos.md).
## Job 60: Hummlist feature map and how-to clips

verify-hummlist skill (web build + Playwright, launch/doctor/drive/cleanup proven on hz), 23-feature map with FEATURES-FOR-WRITERS.md for Hummlist Launch, hummlist-howto-clips skill (email GIF, MP4/WebM, PNG; quick-add DE+EN proven). Details: [docs/done/60-feature-map.md](docs/done/60-feature-map.md).

## Job 57: list rows without a check box, a polished strike-through, design alignment

PR: see BOARD (title "Job 57: list rows without checkbox, polished strike-through, design
alignment"), not merged by this job; the lead lands it after review. Details:
[docs/done/57-list-tick-align.md](docs/done/57-list-tick-align.md), decisions in DECISIONS
"Job 57", evidence in `docs/screenshots/57/` (also `/workspace/hummlist/research/57-list-tick-align/`).

**Built.** A tap on a row draws a 2 px muted line across the words only (line by line on a
wrapped name), the row turns mint like the site's done row, then closes so the rows below move
up, with an emptied category or store heading closing along; tick after 440 ms (tokens), reduced
motion shows the struck row 260 ms without the close. Rows are checkboxes to screen readers and
announce "<Name> abgehakt" / "<name> ticked off". No list row draws a check box anywhere in the
app or Widgetbook; consent and opt-in check boxes stay hexagons (`HexCheckbox`). Theme: one hex
segmented control System / Hell / Dunkel (Peter 14:20), storage unchanged. Job 56: 29 of its 30
SAFE items (item 6 left to Peter: it reverses his job 29a call). Addendum 5 (Peter's calls on
items 31 to 34): the empty list shows a honey hex with the cart; `StoreBadge` shows the store's
full name in a hex pill (no retailer colours, cobalt rules; a logo variant waits for the Legal
Review); every single-line text field is a hex from one input theme (multi-line rounded, the add
field opted out and tested); a partner's new row is honey. Widgetbook: an auto-ticking "Abhaken (Animation)" story and stories for every new
component.

**Tests.** `flutter test`: 1359 pass (app), 326 (Widgetbook). Local e2e, full suite on the final
build: everything passes except the 7 fake-OIDC specs (`id-token`, `social-sign-in`, onboarding
AC6), which cannot reach the fake provider from containers on the Hetzner box; CI runs them.
Gates gitleaks, lint, flutter, fg-cli pass locally.

**Site follow-up (not done)** (ADDENDUM 1: this PR is app-only)
1. *Scene edits to drop the hex check box* (job 56 item 35). `site/scenes/scenes.css`: delete the
   `.cb` rules and the mint ticked hex (`.item--done .cb`), make `.item` two columns
   (`28px 1fr`) with equal side padding, give `.item--done` the app's done row
   (`--hl-color-mint-soft` fill, text `--hl-color-text-muted`) and a strike as `.name::after`
   over the text width only (2 px `--hl-border-width`, muted). Remove the `<span class="hxp cb">`
   (and `.tick`) from every row in `hero.html` (3 rows), `add-tick.html` (5),
   `household-sync.html` (9); `mcp-chat.html` loses its `.tick` column (four-column grid to
   three). A ready patch from this job's first pass (cobalt-on-accent-soft variant, adjust the
   colours to mint as above): `~/groceries-ops/jobs/57-list-tick-align/site-followup/site-scenes.patch`.
   Effort: about 30 min.
2. *Stills that change*: re-film with `node site/scenes/film-all.mjs hero add-tick household-sync
   mcp-chat` (32 WebP stills: `site/public/media/{hero,add-tick,household-sync,mcp-chat}-{de,en}-
   {wide,compact}[-dark].webp`); `stores` has no rows and stays. Effort: 15 min filming plus
   30 min contact-sheet review.
3. *Demo loops (#163) that change*: all three are real-app footage and now show the old app
   (rows, add bar, chips): `add-tick` (the tick itself: strike, mint, close; its `scene.mjs`
   assumes the 260 ms leave, now 440 ms), `household-sync` (Noah's tick and the add bar),
   `mcp-chat` (the list and add bar behind the chat; its ticks arrive remotely without the
   animation). Re-take with `marketing/videos/` (capture `take.ts`, `build.mjs`, DE and EN, wide
   and compact) after this PR lands: about 2 to 3 h agent time including review.
4. *Job 56 SAFE items touching `site/`*: none; job 56 filed the site work as items 35 and 36
   (above).
5. *Addendum 5 site follow-ups.* Item 32: the scenes show no store badge; once this ships they can
   draw the same hex name pill and the cobalt rule (`scenes.css` `.store-head`), about 30 min plus
   re-filming the stores and hero stills. Item 34: `household-sync.html` drops `.item--arrived`
   (mint plus edge bar) for `.item--fresh` (honey-soft), re-film `household-sync` stills (8), about
   20 min; the household-sync demo loop shows honey once re-taken (point 3).

**Missing / for Peter.** NEEDS_PETER "Job 57": a look at the self-drawn Apple button on an
iPhone; retailer logos for the store badge after the Legal Review; job 56 item 6.
## Job 59: fuzzy suggestions while typing (typos, part of a word, recently used)

Suggestions now find what was meant despite a typo or from part of a word: "Hafermlch" and "milch" both offer Hafermilch. This works on the server (PR #177, merged) and offline on the device, with one shared rule: typos from 3 letters, in-word matches from 4, and prefixes only for shorter input. With the field empty, the add sheet shows the due items and then what was used in the last 30 days ("Zuletzt verwendet"). Tap-to-add, clearing and refocus are unchanged and now locked in by widget and web e2e tests. `suggest_entries` p95 is 29 ms locally and 32 ms on CI, against 21 ms before; a db-gate check fails at 50 ms. Details: [docs/done/59-fuzzy-suggest.md](docs/done/59-fuzzy-suggest.md).
iPhone; job 56's taste calls (items 31 to 34) and item 6.

## Job 58: add your own store (inline in the store picker, Mehr → Läden), PR #176

Households add their own stores right in the add and edit sheets' store options ("+ Neuer Laden": type, Enter, created and picked) or under Mehr → Läden, which now also renames and deletes stores (open items fall back to "Ohne Laden"). Store names are unique per household ignoring case and spacing; a new store starts from the route order with every category. Works live for the partner and over MCP by name. Review 0: onboarding now offers ten common stores to pick (none preselected) plus own ones instead of seeding dm, Lidl and Edeka; Legal's store-name disclaimer stands under Mehr → Läden, in onboarding and on the site's Impressum; households without stores work on MCP, Siri, voice and Alexa. Details: [docs/done/58-add-own-store.md](docs/done/58-add-own-store.md).

## Job 61: typed quantities at the end of a line (2026-11-01)

**Built.** A bare number at the end of a typed or said line is the quantity when it is 1 to 20, follows no size or unit word, is not glued to letters, and the rest is a known name ("Karotten 2", "carrots 2"; not "Windeln Größe 4", "Vitamin D3", "7up", "Büroklammern 100"). "Karotten x2" and "2x Karotten" work too. A suggestion tapped while the rows for the new text load keeps the quantity typed now (the bug Peter hit). Rows show the quantity after the name: "Karotten · 2".

**Where.** Server: `supabase/migrations/20261101230000_trailing_count.sql` (`parse_item` + `is_known_name`), used by MCP add_items, Siri/voice, Alexa and `suggest_entries`; `supabase/functions/voice/parse.ts` hands bare counts to it. App: `app/lib/list/entry.dart` (`parseEntry` with the rule, offline lookups in `lexicon_forms.dart`, generated by `supabase/classifier/client_lexicon.sh`, checked in the db gate), `add_sheet_cubit.dart` (stale rows), `add_sheet.dart` (the hint). Table for both sides: `supabase/tests/quantity_parse.tsv`. Decisions: `docs/DECISIONS.md` "Job 61".

**Verify.** `cd app && flutter test test/list/entry_test.dart test/list/add_sheet_test.dart`; the db gate runs `add_paths_integration_test.ts` (the table through MCP and voice) and `client_lexicon.sh --check`. On the app: recipe `qa-trailing-count` in `.cursor/skills/verify-family-groceries/features/quick-add.md`.

**Results.** Gates lint, functions, flutter, db pass locally on hz. Real Linux app via fg: Karotten 2, Eier 10, "2 Möh" → catalog Mohrrübe 2 stored with their quantities; Windeln Größe 4, Vitamin D3, Büroklammern 100 unchanged. Screenshots in `docs/screenshots/61/`.

**Changed expectation.** `entry_test.dart` 'Eier   10' is now Eier with 10 (was Eier 10, no quantity).

**Open.** None known. Offline typo matching for the known-name check stays server-only (the app matches exact and compound words).
## Job 66: deep links (app.hummlist.com opens the app), PR #188

app.hummlist.com links to the list, the add sheet, a store, the More tab and its pages, and invites open the installed iPhone or Android app, or the web app where it isn't installed; signed out they wait through sign-in (and onboarding) and then open their screen. Details: [docs/done/66-deep-links.md](docs/done/66-deep-links.md).
## Job 67: paywall release readiness, PR #187, not merged

The paywall go-live is now the ordered checklist `docs/PAYWALL_RELEASE.md`, with an owner per step and nothing flipped. The audit with every flag on found 13 bugs, all fixed with tests: a failed renewal ended Premium on day one of the grace period, a restore of a lapsed plan blocked Buy until the app restarted, offline showed "bald verfügbar", and others. Store builds read the Premium switches from repository variables. PR #153 is rebased and green but not merged. The legal gaps are in the PR. Details: [docs/done/67-paywall-ready.md](docs/done/67-paywall-ready.md).
- Job 64, polish from the Play reshoot (no default stores, Premium hidden before launch, one open item per name, three whole due rows): [docs/done/64-polish-seed.md](docs/done/64-polish-seed.md)

## Job 68: account deletion Premium warning, Alexa read-back wording (2026-11-02), PR #191

The deletion dialog warns the last member of a household with Hummlist Premium that Premium ends and isn't refunded automatically (a box to tick, refund help), and names archived households, which go with the account; shown with `HOUSEHOLD_ARCHIVE` or the `premium_offer` switch, so not in today's releases. Deleting the account never archives (DECISIONS and NEEDS_LEAD "Job 68"). Alexa and Siri now say one sentence for what was added and one for what was already there. The onboarding skip hint names Mehr → Läden. Details: [docs/done/68-delete-warn-alexa.md](docs/done/68-delete-warn-alexa.md).
## Job 69: Alexa skill icon, phrasings, English and certification readiness, PR #193

The Alexa skill's icons are the Hummlist app icon, generated with the app icons and checked by the lint gate. The guide says which sentences reach the skill („Alexa, sag Hummlist, …“, „Alexa, öffne Hummlist“), warns that „auf die Hummlist setzen“ goes to Alexa's own lists, and gives the „Humm-list“ tip; a site test keeps its phrasings in the skill model. „Setz Milch drauf“ now adds Milch, by Siri and by Alexa. The skill also speaks English (en-US, en-GB, en-AU, en-CA, en-IN), is set to worldwide and is ready for Amazon's validation; „Alexa, öffne Hummlist“ never reached the skill on Peter's Echo (logs), so his device check decides between a misheard name and the wrong account (inferred from logs). No Alexa line mentions Premium any more. Amazon's validation, the simulator and the development deploy have not run (ASK login is on the box only), and the testing instructions are not Ops' draft yet. Details: [docs/done/69-alexa-icon-invocation.md](docs/done/69-alexa-icon-invocation.md).

## Job 71: German native Siri only opened the app, PR #194, not merged

German Siri opened Hummlist for every phrase because it writes the name as a German word („Hummliste“), and the phrases only knew "Hummlist". This is inferred from CI's Siri training log, since no iPhone reaches the runner. The app now gives Siri the German and English spellings of its name and has German sentences with an article („Füge etwas zur Hummlist hinzu“). The server drops those spellings from items. A lint check and an iOS build check guard both. The device test is in `docs/NEEDS_LEAD.md` "Job 71". Details: [docs/done/71-siri-german.md](docs/done/71-siri-german.md).

## Job 72: Alexa link data cleanup (Legal N-24, N-28) and fact answers, PR pending

Ending an Alexa connection now deletes what the server kept about it at once: the link and the add counter go with the session (Zugänge "trennen", disabling the skill, linking again, signing out everywhere). Disabling the skill also removes "Amazon Alexa" from Zugänge, which it did not before. A daily job deletes counters of a past minute, revoked Alexa grants, and Alexa sessions unused for 12 months with their link and grant. The Alexa skill is no longer part of Premium: the integration lock never covers it, and the app's Premium copy no longer names it (Legal Review N-27). The answers to Legal Review's fact questions 3, 4, 5, 6 and 9 are in docs/NEEDS_LEAD.md "Job 72". Details: [docs/done/72-alexa-data-cleanup.md](docs/done/72-alexa-data-cleanup.md).
## Job 64b: an add that is already on the list never vanishes; large text fits (2026-11-02)

An undone delete or an offline add whose item another member had put on the list vanished after
job 64's duplicate skip. `put_item` now answers with the open item and the app folds its copy (and
its queued tick or edit) into it. At the largest text scales the third „Wieder fällig“ row and the
rest of the list fit or scroll. Details, tests and screenshots: [docs/done/64b-dup-skip-undo.md](docs/done/64b-dup-skip-undo.md).

## Job 74: one privacy-safe log line per Alexa request

The alexa function logs `alexa: <type> <intent|-> <locale|-> linked=<bool> -> <kind>` once per request (skill events included), with no tokens, ids, item names, utterances or addresses; a test feeds them through every reply kind and checks none appears. docs/ALEXA.md "Request log" has the logs query. PR only, deploys from main after the lead merges. Details: [docs/done/74-alexa-request-log.md](docs/done/74-alexa-request-log.md).

## Job 73: the Hummlist API, PR #197, not merged

A versioned REST API (`/v1`) next to the MCP server lets people automate their list (curl, Shortcuts, n8n, Home Assistant) with API keys made under Mehr → Zugänge (read, or read and write), with Postgres rate limits, idempotency keys, cursor pages and the Premium lock. MCP and API share one list module. The key UI waits for the PostHog flag `public-api` (off). Review 0 fixes: the migration runs after job 72's and keeps Alexa free, the address throttle keys on the gateway's `X-Real-IP` (verified on hosted: `X-Forwarded-For` is forgeable), and only unknown keys count or get blocked. Details: [docs/done/73-public-api.md](docs/done/73-public-api.md).

## Job 75: the API is off on the server until switched on

The PostHog flag `public-api` only hid the app's API section; anyone signed in could still make a key and use the API. A server switch, `app_switches.public_api`, now starts off (migration `20261102200000_public_api_switch.sql`). While off, `create_api_token` refuses with `api_disabled` (the app says „Die API ist noch nicht freigeschaltet.“) and every `api` request answers 404 `not_found` before any key lookup or counter. MCP, Siri and Alexa don't read it. How to turn it on: docs/NEEDS_LEAD.md "Job 75" and docs/API.md "Switched off". Details: [docs/done/75-api-server-flag-gate.md](docs/done/75-api-server-flag-gate.md).

## Job 80: Access screen, tips card, account email

Connected apps in Zugänge show where they were approved („Chrome · macOS“, a short label the consent page records; no user agent, IP or location) and when they were last active, with a plain-words details sheet instead of scope text. A token hint mentions automations (API-aware). The Siri card no longer says "now works without setup". A dismissible tips card (typed queue, platform and version targeting, per user per device) sits at the top of the List tab. The Konto email has a copy button. Legal Review line for the device label: NEEDS_LEAD "Job 80". Details: [docs/done/80-polish-access-tips-account.md](docs/done/80-polish-access-tips-account.md).

## Job 89: a count said after the item is its quantity again

Dictating „Gurken zwei“ (in-app dictation, Siri, Alexa; DE and EN „cucumbers two“) sets the quantity again. Job 61 had passed the count back into the name for the typed rule, which in-app dictation never ran. Typed input is unchanged. Details: [docs/done/89-fix-voice-quantity-words.md](docs/done/89-fix-voice-quantity-words.md).
## Job 88: an own store named like an offered chain ticks the chain

In onboarding, typing an own store such as „edeka“ now ticks the EDEKA chip instead of keeping a hidden store; server already deduplicated. PR #214. Details: [docs/done/88-fix-onboarding-own-store-chain.md](docs/done/88-fix-onboarding-own-store-chain.md).
## Job 93: hummlist.com for AI agents, deterministic checks

Agents get llms.txt, a Markdown twin of every page, a sitemap, robots and JSON-LD. Each is checked in CI with fixture tests, and so are the launch guard, the MCP probe (live discovery plus a throwaway household on the local stack) and the waitlist form, which stays skipped until job 82. PR #223, not merged (lead review). Details: [docs/done/93-agent-first-site-checks.md](docs/done/93-agent-first-site-checks.md).

## Job 91: Alexa dispatch diagnosis

Alexa's „Verbindungsproblem“ comes from Amazon: no spoken request has ever reached the `alexa` function, and account linking works. `scripts/alexa/diagnose.sh` shows, for a window, every call the function got, the Alexa OAuth steps and the live links, with no personal data. `scripts/alexa/smoke.sh` has Amazon call the endpoint. docs/ALEXA.md „Troubleshooting“ maps Alexa's errors to causes and fixes. Token rotation is compatible with Amazon, so no config change. Peter's checks: NEEDS_PETER „Job 91“. The Vercel DPA is in `docs/legal/dpas/` (rendered from the public page, same 2026-03-17 version; index `docs/legal/dpas/README.md`). Details: [docs/done/91-alexa-dispatch-diag.md](docs/done/91-alexa-dispatch-diag.md).



## Job 87: PW-P4 „Haushalt“ is the Hummlist Premium page

Peter's pick from job 81 is now the real paywall at `/more/lifetime`. Every state shows the household hero. When a plan is on offer, the page shows two plan tiles side by side with the store's prices, the household binding line, one Buy button for the picked plan, its terms, Restore, Terms and Privacy. Beta builds (flags off) show no price and no Buy. A free unlock shows Legal's approved beta texts (title, subtitle, privacy link) while `premium_offer` is off; „bald verfügbar“, „Danke!“ and the web's buy-in-the-app note are hidden until sales start. The web shows the hero only. Merge waits for Legal Review sign-off (NEEDS_LEAD "Job 87"). Details: [docs/done/87-paywall-pw-p4.md](docs/done/87-paywall-pw-p4.md).

- Job 95, SiriKit example phrases (ITMS-90626): [docs/done/95-siri-example-phrases.md](docs/done/95-siri-example-phrases.md)

## Job 86: iOS paywall screenshots for the App Store in-app purchase review

PW-P4 as merged on main (84e8da41, job 87 with Legal's N-67..N-71), German, light, 1290x2796, from the iOS simulator on GitHub's macOS runner (run 41792307363): `/workspace/hummlist/research/iap-check/paywall-ios-de.png` (yearly picked, "Jährlich abschließen") and `paywall-ios-de-lifetime.png` (Lifetime picked, "Lifetime kaufen"), both showing "9,99 € pro Jahr" and "29,99 € einmalig". Also in `docs/screenshots/86/`. The prices are the German storefront's, set by the capture: on the runner StoreKit answers with the sandbox's US storefront and its local test store doesn't open. PR #213 is rebased onto main, not merged (lead review); its head SHA and ci-ok are on the BOARD and in the job's DONE_SUMMARY. Retake: workflow "Paywall screenshot". Upload to App Store Connect: NEEDS_LEAD "Job 86". Details: [docs/done/86-iap-review-screenshot.md](docs/done/86-iap-review-screenshot.md).

- Job 96 (Legal N-80..N-86 brand-free copy, native-Siri hold gate): [docs/done/96-brand-free-copy.md](docs/done/96-brand-free-copy.md)
- Job 97 (Siri fix-now: iOS 17 minimum, App Shortcuts catalog, German spoken name, SiriKit failures in Siri): [docs/done/97-siri-app-shortcuts.md](docs/done/97-siri-app-shortcuts.md)
- Job 100, HC1 hill-climb hc-size-start (harness, 4 attempts, none kept): [docs/done/100-hc-size-start.md](docs/done/100-hc-size-start.md)
- Job 102 (judge-panel hill-climb of the app's core screens: harness and measurement fixes, no kept step, 6.5 -> 6.5, DO NOT MERGE): [docs/done/102-hc-ui-app.md](docs/done/102-hc-ui-app.md)
- Job 108, hill-climb hc-ui-perf (frame-time harness; emoji icons name their font, a Linux-only speedup, score 7.479 → 6.598, 1 of 6 attempts kept, early stop at about 5 h): [docs/done/108-hc-ui-perf.md](docs/done/108-hc-ui-perf.md)
- Job 112 (Siri/Alexa reply for branded open items, Alexa single leftover read): [docs/done/112-fix-speech-replies.md](docs/done/112-fix-speech-replies.md)
- Job 137 (sign out looks like a normal More row): [docs/done/137-sign-out-neutral.md](docs/done/137-sign-out-neutral.md)
- Job 98 (hc-tests hill-climb: test speed and coverage; fresh mutant sample: 10.95 -> 14.42 on the box, wall alone 1.16x; 10.29 -> 11.34 on hz after the rebase onto ec0a49e7; reviews 0, 1, 3, 4 and 5 fixed): [docs/done/98-hc-tests.md](docs/done/98-hc-tests.md)


## Job 99: hc-sync, offline and sync robustness

A seeded fuzz harness drives the real list sync layer (cubit, cache, Supabase repository over a fake PostgREST and Realtime) with 3 phones, network drops and restarts. Failing seeds of 1..1000 went from 175 to 0 with eight `ListCubit` fixes, each with a seed-named regression test. `flutter test` now runs seeds 1..100. One server-side change goes to the Lead: a delete should win over a replayed add (NEEDS_LEAD "Job 99", not applied). The PR is ready for review and not merged (the Lead merges). Details: [docs/done/99-hc-sync.md](docs/done/99-hc-sync.md).


## Job 90: category names unique ignoring case, PR #220, merged

„baby“ and „Baby“ are one category now: a unique index on the name key, create_category returns the existing one, and a migration merges existing duplicates into the fallback or the oldest (items, history, layouts, learned corrections, seed keys). The add and rename dialogs say „Eine Kategorie „Baby“ gibt es schon.“ in the dialog. Details: [docs/done/90-fix-category-case.md](docs/done/90-fix-category-case.md).

## Job 118: the ios gate builds once (flaky #258), PR #259, not merged (lead review)

The ios CI job built the app twice and timed out on a slow runner; it builds once now: median 20.0 -> 13.4 min, slowest 40.8 -> 21.5. Review 0: the phase script keeps matrix jobs that start in the same second. Details: [docs/done/118-fix-ios-ci-timeout.md](docs/done/118-fix-ios-ci-timeout.md).

## Job 109: delete_category NULL seed keys, store_name_key normalization order, PR #239, not merged (lead review)

`delete_category` hands over only real seed keys, each once (no more `{NULL}`); a migration strips the NULLs it left and a check stops new ones. `store_name_key` and `store_name` collapse whitespace before trimming, like `category_name_key`; stores that clash under the new key are renamed „Name (n)“ and keep their items. Details: [docs/done/109-fix-category-store-keys.md](docs/done/109-fix-category-store-keys.md).

## Job 82: the hummlist.com waitlist (Spec #10)

hummlist.com gets a waitlist instead of browser-app links: a double opt-in form, confirm and unsubscribe pages, a Vercel function in fra1 in front of a Supabase edge function, locked-down tables with Legal's retention purge, and a manual invite script. Everything is off in production until Peter sets the env vars and approves the texts, and a production build fails while a placeholder is left. PR #210 is open (Peter OKs the copy, Legal reviews). Requeue 2026-11-04 (Addenda 5 to 10): main's landing page with stage CTAs (`site/config/stage.ts`), consent on the confirmation page, Legal's v2 texts, `form-action 'self'`, `/get`; no placeholders can ship. Head `2d303956` (ci-ok green), preview https://hummlist-site-git-job-82-waitlist-peter-trost.vercel.app/de (Vercel login). Details: [docs/done/82-waitlist.md](docs/done/82-waitlist.md).
- Job 134, no hint text inside the store name pill: [docs/done/134-store-rename-hint-out.md](docs/done/134-store-rename-hint-out.md)
- Job 135, the add field floats over the list: [docs/done/135-floating-add-field.md](docs/done/135-floating-add-field.md)
- Job 144, the tabs float as a hex pill: [docs/done/144-bottom-nav-floating-pill.md](docs/done/144-bottom-nav-floating-pill.md)
- Job 147, item icons for 1,430 items and a neutral fallback: [docs/done/147-item-icon-coverage.md](docs/done/147-item-icon-coverage.md)
- Job 148, UI consistency pass (floating top bar, hex Anpassen, one 3D depth switch, no category numbers, one hex per store row, centred hex text): [docs/done/148-ui-consistency-pass.md](docs/done/148-ui-consistency-pass.md)
- Job 145, interactive store chips on the landing page (PR #290, not merged, lead review): [docs/done/145-landing-store-chips.md](docs/done/145-landing-store-chips.md)
- Job 156, nexus.hummlist.com ops dashboard (not merged, lead review; live after one Vercel token, NEEDS_LEAD): [docs/done/156-nexus-dashboard.md](docs/done/156-nexus-dashboard.md)

## Job 113: CI tool downloads cached and retried

A short 504 from GitHub releases or dl.deno.land no longer fails the gitleaks, lint, functions, fg-cli, db or e2e setup. Pinned tools (gitleaks, actionlint, ast-grep, squawk) and the Deno binary come from the Actions cache; their downloads retry with backoff through `scripts/ci/download.sh`, and npm and apt get their own retry settings. Not covered: Docker image pulls, Playwright (its own retries), setup-cli's `bun install`. Workflows with secrets download and checksum-verify Deno instead of using the cache. Pins (lint's `.dvmrc` 2.9.8, `v2.x` elsewhere), `ci-ok` and the gates are unchanged, and a download that still fails after its retries fails the job (proved on the PR with a temporary actionlint pin whose URL answers 404). The PR is ready for review and not merged (the Lead merges). Details: [docs/done/113-ci-download-resilience.md](docs/done/113-ci-download-resilience.md).
- Job 158 (mcp.hummlist.com page for people): [docs/done/158-mcp-landing.md](docs/done/158-mcp-landing.md)
- Job 150, the site videos show the add field's microphone (scripted recognizer in the Linux capture build), a new voice-add video in the voice block, and two dictation fixes (the field follows the words, rows land in their category at once): [docs/done/150-site-videos-mic-voice.md](docs/done/150-site-videos-mic-voice.md)
- Job 159, three small gaps: a store name the household has keeps the add dialog open with why, „Drei Glocken Nudeln“ said stays one item, the mouse wheel over the add field and the tab pill scrolls the list: [docs/done/159-small-gaps.md](docs/done/159-small-gaps.md)
- Job 162, legal and help texts follow the app (tester list, archived households, Alexa 12-month purge, Zugriffstoken): [docs/done/162-legal-copy-sync.md](docs/done/162-legal-copy-sync.md)
- Job 161, the sync indicator S2-C3F2 (a hex card for offline and sync failing that folds into a pill; a real failing state; a 5xx no longer drops a change): [docs/done/161.md](docs/done/161.md)
- Job 165, sync indicator polish (one transient error shows nothing; the card folds into the pill as one shape): [docs/done/165.md](docs/done/165.md)






## Job 155: native store rating prompt

Public store builds ask for the system rating dialog 3 s after a completed trip (3 or more own ticks), behind every gate of the brief; More gets „Hummlist bewerten“ / "Rate Hummlist" (iOS and Android) opening the store listing. iPhone release builds may ask (TestFlight never shows the dialog); Android asks only in the future Play production build with `STORE_RELEASE=true`; no device proof (no device or emulator on the runner). Not merged (the Lead merges). Details: [docs/done/155-review-prompt.md](docs/done/155-review-prompt.md).
