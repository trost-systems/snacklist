# Store assets

The finished Play and App Store screenshots, the Play feature graphic and icon, and the App Store
app previews, for de-DE and en-US, as Snacklist Ops uploads them (job 369). Nothing here is
uploaded by anyone but Ops, and only after Peter's yes.

- `screenshots/<locale>/<set>/<n>-<shot>.png`, `screenshots/<locale>/play/` (feature graphic, icon),
  `contact-sheet.png` per locale, `CAPTIONS.md` (every caption, for Legal), `summary.md`.
  Held frames (`*.BLOCKED.*`, `*.ON-HOLD.*`) are left out by `collect.sh`; they must not be uploaded (their caption is held, see
  `docs/STORE_SCREENSHOTS.md`, "Captions").
- `previews/<locale>/appstore-iphone69/<n>-<name>.mp4` (886 x 1920, 15 to 30 s, silent AAC track).
  No app preview is held at the moment (`marketing/store-previews/README.md`).
- `SHA256SUMS`: every file's hash.
- The build the footage comes from: `marketing/capture-flags.mjs` (the full-rollout flags minus
  `marketing/CAPTURE_FLAGS_OFF`, plus `marketing/CAPTURE_FLAGS`); every capture checks the
  compiled list. No prices, totals, Verlauf tab or trip chrome (HP2), no Alexa.

Remake: `scripts/store-screenshots.sh`, `marketing/videos/remake.sh` (the previews cut the takes),
`marketing/store-previews/make-previews.sh`, then `marketing/store-assets/collect.sh`.
