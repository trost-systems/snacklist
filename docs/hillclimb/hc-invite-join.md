# Hill-climb: household invite and join, enabled paths (job 460)

Started 2026-11-26 11:54:45 CET (epoch 1795690485). Budget: 4 kept-or-reverted steps or 4 hours,
whichever comes first. Usage gate at start: `weekly_util` 0.85.

## What is climbed

These join paths are on for everyone (`join-household-jh2` at full rollout):

- **link**: an invite link `/join/<code>`. With JH2 the household is joined as soon as the preview
  answers, with no tap (`JoinCubit._joinLink`).
- **code**: the guided start's "Bestehendem Haushalt beitreten" (`JoinCodeScreen`). The code is
  looked up at the 8th character, then "Beitreten" is tapped.
- **typed**: the switcher's "Mit Code beitreten" and Willkommen's "Einladung annehmen" (`JoinScreen`
  at `/join`). The user types the code, taps "Weiter", then taps "Haushalt beitreten".

Out of scope: flags that are off (`joiner-direct-list` is partial), App Links (job 462), copy (456).

## Frozen metric (lower is better)

`score = 100 x failed tests + 10 x uncovered cells + happy-path steps`

- **failed tests**: every test in `app/test/household/`, `app/test/onboarding/` and
  `app/test/shell/router_test.dart`, run with CI's Flutter (3.50.0). This number must stay 0.
- **cells**: `tool/hillclimb/hc-invite-join/cells.tsv` lists 20 cells, each a path paired with an
  outcome: it joins, the code is invalid (made up, expired, revoked or used, which the server answers
  the same way), rate limited, offline at the preview, offline at the join, 20 households, declined
  recently, what happens to the link after a refusal (cell `link/after-refusal`: forgotten on a
  final answer, kept on offline, the rate limit and a server error), refused at the join after a good preview, and an
  answer the app can't read. A cell is covered when a test that drives that path as users get it
  (JH2 on) passes and asserts the text the user reads. A cell with no such test is uncovered. A
  test that finds a bug fails until the bug is fixed.
- **steps**: the user actions in each path's happy-path test, from having the code or link to the
  household's list, signed in. link is 1, code is 2, typed is 3. Steps only go down through a
  design change, so this climb does not move them. Candidates for that are in
  `hc-invite-join/prototype-candidates.md`. That file sits in a folder, not at the brief's
  `hc-invite-join-prototype-candidates.md`, because Nexus requires every top-level
  `docs/hillclimb/hc-*.md` to be a registered climb with a baseline and a steps table
  (`nexus/test/hillclimbs_test.ts`).

Run it with `tool/hillclimb/hc-invite-join/measure.sh`. It prints one JSON line and runs under
`flock /tmp/fg-hc-measure.lock`.

Weights: one failing test outweighs every coverage gain (100 against at most 200 for all 20 cells).
A step counts less than a cell, since steps are fixed here.

## Baseline (main cfcf460c6)

Baseline score **146** in all three runs (N=3): 0 failed of 612 tests, 14 of 20 cells uncovered, 6 steps. The
measure counts tests, so it has no noise; the noise band is 0. Any drop in gaps counts.

The first baseline ran with the box's default Flutter (3.47.8) and showed 12 false failures in
`default_list_test.dart` (`!timersPending`). The measure now takes CI's pin through `scripts/lib.sh`.

## Steps

The decision log (`decision.tsv`) is kept outside the tree, in the job directory
(`~/groceries-ops/jobs/460-hc-invite-join/hc/`). Every step ran the full measure once (it has no
noise) and ended green.

| # | Hypothesis | Change | Score | Kept |
| --- | --- | --- | --- | --- |
| 0 | baseline | none | 146 | |
| 1 | The link path with JH2 explains its errors, but no test asserts what the user reads | 6 widget tests: invalid, rate limit, offline at the preview and at the join, 20 households, declined | 86 | kept, no bug |
| 2 | A link refused for good stays pending, so the router reopens its join | `JoinCubit._refused` answers the link on every refusal except offline and the rate limit. The test failed first: `router.go('/')` landed on `/join/ABCD2345` | 76 | kept, bug fix |
| 3 | The typed path (`/join`) is tested only through the flags-off link tests | 5 widget tests that type at `/join`, in a household, JH2 on | 26 | kept, no bug |
| 4 | A guided-start code that the join refuses after its preview is untested | 1 widget test: the text at the join, the link answered, Cancel leaves | 16 | kept, no bug |
| R | Review 0: step 2 forgot the link on every refusal but offline and the rate limit, so a server error (`other`: a 502, 503 or statement timeout) threw the link away too | `_refused` forgets only on `invalidInvite`, `tooManyHouseholds` and `declinedRecently`. Tests: offline, the rate limit and a server error at the join keep the link (the server-error one failed on step 2's code). An unreadable answer at the preview says so and keeps the link | 6 | kept, bug fix |

After step 4: 16 (0 failed of 626 tests, 1 of 20 cells uncovered). Final, after the review fix: 6
(146 to 6, 96 % lower). 0 failed of 636 tests, 0 of 20 cells uncovered, 6 steps.

## Left open

- The wording of an answer the app can't read („Etwas ist schiefgelaufen: other“).
  `genericError(<code>)` is how the app shows error codes on several screens, so the wording goes to
  job 456 and is not a factual bug. The cell is covered: the text shows and the link is kept.
- Steps stay 6. A lower count changes the design: see `hc-invite-join/prototype-candidates.md`.
