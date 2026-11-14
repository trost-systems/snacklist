# family-groceries

Shared shopping list for one household (Peter and Lea). Flutter app (iOS,
Android, web) on Supabase (Postgres + RLS, Auth, Realtime, Edge Functions).
The product spec is [`docs/SPEC.md`](docs/SPEC.md); decisions and their
reasons are in [`docs/DECISIONS.md`](docs/DECISIONS.md).

## Layout

- `app/`: the Flutter app. `lib/list/` is the list feature (model, cubit,
  repository, screen), `lib/session/` auth and household state,
  `lib/household/` onboarding and invites, `lib/app/` router, environment
  and app shell. UI strings live in `app/l10n/app_de.arb` (German template).
- `supabase/`: `config.toml` for the local stack, `migrations/`, pgTAP tests
  in `tests/`, Deno edge functions in `functions/` (`_shared/` for helpers).
- `e2e/`: Playwright tests that drive the Flutter web build against the local
  stack.
- `analytics/`: the PostHog gate insights as HogQL (`queries/`), a TypeScript
  reference over fixture events that the functions gate tests, and the manual
  proofs. The app's side is `app/lib/analytics/` (consent, allow-list, the
  posthog_flutter SDK in `posthog_client.dart`, feature flags in
  `flags.dart`), the functions' `supabase/functions/_shared/telemetry.ts`
  (`docs/ANALYTICS.md`).
- `app/fastlane/`, `.github/workflows/release.yml`: TestFlight and Play
  internal releases after every green CI on `main` (and by hand), signing
  from secrets (`docs/RELEASE.md`).
- `vercel.json`, `scripts/vercel.sh`: Vercel builds the web app only for
  `release`, and only when the app changed (`scripts/vercel-ignore.sh`, the
  `ignoreCommand`; `scripts/vercel-local.sh` runs the same build in Vercel's
  base image). `main` no longer builds, so the preview is frozen; production
  (`app.snacklist.app`; `app.hummlist.com` serves it too until R1, for old links) moves when a `release.yml`
  run uploads to a store and pushes the `release` branch (`docs/DEPLOY.md`,
  section "Web app").
  `supabase-deploy.yml` deploys migrations (`supabase/deploy/`, Management
  API) and edge functions (`--use-api`) from main, then runs
  `scripts/smoke-remote.sh`; its `ref` input rolls functions back.
  `keepalive.yml` reads through `health` daily so the free project doesn't
  pause. Runbook: `docs/DEPLOY.md`.
- `marketing/`: `store-screenshots/` (`scripts/store-screenshots.sh`: the Play and App Store
  screenshots, feature graphic and icon from the real web build, words in `captions.yaml`,
  `docs/STORE_SCREENSHOTS.md`) and `videos/` (the site's demo loops, `marketing/videos/README.md`).
- `site/`: the public site on snacklist.app (hummlist.com redirects there)
  (landing pages `/de` and `/en`, guides, changelog, legal pages), its own Vercel project (Root Directory
  `site`), static HTML from Markdown and `site/content/landing/copy.yml`;
  `site/README.md` explains adding a guide and the landing copy and media. Separate from the app's build.
  A production build waits for the same commit's `supabase-deploy` run (`site/scripts/supabase-gate.mjs`,
  the `ignoreCommand`).
  Production hides content tagged `since:` a version above the live one:
  the newest public release in `releases/releases.json` (the public release
  record, `releases/README.md`), else `app/pubspec.yaml`.
  `public-release-record.yml` (`scripts/release/record.mjs`) appends a
  release there and pushes it to main, which redeploys the site.
  `/de/changelog` and `/en/changelog` list the public releases' changelogs
  (job 39, `docs/CHANGELOG.md`): `scripts/release/changelog.mjs` collects
  them from the PRs' `## Changelog` notes into `releases/changelog/<v>.json`
  drafts with the store "What's new" texts; `record.mjs` moves a draft into
  the record.
