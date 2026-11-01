# Site browser checks

Chromium checks of the built site (`site/dist`), served by `../scripts/preview.mjs` with
`vercel.json`'s headers (CSP `default-src 'self'`, `X-Robots-Tag: noindex`), redirects and clean
URLs. They are not part of `npm test` or the `site` CI gate: they need a browser and take minutes.
Run them after any change to the site's CSS, templates, scripts or media.

```bash
cd site && npm run build
cd checks && npm ci
flock /tmp/fg-e2e.lock node crawl.mjs ../dist        # pages, links, CSP, axe, targets, focus, motion
flock /tmp/fg-e2e.lock node contrast.mjs ../dist     # text and non-text contrast, with a table
flock /tmp/fg-e2e.lock node lighthouse.mjs ../dist   # Lighthouse scores, JSON and summary in --out
flock /tmp/fg-e2e.lock node selftest.mjs ../dist     # proves crawl.mjs reports each breakage
```

Every script takes `--port` (127.0.0.1 only) and `--pages /de,/en` to narrow it. On a shared host
the lock keeps it to one browser at a time. Exit code 1 means a problem, listed with its page,
selector and run.

## What each check proves

`crawl.mjs` crawls every page reachable from `/de` and `/en`, plus `/` and a missing path, at
390 and 1440 px in light and dark with reduced motion, and once more at 1440 light with motion
allowed:

- no CSP violation, no failed, 4xx or off-origin request; every linked file answers 200;
- Bricolage Grotesque and Inter loaded; no horizontal scroll;
- axe-core (WCAG 2.0, 2.1 and 2.2 A and AA): no violation;
- every button and non-inline link is at least 48 × 48 px;
- every tab stop shows a focus indicator that changes enough pixels by at least 3:1 (WCAG 2.4.13);
- with reduced motion nothing animates and no video plays; with motion a demo video plays only in
  view;
- a hex button's face sinks by its edge (`--hl-depth-edge`) on press.

`contrast.mjs` covers the landing pages, a guide, the changelog and the privacy policy: text through
axe's color-contrast rule with the blocks' background images removed, and the pixels for nodes axe
cannot decide (at least 4.5:1, large text 3:1). Non-text: each hex control's contour against its
block and each focus ring against its surroundings (at least 3:1).

`lighthouse.mjs` runs Lighthouse for `/de` and `/en`, mobile (390) and desktop (1440), light and
dark. Chrome gets `--blink-settings=preferredColorScheme=0|1`, and each run proves the scheme took
effect from the page ground in Lighthouse's own final screenshot. `is-crawlable` fails on purpose
(the noindex header until the beta launch); accessibility must be 100.

`selftest.mjs` copies the build, breaks `/de` in one known way per check (a small button, an
autoplaying video, an external image, a wide paragraph, faint text, no focus ring, no press depth,
a spinning logo) and fails unless `crawl.mjs` reports every one.
