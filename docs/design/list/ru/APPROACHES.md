# Round RU: "Recently used" open by default (job 355)

Peter asked for this on Nov 21, 2026, through the Snacklist PM. Undo is a tap on an item in "Recently used", and there is no undo button. He wants that section open by default and clearly different from the open items, so a tick doesn't look like the item vanished. This is a prototype round. Nothing in the app changes until Peter picks.

Preview: the `family-groceries-design` project, path `/list/ru/`. The deployment ID is in the job's `out/DEPLOYMENT`. Add `?lang=de`, `?theme=dark`, `?ts=200` or `?ts=310`, or `?device=android`.

## Today

- Ticking a row removes it from the list with a slide. No snackbar has followed a tick since job 29b (SPEC, Core features 1).
- "Recently used" is a folded `ExpansionTile` after the last store and after the shopping total (`app/lib/list/list_view/shopping_list_view.dart`, the `recently-used` tile and `_usedRow`). Its rows are the list's own `ItemRow` at 55 % opacity. A tap on one puts the item back ("Back on the list"), and its screen-reader label says so.
- `recentlyUsed()` (`app/lib/list/model.dart`) lists bought items newest first, one per thing, and none that is open again. The limit is 20, and the household's purchases are shared, not only mine.
- The base for this round is today's list with job 350's `hide-categories` (no category headings, same order, PR #608) and job 348's TE1 total (only stores with a price, PR #607). Both are unmerged and behind flags. The replica draws them as their PRs describe.

## Options

| Option | Header | Background | Rows | Divider | Hint that a tap brings it back |
| --- | --- | --- | --- | --- | --- |
| Today | "Recently used", folded | none | the list's rows at 55 % | tile rules | the row's screen-reader label only |
| RU1 Faded, as today, open | "Recently used" and count, chevron | none | the list's rows at 55 %, no price | tile rules | a line under the header: "Tap an item to put it back on the list." |
| RU2 Tinted tray with a peek | round check, "Ticked off" and count | sunken tint, rounded top | compact (40 px), muted, no price | the tray's edge | an undo arrow on every row. A peek on the add field holds the newest item while the tray is off screen |
| RU3 Chips | overline "Recently used" | none | outlined pills that wrap | dashed rule | the header sentence: "Need it again? Tap to put it back." |
| RU4 Ticked with checkmarks | a labelled rule, "Recently used · 3" | none | full height, filled round check, name struck through. The newest 5, then "Show all" | labelled rule | a line at the end: "Tap a ticked item to untick it." |

Every option starts open. A tick flashes the check (150 ms), folds the row out of the list (250 ms) and lands the item first in the section with a highlight that fades over 700 ms. With reduced motion this happens at once. One tap on a recent item puts it back at its place in its store with a highlight. None of the new elements uses a hexagon (job 353 is redesigning in parallel).

## Measured

At scroll top, at 390 × 844 and at 360 × 640, at 100 % and at the largest text, in English and German, with 0, 3 and 15 recent items, **no option shows one whole recent row**. The shopping total sits between the list and the section and fills the rest of the screen. With 0 recent items, every option draws no section and shows the same open rows as today. The full tables are in `RECOMMENDATION.md`, and `verify.mjs` checks the numbers quoted there against a fresh measure.

## Recommendation

**Pick: RU2. Runner-up: RU4.** RU2's peek is the only element that shows the ticked item landing on the first screen. It costs 1 open row on a long list on the iPhone and 2 on Android. RU4 is the clearest "ticked, not gone" once you scroll there, and the shortest section with 15 items. The reasons and the open questions RU-Q1 to RU-Q12, each with a default, are in `RECOMMENDATION.md` (German: `RECOMMENDATION.de.md`).
