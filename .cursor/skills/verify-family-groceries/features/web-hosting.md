# Hosted web app

Anyone opens the production web app on Vercel and gets the sign-in page. Deep links such as `/oauth/consent` (MCP and Alexa connections, ending on "Verbunden" after "Erlauben") and `/join/CODE` (invites) boot the app on that route; the old `/settings` redirects to Zugänge (Konto with `?section=account`). "Mit Google anmelden" leads to Google's sign-in for the hosted Supabase project, and "Mit Apple anmelden" to Apple's for the Services ID `com.petertrost.familygroceries.web`. Each push to `main` deploys to `https://preview.app.snacklist.app`, behind Vercel Authentication. Production (`https://app.hummlist.com` and `https://app.snacklist.app`, one Vercel project) is the `release` branch, which `release.yml` moves to the commit it ships to the stores (`docs/DEPLOY.md`, section "Web app"). Branches get preview URLs.

## Sub-features

- `web-spa-routes` serves `index.html` with `Cache-Control: no-cache` for every app path, dotted ones such as `/join/AB.CD` included, and answers 404 for a missing asset such as `/missing.js`, `/assets/x.png` or anything under `canvaskit/`, `fonts/`, `icons/` or `.well-known/` (`vercel.json`, DECISIONS 7b.2). `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` answer as JSON, so `/join` links open the installed app.
- `web-cache` makes `index.html`, `manifest.json`, `flutter_bootstrap.js`, `flutter_service_worker.js` and `version.json` `no-cache`, the self-hosted fallback fonts (`/fonts/**/*.woff2`, the build's `fontFallbackBaseUrl`) `public, max-age=31536000, immutable`, and other files (`main.dart.js`, `main.dart.wasm`, `main.dart.mjs`, icons, assets) `public, max-age=0, must-revalidate`. `web-smoke.mjs` checks the three Flutter files and the three entry files; `curl -sI <url>/manifest.json` shows the rest.
- `web-google` takes the Google button to `accounts.google.com` with the web client ID from `app/config/auth.json`.
- `web-apple` takes the Apple button to `appleid.apple.com` with the Services ID.
- `web-build` runs `vercel.json`'s install and build commands in Amazon Linux 2023 from a fresh clone.
- `web-wasm` (job 28): the build is `flutter build web --wasm`. Chromium runs `main.dart.wasm` (skwasm, single-threaded: no COOP/COEP headers); Safari, every iOS browser, Firefox and browsers without WasmGC run `main.dart.js` from the same build (Flutter's `wasmAllowList` default, DECISIONS job 28). `vercel.json` serves `.wasm` as `application/wasm` and `.mjs` as `text/javascript`; `web-smoke.mjs` checks both and that Chromium loads the wasm app.

- `web-no-google` (job 33c, legal review H-02): the engine (`/canvaskit/`) and every font (the build's Roboto, the Noto fallback fonts under `/fonts/`) load from the app's own origin, nothing from `*.gstatic.com` or `*.googleapis.com`. Every response carries the CSP in `vercel.json`, which allows connections to the Supabase project, `eu.i.posthog.com`, `snacklist.app` (the item icon table, job 147; job 174, `test/core/web_csp_test.dart` ties it to `ITEM_ICONS_URL`) only (DECISIONS job 33c). `e2e/tests/no-google.spec.ts` proves it in Chromium, Firefox and WebKit with emoji, CJK and Arabic item names; `e2e/host-census.mjs` counts hosts on any URL.

## How to get to it (user POV)

- Open the production URL `https://app.snacklist.app` or `https://app.hummlist.com` (alias `https://family-groceries-pied.vercel.app`) in a browser.
- Follow an MCP client's "connect" link, which lands on `<url>/oauth/consent?authorization_id=...`.
- Open an invite link `<url>/join/CODE`.

## Driving it with fg

Preconditions:

- No `fg` stack is needed: the checks run against the hosted project. Install the e2e dependencies once with `(cd e2e && npm ci)`.

- **Routes, headers and both providers.** Run `node e2e/web-smoke.mjs <production-url> <dir>`. Every check line starts with `ok` (two more lines print the Google `client_id`, which must equal `GOOGLE_WEB_CLIENT_ID` in `app/config/auth.json`, and the screenshot directory), and the exit code is 0. Run it under `flock /tmp/fg-e2e.lock`: it starts a browser. `<dir>` then holds `1-sign-in.png` (Google and Apple buttons on `/oauth/consent`), `2-google-consent.png` (Google's "Anmeldung" page, "Weiter zu jdwqrallbpdbshrdhenk.supabase.co") and `3-apple-sign-in.png` (Apple's page naming the Services ID's description, "Einkauf Web" until Peter renames it to "Snacklist", `docs/NEEDS_PETER.md` job 20).
- **The build Vercel runs.** Run `scripts/vercel-local.sh /tmp/fg-vercel-out`. It ends with `output: /tmp/fg-vercel-out`. To check the providers against that output, start `node e2e/serve.mjs /tmp/fg-vercel-out 55081`, then run `SMOKE_BROWSER_ONLY=1 node e2e/web-smoke.mjs http://127.0.0.1:55081 <dir>`. `e2e/serve.mjs` routes like `vercel.json` but sends `cache-control: no-store` on everything, so the HTTP checks are skipped. Add `--csp https://jdwqrallbpdbshrdhenk.supabase.co https://eu.i.posthog.com` to send the production CSP.
- **Nothing from Google.** Run `flock /tmp/fg-e2e.lock node e2e/host-census.mjs <url> chromium,firefox,webkit` against a deployment or a local `serve.mjs --csp` of a build. It prints `<browser> <host> <count>` per host, plus `GOOGLE <url>` and `CSP <violation>` lines, and exits 1 if there is any. On a good build every host is the app's own (the login screen fetches nothing else). Before job 33c, Chromium showed `www.gstatic.com 2` and `fonts.gstatic.com 1`. The signed-in path with non-Latin items is `scripts/ci-e2e.sh --no-db --spec tests/no-google.spec.ts`, whose `HOSTS <browser> ...` lines list the counts.

## Gotchas

- Which app a browser runs: DevTools' Network tab shows `main.dart.wasm` or `main.dart.js`; in the e2e specs `watchBuild` (`e2e/tests/web-build.ts`) records it. `withoutWasmGC` makes Chromium take the JS fallback, `wasmAllowList` opts an engine in or out for one page.

- The smoke test stops at the providers' sign-in pages and never signs in. A full Google or Apple round trip needs a real account, so it is a manual step (`docs/NEEDS_PETER.md`, section 4, step 18).
- Production is the last store release, not `main`: to check what just merged, use `https://preview.app.snacklist.app` (its build of `main`) with a share link. Without a share link or a Vercel login it shows Vercel's login wall, not the app, and production stays on the last store release until the next dispatched Release run that uploads (the automatic per-merge runs only reach the internal testers, docs/RELEASE.md); a failed or skipped run keeps it there longer.
- Previews are behind Vercel Authentication (302 to vercel.com). Pass a share link from the Vercel dashboard as the URL (`<preview>/?_vercel_share=...`); the smoke test reuses its cookie. Production is public.
- On a preview URL or on localhost, the provider round trip ends on the production Site URL unless that origin is in the hosted redirect list. Reaching the provider page does not depend on it.
- `scripts/vercel-local.sh` builds the committed `HEAD` and ignores uncommitted changes, like Vercel does.
