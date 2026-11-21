# The list: prototype round RU (job 355), "Recently used" expanded

A throwaway HTML sandbox for one decision: how "Recently used" stays open under the list and looks different from the open items, so a tick visibly lands there and one tap brings an item back (undo is that tap; SPEC has no undo button). Nothing here ships, and the app is unchanged. The sandbox uses mock data only (the fictional Brandt family: an EDEKA and a dm list, 15 bought items) and makes no network calls.

- `index.html` is the overview, with one card for round RU. The preview's root overview links the round too (`tools/link-overview.mjs`).
- `ru/` is round RU: Today (with the real app's screenshots), then RU1 to RU4. Each has a live phone with scene buttons (short list with 0, 3 or 15 recent items, long list with 3 or 15, reset) and frames: `short-0`, `short-3`, `short-15`, `long-15`, `scrolled` (long list, scrolled to the section), the tick strip (`tick-start`, `tick-mid`, `tick-landed`), `back` and, for RU4, `all`. Then the measured table and `ru/RECOMMENDATION.md` (English) or `ru/RECOMMENDATION.de.md` (German).

The controls set the language (`?lang=de`), the theme (`?theme=dark`), the text size (`?ts=200` or `?ts=310`) and the phone (`?device=android`, 360 × 640; the default is a 390 × 844 iPhone).

The base list is today's list with job 350's hidden categories (no category heads) and job 348's total (TE1: only stores with a priced item get a line, the total once with "N without price"). The replica's geometry comes from job 347's (`docs/design/order`). Today's "Recently used" tile and rows were checked against the release web build (`ru/real/`, `tools/capture-today.mjs`): 21 px below the total, a 48 px tile (164 px at 310 %), 48 px rows (79 px at 310 %).

## Files

- `model.js` holds the mock items (store, walk rank, price), the open lists, the bought bank, the state and its actions (`tick`, `back`, `fold`, `showAll`) and TE1's summary. An item's place on the list is derived from its store and rank, so a tap-back lands where the item was.
- `options.js` holds Today and RU1 to RU4 as records: the section (`recent`), RU2's peek (`peek`), whether it starts folded, and how a tick leaves the list (`motion`).
- `phone.js` draws the list screen, settles a phone's scroll and RU2's peek, and measures what a phone shows (`measure`). `page.js` builds the pages, runs the live phones and the tick motion (check 150 ms, fold 250 ms, highlight fading 700 ms; instant with reduced motion). `text.js` holds the page's own words.
- `strings.js` is generated from the ARB files (`tools/strings.mjs`). Its `proposed` part holds the five new words, which the phones mark with a dotted underline.
- `icons.js` holds the app's Material icons (job 347's, plus `check_circle` and `undo`).
- `tools/measure.mjs [--write]` measures every option in every scenario, language, phone and text size into `ru/measured.json` and fills the measured tables of both RECOMMENDATION files.
- `verify.mjs [--dir <root> --path <url path>]` drives the round in Chromium. Its last line is `all checks passed (N)`.
- `tools/mutate.mjs` breaks the round six ways in a built copy and records which checks fail in `ru/MUTATIONS.md`.
- `build.sh <out> [--base <deployment id>]` builds the preview folder. `tools/shots.mjs <out>` takes the PR's screenshots (`docs/screenshots/355/`).

## Run

From the repo root, run `node docs/design/list/verify.mjs`. To check the preview, run `bash docs/design/list/build.sh /tmp/dist` and then `node docs/design/list/verify.mjs --dir /tmp/dist --path /list/`.
