# Review: voice-add

Mia taps the microphone in the real add field and says „Pizza, Orangensaft und zwei Packungen
Fischstäbchen“. The app listens (red stop button, the words fill the field), she taps stop, the
server splits the sentence and the three rows land under Getränke and Tiefkühl. In the store she
ticks them off, so the loop starts and ends on the same list. One take per language, one phone,
11.2 to 11.5 s.

## Hand-over notes (snacklist-ui-craft)

- Plan: placed in the voice block's "In der App" card; focal object the add field with the
  microphone; action the tap and the sentence, shown word by word in a cobalt speech caption on
  the recognizer's clock; payoff the three rows in their sections and the app's own "Hinzugefügt"
  line; left out: Siri, Alexa, status bar, keyboard, any drawn UI.
- Speech: the Linux build has no recognizer. `app/test_driver/scripted_speech.dart` replaces
  speech_to_text's platform interface and reports the sentence as partial results (first word
  0.7 s after listening starts, then one per 0.34 s); `DeviceDictation`, the button, the splitter
  and the list are the app's real code. The caption's words use the same timings.
- English: dictation follows the app language (German or English) since #487; this take is still
  a German example, so the English cut hears the German sentence and says "Dictation follows the
  app language." under it. The rows land in German among the
  English items, as they would for an English-speaking user.
- Layout: wide, phone 256 u at x 296 (gutter 24) from mid-list to under the tab pill, its head
  dissolving; caption and speech caption in the left column. Compact: caption and speech caption
  above, phone 264 u centred, from the drinks to under the tab pill.
- Beats: calm list (1.0 s), tap the mic, listening, words 1.8 to 3.5 s, tap stop 4.4 s, rows and
  message 5.2 to 5.6 s (poster about 1.2 s later), three ticks bottom up, the list as it started.
- Captured: wide and compact, DE and EN, light only, reduced motion shows the poster (site).

## Ranked notes (fresh eyes, frames only) and what happened

- P1, all cuts, 3.5 to 7.6 s: four seconds of nothing while the recognizer waited out its 3 s
  pause → Mia now taps the red stop button 0.9 s after her last word (a real app action, "Diktat
  beenden"); the rows land about 1 s later. No footage is cut or sped up. Fixed.
- P2, the app's message covers a row and rows peek around the floating field and pill → the app
  as it looks since job 148 (floating field and pill over the list); kept.
- P3, wide seam: a "Z" of "Zuletzt verwendet" beside the field only in the last frame → one item
  (Zahnpasta / Toothpaste) is bought off camera before filming, so the section is there from the
  first frame. Fixed; seam SSIM 0.998.
- P3, the caret blinks in the field after the add → the app focuses the field after dictation (the
  text waits there when the split fails); kept.
- P4, EN: the German rows look like a translation slip, and the note came late → the note now
  arrives with the first word. Fixed (the rows stay German: that is what the app does).
- Found while filming, fixed in the app (not in the footage): the field showed only the start of a
  long sentence while listening, and dictated rows showed up in the wrong place for about 0.35 s
  before jumping to their category (DECISIONS "Job 150").

## Kept warnings (hyperframes check)

As in add-tick: `line_unread` on the seam caption and Studio layout hints for the touch dots.

## Files

<!-- report -->
| Cut | File | Codec | Size | fps | Duration | Bytes | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| de-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 11.63 s | 765 KB | none |
| de-wide | voice-add-de-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 11.63 s | 308 KB | none |
| de-wide | voice-add-de-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 11.63 s | 335 KB | none |
| de-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 11.63 s | 628 KB | none |
| de-compact | voice-add-de-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 11.63 s | 275 KB | none |
| de-compact | voice-add-de-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 11.63 s | 315 KB | none |
| en-wide | master (render) | h264 yuv420p | 1920x1080 | 30/1 | 10.67 s | 853 KB | none |
| en-wide | voice-add-en-wide.mp4 | h264 yuv420p | 1920x1080 | 30/1 | 10.67 s | 321 KB | none |
| en-wide | voice-add-en-wide.webm | vp9 yuv420p | 1920x1080 | 30/1 | 10.67 s | 330 KB | none |
| en-compact | master (render) | h264 yuv420p | 1080x1350 | 30/1 | 10.67 s | 693 KB | none |
| en-compact | voice-add-en-compact.mp4 | h264 yuv420p | 1080x1350 | 30/1 | 10.67 s | 289 KB | none |
| en-compact | voice-add-en-compact.webm | vp9 yuv420p | 1080x1350 | 30/1 | 10.67 s | 314 KB | none |

| Cut | Seam SSIM (first vs last frame) | Poster | Poster at |
| --- | --- | --- | --- |
| de-wide | 0.9741 | voice-add-de-wide.webp, 41 KB | 6.53 s |
| de-compact | 0.9678 | voice-add-de-compact.webp, 41 KB | 6.53 s |
| en-wide | 0.9775 | voice-add-en-wide.webp, 38 KB | 6.17 s |
| en-compact | 0.9726 | voice-add-en-compact.webp, 38 KB | 6.17 s |

Measured in the takes (Marionette polls, so an upper bound for the app side):

- DE: tapToAddedMessageMs 4212 ms
- EN: tapToAddedMessageMs 3833 ms
<!-- /report -->
