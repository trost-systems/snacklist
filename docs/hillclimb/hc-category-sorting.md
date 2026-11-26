# hc-category-sorting (job 459)

Started 2026-11-26 11:53:47 CET (`1795690427`). Usage gate at start: weekly 0.85 (< 0.93).

Scope: the order of the enabled list (flag `hide-categories` full): one section per store in the
household's order, then the section without a store; inside a section the items in the store's
category walk order, each category's items by `sort_key`, items still being classified first,
items of unknown categories last. Learned order (flag `learned-order`, off), trips and Verlauf are
out of scope.

## Frozen metric

`tool/hillclimb/hc-category-sorting/measure.sh [runs=5]` runs
`app/test/list/sections_bench_test.dart` (`SECTIONS_BENCH=1`) `runs` times under
`flock /tmp/fg-hc-measure.lock` and prints one JSON line `{"goal","score","higher_is_better","valid","parts",...}`.

Weights, frozen before the baseline:

1. **correctness_failures** (gate, must be 0): 8 fixed households with the order a shopper must
   see, written from SPEC 2/3 and `docs/STORE_LAYOUTS.md`.
2. **stability_failures** (gate, must be 0): 40 seeded households (60 to 255 items, 2 to 6 stores,
   25 categories, 20 layout rows per store, every fourth with two stores on the same sort order,
   as two concurrent `add_store` calls give); per household the order computed twice, from 5
   shuffles of the rows, and for 5 moves to another store or category the optimistic view against
   the server's answer (the items trigger puts a moved item last in its new group, max + 1024).
3. **score** = median over runs of the regroup p50 in µs (lower is better): `sectionsOf` +
   `shownSections` after an add and after a category change on a 1,000-item, 12-store household,
   N = 2000 of each per run after 200 warm-up rounds. `valid` is false while a gate fails; a gate
   failure outranks any speed.

Noise: baseline runs 210 to 314 µs at load 10 to 16 (hz shared with other jobs); a step must beat
the baseline by more than 15 % to count as faster, in A/B pairs (without, with, alternating) at
similar load. Flutter is CI's (`scripts/lib.sh`, 3.50.0); a first baseline on 3.47.8 gave 219 µs.

## Baseline (main cfcf460c6 + the measure)

Baseline **217** µs, valid false: correctness 0/8, stability 75 failures in 407 checks (a failed shuffle ends its round early; 440 when none fails): 65 moves jump when the server
answers, 10 shuffles of households with tied store sort orders change the order).

## Result

score 195 µs, valid true (correctness 0/8, stability 0/440), at load 14 to 19; in same-load A/B
pairs step 3 alone is 311 → 202 µs (−35 %). 3 steps, all kept, 1 h from start. Stopped there:
what is left for the score is marginal for users (about 0.2 ms of a 16 ms frame), and the bigger
lever (one `sectionsOf` per build instead of about three) is invisible to this frozen metric.

Findings not climbed:
- With category headings showing (only before the first flag answer, `hide-categories` is full),
  a store with both an item still being classified and an item of an unknown category builds two
  dividers keyed `category-<store>-null`. Off-state of a full flag, so left alone.
- `sectionsOf` runs about three times per list build (`shopping_list_view.dart` lines 128, 652 and
  `_weightIn`); one result per build would cut the regroup cost again.

Prototype candidates (not built): `docs/hillclimb/hc-category-sorting/prototype-candidates.md`.

Decision log (one row per attempt): `~/groceries-ops/jobs/459-hc-category-sorting/decision.tsv`.

Scores are the regroup p50 in µs; a step that only fixed a gate has no score of its own (n/a).

| # | change | score | kept | why |
| --- | --- | --- | --- | --- |
| 1 | `ItemChanges.apply` clears the sort key when an edit changes store or category, like `MoveItem` | n/a (232 µs, in noise; stability 75 → 10) | kept (bug, test) | an edit to another store kept its old key until the server put it last (max + 1024): the item jumped |
| 2 | `sectionsOf` sorts stores by sort order, name key, id | n/a (A/B 317/334 vs 333/321 µs; stability 10 → 0) | kept (bug, test, time neutral) | stores tied on `sort_order` (concurrent `add_store`) followed the rows' arrival order |
| 3 | cache each store's walking order per `Catalog` instance (`Expando`) | 202 (same-load A/B pair, 311 without) | kept (−35 % in that pair; review's 4 pairs −28 % by median) | `walkingOrder` ran for every section on every regroup, ~30 % of it, while an add leaves the catalog as it is |
