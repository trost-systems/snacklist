# snacklist.app

The landing pages, guides, changelog and legal pages: static HTML from Markdown and YAML.
`build.mjs` (markdown-it, gray-matter) writes `dist/`; it is its own Vercel project, separate from
the app on app.snacklist.app. The JavaScript is `public/demo.js`, which starts and pauses the
landing pages' demo videos, `public/stores.js`, which switches the stores card's route when a
store button is pressed, `public/waitlist.js`, the sign-up form and the pages behind the
waitlist mails (below), `public/report.js`, the report form (below), and `public/open-in-app.js`,
the guides' hand-off to the app (Data for the app, App links).

```bash
npm ci
npm run build                          # dist/ in the stage of config/stage.ts
VERCEL_ENV=production npm run build    # fails on [PETER: placeholders, like the production deploy
npm test                               # builds real content and fixtures, checks the output
npm run preview                        # http://127.0.0.1:55990 with vercel.json's redirects and headers
```

`scripts/gates/site.sh` (the `site` CI gate, `scripts/verify.sh --only site`) runs the tests and a
production build. The browser checks (axe, contrast, Lighthouse, CSP crawl) live in `checks/`
(`checks/README.md`).

## Landing pages

`/de` and `/en` (job 53) are built by `landing.mjs` from one copy file and the media folder:

- `content/landing/copy.yml`: every string, with `de`, `en`, `status` (`draft` or `reused`) and
  `source`. A string missing in one language, an unknown field or an id the page doesn't use fails
  the build. In the page every string carries `data-copy-id="<id>"`. After a change run
  `node scripts/copy-needed.mjs`, which writes `COPY_NEEDED.md` (the list for Snacklist PM; a
  test fails while it is stale).
- `public/media/`: the illustrations' posters (light and dark, wide and compact) and the demo
  videos' files; `public/media/README.md` names them. A missing poster, a poster of the wrong
  shape or half a video set fails the build. The illustrations are filmed from the HTML scenes in
  `scenes/` (`scenes/README.md`), which are not part of the build.
- Styles: `public/tokens.css` is generated from `design/tokens/snacklist.tokens.json`
  (`node design/tokens/build.mjs`, never edit it); `public/styles.css` (every page: fonts, hex
  controls, header, footer, prose) and `public/landing.css` use its `--hl-*` variables. Fonts
  (Bricolage Grotesque, Inter, OFL texts beside them) are in `public/fonts/`.

## Data for the app

`public/data/item-icons.v1.json` is the item icon table the app fetches (job 147). It is
generated: edit `tool/item_icons/*.tsv` and run `node tool/item_icons/build.mjs`, which also writes
the app's bundled copy. Raise `tool/item_icons/REVISION` by hand whenever the entries change: apps
only take a file whose revision is above their own, and the lint gate's `--check` fails when the
entries differ from main's without a higher revision, or the JSON differs from the TSVs. Never
edit the JSON by hand.

The remote file can add and change icons, not remove them: apps lay it over their bundled table,
so a form deleted from the TSVs keeps its icon in older apps. To take an icon away, keep the form
and make it a stop (`-`).

The app (`app/lib/list/item_icons_remote.dart`) asks for it at most once a day with a plain GET
(no names, no cookies; on iOS and Android `If-None-Match` with the cached ETag) and uses it only
when `schema` is 1 and `revision` is above the bundled table's. A file it cannot read changes
nothing. `vercel.json` serves `/data/` to any origin (`Access-Control-Allow-Origin: *`, for the
web app on app.snacklist.app) with a day's cache; Vercel sets the ETag. A new schema gets a new file
name (`item-icons.v2.json`), so apps in the stores keep reading v1.

### Guides as JSON

