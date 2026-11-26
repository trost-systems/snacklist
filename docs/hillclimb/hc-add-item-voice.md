# Hill climb: hc-add-item-voice

Job 457. Started 2026-11-26 11:48:24 CET (`1795690104`). Bounded at 4 kept-or-reverted steps
or 4 hours, whichever comes first. The scope is the add sheet with the flags users have today
(`input-stable-rows`, `on-device-catalog`, `add-feedback-list`, `add-sheet-compact`,
`add-match-rows`, all `full` in `releases/flags.json`) and the app's dictation button. The voice
function is frozen, and no file under `supabase/functions/` changes.

## The metric (frozen before the baseline)

`tool/hillclimb/hc-add-item-voice/measure.sh [runs]` prints one JSON line. Lower is better.

```
score = key_ms_p50 + enter_ms_p50
      + 50 * (rank_keys_new + rank_keys_bought)
      + 1000 * (gate_failures + adds_missed)
```

- `key_ms_p50`, `enter_ms_p50`: wall time of one key (`enterText` plus one frame) and of Enter
  (`receiveAction(send)` plus one frame) in the add sheet over a list of 30 open items. 12
  typed lines are added twice and the second pass is timed (133 keys, 12 Enters). The probe is
  `app/test/list/add_item_probe_test.dart` (runs only with `HC_ADD_PROBE=1`). These are
  `flutter test` numbers (debug JIT, no raster). They compare builds of this sheet. They are
  not what a phone shows.
- `rank_keys_new`, `rank_keys_bought`: the share of an item's letters typed before it is one of
  the first three rows, computed by `suggestEntries` over 66 catalog terms (every 25th term).
  The first value uses no history. The second uses the same terms after the household bought
  every fourth one. A value of 1 means only the whole name finds the item.
- `gate_failures`: failed tests in the 21 add-path test files that `measure.sh` lists (398
  tests): add sheet, match rows, dedupe hint, entry and quantity parsing, dictation, the
  suggest fuzz and server parity tests.
- `adds_missed`: Enters in the probe that added nothing (24 expected).

Dropped from the score: client-side voice parse accuracy. The app does not parse a dictated
sentence. `ListCubit.addSpoken` sends it to the `voice` function's German or English splitter
(`supabase/functions/voice/parse.ts`), which is frozen for this job. Dictation client bugs
count only as proven bug fixes with tests.

The ranking parts can only move together with `public.suggest_entries`. `suggest_parity_test`
holds the device ranking to the server's ranking row for row. They stay in the score as a
guard.

## Baseline (origin/main cfcf460c6, 5 probe runs each)

| Run | score | key ms p50 | enter ms p50 | rank new | rank bought | gate | 1-min load |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 76.36 | 21.01 | 20.54 | 0.4291 | 0.2671 | 0 / 398 | 11.8 |
| 2 | 61.72 | 13.81 | 13.10 | 0.4291 | 0.2671 | 0 / 398 | 9.9 |

Baseline **61.72**, the lower of the two runs, so no step gets credit for noise.

Noise. The per-run key p50 ranged from 11.5 to 24.4 ms while other jobs loaded the host (load
10 to 21). The two baselines differ by 14.6 points. The noise band is ±15 points on the score,
and a timing step must clear it in A/B pairs. The ranking and gate parts are deterministic.

## Steps

| # | Hypothesis | Change | Score | Kept | Why |
| --- | --- | --- | ---: | --- | --- |
| 1 | A second microphone tap while the recognizer gets ready starts a second session. The button knows only idle and listening. | A preparing guard in `DictationButton`, with a test that failed before (2 prepares). | 65.92 | kept | A proven bug. The score sits inside the noise band, as expected. |
| 2 | Enter adds something other than what was typed. | None. A scratch scan of 37 typed lines through the sheet. | n/a | no change | Only by-design findings, which became prototype candidates. |
| 3 | A tap while the server splits the last sentence starts the next one. The last one's answer then empties the field under the new live words, and its focus call lands mid-listen. | A sentence's answer clears the field only while the field still holds its text, and calls `onDone` (focus) only while no sentence is listening or getting ready. A test failed on main (the field was emptied under „Eier“). | 82.08 | kept | A proven bug. The first version (review 0 FIX) ignored the tap instead and lost the second sentence. |
| 4 | `_AddBar` watches the whole sheet state but reads only `open` and whether text is typed, so every key rebuilds the field. | A `context.select` of those two values. | key p50 about −12 % (5 alternated pairs), Enter unchanged | reverted | Inside the noise band. Rebuilds per key fell from 201 to 132. |
| 5 | `AddSheet.build` rebuilds more than it needs to. | A `select` in `AddSheet.build`. | rebuild count unchanged | reverted | No effect. |

Step 3's first version added an `adding` phase, so a tap during the split did nothing. Review 0
showed that this lost a second sentence spoken right after the first. Main added it, and the
button gave no sign that the tap was ignored. The fix keeps main's behaviour, where a tap during
the split starts the next sentence. It removes only the side effects of the late answer on the
newer sentence. In review 1, a per-tap counter became the "nothing listening or getting ready"
check, so a newer sentence that hears nothing still gets the field focused again.

The brief named the candidates file `docs/hillclimb/hc-add-item-voice-prototype-candidates.md`.
It lives at `docs/hillclimb/prototype-candidates/hc-add-item-voice.md` because nexus treats every
`docs/hillclimb/hc-*.md` as a climb doc. Step 2 changed no code, so it doesn't count toward the 4
steps.

Step 3's 82.08 was measured at a 1-minute load of 18 to 23 (per-run key p50 14.8 to 29.1 ms).
The ranking parts (0.4291, 0.2671) and the gate (0 of 400 failed) match the baseline, so the
whole difference is timing noise.
After review 1's fix, a 2-run check at load 10 read 61.61 (gate 0 of 401). That backs the
reading: the climb left the score where main had it.

Usage gate readings: 0.84 at the start, 0.85 before steps 1 and 3, 0.87 before step 4, and 0.88
before review 0's fix (all under 0.93).

`measure.sh` runs the add-path gate outside `/tmp/fg-hc-measure.lock`. Only the probe runs
inside the lock, so a parallel climb's gate run can land inside another job's timed probe. That
noise is part of the ±15 band.

The climb stopped after four kept-or-reverted steps (1, 3, 4 and 5) at 12:37 CET, 49 minutes
into the four hours.

## Where the time goes (step 4's profile)

Flutter's in-process timeline around each timed event in the probe, at a key p50 of about
19.5 ms. A key costs about 16 ms of frame work. Layout takes 11.6 ms, 9.8 ms of which is widget
build, because the sheet's `LayoutBuilder`s build during layout. Semantics takes 1.6 ms, paint
1.4 ms, post-frame callbacks 1.0 ms and compositing 0.5 ms. Each key rebuilds about 200 widgets:
the `TextField` subtree right after the key, then the suggestion rows whose content changed.
An Enter costs about 14 ms of layout (12 ms build) and rebuilds about 186 widgets. The list
behind the sheet builds only the new row. Rows whose content didn't change are already
reused. A 35 % cut would need fewer rows rebuilt per key, and those rows really change, so a
simple fix can't get there.

## Next

The best next idea is the prototype candidates in
[prototype-candidates/hc-add-item-voice.md](prototype-candidates/hc-add-item-voice.md),
especially an offline split of a dictated sentence. For speed, the `_AddBar` select is a free
12 % on key time that doesn't clear this host's noise. It could land with a quieter A/B, for
example on a CI runner.
