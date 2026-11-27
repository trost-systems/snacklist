# Prototype rounds sandbox

A throwaway React/Vite app that hosts the newest prototype rounds behind one overview. Mock data only, no
backend calls, nothing here ships in the app.

| Path | Round |
| --- | --- |
| `/` | Overview of every round, newest first (older rounds link to their draft PR) |
| `/focus/fh/` | FH1–FH5 focus highlight (job 485), `src/fh/` |
| `/reminders/sr/` | SR1–SR5 shopping reminders (job 465), `src/sr/` |
| `/round`, `/onboarding/t` | T1–T5 onboarding transitions (job 454's round, copied unchanged from the box sandbox) |

## Run and check

```sh
cd docs/design/rounds
npm ci
npm run dev            # http://127.0.0.1:4195/reminders/sr/
npm run build
npm run verify:sr      # needs a Chromium; VERIFY_CHROME=/path/to/chrome to override
npm run verify:fh      # round FH; about 3 minutes
```

`scripts/verify-fh.mjs` screenshots every control of round FH unfocused and focused (Today and FH1–FH5, light and
dark, soft and hex looks) in a 390×844 phone and compares the pixels: how far each indicator reaches past its
control and so what is left of the gap to each neighbour, the WCAG 2.4.13 area at 3:1 against a 2 px perimeter,
layout shift, and at 200 % and 310 % text (EN and DE) clipped labels and indicator pixels over glyphs. It exits 1
when an FH option misses one of those, or when the table on the page (`src/fh/meta.ts`) differs from what it
measured; `--print` prints the rows. `src/fh/shape.ts` is `HexBorder.pathFor` from the app, so a ring follows the
hexagon and the soft shape exactly; `src/fh/options.ts` says what each option paints on each kind of control.

`scripts/verify-sr.mjs` clicks every add path in SR1–SR5 from the empty state and counts the taps, edits and
deletes a reminder in each option, checks the "time already passed" fixture, measures the Mitteilungen content
at 390×844 (100 % and 140 % text, English and German), checks that no section card has a shadow, and takes 61
screenshots (`VERIFY_OUT`, default `verify-screenshots/sr/`, not committed). It exits 1 when a tap count or a
height differs from the table on the page (`src/sr/meta.ts`).

The page's URL keeps its state: `?o=sr2&f=passed&lang=de&theme=dark&text=140`, and for FH
`/focus/fh/?o=fh1&f=field&look=hex&theme=dark&text=310&lang=de`.

## Deploy (preview only)

The `family-groceries-design` Vercel project serves the static build. Copy `dist/` to `public/` in an
empty folder with a `vercel.json` that rewrites every path to `/index.html`, link that folder to the project
and run `vercel deploy` without `--prod`. Deployment Protection stays on; the lead mints the share link.