The app shows the guides in its own view (job 462), so the build writes each guide it renders as
`dist/data/guides/<locale>/<slug>.json` and each locale's list as `dist/data/guides/<locale>/index.json`,
served at `https://snacklist.app/data/guides/...` with the `/data/` headers above. `guide-data.mjs`
walks the same markdown-it tokens the page is rendered from, after the `since`, `once` and `until`
gating and the `alexa-skill:` links, so the JSON holds what that build's page shows: production
leaves out what its pages leave out, and no draft or gate banner gets in. A shown version note
("Ab App-Version 1.4.0") is an `em` paragraph.

```
Guide  = { "schema": 1, "locale": "de"|"en", "slug", "title", "description", "updated": "YYYY-MM-DD",
           "url": "https://snacklist.app/de/anleitungen/<slug>", "blocks": [Block] }   // no h1: that is "title"
Block  = { "type": "heading", "level": 2..4, "id": string|null, "text": [Span] }
       | { "type": "paragraph", "text": [Span] }
       | { "type": "list", "ordered": bool, "items": [[Block]] }
       | { "type": "quote", "blocks": [Block] }
       | { "type": "code", "text": string }
       | { "type": "table", "header": [[Span]], "rows": [[[Span]]] }
Span   = { "text": string, "strong"?: true, "em"?: true, "code"?: true, "href"?: string }
Index  = { "schema": 1, "locale", "title", "guides": [{ "slug", "title", "description", "url" }] }
```

`href` is absolute (a site-relative link gets `https://snacklist.app`), an in-page anchor stays
`#id`. A line break inside a paragraph is `\n` in the text. The app skips block types it does not
know, so a new type needs no new schema; a change to an existing shape does. `test/guide-data.test.mjs`
pins the contract.

### App links

The app claims the guide indexes and guides on snacklist.app (job 462): `public/.well-known/apple-app-site-association`
lists `/de/anleitungen`, `/en/guides` and the paths below them for `VCZSHMZY25.com.snacklist.app`,
`public/.well-known/assetlinks.json` is the `com.snacklist.app` statement of the app host's file
(`app/web/.well-known/assetlinks.json`; `test/app-links.test.mjs` fails when they differ).
`vercel.json` serves the AASA as JSON, also at `/apple-app-site-association`. Keep both paths
out of redirects. The link table is `app/lib/core/deep_links.dart`; a path claimed here must be
in it. From the `launch` stage on, when the link opens the browser anyway, `public/open-in-app.js` shows "In der App öffnen" /
"Open in the app" under a guide's or an index's title on iOS and Android: the app's
`com.snacklist.app://open<path>` on iOS, an `intent://` URL with this page as its fallback on
Android.

## Adding a guide

Add `content/guides/<locale>/<slug>.md` (`de` or `en`). No code change: the build adds the page
and lists it on that locale's index. Frontmatter, all required:

```yaml
title: "Snacklist per Siri: Kurzbefehl einrichten"   # h1-level title, og:title, index entry
description: "…"                                    # meta and og:description, index entry
slug: siri-kurzbefehl                               # must equal the file name; the app links to it, so keep it stable
locale: de                                          # must equal the folder
translation_key: siri-shortcut                      # same key in de and en links the two versions
updated: 2026-10-27                                 # shown under the guide
```

German guides live at `/de/anleitungen/<slug>`, English ones at `/en/guides/<slug>`. The body
starts with exactly one `# ` heading and an intro paragraph before the first `##`, and must not
skip heading levels; images need alt text. A
missing field, a second h1, a skipped level, an image without alt, a script, an external resource
or a link to a page that doesn't exist fails the build with the file and the reason.

### Versioned content

Content for an app version the stores don't have yet carries `since` with a version
`MAJOR.MINOR.PATCH`. Three places:

~~~markdown
since: 1.4.0                        # frontmatter: the whole guide

## Einkaufen per Uhr {#uhr since=1.4.0}

The heading and everything up to the next heading of the same or a higher level.
`{since=1.4.0}`, `{#uhr since=1.4.0}` and `{since=1.4.0 #uhr}` all work.

