# Job 221: CI wait and list CPU, measured (2026-11-15)

PRs, one commit each on main:

- https://github.com/trost-systems/snacklist/pull/472 (merged as `88d0fbdc`)
- https://github.com/trost-systems/snacklist/pull/462 (merged as `f96c2ecf`)
- https://github.com/trost-systems/snacklist/pull/460 (merged as `07e1ad35`)
- https://github.com/trost-systems/snacklist/pull/470 (merged as `6877ea5a`)

This file, the hill-climb section and the lead's points came in a fifth PR, docs only. It also
adds the three later runs of four shards to the measurements in `docs/CI.md`.

The numbers, the baseline and the cost are in
[`docs/hillclimb/fable-improvement-2026-11.md`](../hillclimb/fable-improvement-2026-11.md),
section "Job 221". The decisions are in `docs/DECISIONS.md`, four sections named "Job 221"; the
last corrects a sentence of the second (a run with the ios job does not always wait for it).

## What changed

- **CI runs the e2e suite in four shards (#460).** The same 271 tests, split by Playwright's own
  `--shard`. The shard list in `ci.yml` is the one place that sets the count, and
  `scripts/check-gates.sh` holds the lines the count travels on, in `ci.yml` and in the on-demand
  `e2e.yml`. `scripts/ci-e2e.sh` takes `--shards 1..6`. `scripts/ci-timings.sh --steps` prints a
  true median.
- **A gate's script runs android and ios only when it is theirs (#462).** A PR that changes only
  `scripts/gates/lint.sh`, `db.sh` or another gate's script no longer runs the android, ios,
  fastlane and emails jobs. It still runs every heavy gate. Two scripts the ios gate runs joined
  the native rule, and a file moved out of a rule's paths now counts where it came from. The
  filter has its first test, `scripts/ci-changes-test.sh`, in the lint gate.
- **The save after a tick encodes one row (#470).** `ListSnapshot.encode()` keeps each item's
  JSON text with its `Item`. What the device holds, when it is saved and what an older build
  reads back are unchanged. A new harness, `tool/hillclimb/hc-list-cpu/measure.sh`, times the
  list's in-memory work without rendering, and the two older harnesses (`hc-size-start`,
  `hc-ui-perf`) run on `main` again.
- **The declutter total test prices its item today (#472).** It carried the date it was written
  on, and a price counts on its calendar day only, so the test failed from 15 November on (seen on
  `main` 46f0ae0d, on #470's branch and in #467's CI run at 00:07 UTC).

No gate was weakened, skipped or given a retry. No user-facing change, no flag, no migration.

## Verification

- Each PR: a `claude-fable-5-2` review that ended in PASS (15 rounds over the four PRs, 9 of them
  FAIL, each on a figure that did not match its source or on a sentence that claimed more than
  its test held), and `ci-ok` green on the merged commit.
- Mutants: 17 of the two workflow files against `scripts/check-gates.sh`, 28 against
  `scripts/ci-changes-test.sh`, 32 against the two Dart test files of #470. Each fails its
  check. The scripts are in the job's research folder, not tests in the repository. What a
  check does not hold is named in its PR and in `docs/DECISIONS.md`.
- Measured before and after: the table in the hill-climb section. In short: the slowest e2e
  shard's job ran 11:35 to 14:55 in five runs of four shards, against a median of 19:53 with
  two (12 runs); 10 of the 136 PRs merged in the week before no longer run the ios job, whose
  27 finished runs for them took 627 macOS runner minutes; one tick and its save's text take
  1.11 ms on the UI isolate against 4.54 ms (Linux profile build, 300 items, seven alternating
  pairs of launches).
- What it costs: 5 to 10 more Linux runner minutes per CI run (five runs), and the first save after
  a load or a resync is 0.4 to 3.6 ms slower.
- Not measured yet: a median of `ci-ok`'s time for a PR that runs e2e without the native gates
  under four shards (one run: 13:49, against 21:24 for the same PR with two), how often one of
  four stacks fails to start, a phone, and frame times.

## Ops

- Nothing to deploy and nothing to configure. No migration, no edge function, no secret.
- #470 changes `app/lib`: it ships with the next green main build.
- A land of a PR that changes only another gate's script no longer needs `MERGE_WAIT_MINUTES=45`
  (`AGENTS.md` and `docs/CI.md` name the list, which is `scripts/ci-changes.sh`).
- Seven points for the lead are in `docs/NEEDS_LEAD.md`, "Job 221".
