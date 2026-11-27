# hc-tick-untick: ticking, unticking and the undo (job 458)

Started 2026-11-26 11:51:32 CET (`1795690292`). Budget: at most 4 kept-or-reverted steps or 4 hours,
whichever comes first. The usage gate stops the climb at `weekly_util >= 0.93` (0.84 at the start).

## Scope

A row's tick (`ListCubit.willTick` at the tap, `tick` once the row has closed), the undo from
„Zuletzt verwendet“ (`readd` within `ListCubit.undoWindow`), and the offline queue of both. The
"no undo snackbar on a tick" rule (job 29b) stays. Design changes go to
`hc-tick-untick-prototype-candidates.md` and are not built.

## Frozen metric

`tool/hillclimb/hc-tick-untick/measure.sh [runs]` prints one JSON line. Lower is better.

    score = n3000 tick p50 + n3000 undo p50        (µs, median over the launches)
            + 1,000,000 per failure

- **Tick, undo.** `app/test_driver/tick_untick_probe.dart` in a Linux profile (AOT) build: the real
  `ListCubit` over the in-memory `FakeRepository`, a cache that makes the snapshot's text as the
  device cache does. The hc-ui-perf household (300 items, 10 stores) and the same household ten
  times over (3000 items), every eighth item bought. 20 warm-up rounds, then 60 rounds of tap
  (`willTick` + `tick`) and undo (`readd`), the server answering in between, outside the timed
  part. Then 60 rounds offline, the queue growing to 120 ops, and a drain. The weights are equal:
  a tick and its undo are one mistake and its repair.
- **Failures.** Each failed case of `app/test/list/tick_undo_replay_test.dart` (tick, undo, tick
  again; the undo window; offline across a restart through the snapshot's JSON; a tap killed
  while its row closes; a lost answer; a partner's tick meanwhile) and each probe error (a status
  not as expected after an action, a row not back to open after the drain, a queue not drained).
- **Parts** (not in the score): the same at 300 items, p90s, the offline rounds, and the share of
  each action spent making the snapshot's text (`tick_encode`, `undo_encode`).

Runs under `flock /tmp/fg-hc-measure.lock`, on the gates' SDK (`scripts/lib.sh`, Flutter 3.50.0).
Without CMake on the host (hz) the probe builds in the `verify-family-groceries/linux-build`
container. One run of 5 launches takes about 2 minutes. `measure.sh 1 <bundle>` runs a built probe:
alternate two bundles for a paired A/B when the host is busy (load swung from 10 to 40 during this
climb).

## Baseline (main `cfcf460c6`, 5 launches, load 10-16 on 12 cores)

| | p50 µs | per launch |
| --- | --- | --- |
| n3000 tick | 15,002 | 13,399 to 18,745 |
| n3000 undo | 7,411 | 6,652 to 9,351 |
| n300 tick | 2,602 | 2,451 to 2,987 |
| n300 undo | 1,102 | 1,068 to 1,184 |
| **score** | **22,413** | failures 0 (fixture 8 of 8) |

Baseline score **22413** µs.

Noise band: one launch's score ranges about ±20 % around the median under this load; the median
of 5 moves about ±10 % between runs. A step counts only beyond 15 %.

Where the time goes: making the snapshot's text is 92 % of a tick (13,867 µs) and 83 % of an undo
(6,158 µs) at 3000 items. A tap saves twice (`willTick`, then the `tick`'s enqueue), an undo once;
each save joins every row's text again, 1.9 MB at 3000 items.

## Steps

The decision log is `~/groceries-ops/jobs/458-hc-tick-untick/decision.tsv`.

Scores are the median of 5 launches, in µs; the paired runs are in the "why" column.

| # | time | change | score | kept | why |
| --- | --- | --- | --- | --- | --- |
| 1 | 12:09 | A save after a tick or its undo joined every row's text again (1.9 MB at 3000 items), though only the queue changed. The cubit passes one rows list per server map; `ListSnapshot.encode` keeps the joined text per list. | 14082 | kept | −37 % against 22413, past the 15 % band. |
| 2 | 12:28 | A tap saved the same text twice: `willTick` saves the queue with the promised tick, `tick` moves it into the queue and saved again. `tick` skips its save when its op was the first promised tick, its tap saved it, and no debounced save is due. | 12385 | kept | −12 % unpaired, but load was 19 to 21 against 10 to 15; paired 5 × A/B: 16976 to 13258, −22 %, better in 5 of 5. |
| 3 | 12:37 | A save after the server's answer copies the rows' text twice (the join, then the text around it). One `StringBuffer` would copy once and could replace step 1's cache. | 16258 | reverted | Paired 5 × A/B against step 2: 13671 to 16258; n300 tick worse in 5 of 5. |

Step 3 came from a JIT microbenchmark (3.7 ms to 1.96 ms at 3000 items). The AOT build disagreed:
`List.join` on a list of strings takes the VM's native concatenation, and `StringBuffer.writeAll`
does not.

## Result

Main (`cfcf460c6`) against this branch, 7 paired launches alternating the two probe bundles, load
25 to 38 on 12 cores. The branch was better in 7 of 7 pairs.

| p50 µs, median of 7 | main | branch | delta |
| --- | --- | --- | --- |
| **score** | **43,521** | **15,172** | **−65 %** |
| n3000 tick | 28,678 | 7,726 | −73 % |
| n3000 undo | 14,843 | 7,446 | −50 % |
| n300 tick | 3,058 | 1,003 | −67 % |
| n300 undo | 1,095 | 946 | −14 % |
| n3000 offline tick | 29,576 | 8,730 | −70 % |
| n3000 offline undo | 13,722 | 5,484 | −60 % |

On the quieter host at the start (load 10 to 16), the score went from 22,413 (baseline) to 12,385
after step 2, −45 %. Failures stayed at 0: the fixture passed 8 of 8 and the probe counted no error
in every run.

The undo gains although no step changes its save: inferred, not measured, the branch allocates
two fewer 1.9 MB strings per round (the tap's second save, and the rows' join while the queue
alone changes), so the collector runs less often during the undo.

## Stop

Three steps in 55 minutes. The remaining ideas are under the 15 % band or outside this job:

- Encode the catalog once per catalog (about 0.26 ms of a save at 3000 items, under 5 %).
- Keep `ListState.allItems` per state: three folds of the queue per tick, about 35 µs each.
- The real lever is the device copy's format. Every save still writes the whole list as one string
  (1.9 MB at 3000 items, about 190 KB at 300): one row per key, or appending ops to a log, would
  make a tick's save one row. That is the cache-format change #270, which job 451 left out
  (`~/groceries-ops/NEEDS_LEAD.md`, job 458).
