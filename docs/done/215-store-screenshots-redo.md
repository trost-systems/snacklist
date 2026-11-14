# Job 215: store screenshots and demo videos, redone for Snacklist

Redo of job 65's closed PR #190, in the frame Peter picked in job 214: FR2 Großschrift with
FR1's Wabenband in cobalt. Nothing was uploaded to any store and nothing was merged.

## What was built

- **One command:** `scripts/store-screenshots.sh [--locale de-DE|en-US|all] [--store play|appstore|all] [--assistants neutral|named|named_siri] [--premium-label] [--compose-only] [--videos] [--keep]`.
  `--premium-label` puts „Mit Snacklist Premium“ on the api shot. `--compose-only` frames the
  last run's captures in `out/raw` again (another variant or caption) without a stack.
  It films the real Snacklist release web build against a local stack with „Unser Haushalt“
  (Anna, Jonas, Wochenmarkt, Bäckerei, Supermarkt, Drogerie) and writes 68 files for both
  locales into `marketing/store-screenshots/out/`:
  - Play phone 1080 × 1920, 8 shots.
  - Play 7-inch tablet 1440 × 2560 and 10-inch tablet 1800 × 3200, 4 shots each, no text.
  - App Store 6.9-inch iPhone 1320 × 2868 and 13-inch iPad 2064 × 2752, 8 shots each.
  - Play feature graphic 1024 × 500 (no name or logo) and icon 512 × 512.
  - All 24-bit RGB without alpha.
- **Shots:** list, sync, add, order, voice, assist, api, invite. Voice and assist items arrive
  through the local `voice` and `mcp` functions with Jonas's token. The api shot is the real
  Zugänge screen of a `FLAGS_ON=public-api` build that shows the production hosts, with every
  request answered by the local stack.
- **Words:** all in `captions.yaml`, de-DE and en-US, every caption `draft`. Voice and assist
  have a `neutral` variant (the default), `named` and `named_siri`. `--premium-label` puts
  „Mit Snacklist Premium“ on the api shot.
- **Checks that fail a run:** size and store rule, alpha, 8 MB, text share over 20 % (Play),
  forbidden words (Premium, price, kostenlos, rankings, retailer chains, AI brands, Hummlist, a
  split "Snacklist", assistant names outside named variants), honey rows not matching the
  sticker, the feature graphic's centre zone. `compare.mjs` compares two runs.
- **Workflow:** `.github/workflows/store-screenshots.yml`, workflow_dispatch only. It uploads the
  set as an artifact.
- **Videos:** `add-tick` and `household-sync` (DE and EN, wide and compact) re-filmed with
  „Unser Haushalt“ / "Our Home". `marketing/videos/remake.sh` makes them again. The captions,
  VTT files, alt texts, `site/COPY_NEEDED.md` and FEATURES-FOR-WRITERS are updated.
- **Research:** `docs/store/store-captions-assistants.md` covers whether captions may name Siri,
  Alexa and MCP, with sources and real listings. Also copied to
  `/workspace/hummlist/research/`.

## How to verify

```bash
scripts/store-screenshots.sh                       # about 12 min, plus waiting for /tmp/fg-e2e.lock
cp marketing/store-screenshots/out/manifest.json /tmp/a.json
scripts/store-screenshots.sh && node marketing/store-screenshots/compare.mjs /tmp/a.json
scripts/store-screenshots.sh --assistants named
FG_PORT_PREFIX=<block> marketing/videos/remake.sh  # Linux host with Docker and Xvfb, about 19 min
```

## Results

- **Full run:** 716 to 757 s on the Hetzner runner. 68 files, all checks pass.
- **Determinism:** two neutral runs matched in 68 of 68 files (62 of 62 before the api shot). The named run differs in exactly the
  12 voice and assist frames that carry text.
- **Videos:** 16 files and 4 VTT files. 11.2 to 12.5 s, seam SSIM 0.996 to 0.997, posters
  27 to 48 KB, H.264 and VP9, no audio.
- **Gates:** `scripts/verify.sh --only gitleaks,lint,site,fg-cli` passed. actionlint passes on the
  workflow.

## Screenshots

`docs/screenshots/215/`:

- both contact sheets;
- the de-DE Play phone strip;
- the feature graphic;
- the named voice and assist frames;
- the video posters.

## Open

- Legal and Peter, before any upload: `docs/NEEDS_LEAD.md` "Job 215". The points are the named
  captions, MCP once it is paid (Apple 2.3.2), the API flag, the 50-list limit and an English
  read.
- The workflow can be started only once it is on main.
- The household-sync compact cut layers Jonas's phone over the bottom of Anna's (DECISIONS job
  215, item 9).

## Review 1 and the evening addenda

- **Invite (first wording, superseded below):** „Lade alle ein. Mehrere Listen für jeden Anlass.“ / "Invite everyone. Separate
  lists for everything." It states no number and no unlimited claim. Peter confirms the lead's
  wording against his own (NEEDS_LEAD).
- **MCP and API frame:** the real Zugänge screen, with `https://mcp.snacklist.app` and the
  production API address. No key is shown and the AI-product hint is cropped out. Two runs
  answered 294 requests each from the local stack and none reached production.
- **Premium finding:** MCP and the API are free today, so neither store requires a mark now and
  the default has none. Once they are paid, Apple's App Store guideline 2.3.2 requires the
  screenshot to say the feature needs a purchase, and 2.3.7 forbids a price there. For Google
  Play the research found no comparable rule for screenshots
  (`docs/store/store-captions-assistants.md` §1 and §3). `--premium-label` renders „Mit
  Snacklist Premium“ / "With Snacklist Premium" on the api shot, ready for that day.
- **Named voice captions:** the research's forms. „Snacklist-Skill für Amazon Alexa“, never
  "Works with Alexa", and no Siri on Play. `named_siri` names Siri alone on the App Store.
- **Age rating 4+:** checked every de-DE and en-US frame, both video sets and their seeds. No
  alcohol or tobacco, in names or icons. Items used:
  - Store screenshots (de): Gurken, Tomaten, Brötchen, Milch, Nudeln, Apfelsaft, Spülmittel,
    Zahnpasta, Joghurt, Haferflocken, Kaffee, Bananen, Butter, Äpfel, Eier, Mehl, Erdbeeren,
    Trauben.
  - Store screenshots (en): Cucumbers, Tomatoes, Bread rolls, Milk, Pasta, Apple juice, Dish soap,
    Toothpaste, Yogurt, Oats, Coffee, Bananas, Butter, Apples, Eggs, Flour, Strawberries, Grapes.
  - The add sheet's catalogue rows: Joghurtdrink, Sojajoghurt.
  - Videos (de): Äpfel, Tomaten, Brötchen, Bauernbrot, Vollmilch, Butter, Joghurt, Nudeln,
    Kaffee, Mineralwasser, Zahnpasta, Spülmittel, Hafermilch, Bananen, Käse, Haferflocken,
    Gurken, Karotten, Honig, Marmelade, Eier.
  - Videos (en): Apples, Tomatoes, Bread rolls, Sourdough bread, Milk, Butter, Yogurt, Pasta,
    Coffee, Sparkling water, Toothpaste, Dish soap, Oat milk, Bananas, Cheese, Oats, Cucumbers,
    Carrots, Honey, Jam, Eggs.
  - The site's `mcp-chat` seed (`solo-long-list`) had „Bier“, never in frame. It is now
    „Limonade“.
- **`mcp-chat` re-filmed:** the published cuts still showed „Hummlist“ in the chat card.

## Review 2 and Peter's invite wording

- **Invite:** Peter decided at 20:20 (t883u): don't show the 50-list cap. Every invite frame now
  says „Lade alle ein. So viele Listen, wie ihr wollt.“ / "Invite everyone. As many lists as you
  want.", with no number.
  - Only the six invite frames were recomposed (`--compose-only`). `compare.mjs` against the
    previous set: 62 of 68 identical, changed exactly `8-invite.png` on the phone, iPhone and
    iPad, in de-DE and en-US. All checks pass on 68 files.
- **Docs:** review 2 found stale lines in the hand-off docs.
  - This file now gives the script's real options and 68 files.
  - The first NEEDS_LEAD "Job 215" items 3 and 4 are marked superseded.
  - DECISIONS job 215 has an item 14 listing what changed since items 6, 12 and 13.