::: since 1.4.0
Any blocks, also inside a list item (indent the markers like the item's text).
:::
~~~

Content whose version is above the live version (below) is not in the stores yet. Vercel
production builds leave it out: a guide like a draft (404, not on the index, no language switch
or hreflang to it), a section or block without a trace. Preview and local builds show it with a
banner ("Ab Version 1.4.0, noch nicht im Store" / "From version 1.4.0, not in the stores yet");
a whole guide also gets `noindex`. Once released, content newer than the first public release
shows the note "Ab App-Version 1.4.0" / "From app version 1.4.0" under its heading, unless its
guide already shows that version or a newer one; before the first public release nothing gets the
note. Unreleased content shows the banner instead of the note. A link to a guide production leaves out fails the
production build.

A version that isn't `MAJOR.MINOR.PATCH` (`since: 1.4` too), an unclosed `::: since` block or a
paragraph starting with `:::` (`::: sinse`) fails the build. Legal texts and indexes are not
versioned: `since` there fails too. Markers inside code fences stay text. A block whose code fence
holds a `:::` line fails too, because that line would end the block: mark such a block with four
colons, `:::: since 1.4.0` up to `::::`.

### Content gated on a hold

Content that waits for a release decision rather than an app version names a hold in
`../releases/flags.json` (`holds.<key>.released`):

~~~markdown
::: until native-siri
Today's answer, shown until the hold is released.
:::

::: once native-siri
The answer for after the release.
:::

## Ohne Einrichtung {#ohne-einrichtung once=native-siri}
~~~

Works in guides and legal pages, also next to `since=` on a heading (then both must allow it).
Production renders only the side that is current, without a trace; preview and local builds show
the other side too, under the banner "Erst wenn native-siri freigegeben ist, noch nicht live" or
"Nur bis native-siri freigegeben ist". A hold flags.json doesn't have fails the build. Releasing
the hold in flags.json is the only change the site needs; `test/gates.test.mjs` fails if any
native-Siri wording renders while `native-siri` is held.

`launch-stage` gates on the site's stage instead (`config/stage.ts`, `SITE_STAGE` in previews):
`::: once launch-stage` shows only in the `launch` stage, `::: until launch-stage` in the others.
Every build, production or not, renders only its stage's side, without a banner. The DE Bring!
comparison uses it for availability; `test/waitlist.test.mjs` fails a launch page outside the legal
texts that still names a beta or an upcoming start.

## Live version

The build reads the live version from outside `site/`: the newest public release in
`../releases/releases.json`, or, before the first one, the version in `../app/pubspec.yaml` on the
built commit (what TestFlight and Play internal testers get), so today everything the testers
have shows. `../releases/README.md` explains the record. It logs the version before the page count:

~~~text
live version: 1.0.0 (from app/pubspec.yaml, no public release yet)
live version: 1.4.0 (from public release record)
~~~

A missing or invalid file fails the build and names it. On Vercel the project setting "Include
files outside the root directory in the Build Step" must stay on, or the build can't read them.

## Changelog

`/de/changelog` („Neuigkeiten“) and `/en/changelog` ("What's new") are generated, not Markdown.
The build reads two sources from outside `site/` (`../releases/README.md` explains both formats):

- `../releases/releases.json`: every public release, newest first, with version, date and its
  `changelog` (title, then the items under Neu / Verbessert / Behoben, New / Improved / Fixed).
  A release without a changelog, or with no items, shows "Fehlerbehebungen und
  Verbesserungen." / "Bug fixes and improvements.". PR numbers and commit shas are never shown.
- `../releases/changelog/<version>.json`: drafts of the next release. Preview and local builds
  show each draft whose version the record doesn't have yet on top, with the banner "Entwurf,
  noch nicht im Store" / "Draft, not in the stores yet" and no date. Production never shows them.
  A draft's `held` items (behind a feature flag or a hold, job 40) are never shown, nor is
  `pending.json` or an `<version>.override.md`; the page shows the draft's title and items.

Every build checks every draft, production included: an invalid draft, or a file whose name isn't
its `version` plus `.json`, fails the build and names the file. `pending.json` and other files in that folder are
ignored, and the folder may be missing. Each release has the anchor `#v1-4-0` for version 1.4.0.
With nothing to show, the page says the first version is coming soon. Every page's footer links
the changelog of its language.

## History

`/history` („Chronik“) and `/en/history` ("History") are the release timeline (job 105),
generated by `history.mjs` from `../releases/releases.json` alone: the site never asks git, since
Vercel clones shallow. One entry per public release, newest first, each with:

- the release date and **day N**: days since `project.day_zero` in the record, 2026-10-22, the
  date of the repository's first commit (day 0);
- the commits since the previous public release (the first release counts from the root commit);
- **contributors**: the people among the release's contributors, bots left out (below);
- **lines of code** at the release commit, in total and by language (`releases/README.md`,
  "Lines of code"); an entry recorded before job 105 has none and leaves the rows out;
- the top three people by commits (ties: more additions, then the name), shown as display name
  and GitHub login (`Peter Trost (@peter-trost)`), never an e-mail address;
- the commits bots and AI assistants took part in, under the one label „Bots und
  KI-Assistenten“ / "Bots and AI assistants", and a link to the release on the changelog.

The bot rule: a contributor with `bot: true` in the record (the `identities` marked as bots:
petertrost-bot and AI co-authors such as Claude, plus any `[bot]` login like dependabot) is never
named, never counted as a contributor and never in the top list; `stats.automated_commits` is
their one line. Before the first public release both pages show an empty state. All strings are
`HISTORY_COPY` in `history.mjs`; `COPY_NEEDED.md` lists them under "Release timeline" until the
copy review approves them. The footer of every page links the history of its language; like
every page it is served with `X-Robots-Tag: noindex` until the launch.

To look at the page with releases, build against the fixture record
`test/fixtures/history-record.json` (three releases, the first in the format from before job 105):

```bash
node scripts/history-fixture.mjs        # dist-history/ (git-ignored)
cd checks && node crawl.mjs ../dist-history --pages /history,/en/history
```

## Other pages

- `content/indexes/<locale>.md`: the index intro (`title`, `description`, `locale`); the guide list
  is generated.
- `content/legal/*.md`: pages at a fixed `path` (`title`, `description`, `locale`, `path`,
  `translation_key`, `updated`, optional `draft`), such as `/impressum` and `/en/imprint`,
  `/datenschutz` and `/en/privacy` (`/privacy` redirects there, `vercel.json`), and the help
  pages `/support` and `/en/support` (job 24). A heading ending in `{#id}` gets that anchor:
  `/datenschutz#rechte` is the stores' privacy-choices URL.
- `config.json`: `privacyPublished` shows the Datenschutz/Privacy footer links,
  `supportPublished` the Hilfe/Support one. Set a flag to `true` only together with its pages;
  a footer link to a missing page fails the build. Impressum and the report page are always linked.

## Alexa

The Snacklist skill for Alexa follows Legal N-366 (job 402):

- `config/stores.mjs` `ALEXA_SKILL_URLS` holds the skill's page per language, the one place for
  them. Markdown links them as `[Alexa Skill Store](alexa-skill:de)` (or `:en`); another locale
  fails the build.
- `config.json` `alexaPublished` (on) shows the landing page's Alexa card next to Siri's and turns
  those links into links; off, the card is gone and the link text stays as plain text.
- Every page whose text names Alexa gets Amazon's trademark line in its language in the footer and
  its Markdown twin (`MARKS` in `build.mjs`); no page needs to carry it in its own text.
- Name the skill „der Snacklist-Skill für Alexa“ / "the Snacklist skill for Alexa" and say what the
  skill does, not what Alexa does. Every „Alexa, …“ on a page must be a sentence the skill
  understands: an invocation docs/ALEXA.md names followed by a request matching a sample of the
  de-DE or en-US model, or one of the two own-list sentences the guides warn about. Never
  "Hey Alexa"; no Alexa logo, badge or Echo picture. `test/alexa.test.mjs` checks all of it.

## Report content

`/inhalte-melden` and `/en/report` are the DSA notice route (job 275, Legal Addendum B): legal
pages (`content/legal/inhalte-melden.md`, `report.md`) whose front matter `form:` holds every word
of the report form. `report.mjs` checks that mapping (every key, no other, non-empty strings, the
six reasons `hate`, `personal_rights`, `ip`, `csam`, `danger`, `other`, `{ref}` in `done`) and
renders the form between the page's intro and its first `##` section; a missing or misspelled key
fails the build with the file and the key. Strings are inline Markdown (links).

- The browser's own validation explains a missing reason, field or box and a reason under 20
  characters (`required`, `minlength`, `maxlength`, `type="email"`); `public/report.js` adds the
  edge function's rules on top (trimmed text, code points, the address pattern) with
  `form.ui.invalid` as the message, counts the reason's characters, folds name and e-mail away
  behind `form.ui.show_contact` for child sexual abuse material (unless something is typed in
  them), posts JSON to `/api/report` and shows `form.done` with the number from the answer, or
  the `form.ui` message for 400, 429, any other status, or no connection. Without the script the
  fields all show and the form posts to `/api/report`.
- Only these two pages load `report.js` (a module) and `report.css` (on top of `waitlist.css`,
  whose fields and tiles the form reuses). Their Markdown twins leave the form out.
- `api/report.mjs` (code in `api/_report.mjs`) forwards the body to the `report` edge function:
  `WAITLIST_UPSTREAM_URL` with its last segment `waitlist` replaced by `report`, with
  `WAITLIST_PROXY_SECRET` and `x-region: eu-central-1`, no client address, and passes the answer
  through. It answers `404` while either variable is unset or the URL doesn't end in `/waitlist`,
  `405` to anything but `POST`, `403` unless the body is JSON from the site's own page
  (`Sec-Fetch-Site: same-origin`, or a same-host Origin without fetch metadata), `400` to a body over 64 KiB or not a JSON object, `429` after 5
  requests per client network (an IPv6 /64) in a rolling hour, held in the function instance's
  memory only, and `503` when the edge function can't be reached or answers no JSON. It logs one
  line, `report <status>`. `npm run preview` serves it like the waitlist functions (below).

## Drafts

`unlisted: true` in a guide's frontmatter (job 415) keeps a published guide out of the guide index, the
sitemap and llms.txt and marks it noindex; it still builds and answers at its URL, for a page only a
link points to (the AI assistants' plan page).

`draft: true` in a page's or guide's frontmatter keeps it unpublished: preview and local builds
show it with a banner ("ENTWURF: Freigabe durch Peter" / "DRAFT: pending Peter's approval"), an
HTML comment and `noindex`; Vercel production builds (`VERCEL_ENV=production`) leave it out, so
its path stays a 404. The help pages `/support` and `/en/support` are drafts until Peter approves
them (job 24). To publish, delete the `draft: true` line and then set the footer flag; a footer
link to a draft fails the production build.

## Stages and the waitlist

`config/stage.ts` holds the site's stage in one line, `export const stage: Stage = 'waitlist';`
(the build reads that line as text; job 93's launch guard reads it too). Switching the stage is a
one-line PR. It decides every call to action; only `launch` links the browser app, as „Web-App“ /
"Web app" in the top nav (job 370) and as „Snacklist im Browser öffnen“ / "Open Snacklist in your
browser" under the store badges (job 402). A preview or local build can pick a stage without touching the
file: `SITE_STAGE=launch npm run build` (ignored when `VERCEL_ENV=production`, and it skips the
launch guard, so it never ships):

| Stage | Header button, hero button | Closing block (`#test`) |
| --- | --- | --- |
| `waitlist` (now) | „Auf die Warteliste“ / "Join the waitlist", to `#warteliste` / `#waitlist` | the sign-up form |
| `beta` | „Zur Beta anmelden“ / "Join the beta", same anchor | the sign-up form |
| `launch` | „App laden“ / "Get the app", to `#app`; the hero shows the chip „Jetzt verfügbar“, the store badges and the web app link | each store's badge to its listing and, on desktops, a QR code of the listing URL under it; the web app link |

In `launch` the QR codes are drawn at build time (`qrSvg` in `landing.mjs`, no service). `public/get-app.js`
sets `data-os` on `<html>` from the user agent: a phone shows only its store's badge, a desktop both
with their QR codes, no script both badges. `checks/get-app.mjs` proves it in Chromium. The waitlist
form and script are not rendered; `/api/waitlist*` stays up for old mail links.

On other pages the header button links the landing page's anchor (`/de#warteliste`). The rest of
the landing page is the same in every stage. The copy ids are `waitlist.cta`, `beta.cta` and
`launch.*` in `content/landing/copy.yml`; the build renders all three stages to check that every id
is used. `launch` also needs the `X-Robots-Tag` header gone from `vercel.json` (job 93's guard).

- The form (`waitlist.mjs`) asks for the email (with the Apple ID / Google hint) and iPhone or
  Android. Under the button stands the newest `content/legal/consent/waitlist-<locale>-v<n>.md`,
  Legal's form text, which links the privacy policy; its file name is the version the form sends
  and must equal `CONSENT_VERSIONS` in `../supabase/functions/waitlist/consent.ts` (a test compares
  them). Change the wording only with a new file.
- `/de/warteliste/bestaetigen` and `/en/waitlist/confirm` are where the person consents (Legal
  N-73, N-74): the newest `waitlist-confirm-<locale>-v<n>.md`, the launch-news box unticked and
  the button „E-Mail bestätigen“. The button sends the token, that version (`CONFIRM_VERSIONS`) and
  the box. `/de/warteliste/abmelden` and `/en/waitlist/unsubscribe` delete a sign-up. The mails link
  them with the values in the fragment (`#t=…`, `#id=…&s=…`); nothing is sent before the button.
  These pages exist in every stage (old mails keep working) and are always noindex.
- `public/waitlist.js` checks the address with the edge function's rule (a test compares them),
  shows labelled errors, posts to `/api/waitlist*` with `fetch` and shows the answer. Without the
  script the form posts its body to `/api/waitlist` (`form-action 'self'` in the CSP), never a
  query string. It sets no cookie and stores nothing.
- While the stage is `waitlist`, `llms.txt` also carries Legal's text for assistants
  (`content/llms-waitlist.md`, L-1): a sign-up is pending until the person confirms.

### Launch: badges, QR code and /get

`config/stores.mjs` holds the App Store and Google Play URLs, TODOs until the listings are public;
until then the badges link `/get`. `/get` is a function (`api/get.mjs`, rewritten in
`vercel.json`): an iPhone or iPad goes to the App Store, Android to Google Play once its URL is set,
everything else to `/de` or `/en` by `Accept-Language`, where the launch stage shows both badges.
The badges in `public/media/badges/` are the official artwork (Apple's English badge only: the
German one was not reachable from the build box). The QR code is drawn at build time (`qrcode`) as
inline SVG.

### The functions under /api

`api/waitlist/index.mjs`, `confirm.mjs` and `unsubscribe.mjs` are Vercel functions (Node, region
`fra1` from `vercel.json`); `api/_waitlist.mjs` holds their code. They forward to the `waitlist`
edge function and answer `404` until both variables are set in the Vercel project:

| Variable | |
| --- | --- |
| `WAITLIST_UPSTREAM_URL` | `https://<ref>.supabase.co/functions/v1/waitlist` |
| `WAITLIST_PROXY_SECRET` | the edge function's `WAITLIST_PROXY_SECRET` |

They never log an address, a token, a body or an IP; each request logs one line like
`waitlist signup 202`. `npm run preview` serves them too, with the variables of its own process, so
the whole flow runs against a local edge function:

```bash
WAITLIST_UPSTREAM_URL=http://127.0.0.1:54321/functions/v1/waitlist WAITLIST_PROXY_SECRET=… npm run preview
```

### Noindex

Every response carries `X-Robots-Tag: noindex` (`vercel.json`) until the launch; the pages behind
the mail links also say it in the page and keep it after the launch.

## Placeholders

A `⟦…⟧` marker (job 82's placeholders for copy not written yet) fails every build, preview and
local too, naming the file. Write open facts as `[PETER: what is missing]` instead; preview builds
warn, a production build (`VERCEL_ENV=production`) fails while any published page still contains
one.

## For AI agents

`agent.mjs` (job 93) writes what agents read next to the HTML: a Markdown twin of every page at
its URL plus `.md` (`/de.md`, `/en/guides/claude.md`, linked from the page's head), `llms.txt`
(head from `content/llms.md`, the link sections generated), `llms-full.txt` (every listed twin),
`sitemap.xml`, `robots.txt`, JSON-LD in the head (`WebSite` on landing pages, `TechArticle` on
guides, `FAQPage` from the help pages' „Häufige Fragen“ / "Common questions" section (`FAQ_HEADINGS`)) and, only while
`releases/flags.json` has `public-api` on, `openapi.yaml`. Then its checks read the finished
`dist/` the way an agent does and fail the build with every problem: twins, llms.txt structure and
links, robots.txt, hreflang pairs, the sitemap, JSON-LD, guide and FAQ structure, links with
fragments, the API description, and at `launch` in `config/stage.ts` any noindex left.
`node agent.mjs [dist]` runs the checks alone.

Text that waits for Peter's approval in his own words starts with a marker: `⟦LAUNCH COPY⟧` and
`⟦LAUNCH COPY FAQ⟧` (Snacklist PM's copy), `⟦LEGAL W1⟧` (a retention period), `⟦LEGAL W2⟧` (consent
and privacy policy) and `⟦LEGAL privacy.website⟧`. Preview builds show each as a lemon tag in the
text; a production build fails while any page, `waitlist.js` or `waitlist.css` still contains `⟦`.
Delete the marker when Peter has approved that text.

## Vercel

Every push to `main` is a production deployment and goes live on snacklist.app; other branches
build nothing (`ignoreCommand`). When the push also runs **Supabase deploy**, `scripts/supabase-gate.mjs`
holds the build until that run has succeeded and leaves the live site up if it fails
(`docs/DEPLOY.md`, "The site waits for Supabase deploy"). When a public release is recorded, the
**Public release record** workflow pushes the record to `main`, and that build shows the content
of the new version (`docs/DEPLOY.md`, "Guides site").

Project settings: Root Directory `site`, "Include files outside the root directory in the Build
Step" on; everything else comes from `vercel.json` (install
`npm ci`, build `npm run build`, output `dist`). `/` redirects by `Accept-Language`: `de…` to
`/de`, any other language to `/en`, no header to `/de` (the landing pages).
`dist/index.html` (meta refresh) only serves hosts without these redirects. Every response
carries `X-Robots-Tag: noindex` until the launch; with the stage `launch` in `config/stage.ts`
the build fails until that header is gone.

`dist/index.html` (meta refresh) only serves hosts without these redirects. Every response but
`/de` and `/en` carries `X-Robots-Tag: noindex` until the public launch; the landing pages follow
the waitlist (Noindex, above).
