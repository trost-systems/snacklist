# Store screenshots

The Play Store and App Store screenshots, the Play feature graphic and the Play icon come from one
command. It films the real Snacklist web build against a local Supabase stack with the demo
household „Unser Haushalt“ (Anna and Jonas, generic stores only) and frames the captures in the
look Peter picked in job 214: FR2 Großschrift (honey, a two-line Bricolage headline, a subline,
the app as a card with an ink border and hard shadow on the canvas foot) with FR1's Wabenband in
cobalt behind the cards. Nothing is uploaded anywhere.

## Run it

```bash
scripts/store-screenshots.sh                          # de-DE and en-US, Play and App Store
scripts/store-screenshots.sh --locale de-DE --store play
scripts/store-screenshots.sh --assistants named       # the named voice and assist captions
scripts/store-screenshots.sh --premium-label          # „Mit Snacklist Premium“ on the api shot
scripts/store-screenshots.sh --compose-only --assistants named_siri  # reframe the last captures
scripts/store-screenshots.sh --keep                   # leave stack, server and seeded runs up
scripts/store-screenshots.sh --videos                 # then marketing/videos/remake.sh add-tick household-sync
```

It needs what the verify-snacklist skill needs (Docker, the Supabase CLI, CI's Flutter, Node,
ffmpeg) and uses this checkout's port block in `supabase/config.toml` (CI uses the canonical
543xx). The steps:

1. `.claude/skills/verify-snacklist/helpers/launch.sh` starts the stack, builds the release web
   app (wasm, production defines) when `app/` changed, and serves it. The script builds the app a
   second time for the `api` shot (below) into `app/build/store-screenshots-api-web` and serves it
   on `<prefix>82`.
2. `marketing/store-screenshots/capture.mjs` films every shot under `/tmp/fg-e2e.lock` with one
   browser into `out/raw/<locale>/<set>/`.
3. `marketing/store-screenshots/compose.mjs` frames, checks, and writes the store files, a
   contact sheet per locale, `manifest.json` and `summary.md`.
4. The seeded runs are torn down (`teardown.mjs`), the second server is stopped and
   `helpers/cleanup.sh` stops what the launch started, unless you passed `--keep`.

`--compose-only` runs step 3 alone on the captures in `out/raw` of the last run: another
`--assistants` variant or `--premium-label` needs no new capture (the stickers' words are the same
in every variant).

On GitHub: Actions, workflow "Store screenshots" (`.github/workflows/store-screenshots.yml`), "Run
workflow" with a locale, a store, an assistants variant and the Premium label. The set is the run's
artifact `store-screenshots-<sha>-<variant>` (`-premium-label` added with the label). The workflow runs only when someone starts it, and never
uploads to a store.

## Output

`marketing/store-screenshots/out/` (git-ignored). Every file is a 24-bit RGB PNG without alpha.

| Set | Size (px) | Viewport (dp) | Shots | Words |
| --- | --- | --- | --- | --- |
| `play-phone` | 1080 × 1920 | 432 × 960 | all 8 | headline, subline, sticker |
| `play-tablet7` | 1440 × 2560 | 600 × 960 | list, sync, order, add | none (spec D4-B) |
| `play-tablet10` | 1800 × 3200 | 800 × 1280 | list, sync, order, add | none |
| `appstore-iphone69` | 1320 × 2868 | 440 × 956 | all 8 | headline, subline, sticker |
| `appstore-ipad13` | 2064 × 2752 | 768 × 1024 | all 8 | headline, subline, sticker |
| `play/feature-graphic.png` | 1024 × 500 | | | the tagline only, no name or logo |
| `play/icon-512.png` | 512 × 512 | | | `app/web/icons/Icon-512.png` on cobalt |

Files are `<locale>/<set>/<n>-<shot>.png`, `<n>` being the position in the listing. Sets with
words show the screen down to the floating add bar; the tablets show the whole screen, add bar and
tabs included, nearly as wide as the canvas. Every
viewport is under 840 dp, so tablets show the phone layout with the bottom tabs, as on a real
tablet in portrait, and never the More list (it shows the Premium row). The registry of sets,
sizes, viewports and shots is `marketing/store-screenshots/sets.mjs`; capture and compose both
read it.

