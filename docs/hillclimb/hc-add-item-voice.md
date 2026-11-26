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

Noise. The per-run key p50 ranged from 11.5 to 24.4 ms while other jobs loaded the host (load
10 to 21). The two baselines differ by 14.6 points. The noise band is ±15 points on the score,
and a timing step must clear it in A/B pairs. The ranking and gate parts are deterministic.

## Steps

See the step table in the job's `decision.tsv`, copied below when the climb ends.
