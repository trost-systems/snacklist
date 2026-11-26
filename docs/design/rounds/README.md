# Prototype rounds sandbox

A throwaway React/Vite app that hosts the newest prototype rounds behind one overview. Mock data only, no
backend calls, nothing here ships in the app.

| Path | Round |
| --- | --- |
| `/` | Overview of every round, newest first (older rounds link to their draft PR) |
| `/reminders/sr/` | SR1–SR5 shopping reminders (job 465), `src/sr/` |
| `/round`, `/onboarding/t` | T1–T5 onboarding transitions (job 454's round, copied unchanged from the box sandbox) |

## Run and check

```sh
cd docs/design/rounds
npm ci
npm run dev            # http://127.0.0.1:4195/reminders/sr/
npm run build
npm run verify:sr      # needs a Chromium; VERIFY_CHROME=/path/to/chrome to override
```

`scripts/verify-sr.mjs` clicks every add path in SR1–SR5 from the empty state and counts the taps, edits and
deletes a reminder in each option, checks the "time already passed" fixture, measures the Mitteilungen content
at 390×844 (100 % and 140 % text, English and German), checks that no section card has a shadow, and takes 61
screenshots (`VERIFY_OUT`, default `verify-screenshots/sr/`, not committed). It exits 1 when a tap count or a
height differs from the table on the page (`src/sr/meta.ts`).

The page's URL keeps its state: `?o=sr2&f=passed&lang=de&theme=dark&text=140`.

## Deploy (preview only)

The `family-groceries-design` Vercel project serves the static build. Copy `dist/` to `public/` in an
empty folder with a `vercel.json` that rewrites every path to `/index.html`, link that folder to the project
and run `vercel deploy` without `--prod`. Deployment Protection stays on; the lead mints the share link.
