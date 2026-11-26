# Deep links (app.snacklist.app, app.hummlist.com, snacklist.app)

A link to `https://app.snacklist.app/<path>` or `https://app.hummlist.com/<path>` opens the
matching screen of the installed Snacklist app: iOS universal links, Android App Links. A link to
a guide on the public site (`https://snacklist.app/de/anleitungen/<slug>`,
`https://snacklist.app/en/guides/<slug>` and the two guide lists) opens the app's own view of that
guide (job 462). Hummlist builds, until Hummlist retires, claim only app.hummlist.com. Where the
app is not installed, the same URL opens the web app or the site, which shows the same thing.
Emails (the E2 onboarding email links `https://app.snacklist.app/more/invites`), the site and
invites use these URLs. The phone apps' invite links use `APP_URL`, `https://app.snacklist.app`
since job 174. Job 66; invite links (`/join/<code>`) came first in job 22; guides, Verlauf,
Anpassen and trip links in job 462.

| | |
| --- | --- |
| Route tables in code | [`app/lib/core/deep_links.dart`](../app/lib/core/deep_links.dart): `appLinks` (the app hosts), `siteLinks` (snacklist.app) |
| Routing | [`app/lib/shell/router.dart`](../app/lib/shell/router.dart) (`authRedirect`, `buildRouter`); guides: [`app/lib/guides/`](../app/lib/guides/) |
| iOS | [`app/ios/Runner/Runner.entitlements`](../app/ios/Runner/Runner.entitlements) (`applinks:app.snacklist.app`, `applinks:app.hummlist.com`, `applinks:snacklist.app`); [`app/web/.well-known/apple-app-site-association`](../app/web/.well-known/apple-app-site-association) (`appIDs` `com.snacklist.app` and `com.hummlist.app`); [`site/public/.well-known/apple-app-site-association`](../site/public/.well-known/apple-app-site-association) (`com.snacklist.app` only) |
| Android | [`app/android/app/src/main/AndroidManifest.xml`](../app/android/app/src/main/AndroidManifest.xml): two `autoVerify` filters, one for the app hosts and `appLinks`, one for snacklist.app and `siteLinks`; [`app/web/.well-known/assetlinks.json`](../app/web/.well-known/assetlinks.json) (`com.snacklist.app` and `com.hummlist.app`), [`site/public/.well-known/assetlinks.json`](../site/public/.well-known/assetlinks.json) (`com.snacklist.app`, the same fingerprints) |
| Serving | [`vercel.json`](../vercel.json) (web app) and [`site/vercel.json`](../site/vercel.json) (site): `.well-known/` stays out of the SPA rewrite; the AASA is served as `application/json`, also at `/apple-app-site-association` |
| Browser handoff | [`app/web/join/join.js`](../app/web/join/join.js) and [`site/public/open-app.js`](../site/public/open-app.js): „In der App öffnen“ on phones (below) |
| Checks | [`app/test/core/deep_links_config_test.dart`](../app/test/core/deep_links_config_test.dart), [`app/test/shell/router_test.dart`](../app/test/shell/router_test.dart), the guide tests in `app/test/guides/`, [`scripts/gates/web-prod.sh`](../scripts/gates/web-prod.sh), [`e2e/tests/deep-links.spec.ts`](../e2e/tests/deep-links.spec.ts), [`e2e/tests/join-page.spec.ts`](../e2e/tests/join-page.spec.ts), the site tests, [`e2e/web-smoke.mjs`](../e2e/web-smoke.mjs) on a deployed URL |
| Decisions | [DECISIONS.md](DECISIONS.md), "Job 66" and "Job 462" |

## Route table: app.snacklist.app and app.hummlist.com (`appLinks`)

