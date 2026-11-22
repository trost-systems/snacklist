# Job 348: TE1, the total shows only what has a price

Peter's pick from round TE (job 343, draft PR #602), every TE-Q default accepted. Behind the new
PostHog flag `total-priced-only` (off for users; the flag sync creates it for internal installs,
which are Peter and the internal tester group).

## What changed, flag on

- No item with a price: no summary block at all.
- Some prices: a line only for a store (or „Ohne Laden“) with a priced item, without „<n> ohne
  Preis“; one „<n> ohne Preis“ under „Gesamt“, no „mit Preis“. Every item priced: no count line.
- Kept: „mind.“, „≈“, „Ohne Laden“ as its own line, bought/open while a trip runs, „alles gekauft“
  for a priced store bought in full.
- A price in another currency counts as none (TE-Q10).
- At the largest text an amount too wide beside its name goes under it, whole (TE-Q9).

Flag off: unchanged (pinned by the same tests run with the flag off, and the existing
`summary_block_test.dart`).

## Where

- `app/lib/list/subtotals.dart`: `Summary.pricedOnly`, `lines`, `shown`, `perStore`.
- `app/lib/list/list_view/summary_block.dart`: store lines from `lines`, counts, stacked amount.
- `app/lib/list/list_view/shopping_list_view.dart`: reads the flag, hides the block by `shown`.
- `app/lib/analytics/flags.dart`: `totalPricedOnlyFlag`; `releases/flags.json`: rollout off.

## Verify

- `flutter test test/list/summary_priced_only_test.dart`: 20 tests, every case (none priced, partly
  priced, one store priced, all priced, trip running, priced store bought in full, weighed item,
  no-store item, foreign currency, 310 % text) with the flag on and off. Two mutations fail it
  (lines not filtered: 6 failures; amount never stacked: 1).
- `flutter test test/list test/trip`: 1441 passed.
- `journeys/total-priced-only.mjs` on the release web build: `--expect on` German 100 % and 310 %,
  English dark; `--expect off` German, all PASS. Screenshots `docs/screenshots/348/`.

merged as: the next commit on main (see the PR).
