# Round AI: the app icon without the hexagon

Job 372. Five icons (AI1 to AI5) for Snacklist once RD1 removes the hexagons, next to today's icon. The
recommendation and the measurements are in [RECOMMENDATION.md](RECOMMENDATION.md) ([German](RECOMMENDATION.de.md)),
both generated from the page's words.

## Files

- `design/app-icon/art/today.mjs`, `ai1.mjs` ... `ai5.mjs`: one art module per icon. `design/app-icon/build.mjs`
  draws the module it is given (`--art`, default today) and writes into the repo or `--out <dir>`.
- `assets/<option>/`: each option's full set, laid out like the repo: iOS AppIcon (light, dark, tinted) and the
  Icon Composer bundle, Android adaptive foreground, background and monochrome plus legacy mipmaps, splash
  screens, web icons, brand block, email and Alexa icons, and `store/app-store-1024.png` and `store/play-512.png`.
- `index.html`, `page.js`, `page.css`, `copy.js` (words, English and German), `options.js`: the page.
- `tools/render.mjs`: renders every preview image and writes `measured.json`.
- `tools/approaches.mjs`: writes `RECOMMENDATION.md` and `.de.md`.
- `build.sh <out>`: builds the page into `<out>/app-icon/ai/`.
- `tools/fetch-base.mjs`, `tools/link-overview.mjs`: the preview keeps the earlier rounds and lists this one first.

## Check

```sh
node docs/design/app-icon/ai/verify.mjs
```

It checks that today's icon files are unchanged (`build.mjs --check`), that each committed asset set is what
the generator writes, that `measured.json` and both RECOMMENDATION files match fresh runs, that every option
fits Android's 66 dp safe circle, and that each number the recommendation quotes matches `measured.json`.

## Deploy (preview only)

```sh
node docs/design/app-icon/ai/tools/fetch-base.mjs <latest prototypes deployment> /tmp/out   # VERCEL_TOKEN set
docs/design/app-icon/ai/build.sh /tmp/out
node docs/design/app-icon/ai/tools/link-overview.mjs /tmp/out
cd /tmp/out && vercel deploy   # project family-groceries-design, never --prod
```
