# Item order: prototype round IO (job 347)

A throwaway HTML sandbox for one decision: how the list puts items in the right order with little or no category noise, and how people and agents change that order. Peter (t1119u) and Lea find stores and categories noisy and want the items in the order they walk. Nothing here ships, and the app is unchanged. The sandbox uses mock data only (the fictional Brandt family: an EDEKA trip, an IKEA trip, two items without a store), makes no network calls, and shows store names as plain text.

- `APPROACHES.md` holds the thinking: how order works today (with file and line), the five ordering models, how API and MCP read and set order, and the data, migration and sync.
- `index.html` is the overview. The preview's root overview (#414's) links the round too (`tools/link-overview.mjs`).
- `io/` is round IO. It starts with Today (the replica and the real app's screenshots), then IO1 to IO5. Each option has a live phone and frames for the supermarket, IKEA, a new item, fixing a place and the result. Then come the measured table and `io/RECOMMENDATION.md` (English) or `io/RECOMMENDATION.de.md` (German) with the pick (IO4), the runner-up (IO2) and IO-Q1 to IO-Q12.

The controls set the language (`?lang=de`), the theme (`?theme=dark`), the text size (`?ts=200` or `?ts=310`) and the phone (`?device=android`, 360 × 640; the default is a 390 × 844 iPhone).

## Files

- `model.js` holds the mock list, the categories the classifier gives each name (German and English), the real walking order, and the orders: today's (`categorical`), a learned sequence with its prior (`placeByPrior`, `learnTrip`), and a manual one. `act` is every action a live phone takes.
- `options.js` describes Today and the five options as records. `paths.js` is each option's fix as the taps a person makes, and the IKEA cost.
- `phone.js` draws the list screen, the edit sheet and the stores screen with the geometry of the release web build. `page.js` builds the pages and runs the live phones (tap ticks, hold or right click edits, IO3's handles drag). `text.js` holds the page's own words.
- `strings.js` is generated from the ARB files (`tools/strings.mjs`). Its `proposed` part holds the four new words, which the phones mark with a dotted underline.
- `icons.js` holds the app's Material icons, read from Flutter's icon font.
- `tools/capture-today.mjs` puts the same list into the real app (a verify-snacklist instance) and records the categories, the row positions and screenshots in `io/real/`.
- `verify.mjs [<root>] [--path <url path>] [--write]` drives the round in Chromium. It runs both languages on both phones at every text size. It checks:
  - that `strings.js` equals the ARB files;
  - each option's order against the model, no category heads where an option has none, and nothing sticking out of any frame;
  - Today's rows against the release build's positions (3 px at 100 %, 5 % at large text), and the model's categories against the classifier's;
  - every fix replayed on the live phone by real clicks, counted, and where Eggs end up;
  - where a new item lands, that a tap ticks, and that a trip's end teaches its order only in the learning options;
  - IO3's sort mode and IO5's switch;
  - the numbers in `io/measured.json` and both `RECOMMENDATION` files.

  Its last line is `all checks passed (N)`. `--write` stores the measurements in `io/measured.json`.
- `build.sh <out> [--base <deployment id>]` builds the preview folder. `tools/shots.mjs <out>` takes the PR's screenshots.

## Run

From the repo root, run `node docs/design/order/verify.mjs`. To check the preview, run `bash docs/design/order/build.sh /tmp/dist` and then `node docs/design/order/verify.mjs /tmp/dist --path /order/`.
