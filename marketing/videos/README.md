# Demo videos for hummlist.com

The three silent, captioned loops on the landing pages `/de` and `/en` (job 54): `add-tick`,
`household-sync` and `mcp-chat`, each in German and English, wide (1920 × 1080) and compact
(1080 × 1350). The finished files live in `site/public/media/` under the names
`site/public/media/README.md` asks for; this folder holds everything that makes them.

Every picture of the app is the real Hummlist app: the Linux build, driven with real input
against a local Supabase stack seeded with fictional test households. Nothing in the app is drawn.
What is drawn (captions, name tags, touch dots, the phone body and the generic AI chat) follows
the hummlist-ui-craft skill (`.claude/skills/hummlist-ui-craft/`).

## Make them again

Needs the verify-family-groceries toolchain on a Linux host with Docker (`scripts/fg`, Xvfb,
ffmpeg, Deno, Node 22+), xdotool, and `npm ci` here (HyperFrames and GSAP, pinned).

```bash
export FG_PORT_PREFIX=577 FG_PROJECT_ID=family-groceries-54 FG_SURFACE=linux
export FG_EXTRA_PATH="$PWD/.cursor/skills/verify-family-groceries/linux-build"   # without a local CMake
scripts/fg up --only stack                       # local Supabase on 577xx
(cd app && flutter build linux --profile -t test_driver/main_marionette.dart \
  --dart-define=SUPABASE_URL=http://127.0.0.1:57721 --dart-define=SUPABASE_PUBLISHABLE_KEY=<local key> \
  --dart-define=FAKE_STORE=ok)                    # the key from `supabase status`; never commit it

for v in add-tick household-sync mcp-chat; do for l in de en; do
  deno run -A marketing/videos/capture/take.ts $v $l   # one take: seed, film, tear down
done; done
cd marketing/videos && npm ci && node build.mjs  # projects, check, render, encode, review
```

`build.mjs` takes video names and `--lang`, `--format`, `--step project,check,render,encode,review`
to redo a part. A copy change in `copy.json` needs only `node build.mjs` (no new take); a change
in the app or its design needs new takes.

## How it works

- `capture/driver.ts` starts each member's app as the profile build on its own Xvfb display at
  3× (`GDK_SCALE=3`), signs it in through the real login screen, and films all displays with one
  ffmpeg so they share a clock. Taps and key strokes are real X input (xdotool); Marionette only
  reports where widgets are. The engine runs its software renderer with Skia: under Xvfb the
  OpenGL path presented a frame only when an X event arrived, so animations lost their frames.
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
  cut to `out/<name>/review/`. It fails when a source or page shortens the name "Hummlist".

## The test data

- `add-tick`, `household-sync`: `test/fixtures/scenarios/demo-familie.yaml` and
  `demo-family-en.yaml`, the fictional Brandt family (Mia, Noah, Ida) with no store tags, so no
  retailer shows.
- `mcp-chat`: `solo-long-list.yaml`, Sam in "Sams Wohnung". The take signs Sam in over the auth
  API, creates a personal access token with the app's own RPC, keeps it in memory only, and calls
  the local `mcp` function; the fixture teardown deletes token and user.

## Words

`copy.json` holds every word on screen besides the app's own, German and English, as drafts for
Launch (`site/COPY_NEEDED.md`, section "Demo videos"). The text alternatives of the three slots
are `demo.*` in `site/content/landing/copy.yml`.
