# Demo videos for snacklist.app

The four silent, captioned loops on the landing pages `/de` and `/en`: `add-tick`,
`household-sync` and `mcp-chat` (job 54) and `voice-add` (job 150), each in German and English, wide (1920 × 1080) and compact
(1080 × 1350). The finished files live in `site/public/media/` under the names
`site/public/media/README.md` asks for; this folder holds everything that makes them.

Every picture of the app is the real Snacklist app: the Linux build, driven with real input
against a local Supabase stack seeded with fictional test households. Nothing in the app is drawn.
What is drawn (captions, name tags, touch dots, the phone body and the generic AI chat) follows
the snacklist-ui-craft skill (`.claude/skills/snacklist-ui-craft/`).

## Make them again

Needs the verify-family-groceries toolchain on a Linux host with Docker (`scripts/fg`, Xvfb,
ffmpeg, Deno, Node 22+), xdotool, and the Flutter version CI uses (`FLUTTER_DIR`, else
`~/flutter-<version>`, else `~/flutter`).

```bash
FG_PORT_PREFIX=577 FG_PROJECT_ID=family-groceries-54 marketing/videos/remake.sh   # add-tick household-sync
FG_PORT_PREFIX=577 FG_PROJECT_ID=family-groceries-54 marketing/videos/remake.sh voice-add mcp-chat
```

`remake.sh [video ...]` (default `add-tick household-sync`) starts fg's stack on the port block
(`fg up --only stack`; with `FG_STACK_WORKDIR` set it uses that running stack instead), builds
the Linux profile bundle with the stack's URL and key when `app/` or the stack changed (in the
linux-build container where CMake is missing), takes every named video in German and English
(`capture/take.ts`: seed, film, tear down) and runs `node build.mjs` for them.
`scripts/store-screenshots.sh --videos` calls it for add-tick and household-sync. One run of
both videos took 18 min 43 s on the Hetzner runner (job 215): the Linux build was cached, the four takes took about 2 min, the eight renders and review sets the rest.

`build.mjs` takes video names and `--lang`, `--format`, `--step project,check,render,encode,review`
to redo a part. A copy change in `copy.json` needs only `node build.mjs` (no new take); a change
in the app or its design needs new takes.

## How it works

- `capture/driver.ts` starts each member's app as the profile build on its own Xvfb display at
  3× (`GDK_SCALE=3`), signs it in through the real login screen, and films all displays with one
  ffmpeg so they share a clock. Taps and key strokes are real X input (xdotool); Marionette only
  reports where widgets are. The engine runs its software renderer with Skia: under Xvfb the
  OpenGL path presented a frame only when an X event arrived, so animations lost their frames.
- Every app starts with `FG_DICTATION` set, which gives the Linux build the phone's microphone
  in the add field (`app/test_driver/main_marionette.dart`). A shot's `dictation` is the sentence
  it hears: `test_driver/scripted_speech.dart` stands where the iOS and Android recognizers stand
  and reports it word by word; everything after it is the app's real dictation. The app listens
  in German in every language, so `voice-add` hears the same German sentence in both takes.
- `capture/shots.ts` is what each video films; `capture/take.ts` runs one take and writes
  `<video>/footage/<lang>/` (not committed): one `.mkv` per member, `events.json` (every input on
  the recording clock), `take.json` (clock offsets, measured latencies, the real MCP results).
- `<video>/scene.mjs` turns a take into a HyperFrames composition: where the loop sits in the
  take, the crop of each phone, the touch dots at the logged taps, the captions from `copy.json`.
  `lib.mjs` and `video.css` hold the shared parts; sizes are in `u`, one pixel as the site shows
  the video (576 × 324 wide, 358 × 448 compact).
- `build.mjs` writes the projects to `out/` (with GSAP, tokens and fonts copied in, nothing
  fetched), runs `hyperframes check`, renders, encodes WebM (VP9) and MP4 (H.264, `yuv420p`,
  `+faststart`, no audio), the poster WebP and the WebVTT captions, and writes a review set per
  cut to `out/<name>/review/`. It fails when a source or page splits the name "Snacklist" or still uses the old name (`build.mjs` holds the pattern).

## The test data

- `add-tick`, `household-sync`: `test/fixtures/scenarios/demo-haushalt.yaml` and
  `demo-household-en.yaml`, the fictional demo household „Unser Haushalt“ ("Our Home" in English)
  with Anna and Jonas and four generic stores: Wochenmarkt, Bäckerei, Supermarkt, Drogerie
  (Farmers market, Bakery, Supermarket, Drugstore), no retailer (Legal N-23). A purchase five
  weeks back sends the videos' items (Honig, Marmelade, Eier) to the Wochenmarkt, the first store,
  so they land just under the household name. Job 215 replaced the Brandt family here; the scenes
  pan the view from the add field to the top of the list and back (`pans` in `lib.mjs` `phone`).
- `voice-add`: `demo-familie.yaml` and `demo-family-en.yaml`, the fictional Brandt family (Mia)
  with no store tags.
- `mcp-chat`: `solo-long-list.yaml`, Sam in "Sams Wohnung". The take signs Sam in over the auth
  API, creates a personal access token with the app's own RPC, keeps it in memory only, and calls
  the local `mcp` function; the fixture teardown deletes token and user.

## Words

`copy.json` holds every word on screen besides the app's own, German and English, as drafts for
Launch (`site/COPY_NEEDED.md`, section "Demo videos"). The text alternatives of the three slots
are `demo.*` in `site/content/landing/copy.yml`.
