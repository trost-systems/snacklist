# Job 337: server-side tester groups (TG1), the long-press internal switch removed (2026-11-21)

**For Peter and the lead.** Nobody can make an install internal from the app any more. Internal
testers and opt-in test groups live in one server table that only SQL can write. Peter and Lea are
internal again once the lead adds them to the group `internal` (docs/ANALYTICS.md, "Tester groups",
has the SQL with placeholders).

## What was built

- **App.** The long press on the version line under More and the string „Interne Installation“
  are gone. Older builds' stored mark (`analytics.internal`) is deleted at start
  (`Analytics.load`). `isInternal` takes the user's tester groups instead (`app/lib/analytics/internal.dart`).
  `TesterGroupsSync` (`app/lib/analytics/tester_groups.dart`, wired in `main.dart`) reads
  `my_tester_groups()` at sign-in and on every return from the background, keeps the last user's
  groups for an offline start (`DeviceCache` `analytics.tester_groups`) and deletes them at
  sign-out. After the analytics yes the flag request carries `is_internal` and `tester_groups`
  (sorted, comma-joined) as flag properties. More shows „Testfehler senden“ (and „Installations-ID
  kopieren“ after a yes) in a build that can send, only in a debug or profile build or to a user in
  the group `internal` (`Analytics.showsInternalTools`); test accounts and the RevenueCat tester
  household (App Review) see no tools.
- **Server.** `supabase/migrations/20261121074836_tester_groups.sql`: `public.tester_groups`
  (user, group name `^[a-z0-9-]{2,32}$`, added at; cascades with the account), RLS read-own, no
  client writes; `my_tester_groups() returns text[]`; `export_my_data` gains `tester_groups`.
  pgTAP `supabase/tests/tester_groups.test.sql` (22 tests), the export comparison in
  `account_deletion.test.sql`, `NO_ROW` in the outsiders test, a backup-drill fixture row.
- **Without consent (step 4).** Built behind `sharedFlagsCarryTesterGroups = false`
  (`app/lib/analytics/posthog_client.dart:19`): when on, the shared `no-consent` request adds
  `is_internal` and `tester_groups` for internal or grouped users only. The question for Legal is in
  docs/DECISIONS.md (Job 337, item 6).
- **Docs.** docs/ANALYTICS.md ("Tester groups", flag targeting by group, "Tester groups without
  consent"), docs/PRIVACY_DATA_MAP.md (the table, the device cache, the flag properties, the shared
  request), docs/FEEDBACK.md, the feature files, NEEDS_PETER's old long-press steps.

## How to verify

- `node .cursor/skills/verify-snacklist/journeys/tester-groups.mjs <dir>` after `launch.sh`:
  PASS on 2026-11-21 (log and screenshots in `docs/screenshots/337/`).
- `supabase test db` (`tester_groups.test.sql`), `flutter test test/analytics`.

## Test results

- Flutter: all 4080 tests pass (129 skipped, as on main); `scripts/verify.sh --only flutter` passed.
- db gate: passed (pgTAP 77 files, 3401 tests; Deno integration 158 + 2; backup drill 69 tables).
  The first run failed only on the `suggest_entries` p95 bench (52 ms against 50), a known load
  flake on hz; the rerun passed.
- lint, gitleaks, changelog gates passed.
- Web journey: a customer's long press shows nothing; the group `internal` shows „Testfehler
  senden“; the user's own insert is refused (42501); the flag request after the yes carries
  `"is_internal":true,"tester_groups":"beta-de,internal"`; the three shared requests before it carry
  only `platform` and `app_version`.

## Open

- Legal's GO on the new table (data map row) and the step-4 question; the lead seeds Peter and Lea
  in production after the merge. Not merged by this job (brief).
- Job 332's flag sync is not on main (#589): nothing to change there.
- Until the lead seeds them, Peter's and Lea's TestFlight installs are no longer internal (their
  stored long-press mark is deleted at the first start of this build): flags on `is_internal`
  switch off for them until then. Peter's household stays internal through
  `ANALYTICS_INTERNAL_HOUSEHOLDS` if that define is set in the release build.

## Review 0 (2026-11-21)

- **Must fix 1, App Review saw „Testfehler senden“.** The tools followed all of `internalNow`, which
  includes the RevenueCat tester household (App and Play Review's accounts). Now only debug and
  profile builds and the group `internal` (`showsInternalTools`). Widget tests: the tester
  household and a test e-mail in a release build show no tools; a debug build shows them. The e2e
  spec adds its account to `internal` with the service client first.
- **Must fix 2, conflict with main.** Rebased onto main (e181b691's flag list kept, this PR's
  targeting text after it).
- **Nice to have, done.** A test for the stale-read guard (an answer after the sign-out reaches
  neither analytics nor the device; it fails with the guard removed, as does the App Review test
  with the old gate). The ARB descriptions say "debug builds and the tester group internal only".
  The PR body's images are pinned to a commit. A note on #589 about `tester_groups`.
