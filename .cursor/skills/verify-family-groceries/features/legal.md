# Help page and legal links

The help and contact page lives on the guides site (`site/`, snacklist.app): `/support` (German) and `/en/support`, from `site/content/legal/support.md` and `support-en.md`. Peter approved the text on 2026-10-30 (#126), so both pages are published in every build without a banner, and the site footer links them. The app opens them from More → "Hilfe & Kontakt" in every build. The privacy policy and its app links are job 33a/33b's (in the app: the row "Datenschutzerklärung" in the legal group on More); the imprint is `sm-imprint` in `shell-more.md`; the guides on the same site are `features/guides.md`.

## Sub-features

- `lg-help-row` More shows "Hilfe & Kontakt" / "Help & contact" (`more-help`, one line with an external-link icon, no detail since job 85) under "Feedback senden", in release builds too (`supportPagePublished` in `app/lib/core/guides.dart`).
- `lg-help-open` a tap opens https://snacklist.app/support (German UI) or https://snacklist.app/en/support (any other language) in the system browser (a new tab on the web); the app stays on More.
- `lg-pages` https://snacklist.app/support and https://snacklist.app/en/support answer 200 without an "ENTWURF" / "DRAFT" banner and link the Alexa guide (`/de/anleitungen/alexa`, English `/en/guides/alexa`). The whole site still sends `X-Robots-Tag: noindex` until the beta launch.
- `lg-draft` the site's draft mechanism stays for other pages: `draft: true` shows a page with the banner, an HTML comment and `noindex` in preview and local builds, and `VERCEL_ENV=production` builds leave it out (404). The data processing agreement (`/avv`, `/en/dpa`) answers 404 in production that way. The old purchases privacy drafts (`/datenschutz-kaeufe`, `/en/privacy-purchases`) are deleted (Legal N-364) and answer 404 everywhere.

## How to get to it (user POV)

- Tap "Mehr", scroll to "Feedback senden" and tap "Hilfe & Kontakt" below it.
- Open https://snacklist.app/support, or follow the footer link on any page of the site.
- Imprint and privacy also sit under the login form as "Impressum · Datenschutz" (`legal-imprint`, `legal-privacy`; web e2e `e2e/tests/legal.spec.ts`), and in the app as direct rows on More, a group without a label (`more-imprint`, `more-privacy-policy`, `more-terms`, `more-licenses`; `features/shell-more.md`, `sm-legal`). The imprint is two taps from the list (Mehr, Impressum).

## Driving it with fg

Preconditions: for the app, the baseline from `features/README.md` with peter on the list; for the site, Node and `cd site && npm ci`, no app and no Supabase.

- **`lg-help-row`.** `fg tap --key tab-more`, `fg wait --key more-screen`, `fg marionette -- scroll-to --key more-help`; `fg find --key more-help` counts 1. Take `fg screenshot --name lg-help-row`.
- **`lg-help-open`.** `fg tap --key more-help`; `fg wait --key more-screen` still succeeds. The URL goes to the system browser, not to an app screen: read it as in `features/shell-more.md` (Gotchas, a host without a browser), which logs https://snacklist.app/support, and https://snacklist.app/en/support after switching to English (`features/settings.md`). On the web, `e2e/tests/help.spec.ts` clicks the row and checks the new tab's URL for German and English, at 390 and 1366 px.
- **`lg-pages`.** `curl -s -o /tmp/support.html -w '%{http_code}\n' https://snacklist.app/support` prints 200, and `grep -c -i -E 'ENTWURF|DRAFT' /tmp/support.html` prints 0; the same for `/en/support`. `curl -s https://snacklist.app/support | grep -o 'href="/de/anleitungen[^"]*"' | sort -u` lists `href="/de/anleitungen"` (nav and footer) and `href="/de/anleitungen/alexa"` (2026-11-02). `curl -sI https://snacklist.app/support | grep -i x-robots` reads `noindex`.
- **`lg-draft`.** `cd site && npm test`: all tests pass; `draft.test.mjs` proves the draft path on copies of the pages turned back into drafts and that the support pages are published, `consistency.test.mjs` that the app's links are real pages and the publish switches agree.
- **Proof.** The screenshot, the logged URLs and the curl output.

## Gotchas

- `fg logs` doesn't show the browser launch; only a URL handler (or a running browser and `pgrep -af snacklist.app`) shows where the tap went.
- The local preview (`npm run build && PORT=<port> node scripts/preview.mjs`, default 55990) serves `vercel.json`'s redirects and headers; use a port from your own block. Stop it by its pid, not with `pkill -f preview.mjs` from a shell whose command line contains that text.
