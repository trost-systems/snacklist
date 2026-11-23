# Guides on snacklist.app

The public guides site (`site/`, its own Vercel project, static HTML from Markdown) explains how to set up the voice entry points, the Siri Shortcut (job 24a, #54) and the Alexa skill (#127), and how to connect Claude over MCP (job 62, #184); a Home Screen widget guide (#185) is still a draft. German guides live under `/de/anleitungen/<slug>`, English ones under `/en/guides/<slug>`; each language has an index that lists its guides, each guide links its translation, and `/` sends a visitor to the landing page (`/de` or `/en`) in their browser's language. The help page and the legal pages on the same site are `features/legal.md`. hummlist.com redirects to it (S3); its pages name snacklist.app as canonical since job 174. The app links no guide yet (`siriGuideUrl` in `app/lib/core/guides.dart` has no caller), but it links the changelog (Feedback & Ideen's `feedback-whats-new`, `changelogUrl`); the help page links the Alexa guide, the landing page (`site/content/landing/copy.yml`) the Siri guide, and every page's nav the guides index.

## Sub-features

- `gd-index` `/de/anleitungen` ("Anleitungen") and `/en/guides` list the guides of that language with title and description, generated from `site/content/guides/<locale>/`.
- `gd-siri` `/de/anleitungen/siri-kurzbefehl` and `/en/guides/siri-shortcut` walk through the Shortcut that calls the voice endpoint (`features/voice.md`).
- `gd-alexa` `/de/anleitungen/alexa` and `/en/guides/alexa` explain enabling the skill "Snacklist", linking the account and the phrases (`features/alexa.md`).
- `gd-claude` `/de/anleitungen/claude` ("Snacklist mit Claude verbinden") and `/en/guides/claude` ("Connect Snacklist to Claude", a full English guide) walk through adding the connector, connecting, example phrases, troubleshooting and disconnecting (`features/mcp-access.md`).
- `gd-widget-draft` `/de/anleitungen/widget` and `/en/guides/widget` (the Home Screen widget) are `draft: true`: shown with the draft banner in preview and local builds, left out of production (404).
- `gd-translation` every guide names its other language (`hreflang` de and en) and links it, such as `/de/anleitungen/alexa` → `/en/guides/alexa`.
- `gd-language-redirect` `/` answers 307 to the landing page `/de` for `Accept-Language: de…` (and without the header), and to `/en` for any other language (`site/vercel.json`).
- `gd-changelog` `/de/changelog` („Neuigkeiten“) and `/en/changelog` ("What's new") list each public release of `releases/releases.json`, newest first, with date and its changelog items; preview and local builds also show drafts from `releases/changelog/<version>.json` on top with the banner "Entwurf, noch nicht im Store". Every page's footer links it. Before the first public release production shows only the line that the first version is coming soon (`site/README.md`, "Changelog").
- `gd-noindex` every response carries `X-Robots-Tag: noindex` until the beta launch.
- `gd-since` content tagged `since` a version above the live version (newest public release in `releases/releases.json`, else `app/pubspec.yaml`) is left out of production and shown with a banner ("Ab Version X, noch nicht im Store") in preview and local builds; guide frontmatter `since:`, heading suffix `{since=X}`, block `::: since X` (`site/README.md`, "Versioned content"). Today the heading „Ohne Einrichtung: Siri kennt Snacklist“ (and its English twin) of both Siri guides is tagged `since=1.0.0` and `once=native-siri` (shown only once the hold `native-siri` in `releases/flags.json` is released, `site/README.md`), so production leaves it out.

## How to get to it (user POV)

- Open https://snacklist.app in a browser; it lands on the landing page in the browser's language, whose nav links "Anleitungen" / the guides index.
- From the help page (Mehr → "Hilfe & Kontakt", `features/legal.md`), follow the Alexa link.

## Driving it with fg

Preconditions: no app and no Supabase. `curl` for the live site; for a local build Node and `cd site && npm ci`.

- **Live pages.** `for p in de/anleitungen en/guides de/anleitungen/alexa de/anleitungen/siri-kurzbefehl de/anleitungen/claude en/guides/alexa en/guides/siri-shortcut en/guides/claude; do curl -s -o /dev/null -w "%{http_code} $p\n" https://snacklist.app/$p; done` prints 200 for each.
- **Redirect.** `curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H 'Accept-Language: de' https://snacklist.app/` prints `307 https://snacklist.app/de`; with `Accept-Language: en` it prints `307 https://snacklist.app/en`. `de/anleitungen/widget` answers 404 in production (draft).
- **Translation link.** `curl -s https://snacklist.app/de/anleitungen/alexa | grep -o -E 'href="/en/guides/[^"]*"|hreflang="[a-z]+"' | sort -u` lists `href="/en/guides/alexa"`, `hreflang="de"` and `hreflang="en"`.
- **No index.** `curl -sI https://snacklist.app/de/anleitungen | grep -i x-robots` reads `noindex`.
- **Local build.** `cd site && npm test` passes (content rules, links, drafts, placeholders, versioned content, the changelog, the preview server). `npm run build`, then `PORT=<port from your block> node scripts/preview.mjs` serves `dist/` with `vercel.json`'s redirects: the pages above answer 200 on `http://127.0.0.1:<port>/`, and `/` with `Accept-Language: en-US` answers 307 to `/en`; the widget drafts answer 200 with the draft banner. Stop the preview by its pid.
- **Live version.** `cd site && VERCEL_ENV=production node build.mjs` prints `live version: 0.1.0 (from app/pubspec.yaml, no public release yet)` before the page count while the record has no public release. `node --test test/versions.test.mjs` covers hidden guides, sections and blocks against fixture records.
- **Changelog.** `curl -s https://snacklist.app/de/changelog | grep -o 'Die erste Version[^<]*'` prints the empty state while the record has no public release; `curl -s https://snacklist.app/impressum | grep -o 'href="/de/changelog"'` finds the footer link. `node --test test/changelog.test.mjs` covers releases, drafts and the anchors (`#v1-0-0`) against fixtures.
- **Proof.** The curl output; for a page's look, a screenshot of the local preview in a browser.

## Gotchas

- The site is a separate Vercel project (Root Directory `site`); the app's build (`vercel.json` at the repo root, `features/web-hosting.md`) doesn't include it.
- A guide's `slug` must equal its file name and stays stable: links point to it (`site/README.md`, "Adding a guide"). A broken internal link, a second h1 or an external resource fails the build.
- `[PETER: …]` placeholders only warn in a local build; `VERCEL_ENV=production npm run build` fails on them.
