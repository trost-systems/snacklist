# Review: add-tick

Anna of „Unser Haushalt“ types two items into the real add sheet, closes it, the view follows
them to the top of the list where they sit in the Wochenmarkt, and she ticks both off again. One
take per language, one phone, 12.1 to 12.5 s (job 215). The sections up to job 150 describe the
earlier takes with Mia of the Brandt family.

## Hand-over notes (snacklist-ui-craft)

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

## Re-take (job 146, 2026-11-06)

Filmed again from main 605ad96d after the UI jobs: the add field floats over the list as a hex
pill above the floating tab pill (#278, #288), the add sheet confirms in its own line
("Hinzugefügt: Honig · Rückgängig"); no snackbar shows anywhere in the takes.

- The crop moved down 56 to 57 logical px (wide `appTop` 413 → 470, compact 173 → 229) so it ends under
  the tab pill: the floating field and the pill are in every frame, the new rows still land mid-view.
- The take closes the List tab's tips off camera (`driver.ts` `login`), as a returning user has; the
  first take filmed the "Artikel bearbeiten" card above the list.
- Compact fade starts 6 u lower (`fadeTop` [82, 130]) so the cut "Kühlregal" label above Vollmilch
  dissolves fully.

## Re-take (job 150, 2026-11-06)

Filmed again from main 02cc9da8 (job 148's floating top bar and hex Anpassen) with the
microphone in the add field: the Linux capture build now starts with `FG_DICTATION`
(`test_driver/main_marionette.dart`), so the field looks as on a phone. Same shots and timing.

## Re-take (job 215, 2026-11-14)

Filmed again from main 789ffd6a with the demo household „Unser Haushalt“ (EN "Our Home"), Anna
alone (`demo-haushalt.yaml`, `demo-household-en.yaml`): four generic stores, no retailer, no
Premium, no price.

- Honig and Marmelade (Honey, Jam) were bought at the Wochenmarkt (Farmers market) five weeks
  back, so the app's item→store memory puts them in the first store, under the household name.
- The add field sits at the bottom of the screen and the household name at the top, too far
  apart for one legible crop. The view now pans (`pans` in `lib.mjs` `phone`, 0.7 s): from the
  add field up to the top of the list when the sheet closes, and back down after the second
  tick. The poster is the top of the list: „Unser Haushalt“, the Wochenmarkt and both new rows.
- The capture signs in through the guided start's „Anmelden“ (job 168b) before the login form.
- Wide: phone narrowed to 333 u (k 0.75) so the household name and both new rows fit one crop;
  the caption column moved left to 381 u.
- Checked: ffprobe of all eight web files (sizes, codecs, 30 fps, no audio, `+faststart`, 12.1
  to 12.5 s); first, middle and last frame of every cut and all four posters; seam SSIM 0.9967
  to 0.9971. Only Anna, „Unser Haushalt“/"Our Home" and the four generic stores appear.

## Kept warnings (hyperframes check)

- `line_unread` on the last caption: it is the first caption again (loop seam), on screen for
  about 5 s in total across the seam.
- `nested_structure_needs_subcomposition`, `timeline_track_too_dense`: Studio layout hints for the
  touch-dot hosts; the projects are generated, not edited in Studio.

## Files

<!-- report -->
| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| de-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 12.50 s | 2735 KB | none |
| de-wide | add-tick-de-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 12.50 s | 1046 KB | none |
| de-wide | add-tick-de-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 12.50 s | 689 KB | none |
| de-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 12.50 s | 2323 KB | none |
| de-compact | add-tick-de-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 12.50 s | 872 KB | none |
| de-compact | add-tick-de-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 12.50 s | 723 KB | none |
| en-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 12.10 s | 2402 KB | none |
| en-wide | add-tick-en-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 12.10 s | 885 KB | none |
| en-wide | add-tick-en-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 12.10 s | 638 KB | none |
| en-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 12.10 s | 2128 KB | none |
| en-compact | add-tick-en-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 12.10 s | 788 KB | none |
| en-compact | add-tick-en-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 12.10 s | 687 KB | none |

| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |
| --- | --- | --- | --- |
| de-wide | 0.9970 | add-tick-de-wide.webp, 30 KB | 7.83 s |
| de-compact | 0.9967 | add-tick-de-compact.webp, 34 KB | 7.83 s |
| en-wide | 0.9971 | add-tick-en-wide.webp, 26 KB | 7.47 s |
| en-compact | 0.9968 | add-tick-en-compact.webp, 29 KB | 7.47 s |
<!-- /report -->