## Shots

| Shot | What it shows | How the data arrives |
| --- | --- | --- |
| `list` | Jonas's list, two honey rows under „2 neu von Anna“ | Anna's two inserts at the Wochenmarkt through the API, as her app writes them |
| `sync` | Anna's list with Kaffee in honey, Jonas's „Hinzugefügt: Kaffee → Supermarkt“ as a sticker | Jonas types it in his add sheet |
| `add` | the add sheet with „3 Jogh“ and „Joghurt · 3 · Schon mal gekauft“ | typed |
| `order` | the Supermarkt's walking order, Kühlregal mid-drag | held and dragged |
| `voice` | Anna's list, the stores above the Supermarkt folded, three honey rows under „3 neu von Jonas“, a speech bubble with the sentence | the sentence sent to the local `voice` function with Jonas's personal access token, as the Siri Shortcut sends it |
| `assist` | Anna's list as in `voice`, three honey rows under „3 neu von Jonas“, a chat sticker (request, reply, the items) | `add_items` on the local `mcp` function with Jonas's personal access token |
| `api` | Zugänge with the API section on: access tokens, „API“ with the production base URL, „API-Dokumentation“, „Kein aktiver API-Schlüssel.“ and „API-Schlüssel erstellen“; the MCP-Server heading and `https://mcp.snacklist.app` cut out of the same screen as a sticker | nothing made: no token, no key |
| `invite` | the household page down to its join requests: members, „Leute einladen“, the lists Wocheneinkauf, Baumarkt, Geburtstag (the sections below, among them the voice default naming Siri and Alexa, stay out) | the lists made through `rename_list` and `create_list` |

The chat sticker is our own 6b style (snacklist-ui-craft, "Generic AI chat"): no assistant's
name, logo, layout or colours. The invite shot shows no code and no link.

The `api` shot comes from a second build of the app with `SUPABASE_URL` set to the production
project's URL (read from `app/lib/app/environment.dart`, with the local publishable key) and
`FLAGS_ON=public-api`, so the screen shows the hosts users see: `https://mcp.snacklist.app` and
`https://<project>.supabase.co/functions/v1/api/v1`. Every browser context of the capture routes
requests and websockets for the production host to the local stack (`route.fetch`,
`routeWebSocket`); a request to that host the route did not take fails the run, and the capture
prints how many there were. The card starts below the MCP-Server tile, whose hint names AI
assistants; the sticker keeps the heading and the address only, cut halfway into the gap above
the hint (found from the pixels).

The scenarios are `test/fixtures/scenarios/store-screenshots.yaml` and
`store-screenshots-en.yaml`. Shots that change data get a fresh `fg seed` run each; `add` and
`order` share one run per locale, `invite` another one with the extra lists.

## Captions

`marketing/store-screenshots/captions.yaml` holds every word the files show besides the app's own:
per locale and shot the headline (`h`, two lines), the subline (`s`), the alt text (`alt`, at most
140 characters) and a `status` (`draft` or `approved`), plus the sticker words and the feature
graphic's tagline. The voice sentence and the assistant's items there are also what the capture
sends to the functions.

`voice` and `assist` have `variants`; `--assistants` picks one, `neutral` by default:

| Variant | voice | assist | When |
| --- | --- | --- | --- |
| `neutral` | „Per Sprachassistent auf die Liste.“ | „KI-Assistenten schreiben mit.“ | now |
| `named` | „Funktioniert mit Siri und dem Snacklist-Skill für Amazon Alexa.“ (Play: „Mit dem Snacklist-Skill für Amazon Alexa auf die Liste sprechen.“) | „Verbinde deinen KI-Assistenten über MCP.“ | after Legal, and Alexa's certification |
| `named_siri` | „Funktioniert mit Siri: Artikel per Sprache auf die Liste.“ (Play: the neutral line) | neutral | after Legal |

