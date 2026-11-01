# Job 53: first hummlist.com homepage (landing pages /de and /en)

PR #157, **not merged**: Peter approves first (NEEDS_PETER "Job 53"), because every push to
`main` goes live on hummlist.com. Preview (Vercel login):
https://hummlist-site-git-job-53-homepage-v1-peter-trost.vercel.app/de and `/en`.
Decisions: [DECISIONS.md](../DECISIONS.md) "Job 53".

## What was built

- **Landing pages `/de` and `/en`** from the existing generator: `site/landing.mjs` renders them
  from `site/content/landing/copy.yml` (every string in DE and EN with a status and a source) and
  `site/public/media/`. The layout follows the 6b prototype homepage: a cobalt hero, three feature
  cards (lemon, cobalt mist, mint), a tomato voice block, a cobalt privacy block and a lemon test
  block. It uses hex controls, the navy contour and the sticker shadow, in the final palette
  (design 6's yellow `#ffe24a`), light and dark, reduced-motion aware.
- **Redirects:** `/` sends `de…` to `/de`, other languages to `/en`, no header to `/de`, with
  `Vary: Accept-Language`. Every old route stays.
- **One header and footer on every page.** The brand (app icon #5) links the landing page. The
  header has Anleitungen/Guides, Neuigkeiten/What's new, the language switch and "Im Browser
  öffnen". The footer has the site links, the legal links (by their flags) and a skip link. The
  guides, the changelog and the legal pages keep their texts and get the 6b type and colours.
- **Tokens** are job 52's files, taken verbatim (`design/tokens/*`, `site/public/tokens.css`,
  `app/lib/design/tokens.g.dart`, the `--check` in the lint gate). The fonts are self-hosted with
  their OFL texts.
- **Three demo-video slots** (`add-tick`, `household-sync`, `mcp-chat`) for job 54.
  `site/public/media/README.md` names the files. The page shows a poster until the files exist,
  and then a muted, looped, captioned `<video>` that `public/demo.js` plays only in view and
  never under reduced motion. Half a set fails the build.
- **Illustrations:** five HTML scenes in `site/scenes/`, filmed by `node site/scenes/film-all.mjs`
  into 40 WebP stills (DE and EN, wide 16:9 and compact 4:5 at 358 px, light and dark, 29 to
  50 KB). The hand-over notes per scene are in `site/scenes/README.md`.
- **Copy for Hummlist Launch:** `site/COPY_NEEDED.md` is generated from `copy.yml`. It lists 43
  drafts and 2 reused strings, each tagged in the page with `data-copy-id`. Siri is „Bald“ /
  "Coming soon". There is no pricing, no Alexa, no Apple Watch and no ChatGPT listing.
- **Browser checks** in `site/checks/` (`README.md` there): `crawl.mjs`, `contrast.mjs`,
  `lighthouse.mjs`, and `selftest.mjs`, which proves the crawl catches 8 kinds of breakage.

## How it was verified

| Check | Result |
| --- | --- |
| `cd site && npm ci && npm run build && npm test` | 96 tests pass |
| `VERCEL_ENV=production npm run build` | passes, 17 pages, no drafts or placeholders |
| `scripts/verify.sh --only site,lint`, `flutter analyze` | pass |
| `crawl.mjs`: 17 pages × 390/1440 × light/dark (reduced motion) + 1440 with motion | 0 problems: no CSP violation, no failed or off-origin request, fonts load, no horizontal scroll, axe 0 violations, 832 targets ≥ 48 px, 1028 tab stops with a visible focus, 80 hex presses sink by the edge |
| `contrast.mjs`: /de, /en, a guide, the changelog, the privacy policy | all text ≥ 4.5:1 (lowest 5.79, navy on tomato), every hex control and focus ring ≥ 3:1 |
| Lighthouse `/de`, `/en` × mobile/desktop × light/dark | accessibility 100, best practices 100, performance 94 mobile / 100 desktop, SEO 66 (only `is-crawlable`, the intended noindex), CLS 0 |
| `selftest.mjs` | the crawl reports all 8 planted breakages |

The full reports are in `docs/screenshots/53/checks/`. Screenshots: `docs/screenshots/53/`
(DE and EN, 390 and 1440, light and dark, plus a guide, the guides index, the changelog and the
privacy policy).

## Review

- **Scenes:** a fresh-eye reviewer (Sonnet, frames only) found 15 faults. Most were fixed; the
  reasons for the six that stand are in `site/scenes/README.md`.
- **Code:** an independent correctness review (Opus) found nothing must-fix. All five
  should-fix items and nits are fixed: the poster stays until real frames play, the crawl reads
  each video in view (proven by breaking `demo.js`'s reduced-motion gate, which it then reports),
  captions without cues fail the build, a switch to reduced motion pauses a playing video, and
  `chrome-launcher` is declared. With test videos in the `add-tick` slot the crawl passes /de and
  /en in all five runs.
- **Page:** a second fresh-eye reviewer found 15. The fixes and the reasons for what stands are in
  DECISIONS 53.12.

## Not done or open

- Peter's approval and the merge (NEEDS_PETER "Job 53"), and Launch's pass over `COPY_NEEDED.md`.
- The demo videos are job 54's. Until then the three slots show stills.
- Job 52 is not merged. On rebase, take 52's token files verbatim. The site's favicons are copies
  of 52's generated icon #5 web files.
- Mobile LCP is 3.1 s under Lighthouse's slow-4G throttling (desktop 0.7 s). The hero is a 41 KB
  WebP with `fetchpriority="high"`. What remains is the two fonts and three stylesheets on a cold
  start.
