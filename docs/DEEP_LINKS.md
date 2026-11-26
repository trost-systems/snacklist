# Deep links (app.snacklist.app, app.hummlist.com, snacklist.app)

A link to `https://app.snacklist.app/<path>` or `https://app.hummlist.com/<path>` opens the
matching screen of the installed Snacklist app: iOS universal links, Android App Links. Hummlist
builds, until Hummlist retires, claim only app.hummlist.com. Where the app is not installed,
the same URL opens the web app, which routes it the same way. Emails (the E2 onboarding email links
`https://app.snacklist.app/more/invites`), the site and invites use these URLs. The phone apps'
invite links use `APP_URL`, `https://app.snacklist.app` since job 174. Job 66; invite
links (`/join/<code>`) came first in job 22. Job 462 claimed every product screen of the app URL and
the guides on `https://snacklist.app` (`/de/anleitungen…`, `/en/guides…`), which the app shows in its
own guide view, and added an "In der App öffnen" link for when the system did not open the app.

| | |
| --- | --- |
| Route table in code | [`app/lib/core/deep_links.dart`](../app/lib/core/deep_links.dart) (`appLinks`, one row per host group and path: `LinkHost.app` is app.snacklist.app and app.hummlist.com, `LinkHost.site` is snacklist.app) |
| Routing | [`app/lib/shell/router.dart`](../app/lib/shell/router.dart) (`authRedirect`, `buildRouter`) |
| iOS | [`app/ios/Runner/Runner.entitlements`](../app/ios/Runner/Runner.entitlements) (`applinks:app.snacklist.app`, `applinks:app.hummlist.com`, `applinks:snacklist.app`), [`app/web/.well-known/apple-app-site-association`](../app/web/.well-known/apple-app-site-association) (`appIDs` lists `com.snacklist.app` and `com.hummlist.app`), [`site/public/.well-known/apple-app-site-association`](../site/public/.well-known/apple-app-site-association) (`com.snacklist.app` only) |
| Android | [`app/android/app/src/main/AndroidManifest.xml`](../app/android/app/src/main/AndroidManifest.xml) (two `autoVerify` filters: hosts `app.snacklist.app` and `app.hummlist.com`, and `snacklist.app` on its own, because Android pairs every host of a filter with every path of it), [`app/web/.well-known/assetlinks.json`](../app/web/.well-known/assetlinks.json) (statements for `com.snacklist.app` and `com.hummlist.app`), [`site/public/.well-known/assetlinks.json`](../site/public/.well-known/assetlinks.json) (`com.snacklist.app` only) |
| Serving | [`vercel.json`](../vercel.json) and [`site/vercel.json`](../site/vercel.json): `.well-known/` stays out of the SPA rewrite and of every redirect; the AASA is served as `application/json`, also at `/apple-app-site-association` (a rewrite, no redirect) |
| Guide view | [`app/lib/guides/`](../app/lib/guides/) reads `https://snacklist.app/data/guides/<locale>/<slug>.json` and `index.json`, which [`site/guide-data.mjs`](../site/guide-data.mjs) writes from the same gated tokens as the guide's HTML |
| Hand-off | [`app/web/join/join.js`](../app/web/join/join.js) (`appLink`), [`site/public/open-in-app.js`](../site/public/open-in-app.js) |
| Checks | [`app/test/core/deep_links_config_test.dart`](../app/test/core/deep_links_config_test.dart) (both hosts), [`app/test/shell/router_test.dart`](../app/test/shell/router_test.dart), [`app/test/guides/`](../app/test/guides/), [`site/test/app-links.test.mjs`](../site/test/app-links.test.mjs), [`site/test/guide-data.test.mjs`](../site/test/guide-data.test.mjs), [`e2e/tests/join-page.spec.ts`](../e2e/tests/join-page.spec.ts) (the hand-off), [`scripts/gates/web-prod.sh`](../scripts/gates/web-prod.sh), [`e2e/tests/deep-links.spec.ts`](../e2e/tests/deep-links.spec.ts), [`e2e/web-smoke.mjs`](../e2e/web-smoke.mjs) on a deployed URL |
| Decisions | [DECISIONS.md](DECISIONS.md), "Job 66" |

