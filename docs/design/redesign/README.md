# Redesign without hexagons (job 353)

Round RD: ten design directions away from the hexagons, on today's colours. Throwaway prototype: nothing here is app
code. The decision and its numbers are in `rd/RECOMMENDATION.md` (German: `rd/RECOMMENDATION.de.md`); where the
hexagons are today is in `HEX-INVENTORY.md`.

- `rd/index.html`: the round page. `?opt=RD3` shows one option's six frames, `?theme=dark`, `?lang=de`, `?ts=200|310`.
- `options.js`: one row per option (corners, menu, tick, price and store style, taps); `render.js` draws a phone
  frame from it; `proto.css` holds each option's look under `.o-<id>`.
- `data.js`: the mock list (the fictional Brandt family, job 350's 12 items, job 348's TE1 total).
- `strings.js` (from the ARB files, `tools/strings.mjs`), `palette.css` (from `tokens.g.dart`, `tools/palette.mjs`),
  `icons.js` (from Flutter's Material icon font, `tools/icons.py`).
- `measure.js`: rows, tap targets, contrast, borders, overflow, broken words and palette colours of one phone.
- `verify.mjs`: measures all 792 phones (11 options × 6 frames × 2 themes × 3 text sizes × 2 languages) and checks
  the RECOMMENDATION tables. `--write` updates `rd/measured.json`; `tools/table.mjs` rewrites the tables from it.
- `tools/shoot.mjs <query> <png> [--sel <css>]`: a screenshot of the page.
- `build.sh <out> --base <dpl id>`: the preview folder, on top of the previous preview's files.

Run from the repo root: `node docs/design/redesign/verify.mjs` (Playwright from `e2e/node_modules` or
`~/family-groceries/e2e`).