- `supabase/functions/api/`: the public REST API (`/v1/...`, API keys with scopes, Postgres
  rate limits, idempotency), sharing `_shared/list.ts` with the `mcp` function. Guide
  `docs/API.md`, contract `docs/api/openapi.yaml` (checked by the lint gate against
  `api/routes.ts`). Its key UI sits behind the PostHog flag `public-api`.
- `mcp-proxy/`: the Vercel project `hummlist-mcp`, serving the `mcp` function
  at `https://mcp.snacklist.app` by rewrites, and a static page for browsers
  (`public/`, routes tested by `scripts/mcp-proxy-routes_test.ts`). `scripts/mcp-smoke.sh <url>`
  checks MCP discovery on either URL (`docs/MCP.md`).
- `supabase/functions/voice/`: the Siri and in-app dictation endpoint; the
  German sentence splitter is `parse.ts`, its table of sentences
  `parse_test.ts` (`docs/SIRI_SHORTCUT.md` for the Shortcut).
- `supabase/functions/alexa/`: the Alexa skill's endpoint (request verification, intents,
  read-back); the skill package (manifest, de-DE model) is `alexa/skill-package/`. Local requests
  are signed with `scripts/alexa-test-ca.sh`'s test CA (`scripts/alexa-say.sh`, `docs/ALEXA.md`).
  `scripts/alexa-deploy-dev.sh` uploads the package to the development stage (ASK CLI signed in).
- `scripts/`: `bootstrap.sh` (toolchain), `dev.sh` (local stack + web dev
  server), `gates/<gate>.sh` (one per CI job), `verify.sh` (runs the gates
  locally), `lint.sh` (the lint rules below, run by the lint gate),
  `push-pr.sh` and `merge-pr.sh` (push and land a PR as one commit with the
  required author and trailers), `e2e-stress.sh` (a stressed e2e repro:
  pauses the browser, runner or stack S s of every P s, DECISIONS job 119).
  `docs/CI.md` explains CI.
- `tool/hotspots/`: where jobs collide, measured: `history.py` (change counts and co-change on
  main), `conflicts.py` (conflicts in the job transcripts), `replay.py` (main's history of a file
  replayed as rebases), `e2e-duplicates.mjs` (helpers copied between e2e specs) and `stale-head.py`
  (lands refused as "behind main" right after a push). Results:
  `docs/hillclimb/fable-improvement-2026-11.md`.

## Conventions

- Prove behavior with the verify-family-groceries skill
  (`.cursor/skills/verify-family-groceries/`, also `.claude/skills/`): it
  drives the real app through `scripts/fg` (start with `scripts/fg help`)
  and keeps one recipe per feature in `features/`. A PR that changes a
  feature updates its `features/<feature>.md`. Test accounts in a known
  state come from `scripts/fg seed <scenario>` (`test/fixtures/scenarios/`,
  removed with `fg teardown <run>`), multi-client sync proofs from
  `scripts/fg sync` (`docs/TEST_FIXTURES.md`).
- The current feature map is `.cursor/skills/verify-snacklist/features/`
  (`docs/FEATURE_MAP.md`): one file per user-facing feature, plus
  `FEATURES-FOR-WRITERS.md`, which emails and site copy are written from.
  Whenever user-facing behaviour changes, update the feature file and its
  section in FEATURES-FOR-WRITERS.md (last verified: commit and date) in the
  same PR. The verify-snacklist skill drives the web build with Playwright
  (`helpers/launch.sh`, `doctor.sh`, `drive.sh <feature-id>`, `cleanup.sh`);
  snacklist-howto-clips films GIF/MP4 how-to clips of it.
- Make shown UI look finished with the snacklist-ui-craft skill
  (`.claude/skills/snacklist-ui-craft/`, also `.cursor/skills/`): the 6b look,
  restraint, framing, motion, loops, poster frames, the 358 px compact design and
  the film/contact-sheet review loop, for homepage scenes, demo videos, goldens
  and app screens. Its `film.mjs` films HTML/CSS scenes with Playwright.
