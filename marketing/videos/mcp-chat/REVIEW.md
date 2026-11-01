# Review: mcp-chat

A generic AI chat in Hummlist's own style asks Hummlist's MCP server to add two items, then, by
voice, to tick them off. The chat shows the real tool results of the take at the times they came
back; Sam's real app ("Sams Wohnung", fixture solo-long-list) shows the rows arrive and leave.
10.7 to 10.9 s.

## Hand-over notes (hummlist-ui-craft)

- Plan: focal object the chat (the cause), satellite Sam's phone (the effect); action a typed
  request, then a spoken one; payoff the Hummlist result card next to the new rows in the app;
  left out: any vendor look, model names, avatars, sparkles, purple; no assistant is named.
- Layout: wide, chat card 300 u on the left (gutter 24), phone running off top, right and bottom;
  compact, chat card on top over the phone's head, phone running off the bottom. A mint marker at
  the phone's edge points at the new rows while they exist (Sam's own adds get no highlight in the
  app).
- Beats: typing (1.6 s) → tap send → working line for exactly the call's real duration → result
  card (real `add_items` answer) → rows in the app (real realtime latency), marker → mic tap,
  listening bars → spoken request → working line → result card (real `tick_items` answer) → rows
  leave the app → the thread leaves upwards → empty chat, the same list.
- Captured: wide and compact, DE and EN, seams below, reduced motion shows the poster.
- Review: pass 1 fixed a caption over the chat card, typed text spilling out of the field, a false
  occlusion error for messages scrolled out of the chat, and overlapping tweens on the working
  line. Pass 2 and the triage below. Pass 3 re-filmed (rows' position recorded) and checked.
- Not checked: watched at real speed by a person (NEEDS_LEAD).

## Ranked notes (pass 2, fresh eyes) and what happened

- P1 · EN · Sam's list is German around "Honey" and "Jam" → the brief allows only Sams Wohnung
  for this video; kept, NEEDS_LEAD asks whether an English copy of the fixture may be used.
- P1 · t=3.4 s · the new rows pop into a long list with no mark → mint marker at the phone's edge
  for exactly the rows' lifetime · fixed (marker drawn outside the screen; the app is untouched).
- P1 · start and reset · the chat sat empty for about 3 s → loop starts 2.5 s before the send, with
  typing from the second frame, and the reset hold is 0.65 s · fixed.
- P1 · compact · the chat card's edge cut the "Tee" row in half → the edge now falls on a row
  boundary · fixed.
- P2 · the DE request scrolled out of the field ("ib Honig und …") → shorter requests that fit
  ("Noch Honig und Marmelade", "Add honey and jam") · fixed.
- P2 · the working line is on screen 0.3 s, too short to read → it lasts exactly as long as the
  real call; kept on purpose (the speed is the point).

## Kept warnings (hyperframes check)

- `line_unread` on the two working lines: their real duration (above).
- `container_overflow` on the thread: it scrolls inside the chat card by design.
- `nested_structure_needs_subcomposition`, `duplicate_media_discovery_risk`: Studio hints.

## Files

<!-- report -->
| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| de-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.73 s | 1144 KB | none |
| de-wide | mcp-chat-de-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.73 s | 395 KB | none |
| de-wide | mcp-chat-de-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.73 s | 395 KB | none |
| de-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.73 s | 903 KB | none |
| de-compact | mcp-chat-de-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.73 s | 313 KB | none |
| de-compact | mcp-chat-de-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.73 s | 332 KB | none |
| en-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.90 s | 901 KB | none |
| en-wide | mcp-chat-en-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.90 s | 334 KB | none |
| en-wide | mcp-chat-en-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.90 s | 348 KB | none |
| en-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.90 s | 717 KB | none |
| en-compact | mcp-chat-en-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.90 s | 274 KB | none |
| en-compact | mcp-chat-en-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.90 s | 294 KB | none |

| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |
| --- | --- | --- | --- |
| de-wide | 0.9981 | mcp-chat-de-wide.webp, 47 KB | 4.23 s |
| de-compact | 0.9980 | mcp-chat-de-compact.webp, 41 KB | 4.23 s |
| en-wide | 0.9982 | mcp-chat-en-wide.webp, 41 KB | 4.30 s |
| en-compact | 0.9982 | mcp-chat-en-compact.webp, 35 KB | 4.30 s |

Measured in the takes (Marionette polls, so an upper bound for the app side):

- DE: addAnswerMs 359 ms, tickAnswerMs 286 ms, addToAppMs 685 ms, tickToAppMs 1071 ms
- EN: addAnswerMs 404 ms, tickAnswerMs 321 ms, addToAppMs 764 ms, tickToAppMs 1090 ms
<!-- /report -->