## Route table

| Link | Opens | Signed out |
| --- | --- | --- |
| `/list` | the list | sign-in, then the list |
| `/add` | the list with the add sheet open and the field focused | sign-in, then the add sheet |
| `/stores/<store id>` | the list, scrolled to that store's section and unfolded. An unknown id, another household's store or a store without open items: the list | sign-in, then the store |
| `/more` | the More tab | sign-in, then More |
| `/more/invites` | More, Einladungen (invite the partner, open invites) | sign-in, then Einladungen |
| `/more/settings` | More, Einstellungen (theme, language) | sign-in, then Einstellungen |
| `/more/settings/language`, `/more/access`, `/more/account`, `/more/lifetime` | the More page of that path | sign-in, then that page |
| `/join/<code>` | the join screen for that invite | sign-in, then the join screen (job 22) |
| `/join` | the join screen for a typed code | sign-in, then the code entry (also without a household). Without the app Vercel serves the join page's folder, which hands it to the web app at `/?next=%2Fjoin` |
| `/edit`, `/edit/<store>` | Anpassen: the stores, one store's details | sign-in, then that page |
| `/history`, `/history/trip/<id>`, `/trip/<id>` | Verlauf and a trip's summary (the list while the flag `grocery-log` is off) | sign-in, then that page |
| `/households/new`, `/households/new/invite` | one more household | sign-in, then the guided start (an account without a household sets its first one up there) |
| `snacklist.app/de/anleitungen`, `/en/guides` | the app's guide index in that language | the same, without sign-in |
| `snacklist.app/de/anleitungen/<slug>`, `/en/guides/<slug>` | the guide in the app's guide view (✕ goes to `/`), at a link's `#section`; `<slug>.md` and `<slug>.html` are the guide, any other path below the index | the same, without sign-in |
| anything else on the app URL | the list | sign-in, then the list |

The app's own `/` is the list too, but it is not claimed (see below).

Signed out, the link's location rides along as `/login?next=<location>`. After sign-in the
analytics question comes first on a new install, then the link's screen. An account without a
household goes through onboarding first (Step 1, creating or joining) and then lands on the
link's screen instead of Step 3. Signing out never carries the screen the user was on. While a link waits for the
sign-in, "Neu bei Snacklist?" leads back to the sign-in (the link is a sign-in's; it is dropped by
a sign-out or an app restart). A link reached before there is a household (the code entry, `/join`)
is forgotten once shown, so back from it leads to the welcome screen.

On iOS and Android a sign-in that leaves the app (a magic link, Apple on Android) comes back
through `com.snacklist.app://login-callback`, which loses the location. The router keeps the
link's location in memory until the sign-in completes. Invite codes also survive an app kill
(`PendingInvite`, job 22); other links do not, the app then opens the list.

## What the apps claim, and what not

Only the paths in `appLinks` open the app. Each is listed in the AASA `components` and as a
`<data android:path|pathPrefix>` of the verified intent filter; `deep_links_config_test.dart`
fails when either differs from the table.

Not claimed, so they always stay in the browser:

- `/`: web sign-in (Google, Apple, magic link) returns to the app URL with a code that only the
  browser that started it can redeem. A link-continuing web sign-in returns to `/?next=<link>`
  for the same reason.
- `/login`, `/welcome`, `/welcome/*`, `/analytics-consent`: pages a browser flow redirects to.
- `/oauth/consent`: the MCP OAuth consent page (docs/MCP.md) must finish in the browser of the
  MCP client's flow.
- `/settings`: the redirect for links from before job 29d (Zugänge, or Konto with
  `?section=account`). It still works in the app and on the web, it just does not open the app.
- Static files (`/konto-loeschen.html`, assets).
- `/start`, `/start/*`, `/your-name`: the guided start and its questions, flows of the browser
  they started in.