- Run `scripts/verify.sh` before pushing. It runs the same
  `scripts/gates/<gate>.sh` scripts the CI jobs run (gitleaks, lint, changelog, site,
  site-agent, emails, db, functions, nexus, fg-cli, flutter, web-prod, fastlane, e2e); `--only <gate>` runs
  some, `--only e2e -- <spec>` one spec. It stops at the first failing gate;
  its last line is the verdict in plain text (`[verify] passed: ...` or
  `[verify] FAILED: <gate> ...; its output: <file>`), and it notes a gate
  that gave both results on the same files or failed three runs in a row
  (`docs/CI.md`, "The local loop"). A check goes into a gate script,
  never into `ci.yml` or `verify.sh` (`scripts/check-gates.sh` fails
  otherwise). The e2e gate holds the box-wide lock `/tmp/fg-e2e.lock`, so a
  second run waits instead of overlapping.
- No Docker here (the Mac runner), or sparing the box: `scripts/ci-e2e.sh
  [--spec "<playwright args>"] [--no-db]` runs the e2e and db gates on
  GitHub Actions for the pushed branch and prints the result (`docs/CI.md`,
  On-demand e2e).
- Public repo: never commit secrets. Only the project URL and the publishable
  key may appear in code. gitleaks runs as a pre-commit hook
  (`.githooks/pre-commit`) and as a required CI job.
- Lints follow emotely: `flutter_agent_lints` (experimental set), every rule
  an error. Fix the code, not the rule; `dart fix --apply` handles most
  primary-constructor and style findings.
- The TypeScript and JavaScript follow a sibling pack, `tool/lint/ts/pack.ts`:
  every `deno lint` rule and strictness compiler option on or off with a
  reason, `error` rules enforced by `tool/lint/ts/strict.ts` in the lint gate
  (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, no `!`, return
  types on exports). Narrow instead of asserting; `docs/hillclimb/hc-strictness.md`.
- Build-time defines are read only in `app/lib/app/environment.dart`.
- Auth gating happens only in `authRedirect` (`app/lib/app/router.dart`).
- Every household-owned table carries `household_id` and the RLS policy
  `is_household_member(household_id)`. A new table gets the same policy and a
  cross-household case in `supabase/tests/rls.test.sql`.
- Item writes from the app are idempotent ops (`ItemOp` in
  `app/lib/list/model.dart`) applied optimistically and retried until the
  server acknowledges them; the screen shows server rows with pending ops
  folded on top. Add new mutations as new `ItemOp` variants.
- Analytics events pass the allow-list in `app/lib/analytics/events.dart`
  (`eventCatalog`): a new event or property gets a rule there, a test and a
  row in `docs/ANALYTICS.md`. Never list text, names or free text.
- Categorization runs server-side in `public.classify_item(household, name)`
  (called by the items insert trigger). The app, MCP and Siri all go through
  it; change the function, not the callers. Spelling variants, synonyms
  (`supabase/classifier/synonyms.tsv`) and typos are its job too; the shared
  key for them is `items.canonical_key` (job 32a).
- Flutter web e2e: semantics are enabled on web, so Playwright finds widgets
  by role and label. Type with `typeInto` (`e2e/tests/helpers.ts`); synthetic
  key events drop umlauts. A snackbar with an action (undo) keeps its text in
  a group's aria-label: find it with `actionSnackBar`, since `getByText`
  only hits the screen-reader announcement, which the engine soon clears.
- Every PR description has a `## Changelog` section: items (`new`,
  `improved` or `fixed`, then a `de:` and an `en:` sentence in user words)
  or just `none` when users see no change (`docs/CHANGELOG.md`, the PR
  template). push-pr.sh adds `none` for PRs that change neither the app nor
  `supabase/` or `alexa/`, and stops the others without one; the
  `changelog` gate checks the structure.
