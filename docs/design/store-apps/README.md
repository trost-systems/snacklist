# Store apps: prototype rounds OS and SS (job 314)

A throwaway HTML sandbox for two decisions: where "Open <store> app" lives (round OS, for DL1), and how users pick and recognise stores as chains across countries (round SS). Nothing here ships, and the app is unchanged. It uses mock data only (the fictional Familie Brandt), makes no network calls, and opens nothing.

- `index.html` is the overview. It links both rounds and shows each round's pick and runner-up.
- `os/` is round OS: today, and OS1 to OS5. `RECOMMENDATION.md` (and `.de.md`) holds the pick (OS1), the runner-up (OS4), the measured table and OS-Q1 to OS-Q8.
- `ss/` is round SS: SS1 to SS5, five scenarios each, and the registry table. `RECOMMENDATION.md` (and `.de.md`) holds the pick (SS2), the runner-up (SS5), the tap table, the data model proposal and SS-Q1 to SS-Q10.
- `registry/` is the retailer registry proposal:
  - `retailers.json` holds 59 chain and country entries in DE, AT, CH, FR, NL, PL, IT and ES, each id checked against Apple and Google.
  - `verify-registry.mjs` rechecks them (`--offline` checks only the schema; `--only DE,AT` limits the run).
  - `REGISTRY.md` explains how they were checked and lists the TODOs.

The controls set the language (`?lang=de`), the theme (`?theme=dark`) and the text size (`?ts=200`, Android's largest, or `?ts=310`, iOS's largest). OS also sets `?platform=android` and `?installed=no`, and SS sets `?scenario=migrate|new|unlisted|twocountries|country`.

## Files

- `phone.js` holds one state object, `view(state)` (the screens: list, stores, store, summary, and what a tap opens outside the app) and `act()` for the live phones. Each option is a record of hooks; the screens never test an option's label.
- `os.js` and `ss.js` hold the options, their frames, and SS's walks with the taps counted to each frame. `data.js` holds the mock household and the slice of the registry the scenes use. `copy.js` holds the strings: the ARB's where the app has one, new copy otherwise.
- `page.js` and `proto.css` are the pages. `icons.js` holds Material glyphs from Flutter's icon font (`tools/icons.py`). The tokens and fonts come from `site/public/`.
- `verify.mjs [<repo root or build dir>] [<screenshot dir>] [<playwright dir>] [--write]` drives both rounds in Chromium. It checks:
  - every phone in English and German, light and dark, at 100 %, 200 % and 310 %, for content past the edge, text that spills, and targets under 44 px;
  - for OS1, OS3 and OS4, what a tap opens per platform and installed state, and the taps it takes;
  - that a store without an app never shows a button;
  - OS5's done line, live;
  - the extra height and rows in view against today at 390 × 844 (`measured.json`, and the tables in both RECOMMENDATION files);
  - SS's end states per scenario;
  - that every chain the scenes use is a verified registry entry with the same app name and link;
  - the overview at 390 px.

  The last line is `all checks passed (N)`.
- `build.sh <out> [--base <deployment id>]` builds the preview folder. With `--base`, it first fetches the earlier preview's files byte for byte (`tools/fetch-base.mjs`, which needs `VERCEL_TOKEN`).

## Run

From the repo root, run `node docs/design/store-apps/verify.mjs`. To check the preview, run `bash docs/design/store-apps/build.sh /tmp/dist --base dpl_2wt4ZzVtvWc1u3vYiN6U6mYdmw46` and then `node docs/design/store-apps/verify.mjs /tmp/dist`.
