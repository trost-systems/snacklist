# Review: add-tick

Mia types two items into the real add sheet, closes it, the rows sit in their category, and she
ticks both off again. One take per language, one phone, 10.5 to 10.8 s.

## Hand-over notes (hummlist-ui-craft)

- Plan: focal object the add sheet and then the pantry rows; action typing and Enter, then a tap
  per row; payoff the two new rows in "Vorrat & Konserven" / "Pantry"; left out: tabs, store
  sections (no store tags), status bar, keyboard (the Linux build has none; none is drawn).
- Layout: wide "corner bleed", phone 372 u at x 24, running off top and bottom, caption column at
  x 414 (gutter 24); compact: phone full width (gutter 24), its head dissolving under a one-line
  caption, running off the bottom.
- Beats: calm list (1.0 s) → tap the field, sheet opens → type item 1, Enter, "Hinzugefügt" → type
  item 2, Enter → tap "Schließen" → the two rows in place (poster, about 1.5 s hold) → tap row 1
  (blue fill, strike, fade, gone) → tap row 2 → the list as it started (1.4 s). Loop 10.5 to
  10.8 s, poster between the close and the first tick.
- Captured: wide and compact, DE and EN, light only (the videos are light; the site shows their
  light poster in dark mode), reduced motion shows the poster (site crawl), seam SSIM below.
- Review: pass 1 (own contact sheets) fixed a nav-bar sliver at the bottom edge, the touch dot
  over the field's placeholder, stickers that wrapped to four lines, and glyphs off-centre in their
  hexes. Pass 2 (fresh-eye agent, frames only) and the triage below. Pass 3: re-filmed and checked
  the changed frames.
- Not checked: the loop watched at real speed in a phone browser by a person (Peter's gate,
  NEEDS_LEAD); dark-mode pages show the light video.

## Ranked notes (pass 2, fresh eyes) and what happened

- P1 · t=5.5 s · poster · the tick caption sat over a frame with no tick → the add caption now
  holds until just before the first tick, so the poster (new rows) and its words agree · fixed.
- P1 · t=8.5 s · the ticked row leaves in one frame and the rows below jump → the app does this
  (260 ms fade, then removal); kept, reported in NEEDS_LEAD as an app finding.
- P2 · t=6.3 s · the add sheet shows its empty surface for about 300 ms while closing → the app's
  closing animation; kept, NEEDS_LEAD.
- P2 · EN · Honey, Jam, Pasta, Rice show the tin-can emoji → the app's icons for English names;
  kept, NEEDS_LEAD.
- P2 · wide · empty space right of the caption → caption moved to the vertical middle; the space
  stays (the phone keeps two thirds of the width, a wider phone would shrink the type).
- P2 · EN wide caption broke as "one / tap" → hand-set line breaks from copy.json · fixed.
- P2 · section labels are about 7 px at the shown size → real app text at 0.84×; item names are
  16 px; kept.

## Kept warnings (hyperframes check)

- `line_unread` on the last caption: it is the first caption again (loop seam), on screen for
  about 5 s in total across the seam.
- `nested_structure_needs_subcomposition`, `timeline_track_too_dense`: Studio layout hints for the
  touch-dot hosts; the projects are generated, not edited in Studio.

## Files

<!-- report -->
| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| de-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.83 s | 1441 KB | none |
| de-wide | add-tick-de-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.83 s | 434 KB | none |
| de-wide | add-tick-de-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.83 s | 387 KB | none |
| de-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.83 s | 1120 KB | none |
| de-compact | add-tick-de-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.83 s | 380 KB | none |
| de-compact | add-tick-de-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.83 s | 370 KB | none |
| en-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.47 s | 1275 KB | none |
| en-wide | add-tick-en-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.47 s | 398 KB | none |
| en-wide | add-tick-en-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.47 s | 345 KB | none |
| en-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.47 s | 961 KB | none |
| en-compact | add-tick-en-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.47 s | 329 KB | none |
| en-compact | add-tick-en-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.47 s | 337 KB | none |

| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |
| --- | --- | --- | --- |
| de-wide | 0.9976 | add-tick-de-wide.webp, 26 KB | 7.23 s |
| de-compact | 0.9974 | add-tick-de-compact.webp, 28 KB | 7.23 s |
| en-wide | 0.9979 | add-tick-en-wide.webp, 23 KB | 6.87 s |
| en-compact | 0.9974 | add-tick-en-compact.webp, 23 KB | 6.87 s |
<!-- /report -->
