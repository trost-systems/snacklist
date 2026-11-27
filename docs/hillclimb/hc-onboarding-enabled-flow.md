# Hill climb: the guided start's enabled flow (job 461)

Started 2026-11-26 12:26:43 CET (`1795692403`). Usage gate at start: `weekly_util` 0.86.

Scope: the 7 counted steps of the guided start (usage, who, name, stores, need, account, invite):
their validation, error and empty states, back and skip, and completion. Not the step transitions
(job 454, PR #723), not the step count or order, not copy (job 456), not off-flag features.

## Frozen metric

`tool/hillclimb/hc-onboarding-enabled-flow/measure.sh` prints one JSON line. Lower is better.

    score = 10 * failing tests in app/test/onboarding/ + failing dead-end probes

The probes are `tool/hillclimb/hc-onboarding-enabled-flow/probes_test.dart`, written and frozen
before the baseline. The script copies them next to the onboarding tests for the run and removes
them after. Each probe is one avoidable dead-end: a path where the user's answer is lost or a step
refuses what it shows as fine.

| Probe | Dead-end |
| --- | --- |
| D1 | „Was fehlt gerade?“: text typed in the field without + is dropped by Weiter |
| D2 | Name: after Weiter, Zurück to „Mit wem“ and another kind, the old kind's suggestion stays |
| D2b | Guard for D2: a name the user typed survives the same way back (passes at baseline) |
| D3 | Stores: an own store typed without the check is dropped by Weiter |
| D4 | Name: the field takes 80 characters, the server 80 code points; an emoji name the counter shows as fitting is refused |

The time of a scripted happy path is left out: the brief allows it only when stable, and nothing
here changes the path's length (`wall_ms` is printed for the record, not scored).

Run: `tool/hillclimb/hc-onboarding-enabled-flow/measure.sh` (about 45 s; holds
`/tmp/fg-hc-measure.lock` while the tests run).

## Baseline

Baseline **4**, on `cfcf460c6` (main): N=2, identical runs. 88 onboarding tests green; D1, D2, D3, D4
fail, D2b passes. The metric is pass/fail per test, so the noise band is 0: a step is kept when a
probe turns green and nothing else turns red.

## Steps

The decision log is `~/groceries-ops/jobs/461-hc-onboarding-enabled-flow/decision.tsv`.

Job 454's T1 transitions (#723) landed during the climb. The branch was rebased onto it after step
2, and the baseline was measured again on its main (`0579afbbd`): score 4 again, the same four
probes failing.

| # | Hypothesis | Change | Score | Kept |
| --- | --- | --- | --- | --- |
| 1 | D1: Weiter on „Was fehlt gerade?“ never reads the field | `_NeedStepState._next` adds the field's text, then moves on | 3 (from 4) | kept |
| 2 | D2: Weiter on the name step stores the suggestion as if it were typed | `_NameStepState._kept`: the draft keeps null while the field holds the suggestion | 2 (from 3) | kept |
| 3 | D3: the store picker's open field is not read by the button that goes on | `NewStoresPickerState.addTyped`, called by Weiter and by „Haushalt erstellen“ (not by skip) | 1 (from 2) | kept |
| 4 | D4: maxLength counts characters, the server code points | one `session/household_name.dart` (it replaces two copies of `maxHouseholdName`/`validHouseholdName`) with `HouseholdNameLimit`, on the four household-name fields | 0 (from 1) | kept |

Every kept step has a regression test that fails on main and passes on the branch:
`guided_start_test.dart` (need, name, stores, emoji name), `household/onboarding_test.dart`
(Neuer Haushalt), `session/household_name_test.dart` (the formatter). The probes stay in
`tool/hillclimb/` as the harness.

Final: score 0 (97 onboarding tests and 5 probes green). The climb stopped at the brief's cap of 4
steps, at 12:48 CET, 22 minutes in. In the real web build `journeys/onboarding-dead-ends.mjs`
passes in German and English (`docs/screenshots/461/`).

Next ideas: `docs/hillclimb/prototype-candidates-hc-onboarding-enabled-flow.md`.
