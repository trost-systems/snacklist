# Job 54: demo videos for hummlist.com

Three silent, captioned loops fill job 53's video slots on `/de` and `/en`: `add-tick`
(add two items, tick them off), `household-sync` (three members, live sync) and `mcp-chat` (a
generic AI chat adds and ticks items through Hummlist's MCP server). Each comes in German and
English, wide (1920 × 1080) and compact (1080 × 1350), as WebM (VP9) and MP4 (H.264), with a
poster and WebVTT captions: 24 video files of 0.28 to 0.45 MB, 9 MB together. The PR targets
job 53's branch and is not merged (Peter approves 53 and 54 together).

## What is real

Every app screen is the real Hummlist app (main's code since job 52: 6b design, app icon #5),
filmed as the Linux profile build under Xvfb at 3× with real X input against a local Supabase
stack (577xx) seeded with fictional test households. The sync latency on screen is the measured
one (three apps on one recording clock). The chat shows the real `add_items` and `tick_items`
results from the local MCP server for "Sams Wohnung". Drawn on top, per the hummlist-ui-craft
skill: the phone body, captions, name tags, touch dots at the logged taps, a mint marker in the
MCP video, and the generic chat surface (Hummlist tokens, no vendor look).

## Where

- `marketing/videos/`: capture driver and shots (`capture/`), one scene per video
  (`<video>/scene.mjs`), shared parts (`lib.mjs`, `video.css`), on-screen words (`copy.json`),
  the build (`build.mjs`: HyperFrames projects, check, render, encode, review) and `report.mjs`;
  `README.md` explains how to re-make them; `<video>/REVIEW.md` per video.
- `test/fixtures/scenarios/demo-familie.yaml`, `demo-family-en.yaml`: the Brandt family, no stores.
- `site/public/media/`: the finals; `site/content/landing/copy.yml` `demo.*`: text alternatives;
  `site/COPY_NEEDED.md`: new section "Demo videos: words on screen";
  `site/landing.mjs`: no `poster` attribute on the videos (Lighthouse, DECISIONS 54.11).
- `docs/DECISIONS.md` "Job 54", `docs/NEEDS_LEAD.md` "Job 54".

## How to verify

```bash
cd site && npm ci && npm run build && npm test          # 97 tests
cd checks && npm ci && flock /tmp/fg-e2e.lock node crawl.mjs ../dist \
  && flock /tmp/fg-e2e.lock node contrast.mjs ../dist && flock /tmp/fg-e2e.lock node lighthouse.mjs ../dist --pages /de,/en
ffprobe -v error -show_entries stream=codec_name,width,height,pix_fmt -show_entries format=duration,size site/public/media/add-tick-de-wide.mp4
```

Re-making the videos needs the local stack and the Linux build (`marketing/videos/README.md`).

## Results

- Site: `npm test` 97 pass (3 of 53's tests adapted to real videos in the folder, 1 new; the track test now also asserts no `default`); crawl
  0 problems on every page at 390 and 1440, light and dark, with reduced motion (60 videos: none
  plays) and with motion (plays only in view); CSP intact (media self-hosted); contrast passes;
  Lighthouse /de and /en: accessibility 100, best practices 100, performance 94–95 mobile and 100
  desktop on the final commit (53's build measured 94 on the same host), SEO 66 (noindex, intended).
- Gates: `scripts/verify.sh --only site,fg-cli` pass; gitleaks clean; lint's ast-grep rules pass,
  its schema check fails only on main's two newer migrations, which job 53's branch (this PR's
  base) does not have yet (DECISIONS 54.1).
- Videos: `hyperframes check` clean on all 12 projects (kept warnings in each REVIEW.md); seams
  SSIM 0.997 to 0.998 first against last frame; three review passes (own sheets, a fresh-eye
  agent on frames only, re-check after fixes).

## Licences

| Item | Licence | Source | Commercial use | How verified |
| --- | --- | --- | --- | --- |
| HyperFrames 0.8.225 (compositor, CLI, its skills read as docs) | Apache-2.0 | https://github.com/heygen-com/hyperframes | yes | `license` in `node_modules/hyperframes/package.json`; research §6 |
| GSAP 3.13.0 (animation runtime) | GSAP Standard "no charge" licence | https://gsap.com/standard-license | yes (not for no-code tools competing with Webflow) | `license` in `node_modules/gsap/package.json`; research §6 (gsap.com/licensing) |
| Chrome Headless Shell (HyperFrames' pinned renderer, a tool) | BSD-3-Clause (Chromium) | `hyperframes browser ensure` | yes; not shipped | Chromium licence; only renders |
| FFmpeg, xdotool, Xvfb (capture and encode tools) | LGPL/GPL, BSD-3, MIT | Ubuntu packages | yes; not shipped | tools only; outputs carry no licence terms |
| Bricolage Grotesque (captions) | SIL OFL 1.1 | https://github.com/ateliertriay/bricolage | yes | `site/public/fonts/OFL-bricolage-grotesque.txt` |
| Inter (chat, tags, app text) | SIL OFL 1.1 | https://github.com/rsms/inter | yes | `site/public/fonts/OFL-inter.txt`; the app bundles it too |
| Material Icons font (hex glyphs, chat buttons) | CC BY 4.0 (Google) | Flutter SDK `bin/cache/artifacts/material_fonts/` | yes, with attribution | `MaterialIcons_LICENSE.txt` in the SDK; credit line pending (NEEDS_LEAD) |
| Noto Color Emoji (item emoji in the Linux app footage) | SIL OFL 1.1 (font), Apache-2.0 (images) | Ubuntu `fonts-noto-color-emoji` | yes | `/usr/share/doc/fonts-noto-color-emoji/copyright` |
| App icon #5 Wabenstapel (result card) | Hummlist's own | `site/public/favicon.svg` (job 52) | yes | own asset |
| App footage, test data, copy | Hummlist's own; fictional households | local stack, `test/fixtures/scenarios/` | yes | made in this job |
| HyperFrames registry blocks, stock media, music, voice | none used | – | – | the projects contain only the files above |

## Missing or blocked

- Peter's phone check of each loop (NEEDS_LEAD "Job 54") and his approval with job 53.
- The English MCP cut shows Sam's German list (the brief allows only Sams Wohnung); NEEDS_LEAD
  asks whether an English fixture may be used.
- A Material Icons credit on the site (legal text, not edited here).
- Rebase onto main and retarget after job 53 merges.
