# hummlist.com

The landing pages, guides, changelog and legal pages: static HTML from Markdown and YAML.
`build.mjs` (markdown-it, gray-matter) writes `dist/`; it is its own Vercel project, separate from
the app on app.hummlist.com. The only JavaScript is `public/demo.js`, which starts and pauses the
landing pages' demo videos.

```bash
npm ci
npm run build                          # dist/; warns about [PETER: placeholders
VERCEL_ENV=production npm run build    # fails on them, like the production deploy
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
  `node scripts/copy-needed.mjs`, which writes `COPY_NEEDED.md` (the list for Hummlist Launch; a
  test fails while it is stale).
- `public/media/`: the illustrations' posters (light and dark, wide and compact) and the demo
  videos' files; `public/media/README.md` names them. A missing poster, a poster of the wrong
  shape or half a video set fails the build. The illustrations are filmed from the HTML scenes in
  `scenes/` (`scenes/README.md`), which are not part of the build.
- Styles: `public/tokens.css` is generated from `design/tokens/hummlist.tokens.json`
  (`node design/tokens/build.mjs`, never edit it); `public/styles.css` (every page: fonts, hex
  controls, header, footer, prose) and `public/landing.css` use its `--hl-*` variables. Fonts
  (Bricolage Grotesque, Inter, OFL texts beside them) are in `public/fonts/`.

## Adding a guide

Add `content/guides/<locale>/<slug>.md` (`de` or `en`). No code change: the build adds the page
and lists it on that locale's index. Frontmatter, all required:

```yaml
title: "Hummlist per Siri: Kurzbefehl einrichten"   # h1-level title, og:title, index entry
description: "…"                                    # meta and og:description, index entry
slug: siri-kurzbefehl                               # must equal the file name; the app links to it, so keep it stable
locale: de                                          # must equal the folder
translation_key: siri-shortcut                      # same key in de and en links the two versions
updated: 2026-10-27                                 # shown under the guide
```

German guides live at `/de/anleitungen/<slug>`, English ones at `/en/guides/<slug>`. The body
starts with exactly one `# ` heading and must not skip heading levels; images need alt text. A
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

## Live version

The build reads the live version from outside `site/`: the newest public release in
`../releases/releases.json`, or, before the first one, the version in `../app/pubspec.yaml` on the
built commit (what TestFlight and Play internal testers get), so today everything the testers
have shows. `../releases/README.md` explains the record. It logs the version before the page count:

~~~text
live version: 0.1.0 (from app/pubspec.yaml, no public release yet)
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
  a footer link to a missing page fails the build. Impressum is always linked.

## Drafts

`draft: true` in a page's or guide's frontmatter keeps it unpublished: preview and local builds
show it with a banner ("ENTWURF: Freigabe durch Peter" / "DRAFT: pending Peter's approval"), an
HTML comment and `noindex`; Vercel production builds (`VERCEL_ENV=production`) leave it out, so
its path stays a 404. The help pages `/support` and `/en/support` are drafts until Peter approves
them (job 24). To publish, delete the `draft: true` line and then set the footer flag; a footer
link to a draft fails the production build.

## Placeholders

Write open facts as `[PETER: what is missing]`. Preview builds warn; a production build
(`VERCEL_ENV=production`) fails while any published page still contains one.

## Vercel

Every push to `main` is a production deployment and goes live on hummlist.com; other branches get
preview deployments behind Vercel Authentication. When a public release is recorded, the
**Public release record** workflow pushes the record to `main`, and that build shows the content
of the new version (`docs/DEPLOY.md`, "Guides site").

Project settings: Root Directory `site`, "Include files outside the root directory in the Build
Step" on; everything else comes from `vercel.json` (install
`npm ci`, build `npm run build`, output `dist`). `/` redirects by `Accept-Language`: `de…` to
`/de`, any other language to `/en`, no header to `/de` (the landing pages).
`dist/index.html` (meta refresh) only serves hosts without these redirects. Every response
carries `X-Robots-Tag: noindex` until the beta launch; remove that header then.
