# App Store app previews

`make-previews.sh` cuts the App Store app previews from the real-app takes the demo-video
pipeline already filmed (`marketing/videos/<video>/footage/<de|en>/<member>.mkv`, not committed;
`marketing/videos/README.md` says how to film them). ffmpeg and ffprobe only.

```
marketing/store-previews/make-previews.sh      # rewrites out/ (same inputs, same files)
```

If a footage file is missing, run `marketing/videos/remake.sh` first.

## What it writes

`out/<de-DE|en-US>/appstore-iphone69/`:

| File | Take | Shows |
| --- | --- | --- |
| `1-add-tick.mp4` | add-tick (anna) | add two items in the compact sheet, tick them off |
| `2-household-sync.mp4` | household-sync (anna's phone only) | an item added elsewhere appears, a tick elsewhere removes it |
| `3-voice-add.mp4` | voice-add (mia) | dictate a sentence, the items land on the list |

`out/` is generated; do not commit it.

## Spec (iPhone 6.9", checked with ffprobe)

- 886 x 1920 portrait, H.264 High (level 4.1), 30 fps, `yuv420p`.
- 15 to 30 s: add-tick runs its whole take (18.6 to 18.8 s); the others are 12 to 14.6 s of
  footage plus a hold of the last frame to 16 s. The held frame is a calm list; no interaction is
  faked.
- Stereo AAC-LC, 48 kHz, silent (Apple wants an audio track), `+faststart`, `.mp4`, under 1 MB each.
- The footage window is 1236 x 2676 (9:19.5). It is scaled to 1920 high and 1 px per side is
  cropped to 886 wide. Nothing is stretched or padded; if a take ever has another aspect, scale to
  cover the width and pad with the app background `f7f7f2`, never stretch.
- No phone frame, no captions, no overlays. The picture is the app window.
- Not produced: 1290 x 2796 or any other size. App Store Connect scales the 6.9" preview for the
  other iPhone sizes; upload only these. iPad previews are not made.

Nothing is held back: each voice take hears its own language (German and English sentences, `marketing/videos/capture/shots.ts`). Neither is a real-device recording; the scripted recognizer stands in (`marketing/videos/README.md`).
