# Review: household-sync

Mia, Noah and Ida (the fictional Brandt family) on three real app instances filmed on one clock.
Mia adds an item; it arrives on Noah's and Ida's phones at the measured latency, with the app's own
"1 neu von Mia Brandt" note and mint row; Noah ticks it off and it leaves all three lists.
10.6 to 10.9 s.

## Hand-over notes (hummlist-ui-craft)

- Plan: focal object Mia's phone (the cause), satellites Noah's and Ida's (the effect); action
  Mia types and Enter, Noah taps; payoff the mint row on both satellites; left out: stores, tabs,
  any drawn chrome.
- Layout: wide "phone trio" fanned, Ida and Noah at 0.55× behind, Mia at 0.68× in front running
  off top and bottom, caption above the satellites; compact: a deck, Mia on top (head dissolving under the
  caption), then Noah's and Ida's phones as two bands with their real screen tops, each showing
  the header note and the mint row. Name tags in
  the members' colours straddle the phone edges.
- Beats: calm (1.5 s) → Mia taps the field, types, Enter → the row arrives on Noah's and Ida's
  phones (real latency) → Mia taps the list to close her sheet → poster (all three lists with the
  item) → Noah taps the row → it leaves Mia's and Ida's lists (real latency) → hold 2.1 s. The
  satellites' lists were scrolled before filming so the new row lands under their header.
- Captured: wide and compact, DE and EN, seams below, reduced motion shows the poster.
- Review: pass 1 fixed a caption hidden behind Mia's phone, a caption over Mia's screen (moved
  above the satellites), and a false contrast error (hex faces are now real elements). Pass 2 and
  the triage below. Pass 3 checked the changed frames.
- Not checked: watched at real speed by a person (NEEDS_LEAD).

## Ranked notes (pass 2, fresh eyes) and what happened

- P1 · wide · Noah's phone cut "VORRAT & KONSERVE…" and "1 new from Mia Brand…" on Ida's → the
  satellites are smaller (0.55×), so the note and the names fit their visible strip · fixed.
- P1 · poster · Mia's row was dimmed under her open sheet → poster moved after the close, with the
  item on all three lists and still mint on two · fixed.
- P1 · wide · Mia's "Chilled" label sliced by the top edge → Mia's phone sized so the edge falls
  on a row boundary · fixed.
- P2 · the tick removes the row in one frame, rows jump → the app; kept, NEEDS_LEAD.
- P2 · EN "Eggs" shows a milk glass → the app's icon for the English name; kept, NEEDS_LEAD.
- P2 · Mia's name tag sits over her phone's right edge → over empty row space, never over a word
  or control in any frame; kept.

## Review 0 (job reviewer) and what happened

- Must fix · compact · Ida's phone was almost hidden behind Noah's, so "Noah und Ida sehen es
  sofort" was not visible for Ida → compact re-laid out as a deck: Noah's and Ida's phones are two
  stacked bands, both with "1 neu von Mia Brandt" and the mint row; poster and contact sheet
  re-checked · fixed.
- Nice to have · wide · the left half feels cramped; a 3-up row at equal scale → kept: three equal
  phones break the one-lead rule (hummlist-ui-craft), and at 576 px three equal phones would put
  the app text under 10 px.

## Kept warnings (hyperframes check)

- `line_unread` on the last caption and on an avatar initial: the loop's first caption again, and
  a one-letter avatar the checker reads as a line.
- `nested_structure_needs_subcomposition`: Studio hints for the touch-dot hosts.

## Files

<!-- report -->
| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| de-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.87 s | 1003 KB | none |
| de-wide | household-sync-de-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.87 s | 433 KB | none |
| de-wide | household-sync-de-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.87 s | 430 KB | none |
| de-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.87 s | 687 KB | none |
| de-compact | household-sync-de-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.87 s | 315 KB | none |
| de-compact | household-sync-de-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.87 s | 338 KB | none |
| en-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.57 s | 915 KB | none |
| en-wide | household-sync-en-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.57 s | 409 KB | none |
| en-wide | household-sync-en-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.57 s | 404 KB | none |
| en-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.57 s | 632 KB | none |
| en-compact | household-sync-en-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.57 s | 295 KB | none |
| en-compact | household-sync-en-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.57 s | 330 KB | none |

| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |
| --- | --- | --- | --- |
| de-wide | 0.9969 | household-sync-de-wide.webp, 46 KB | 6.00 s |
| de-compact | 0.9978 | household-sync-de-compact.webp, 34 KB | 6.00 s |
| en-wide | 0.9972 | household-sync-en-wide.webp, 43 KB | 5.83 s |
| en-compact | 0.9977 | household-sync-en-compact.webp, 33 KB | 5.83 s |

Measured in the takes (Marionette polls, so an upper bound for the app side):

- DE: addToNoahMs 575 ms, addToIdaMs 573 ms, tickToMiaMs 973 ms, tickToIdaMs 988 ms
- EN: addToNoahMs 460 ms, addToIdaMs 451 ms, tickToMiaMs 897 ms, tickToIdaMs 879 ms
<!-- /report -->