| Link | Opens | Signed out |
| --- | --- | --- |
| `/list` | the list | sign-in, then the list |
| `/add` | the list with the add sheet open and the field focused | sign-in, then the add sheet |
| `/stores/<store id>` | the list, scrolled to that store's section and unfolded. An unknown id, another household's store or a store without open items: the list | sign-in, then the store |
| `/more` | the More tab | sign-in, then More |
| `/more/invites` | More, Einladungen (invite the partner, open invites) | sign-in, then Einladungen |
| `/more/settings` | More, Einstellungen (theme, language) | sign-in, then Einstellungen |
| `/more/settings/language`, `/more/access`, `/more/account`, `/more/lifetime`, `/more/household`, `/more/tips`, `/more/feedback`, `/more/feedback/<id>` | the More page of that path | sign-in, then that page |
| `/edit`, `/edit/<store id>`, `/edit/none` | Liste, Anpassen: the stores, one store's details | sign-in, then that page |
| `/history` | Verlauf (flag `grocery-log`; off: the list) | sign-in, then Verlauf |
| `/trip/<id>`, `/history/trip/<id>` | a trip's summary (flag `trip-mode`; off: the list) | sign-in, then the summary |
| `/join/<code>` | the join screen for that invite | sign-in, then the join screen (job 22) |
| anything else | the list | sign-in, then the list |

The app's own `/` is the list too, but it is not claimed (see below).

## Route table: snacklist.app (`siteLinks`)

| Link | Opens | Signed out |
| --- | --- | --- |
| `/de/anleitungen`, `/en/guides` | the guide list, in the app | the same, no sign-in |
| `/de/anleitungen/<slug>`, `/en/guides/<slug>` | that guide, in the app | the same, no sign-in |

The app shows a guide natively: it reads the page's Markdown twin (`<page>.md`, built by
`site/agent.mjs`, the same production-gated text the page shows) and renders it with the app's
type and colours. It has no browser view of its own (App Store "Unrestricted Web Access: No",
`core/legal_links.dart`). In a guide, a link to another guide opens that guide in the app, a link to
an app path opens that screen, and every other link (claude.ai, the privacy policy) opens the
system browser. The app never opens a claimed URL in the system browser: Android would hand it
straight back to the app. A guide the site does not have (a draft, a removed slug) shows "gibt es
nicht" with a way to the guide list; no connection shows a retry. A guide route needs no sign-in
and skips the consent question; closing it goes back, or to `/` on a cold start. In the web app the
same paths leave for the site.

Signed out, the link's location rides along as `/login?next=<location>`. After sign-in the
analytics question comes first on a new install, then the link's screen. An account without a
household goes through onboarding first (Step 1, creating or joining) and then lands on the
link's screen instead of Step 3. Signing out never carries the screen the user was on.

On iOS and Android a sign-in that leaves the app (a magic link, Apple on Android) comes back
through `com.snacklist.app://login-callback`, which loses the location. The router keeps the
link's location in memory until the sign-in completes. Invite codes also survive an app kill
(`PendingInvite`, job 22); other links do not, the app then opens the list.

## What the apps claim, and what not

Only the paths in `appLinks` (on the app hosts) and `siteLinks` (on snacklist.app) open the app.
Each is listed in its host's AASA `components` and as a `<data android:path|pathPrefix>` of that
host's verified intent filter; `deep_links_config_test.dart` fails when any of them differs from
the tables. `www.snacklist.app` is not claimed: it redirects to snacklist.app, and Apple does not
follow a redirect for the AASA.

Not claimed, so they always stay in the browser:

- `/`: web sign-in (Google, Apple, magic link) returns to the app URL with a code that only the
  browser that started it can redeem. A link-continuing web sign-in returns to `/?next=<link>`
  for the same reason.
- `/login`, `/welcome`, `/welcome/*`, `/start`, `/start/*`, `/analytics-consent`, `/your-name`:
  pages a browser flow redirects to, or the signed-out guided start.
- `/oauth/consent`: the MCP OAuth consent page (docs/MCP.md) must finish in the browser of the
  MCP client's flow.
- `/settings`: the redirect for links from before job 29d (Zugänge, or Konto with
  `?section=account`). It still works in the app and on the web, it just does not open the app.
- `/join` without a code and `/households/new`: steps of a flow nobody links to.
- Static files (`/konto-loeschen.html`, assets).
- On snacklist.app everything but the guides: the landing pages, legal pages (privacy, terms,
  imprint, DPA, report), support, changelog, comparisons, waitlist, `/data/`, `/get`.

## When the link opens the browser anyway

