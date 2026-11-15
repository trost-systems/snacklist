# Review: mcp-chat

A generic AI chat in Snacklist's own style asks Snacklist's MCP server to add two items, then, by
voice, to tick them off. The chat shows the real tool results of the take at the times they came
back; Sam's real app ("Sams Wohnung", fixture solo-long-list) shows the rows arrive and leave.
11.3 to 12.0 s (job 146).

## Hand-over notes (snacklist-ui-craft)

- Plan: focal object the chat (the cause), satellite Sam's phone (the effect); action a typed
  request, then a spoken one; payoff the Snacklist result card next to the new rows in the app;
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

## Re-take (job 146, 2026-11-06)

Filmed again from main 605ad96d. The wide phone's crop moved down 139 logical px (`appTop` 150 →
289) so the floating add field and tab pill show under the new rows (y 421 to 517). Compact keeps
the row crop: its phone strip is 313 logical px tall, not enough for the rows and the pill. The
chat surface is unchanged. This take's MCP answers: add 764 ms (DE), rows in the app 1.6 s after
the call; tick 471 ms.

## Re-take (job 150, 2026-11-06)

Filmed again from main 02cc9da8 (job 148's floating top bar and hex Anpassen) with the
microphone in the add field: the Linux capture build now starts with `FG_DICTATION`
(`test_driver/main_marionette.dart`), so the field looks as on a phone. Same shots and timing.
- Sam's list scrolls only until Ketchup is at y 520 (was 300), so the MCP rows land just above the
  add field (logical 657 to 753) and the compact crop moved down to hold the rows and the field
  with its microphone (`appTop` 357 → 511). The old compact strip ended above the field.

## Kept warnings (hyperframes check)

- `line_unread` on the two working lines: their real duration (above).
- `container_overflow` on the thread: it scrolls inside the chat card by design.
- `nested_structure_needs_subcomposition`, `duplicate_media_discovery_risk`: Studio hints.
- `gsap_repeated_fromto_without_baseline` (DE only): the working dots pulse twice because the add
  answer took 764 ms; each pulse starts from the same values, so a seek shows the right frame.
- `escaped_container` on the mint marker: its glyph is centred on a zero-size anchor at the
  phone's edge on purpose.

## Files

<!-- report -->
| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| de-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 11.20 s | 1095 KB | none |
| de-wide | mcp-chat-de-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 11.20 s | 387 KB | none |
| de-wide | mcp-chat-de-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 11.20 s | 404 KB | none |
| de-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 11.20 s | 859 KB | none |
| de-compact | mcp-chat-de-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 11.20 s | 298 KB | none |
| de-compact | mcp-chat-de-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 11.20 s | 324 KB | none |
| en-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.83 s | 843 KB | none |
| en-wide | mcp-chat-en-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.83 s | 320 KB | none |
| en-wide | mcp-chat-en-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.83 s | 323 KB | none |
| en-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.83 s | 659 KB | none |
| en-compact | mcp-chat-en-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.83 s | 249 KB | none |
| en-compact | mcp-chat-en-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.83 s | 262 KB | none |

| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |
| --- | --- | --- | --- |
| de-wide | 0.9980 | mcp-chat-de-wide.webp, 49 KB | 4.77 s |
| de-compact | 0.9982 | mcp-chat-de-compact.webp, 40 KB | 4.77 s |
| en-wide | 0.9980 | mcp-chat-en-wide.webp, 43 KB | 4.07 s |
| en-compact | 0.9981 | mcp-chat-en-compact.webp, 34 KB | 4.07 s |

Measured in the takes (Marionette polls, so an upper bound for the app side):

- DE: addAnswerMs 879 ms, tickAnswerMs 40 ms, addToAppMs 1291 ms, tickToAppMs 534 ms
- EN: addAnswerMs 141 ms, tickAnswerMs 52 ms, addToAppMs 943 ms, tickToAppMs 1097 ms
<!-- /report -->
