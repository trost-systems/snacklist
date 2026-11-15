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
scripts/store-screenshots.sh --premium-label          # „Mit Snacklist Premium“ on the assist shot
scripts/store-screenshots.sh --compose-only --premium-label  # reframe the last captures
scripts/store-screenshots.sh --keep                   # leave stack, server and seeded runs up
scripts/store-screenshots.sh --videos                 # then marketing/videos/remake.sh add-tick household-sync
```

It needs what the verify-snacklist skill needs (Docker, the Supabase CLI, CI's Flutter, Node,
ffmpeg) and uses this checkout's port block in `supabase/config.toml` (CI uses the canonical
543xx). The steps:

1. `.claude/skills/verify-snacklist/helpers/launch.sh` starts the stack, builds the release web
   app (wasm, production defines) when `app/` changed, and serves it.
2. `marketing/store-screenshots/capture.mjs` films every shot under `/tmp/fg-e2e.lock` with one
   browser into `out/raw/<locale>/<set>/`.
3. `marketing/store-screenshots/compose.mjs` frames, checks, and writes the store files, a
   contact sheet per locale, `manifest.json`, `summary.md` and `CAPTIONS.md` (every caption per
   frame and locale, for Legal).
4. The seeded runs are torn down (`teardown.mjs`) and `helpers/cleanup.sh` stops what the launch started, unless you passed `--keep`.

`--compose-only` runs step 3 alone on the captures in `out/raw` of the last run: `--premium-label`
needs no new capture.

On GitHub: Actions, workflow "Store screenshots" (`.github/workflows/store-screenshots.yml`), "Run
workflow" with a locale, a store and the Premium label. The set is the run's
artifact `store-screenshots-<sha>` (`-premium-label` added with the label). The workflow runs only when someone starts it, and never
uploads to a store.

## Output

`marketing/store-screenshots/out/` (git-ignored). Every file is a 24-bit RGB PNG without alpha.

| Set | Size (px) | Viewport (dp) | Shots | Words |
| --- | --- | --- | --- | --- |
| `play-phone` | 1080 × 1920 | 432 × 960 | all 7 | headline, subline, sticker |
| `play-tablet7` | 1440 × 2560 | 600 × 960 | list, sync, order, add | none (spec D4-B) |
| `play-tablet10` | 1800 × 3200 | 800 × 1280 | list, sync, order, add | none |
| `appstore-iphone69` | 1320 × 2868 | 440 × 956 | all 7 | headline, subline, sticker |
| `appstore-ipad13` | 2064 × 2752 | 768 × 1024 | all 7 | headline, subline, sticker |
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
| `invite` | the household page down to its join requests: members, „Leute einladen“, the lists Wocheneinkauf, Baumarkt, Geburtstag (the sections below, among them the voice default naming Siri and Alexa, stay out) | the lists made through `rename_list` and `create_list` |

The chat sticker is our own 6b style (snacklist-ui-craft, "Generic AI chat"): no assistant's
name, logo, layout or colours. The invite shot shows no code and no link.

The scenarios are `test/fixtures/scenarios/store-screenshots.yaml` and
`store-screenshots-en.yaml`. Shots that change data get a fresh `fg seed` run each; `add` and
`order` share one run per locale, `invite` another one with the extra lists.

## Captions

`marketing/store-screenshots/captions.yaml` holds every word the files show besides the app's own:
per locale and shot the headline (`h`, two lines), the subline (`s`), the alt text (`alt`, at most
140 characters) and a `status` (`draft` or `approved`), plus the sticker words and the feature
graphic's tagline. The voice sentence and the assistant's items there are also what the capture
sends to the functions.

Legal's caption rules (N-187 to N-195, job 252) hold for every frame, both stores, both locales:

- Neutral captions ship now. `voice` says „Per Sprachassistent auf die Liste.“ / "Add items with
  your voice assistant."; `assist` says „Mit KI-Assistenten auf die Liste.“ / "Add to your list with
  AI assistants." No assistant, maker or logo is named (N-191), and neither is MCP or the API.
- Siri: only the plain „Funktioniert mit Siri“ / "Works with Siri", and only on the App Store set
  (`appstore:` in `captions.yaml`). No Siri icon, no „Hey Siri“, no ™ or ®, no „einfach“ (N-189),
  never on Play (N-195), where the voice frame says the neutral line.
- No Alexa caption (N-187) until the skill is live in the Alexa Skill Store for the locale.
- No „kostenlos“ / "free" (N-190), no price, no „API“ or „Automationen“ (N-194), no list cap and
  no alcohol or tobacco (age 4+).
- The API frame is gone: its screen showed the API section, which is off for users, the MCP
  tile's hint that names AI brands, and (below it) the Siri section, which Play may not show. The
  `assist` frame is the AI-assistants frame.
- Play shows no Apple frames or Siri UI and the App Store no Android imagery: the frames are the
  web build's own screen on a plain canvas.
- `--premium-label` adds „Mit Snacklist Premium“ / "With Snacklist Premium" under the `assist`
  subline. It is off until the release that switches `integration-lock` on (N-193, planned 1 Dec),
  and then both stores get it. Apple 2.3.2 asks for it; 2.3.7 forbids a price, so it names none.
- The invite caption „Lade alle ein. So viele Listen, wie ihr wollt.“ stays (Peter's call). The
  50-list cap is not shown anywhere, and the research note's PM remark on it is Legal's to settle.

`out/CAPTIONS.md` lists every caption per frame, set and locale.

## Checks

The run fails, and `summary.md` lists why, when:

- a file has the wrong size, an alpha channel, or more than 8 MB;
- a set's size breaks its store's rule (Play: 9:16, sides within the limits, the long side at most
  twice the short one; App Store: an accepted size);
- the frame's own text covers more than 20 % of a Play file (Play's guidance);
- a headline line is wider than its column, a subline runs over two lines, or a sticker or text
  leaves the canvas;
- the feature graphic's tagline or app card enters the centre zone (x 432 to 592, y 170 to 330);
- a caption, alt text, sticker, tagline or the frame's own words names Premium (but the
  `assist` label with `--premium-label`), a price or „kostenlos“/"free", „beste“, „Nr. 1“, „Top“ or
  „Neu“, a retailer chain, an AI brand, the old product name, a split or shortened "Snacklist",
  Alexa, API, automations, MCP, „Hey Siri“, „einfach“ or a no-setup claim, a trademark sign, a
  list cap, alcohol or tobacco, or Siri on Play;
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