iOS opens a universal link only on a tap in another app or on another domain: typed or pasted
into Safari's address bar, tapped on a page of the same domain, or after the user chose to open
the domain in Safari (the domain's breadcrumb top right), Safari shows the page. Android's Chrome
does the same for a typed address. So the claimed pages a browser shows offer the app themselves:
on a phone (iPhone, or Android with `Mobile` in the user agent) the join page (`/join/<code>`,
below „Im Browser beitreten“) and the guide pages and lists on snacklist.app show „In der App
öffnen“ / "Open in the app". A tap opens the installed app at the same path:

- iPhone: `com.snacklist.app://open<path>`, the app's own scheme (as the web app's „Öffnen“ card,
  `core/open_app.dart`). The router reads only the path; supabase_flutter takes a link for a
  sign-in only with `code`, `access_token` or `error`, so it never carries a query, and it never
  uses the `login-callback` host. Without the app Safari says it cannot open the address and stays
  on the page.
- Android: `intent://<host><path>#Intent;scheme=https;package=com.snacklist.app;S.browser_fallback_url=<the page>;end`.
  Without the app Chrome stays on (reloads) the page.

Only a tap opens it: browsers allow no app switch without a gesture, and an automatic try would show
Safari's error to everyone without the app. Tablets and desktops show no button.

## Adding a link

1. Make the router handle the path (`authRedirect` in `router.dart`; a More page under `/more/`
   needs nothing else).
2. Add it to `appLinks` (app hosts) or `siteLinks` (snacklist.app) in `deep_links.dart`.
3. Add it to that host's AASA `components` (`/x` exact, `/x/*` for a prefix) and to that host's
   verified filter in the manifest (`android:path` or `android:pathPrefix`). `flutter test
   test/core/deep_links_config_test.dart` tells you what is missing.
4. Add a row to `router_test.dart` and to the tables above. A new site path also needs the site's
   „In der App öffnen“ on its pages (`site/build.mjs`).

Apple's CDN caches the AASA (up to a day or two); a new path opens the app once an iPhone has
the new file. Android verifies the domain, not paths, so a new path works with the app build
that has the new filter. A new domain needs a new app build on both: the entitlement and the
filter are in the app.

## Rollout

The web app's hosts serve `app/web/.well-known/` and the join page from the `release` branch, so
the new AASA and the join page's „In der App öffnen“ go live with the next store upload (every
green `main` commit, `release.yml`), together with the app that routes the paths
(docs/DEPLOY.md, "Web app"). The site deploys from `main`: snacklist.app's two files and its
button go live with the merge. An older app that receives a new link still opens: `/edit`,
`/history` and `/trip/<id>` open their screens there too (only the claim is new), and a guide or
guide list opens the list.

What needs a new store build:

- `applinks:snacklist.app` and the snacklist.app filter: yes. Before the build that has them,
  guide links stay in the browser on every phone.
- The guide view and the new `next` paths: yes.
- `/join/<code>` on app.snacklist.app: no. Build 1541 already has `applinks:app.snacklist.app`
  (`Runner.entitlements` since #345, signed with the match AppStore profile), and Apple's CDN
  serves the AASA with `com.snacklist.app`. The join page's „In der App öffnen“ uses the scheme
  1541 already registers.

Check the live files with `node e2e/web-smoke.mjs https://app.snacklist.app` (and
`https://app.hummlist.com`) and Apple's cached copy with
`curl https://app-site-association.cdn-apple.com/a/v1/app.snacklist.app` (and
`.../a/v1/snacklist.app`); Google's view of a domain is
`https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://app.snacklist.app&relation=delegate_permission/common.handle_all_urls`
(and `source.web.site=https://snacklist.app`). A curl with Apple's bot user agent (`AASA-Bot/1.0`)
gets Vercel's challenge (403) from some networks; Apple's CDN itself fetches the file (checked
2026-11-26), so protection stays on.

## Home Screen widgets (job 63)

The widgets open the app with `snacklist-widget://open` and `snacklist-widget://add`, handled by
`app/lib/home_widget/` (not by these links). The widget's Add has its own add-sheet request next
to `ListLinks` in the list screen; it could map onto this table (`router.go('/add')`) instead.
That is a follow-up in job 63's files, not part of job 66.
