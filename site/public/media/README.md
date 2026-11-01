# Landing page media

Images and demo videos of the landing pages `/de` and `/en` (`site/landing.mjs`). The build
looks files up by name: drop a file in with the right name and the next build uses it. A wrong
size or a half-finished set fails the build and names the file.

## Names

`<name>-<locale>-<width>[-dark].<ext>`, with

- `name`: `hero`, `stores` (stills), or a demo slot: `add-tick`, `household-sync`, `mcp-chat`;
- `locale`: `de` or `en` (each language has its own on-screen words);
- `width`: `wide` (shown from 601 px viewport width) or `compact` (up to 600 px);
- `-dark`: optional, the poster for `prefers-color-scheme: dark`. Without it dark mode shows the
  light poster.

## Posters (required for every name, both locales)

| File | Shape | Size | Notes |
| --- | --- | --- | --- |
| `hero-<locale>-wide[-dark].webp` | free | 1000 × 1080 | Sits on the cobalt hero block, runs off its bottom edge |
| `hero-<locale>-compact[-dark].webp` | free | 716 × 800 | Phone column, full block width |
| `<slot or stores>-<locale>-wide[-dark].webp` | 16:9 (checked) | 1152 × 648 | Inside a framed card (radius 28 px, 2 px navy contour) |
| `<slot or stores>-<locale>-compact[-dark].webp` | 4:5 (checked) | 716 × 896 | Flush to the card's sides and bottom |

WebP only, at twice the shown size, under 120 KB each. The posters here now are stills of the
HTML scenes in `site/scenes/` (`node site/scenes/film-all.mjs` re-films them). A demo slot's
poster stays the reduced-motion and before-play picture once its video exists: replace it with a
calm frame of the video (the beat that tells the story alone), same names and shapes.

## Demo videos (job 54)

A slot shows a video once all four files and its captions are here; until then it shows the
poster. Some but not all of them fail the build.

| File | Format |
| --- | --- |
| `<slot>-<locale>-wide.webm` | 1920 × 1080 (16:9), VP9, 30 fps, no audio track |
| `<slot>-<locale>-wide.mp4` | 1920 × 1080, H.264 `yuv420p`, `+faststart`, 30 fps, no audio |
| `<slot>-<locale>-compact.webm` | 1080 × 1350 (4:5), VP9, no audio |
| `<slot>-<locale>-compact.mp4` | 1080 × 1350, H.264 `yuv420p`, `+faststart`, no audio |
| `<slot>-<locale>.vtt` | WebVTT captions for both widths; the placeholders here have no cues, and a video whose captions have none fails the build |

Silent loops of 10 to 16 s whose last frame equals the first, about 1.5 to 3 MB per file. The
page plays a video muted and looped, only while half of it is in view and the visitor has not
asked for reduced motion (`site/public/demo.js`); it loads nothing before that (`preload="none"`).
With reduced motion the poster shows with a play button.

Every slot also has a text alternative in `site/content/landing/copy.yml` (`demo.<slot>`): rewrite
it to say what the video shows, and list the change in `site/COPY_NEEDED.md`
(`node site/scripts/copy-needed.mjs`).

| Slot | Story | Where |
| --- | --- | --- |
| `add-tick` | Add items in the add sheet, tick one off | Feature card "Eine Liste für alle" |
| `household-sync` | One household, several members, live sync | Feature card "Der ganze Haushalt" |
| `mcp-chat` | A generic AI chat adds items through MCP, they appear in the app | Voice block, card "Mit KI-Assistenten" |

Siri and Google Assistant have no slot (Peter, 2026-10-31: no videos for them for now).