- `main` takes one commit per PR with `ci-ok` green. To land a PR:
  1. Push the branch once (`git push -u origin HEAD`) and `gh pr create`.
  2. From then on push only with `scripts/push-pr.sh`, fix rounds included.
     It rebases onto `origin/main` and pushes the one commit main takes
     (subject `<PR title> (#n)`, noreply author, trailers). The pre-push
     hook warns when a PR branch goes up as several commits.
  3. Under the merge lock: `scripts/merge-pr.sh --wait <n>` waits for
     `ci-ok` on that commit and rebase-merges it. One CI run per merge.
     It gives up after 30 minutes. A run with the ios job can take longer:
     land a PR that changes the native projects, the pubspec, `scripts/gates/`,
     `scripts/lib.sh` or the CI definition (the list is `scripts/ci-changes.sh`)
     with `MERGE_WAIT_MINUTES=45`.
  If main moved since your push, merge-pr.sh says so: rerun
  `scripts/push-pr.sh` (one more rebase, push and CI run), then merge-pr.sh.
  The old way still works: merge-pr.sh on a multi-commit PR squashes,
  force-pushes and exits 2; rerun it after `ci-ok`, at the cost of a second
  CI run. GitHub's own squash merge authors the commit with the account's
  default email and rejects the noreply address, hence the scripts.
- The logs every job appends to (`docs/DECISIONS.md`, `docs/NEEDS_LEAD.md`, `docs/NEEDS_PETER.md`,
  `DONE_SUMMARY.md`; listed in `.gitattributes`) merge through `scripts/merge-append-log.sh`: two
  sections added at the same place both stay, main's first. Append yours at the end and start it
  with a heading. An edit of existing lines, an entry main already holds, or a follow-up without
  its own `##` heading next to a section main added, still stops the rebase: place it by hand.
  push-pr.sh's rebase installs the driver in the clone's git config (job 218).

## Lint rules

`scripts/lint.sh` runs these locally and in CI, and each error names the fix.
Rules live in `ast-grep/rules/` with tests in `ast-grep/tests/`, the schema
guards in `supabase/checks/schema_check.ts`, the workflow rules in
`scripts/workflow-hardening.ts`. Silence one finding only on the
line above it, with the reason: `// ast-grep-ignore: <rule-id> -- <reason>` or
`-- squawk-ignore <rule> -- <reason>`; a workflow exception is an entry with
its reason, and the secrets or actions it covers, in `scripts/workflow-hardening.allow.json`.

