# Shopping total: prototype round TE (job 343)

A throwaway HTML sandbox for one decision: what the list's total block shows when no item or only some items have a price. Peter (t1116u) found today's block "quite verbose for 0 info": with nothing priced it lists every store with "1 without price". Nothing here ships, and the app is unchanged. The sandbox uses mock data only (the fictional Brandt family), makes no network calls, and shows store names as plain text.

- `index.html` is the overview. It links the round and shows its pick and runner-up. The preview's root overview (#414's list-declutter rounds) links the round too (`tools/link-overview.mjs`).
- `te/` is round TE. It starts with today's rules (`summary_block.dart`, `subtotals.dart`), the Today replica in the four states and a screenshot of the real app. Then come TE1 to TE5, each with a live phone and a frame per state, the measured table, and `te/RECOMMENDATION.md` (English) or `te/RECOMMENDATION.de.md` (German) with the pick (TE1), the runner-up (TE2) and TE-Q1 to TE-Q9.

The four states: (a) no item has a price; (b) Lidl priced in full (one per-kg item), Edeka's bread priced and its butter not, dm, IKEA and no store unpriced; (c) every item priced; (d) as (b) with a trip running, Lidl and the bread bought.

The controls set the language (`?lang=de`), the theme (`?theme=dark`), the text size (`?ts=200` or `?ts=310`) and the phone (`?device=android`, 360 × 640; the default is a 390 × 844 iPhone).

## Files

- `model.js` holds the mock list, the states, and `Sum`/`summaryOf` from `app/lib/list/subtotals.dart` in JS. `strings.js` is generated from the ARB files (`tools/strings.mjs`): the round adds no UI text.
- `blocks.js` holds Today's block and the five options as records of hooks (`block`, `divider`, `bar`, `sheet`). `phone.js` draws the list screen around them, with the geometry of the release web build. `text.js` holds the page's own words, `page.js` builds the pages and runs the live phones.
- `tools/capture-today.mjs` puts the same list into the real app (verify-snacklist instance) and records its screenshots and semantics boxes. `te/real/heights.json` holds the block heights it measured; the PNGs in `te/real/` are from the same runs.
- `verify.mjs [<root>] [--path <url path>] [--write]` drives the round in Chromium on both phones, in both languages and both themes, at every text size the phone offers. It checks:
  - that `strings.js` equals the ARB files;
  - in every option and state: no store line says "without price", the floor and ≈ marks sit exactly where an item lacks a price or holds a planned weight, the store lines add up to the total, "No store" keeps its own line, a trip shows what was bought;
  - each option's own rules (TE1 to TE5), nothing sticking out of the phone, and 44 px controls;
  - the Today replica against the real app's heights (±3 px on the iPhone at 100 %, 12 % elsewhere);
  - the live phones: pricing an item, opening TE2, TE4's link to the next unpriced item, TE5's sheet, a tick on a trip;
  - the numbers in `te/measured.json` and both `RECOMMENDATION` files.

  Its last line is `all checks passed (N)`. `--write` stores the measurements in `te/measured.json`.
- `build.sh <out> [--base <deployment id>]` builds the preview folder. `tools/shots.mjs <out>` takes the PR's screenshots.

## Run

From the repo root, run `node docs/design/totals/verify.mjs`. To check the preview, run `bash docs/design/totals/build.sh /tmp/dist` and then `node docs/design/totals/verify.mjs /tmp/dist --path /totals/`.