The `api` shot names MCP and the API in every variant (`may_name` in `captions.yaml`; Peter's
call, Legal checks it). `--premium-label` adds „Mit Snacklist Premium“ / "With Snacklist Premium"
under its subline. It is off by default: MCP and the API are free today. Once they are part of
Premium, Apple 2.3.2 requires the screenshot to say a feature needs a purchase, and 2.3.7 forbids
a price, so the label names no price; Play has no such rule, and both stores get the same frames.

The reasons are in `docs/store/store-captions-assistants.md`:

- Named variants wait for Legal's check of the final wording, in both languages.
- Alexa may be named only after Amazon certifies the Snacklist skill and it is live in the store's
  locale. Siri works on iOS only, so a Play variant never names it (`play:` in the variant).
- The `api` shot shows the API, which is off for users (flag `public-api`): it waits until the
  flag is on for everyone and the API is announced.
- "Works with Alexa" is Amazon's device programme; a skill is "the Snacklist skill for Amazon
  Alexa".

## Checks

The run fails, and `summary.md` lists why, when:

- a file has the wrong size, an alpha channel, or more than 8 MB;
- a set's size breaks its store's rule (Play: 9:16, sides within the limits, the long side at most
  twice the short one; App Store: an accepted size);
- the frame's own text covers more than 20 % of a Play file (Play's guidance);
- a headline line is wider than its column, a subline runs over two lines, or a sticker or text
  leaves the canvas;
- the feature graphic's tagline or app card enters the centre zone (x 432 to 592, y 170 to 330);
- a caption, alt text, sticker or tagline names Premium (but the `api` label), a price or
  „kostenlos“/"free", „beste“,
  „Nr. 1“, „Top“ or „Neu“, a retailer chain, an AI brand, the old product name, or a split or shortened
  "Snacklist", "Works with Alexa"; Siri or Alexa outside a named variant, MCP outside `named` or
  API on a shot that may not name them; Siri on Play;
- a frame's own words name Premium, unless it is the `api` shot with `--premium-label`;
- the `api` screen, inside the card's window or on the sticker (by the screen reader's texts),
  shows an AI brand, `127.0.0.1` or `localhost`, or a string like a key, or misses the production
  API URL, „Kein aktiver API-Schlüssel.“ or the MCP address;
- an alt text is missing or longer than 140 characters, or the shots in `captions.yaml` differ
  from `sets.mjs`.

## Deterministic output

A rerun on the same commit and machine writes byte-identical files. Compare two runs with:

```bash
cp marketing/store-screenshots/out/manifest.json /tmp/before.json
scripts/store-screenshots.sh
node marketing/store-screenshots/compare.mjs /tmp/before.json
```

What makes it so:

- **Fixed data.** Each run seeds the scenario afresh. Its times count from the seeding, items
  have their own times, and adds that land in one category come one insert each, so rows that
  sort by time never tie on a random id.
- **Fixed clock.** Each page runs on Playwright's fake clock from its first script, starting at
  the moment its run was seeded. Before its frame a shot pauses the clock on the 16 ms frame grid
  and steps it by a named amount: the honey rows 0.8 to 1.5 s after the strip announced them, the caret
  off (750 ms after a key) in list frames and on (300 ms) in the add sheet.
- **Frames.** The card's crop is cut only in plain background between rows, found from the
  pixels, with up to 64 capture pixels of it kept next to the content; the band is one
  function over the whole strip of a set, so neighbouring shots meet in one band.

A different Chromium or font build can change anti-aliased pixels; compare runs on one machine.

## Add or change a shot

1. Add the shot to `SHOTS` (and a set's `shots`) in `sets.mjs`, and to every locale in
   `captions.yaml` with `status: draft`.
2. Add a scene to `SCENES` in `capture.mjs` that returns the page on a paused clock and the rows
   its caption points at.
3. While working on it: `node capture.mjs --locales de-DE --sets play-phone --shots <shot>` (under
   the e2e lock), then `node compose.mjs --locales de-DE --stores play --sets play-phone`.
4. Run the whole command twice and compare, then read the contact sheets.
