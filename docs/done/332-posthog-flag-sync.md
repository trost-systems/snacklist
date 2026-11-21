# Job 332: PostHog flags from main, and a minimum app version per flag

PR: https://github.com/trost-systems/snacklist/pull/589 (merged as: the next commit on main).

## What was built

- `scripts/posthog/sync-flags.ts` and `.github/workflows/posthog-flag-sync.yml`. After each push to
  main that changes `app/lib/analytics/flags.dart`, `releases/flags.json`, `releases/releases.json`
  or the script, every flag key PostHog lacks is created (active, `is_internal = true` at 100 %).
  Nothing else changes on a flag without `min_version`. It also runs by hand (Actions, with
  `dry_run`). Without the `ops` secret `POSTHOG_PERSONAL_API_KEY` it gives a notice and passes.
- `min_version` in `releases/flags.json` (`"1.4.0"`, `"1.4.0+1420"`, or per platform with
  `default`). The sync adds `app_version semver_gte` and `app_build` (`gte` or `is_set`)
  conditions to every non-internal condition of that flag, split by `platform` for per-platform
  minimums (once). Later runs replace only the sync's own version pair, so platforms, rollouts
  and version conditions edited by hand in PostHog stay (reviews 0 and 1). The workflow also runs
  every 15 minutes; a scheduled run warns on a plan error instead of failing. The pure plan is in `scripts/posthog/plan.ts`; the tests (`plan_test.ts`) run in the
  functions gate. `site/releases.mjs` `parseGates` checks the field.
- Per Peter's override (t1100u), `min_version` is pinned per flag and never bumped, and no
  auto-moving latest-store cohorts exist. `scripts/posthog/latest-store.ts` prints the newest
  public store release, or the pubspec version, to help fill `min_version`.
- App: after an analytics yes, flag requests carry `platform`, `app_version` and `app_build`
  (`app/lib/analytics/analytics.dart`, `_registerContext`). Without consent nothing changes.

## Choices

- Version conditions always need `app_build`, which only installs with a yes send. Legal §18 L2
  forbids property targeting without consent, so installs without consent see version-gated
  flags off.
- `min_version` takes a build because every store build is `0.1.0` so far.
- Conditions per flag, not a cohort per version (Peter allowed either): the version shows on the
  flag itself, and there is no second object to keep in step (docs/DECISIONS.md, "Job 332").

## Verify

- `cd scripts/posthog && deno test --frozen --allow-read=../..`: 24 pass (6 fail on the plan before review 0, 2 more on the one before review 1).
- `cd app && ~/flutter-3.50.0/bin/flutter test test/analytics`: 386 pass.
- `scripts/verify.sh --only e2e -- tests/analytics.spec.ts`: 11 pass. It includes the flag
  request with `app_build` after a yes.
- In GitHub: Actions › PostHog flag sync › Run workflow with `dry_run` (needs the secret).

## Missing or blocked

- The secret `POSTHOG_PERSONAL_API_KEY` does not exist in the `ops` environment. The box's key
  has error-tracking scopes only, so the dry run against PostHog stopped at HTTP 403
  (NEEDS_LEAD Job 332).
- Whether a version condition may also reach installs without consent is Legal's call.
