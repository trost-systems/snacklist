# After-add sheet: prototype round AS (job 319)

A throwaway HTML sandbox for one decision: how the add sheet looks after an item was added. It drops the close key, the "Just added" header, the "Added / Undo" row and the gap above the field, and it keeps every field in view while the keyboard is up. Nothing here ships, and the app is unchanged. It uses mock data only (the fictional Familie Brandt), makes no network calls, and shows store names as plain text (Legal N-292).

- `index.html` is the overview. It links the round and shows its pick and runner-up.
- `as/` is round AS. It shows today's replica and the options AS1 to AS5, each with a live phone and ten frames, followed by the measured table and the recommendation. The recommendation comes from `RECOMMENDATION.md` (in English) and `RECOMMENDATION.de.md` (in German), which give the pick (AS1), the runner-up (AS2) and AS-Q1 to AS-Q10.

The controls set the language (`?lang=de`), the theme (`?theme=dark`), the text size (`?ts=200` or `?ts=310`) and the phone (`?device=android`, a 360 × 640 Android with Gboard; the default is a 390 × 844 iPhone with its keyboard).

## Files

- `model.js` holds the mock household, the app's strings (each from an ARB key; the round adds no UI text), and the one reducer all options share.
- `phone.js` draws the phone: the list behind the sheet, the sheet and the system keyboard. Each option is a record of layout hooks. `walk.js` holds each option's taps for store and category, and the ten frames as reducer actions. `text.js` holds the page's own words. `page.js` builds the pages and runs the live phones.
- `verify.mjs [<root>] [--path <url path>] [--write]` drives the round in Chromium on both phones, in both languages and both themes, at every text size the phone offers. It checks:
  - every frame: no close key, Undo or "Just added"; an empty list before the first add, then only the last two adds;
  - no gap above the field, and every field in view above the keyboard without the sheet scrolling;
  - the store and category taps, clicked on the live phone, with the swipes they need;
  - a tap on an earlier row edits it, and a tap on the list and a swipe on the grabber each close the sheet;
  - the numbers in `measured.json` and `RECOMMENDATION.md`.

  Its last line is `all checks passed (N)`. `--write` stores the measurements in `measured.json`.
- `build.sh <out> [--base <deployment id>]` builds the preview folder. `tools/shots.mjs <out>` takes the PR's screenshots.

## Run

From the repo root, run `node docs/design/after-add/verify.mjs`. To check the preview, run `bash docs/design/after-add/build.sh /tmp/dist` and then `node docs/design/after-add/verify.mjs /tmp/dist --path /after-add/`.