| Rule | What fails | Why |
| --- | --- | --- |
| `no-from-environment` | `String/bool/int.fromEnvironment` outside `app/lib/app/environment.dart` | One inventory of build-time defines |
| `dispose-after-dialog` | A local controller or FocusNode disposed after `await showDialog`/`showModalBottomSheet` (or a picker or pushed route), or in its `.then` | The route still animates out with it; the join dialog crashed (fixed in 1177b52) |
| `shared-preferences-only-in-device-cache`, `device-cache-own-file` | A shared-preferences store outside `DeviceCache`, or one without its own Linux file | A second store on supabase's file signed Linux users out (c4ed2e4) |
| `auth-navigation-only-in-router` | The `/login` or `/welcome` route named outside `router.dart` (path, `loginPath`, `goNamed('login')`) | Auth gating happens only in `authRedirect` |
| `no-hardcoded-ui-text` | A string literal with letters in `Text(...)` or a `label`/`tooltip`/`hintText`-style argument in `app/lib`, also through a same-file constant, list, map, getter or function | UI text lives in `app/l10n/app_de.arb` |
| `purchases-flutter-only-in-revenuecat-repository` | Importing `package:purchases_flutter` anywhere in `app/` but `app/lib/purchases/revenuecat_repository.dart` | One file configures RevenueCat, lazily and with the household id only (Legal Review K.9.9 C3) |
| `posthog-flutter-only-in-posthog-client` | Importing `package:posthog_flutter` anywhere in `app/lib` but `app/lib/analytics/posthog_client.dart` | One file sets the SDK up, only after the analytics yes, with the allow-list as its `beforeSend` (job 44) |
| `revenuecat-user-id-from-session` | `RevenueCatUserId(...)` (also `const`/`new`), its tear-off, or an `as` cast to it, in `app/lib` outside `app/lib/purchases/purchase_cubit.dart` | RevenueCat's App User ID is the session's user id (job 185); built anywhere else it could wrap a household id (job 211) |
| `no-revenuecat-customer-data` | `Purchases.set*`, `collectDeviceIdentifiers`, `enableAdServices*`, `logOut` or `sync*`, called or torn off | RevenueCat gets the Snacklist user id (the App User ID, job 185) and the purchase: no attributes, no device ids, never an anonymous customer (C3) |
| `store-price-channel-only-in-store-prices` | The string `familygroceries/store_prices` in Dart outside `app/lib/purchases/store_prices.dart` (tests use `ChannelStorePrices.channel`) | One file asks the store for prices, only once the Premium page is open (job 49, Legal Review A2-5) |
| `store-prices-channel-methods` | In `store_prices.dart`, an `invoke*Method` whose method is not the literal `'prices'` or `'manageSubscriptions'` | The native side reads product details and opens Apple's sheet; purchases go through RevenueCat only |
| `no-in-app-purchase` | Importing `package:in_app_purchase*` anywhere in `app/` | Its StoreKit observer and Play purchases listener would run next to RevenueCat's; prices come from the channel (job 49) |
| `in-app-review-only-in-store-review` | Importing `package:in_app_review` anywhere in `app/` but `app/lib/review/store_review.dart` | One file holds the store's rating prompt and listing (`StoreReview`, job 155) |
| `request-review-only-in-review-prompt` | A `.requestReview` call or tear-off in `app/lib` outside `app/lib/review/` | The prompt comes only after `ReviewPrompt`'s gates, never from a button (Apple refuses that); a button opens the listing |
| `no-wall-time-wait-in-tests` | `Future.delayed` in `app/test` | It races the timers it waits for: after a stall the test resumes mid-reload (DECISIONS 18.17). Use `elapse()` or `fakeAsync` |
| `snackbars-through-notices` | `ScaffoldMessenger.of`/`maybeOf` in `app/lib` outside `app/lib/app/notices.dart` | A page's messenger shows under an open dialog's or sheet's barrier (job 116). Use `Notices.of(context)` |
| `localizations-through-app-list` | `AppLocalizations.localizationsDelegates` in `app/` outside the generated `lib/l10n/` | gen-l10n still lists the in-framework Material delegate; material_ui widgets then find no MaterialLocalizations (job 201). Use `appLocalizationsDelegates` |
| `text-field-autofill-explicit` | A `TextField`, `TextFormField` or `CupertinoTextField` in `app/lib` without `autofillHints:` | Flutter 3.50 web keeps a hidden copy of each left autofill field, a second textbox of the same name for screen readers (job 201). `null` for none; a field with hints ends its autofill context before the next screen's field takes the input (job 226) |
| `popups-on-root-navigator` | `showModalBottomSheet` without `useRootNavigator: true`, a dialog with `useRootNavigator: false` | `Notices` sees open popups on the root navigator only |
| `scroll-animation-through-hl-scroll-to` | A `.animateTo(...)` with `duration: hlMotion(...)` in `app/lib` outside `app/lib/design/motion.dart` | Reduced motion makes it `Duration.zero`: a scroll animation then asserts, and throws on release web before what follows runs (job 231). Use `hlScrollTo`; an AnimationController's is fine, ignore it with that reason |
| `no-label-in-hex-field` | `labelText:` or `label:` in an `InputDecoration` in `app/lib`, outside `RoundedFields` | A hex field is an outline: a floating label would sit on its contour and pushed the text off centre (job 148). Use `LabeledField` |
| schema check: history | Editing or deleting a migration on `main`; a new one sorting before main's newest | Production already ran it; deploys refuse older migrations |
| schema check: membership reads | A new migration reading `household_members` by user without a `household_id`, `is_default` or `order by` (existence tests and counts pass) | A user is in several households (job 169b): an unfiltered read picks an arbitrary one or fails with "more than one row" |
| schema check: RLS | A public table without RLS; a `household_id` table without an `is_household_member(household_id)` policy or a two-household pgTAP case | PostgREST serves every public table |
| squawk compat rules | Dropping or renaming a column or table, NOT NULL without default, type changes, dropping a function or view | TestFlight and Play builds lag `main`; old apps must keep working |
| `brand-names` | ChatGPT, OpenAI, Claude or Anthropic in site/content, site/public, mcp-proxy/public or an ARB value, outside `scripts/brand-names.allow.json` (or a stale entry there) | Legal N-80..N-86: brand names only in functional help and the trademark notice |
| `action-pinned` | A `uses:` in `.github/workflows` or `.github/actions` that is neither a local path nor a full 40-hex commit SHA (a `docker://` image: its sha256 digest) | A tag can be moved to other code, which then runs with the job's token and secrets (job 220) |
| `secret-in-step` | `secrets.X` anywhere but a step's `env:` or `with:`, such as a job's or the workflow's `env:`, a `run:` or an `if:` (`secrets.GITHUB_TOKEN` is the run's own token and exempt) | From a job's `env:` every step and action of the job gets it; one step needs it |
| `secret-needs-environment` | A job that reads a secret without `environment:`, or in one that is neither `release` nor `ops` | A workflow file on any pushed branch can read a repository-level secret; an environment can be limited to `main`, and its secrets go only to its jobs (`release` for the store release, `ops` for the scheduled production jobs) |
| `no-cache-in-trusted-job` | In a job that reads a secret, names an environment or whose token may write: an action with `cache` in its name, a `cache:` or `...-cache:` input that is not `false` (`no-cache:` that is not `true`; setup-java's `cache-jdk:` too), `actions/setup-node` without `package-manager-cache: false`, the local `deno` action without `cache: false`, `oven-sh/setup-bun` without `no-cache: true`, `supabase/setup-cli` (it has no such input), or a local action that runs one of these | Any run on `main` can write a cache entry, which the job would unpack and run next to its secrets and token; it installs from the lockfile instead |
| `pinned-deps` | An `npm:` or `jsr:` specifier in `supabase/functions/deno.json` that is not one exact version (`^`, `~`, a range, a tag, none); another URL there, an `importMap` or `workspace` key, or a `package.json` beside it; in a function's source: `npm:<name>` or `jsr:<name>` anywhere, an `http(s):` or `data:` URL after `from` or `import` or in a `@jsxImportSource`, `@ts-types` or `<reference types>` pragma; `gradle-wrapper.properties` without a `distributionSha256Sum=` line | A range could resolve at deploy to a version no gate tested; the release job runs the downloaded Gradle next to the signing keys (job 220) |
| merge conflict markers | A tracked file with a line starting `<<<<<<< ` or `>>>>>>> ` | A 3-way apply that stopped left them staged in two feature docs (job 169b W2); no other gate reads those files |
| `no-hummlist` | A tracked file naming Hummlist (any case) that `scripts/checks/hummlist-allow.txt` does not list with its exception and reason | The product is Snacklist (job 174); only redirects, old builds' ids and wire names, and history keep the old name, each until it retires |
| `ignore-needs-reason`, schema check: ignores | An `ast-grep-ignore` or `squawk-ignore` without ` -- <reason>` | An exception a reviewer cannot judge gets copied |