- On snacklist.app everything but the guides: `/`, `/de`, `/en`, the legal pages (Impressum,
  Datenschutz, Nutzungsbedingungen, AVV, Inhalte melden, consent texts), the support pages, the
  changelog, the comparisons, the waitlist pages, `/data/`, `/api/`, `/llms*.txt`. `www.snacklist.app`
  redirects to the apex, so it is not claimed (Apple and Google do not follow redirects).

The app never opens a claimed snacklist.app URL itself: on Android `launchUrl` would resolve it
back to the app. Legal, support and changelog links stay unclaimed (`guides_test.dart` checks
that); a guide inside the app is a route, not a URL.

## When the system does not open the app

A URL typed or pasted into Safari, a link tapped on the same domain, or a choice of "open in
browser" keeps the page in the browser. The join page and the site's guide pages then show a
quiet "In der App öffnen" link, only on iOS and Android. The join page hides it once the invite
turns out invalid or full. The site renders it only in the `launch` stage (`site/config/stage.ts`):
before that most phones have no app and Safari would answer the scheme with "address is invalid".

- iOS: `com.snacklist.app://open/<path>` (the sign-in scheme with host `open`; supabase_flutter
  only reacts to links with auth parameters, the router routes the path like the universal link).
  Without the app Safari says it cannot open the address.
- Android: `intent://<host>/<path>#Intent;scheme=https;package=com.snacklist.app;S.browser_fallback_url=<page>;end`,
  which matches the verified https filter; without the app Chrome stays on the page.

The link is never followed by itself, so web sign-in and the unclaimed pages are untouched.

## Adding a link

1. Make the router handle the path (`authRedirect` in `router.dart`; a More page under `/more/`
   needs nothing else).
2. Add it to `appLinks` in `deep_links.dart`.
3. Add it to the AASA `components` of its host (`app/web/.well-known/` for the app URL,
   `site/public/.well-known/` for snacklist.app; `/x` exact, `/x/*` for a prefix) and to that
   host's verified filter in the manifest (`android:path` or `android:pathPrefix`). `flutter test
   test/core/deep_links_config_test.dart` tells you what is missing.
4. Add a row to `router_test.dart` and to the table above. A site page also needs the hand-off
   (`open-in-app.js`, see `site/build.mjs`) and a way for the app to show it.

Apple's CDN caches the AASA (up to a day or two); a new path opens the app once an iPhone has
the new file. Android verifies the domain, not paths, so a new path works with the app build
that has the new filter.

## Rollout

Job 462 (26 Nov 2026): the site's `.well-known/` files, its `/apple-app-site-association` and the
guide JSON go live when the site's production deploy follows main (after `supabase-deploy`). The app
host's root `/apple-app-site-association` and the join page's hand-off go live with the next
`release` push. The guide view, the new paths of the Android filter and `applinks:snacklist.app` need
a store build. On Android 11 and older, verification of an app's hosts was all or nothing, so
`snacklist.app/.well-known/assetlinks.json` has to be live before that build reaches phones; the
site deploys on merge, the build only after a release run, so the order holds.

Both hosts serve `app/web/.well-known/` from the `release` branch, so the new AASA goes
live with the next dispatched store release, together with the app that routes the paths
(docs/DEPLOY.md, "Web app"). An older app that receives a new link still opens: `/add` and
`/stores/<id>` show the list there, `/more/...` already worked. Check the live files with
`node e2e/web-smoke.mjs https://app.snacklist.app` (and `https://app.hummlist.com`) and Apple's
cached copy with `curl https://app-site-association.cdn-apple.com/a/v1/app.snacklist.app`;
Google's view of the domain is
`https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://app.snacklist.app&relation=delegate_permission/common.handle_all_urls`.
On 2026-11-10 both hosts' files list only `com.hummlist.app`: the `release` branch predates
#345, so Snacklist's entries go live with the next release upload.

## Home Screen widgets (job 63)

The widgets open the app with `snacklist-widget://open` and `snacklist-widget://add`, handled by
`app/lib/home_widget/` (not by these links). The widget's Add has its own add-sheet request next
to `ListLinks` in the list screen; it could map onto this table (`router.go('/add')`) instead.
That is a follow-up in job 63's files, not part of job 66.
