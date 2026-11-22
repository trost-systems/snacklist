# App icon

Snacklist's icon on the Home Screen, in the app drawer, the browser tab, the stores and Alexa: AI1 "Soft tile" since job 385 (Peter's pick from round AI, job 372). A yellow (honey) rounded-square ring on cobalt, inside it a white rounded tile with a cobalt check. It replaced icon #5 "Wabenstapel" (hexagons) for everyone; an icon cannot sit behind a flag.

## Sub-features

- `icon-ios` iOS: light, dark (honey ring on `#0b1024`, a `#9fb6ff` tile, a dark check) and tinted (ring and check in one colour, the inner tile left out). iOS 26 renders the layered `AppIcon.icon` (Icon Composer); older iOS the 1024 PNGs.
- `icon-android` Android: adaptive icon (cobalt background, ring, tile and check foreground) with a monochrome layer for themed icons (ring and check); legacy PNGs for Android 7.
- `icon-web` web app: favicon (SVG follows the browser's light or dark scheme, PNG fallback), PWA icons with a maskable pair, Apple touch icon.
- `icon-splash` the splash screens (iOS launch screen, Android 12 splash and older, the web's `#splash`): the icon on a rounded tile, centred on the surface colour.
- `icon-brand-block` the brand block on the start, login and welcome screens: the icon at 56 dp over the wordmark.
- `icon-elsewhere` the site's favicon and touch icon, the MCP page's logo, the email header, the Alexa skill's icons, and the store listing files `marketing/store-icons/app-store-1024.png` and `play-512.png`.

## How to get to it (user POV)

- Install the app and look at the Home Screen; long-press the Home Screen on iOS 18+ → Edit → Customize for dark and tinted, Android 13+ Wallpaper & style → Themed icons.
- In the web app: the browser tab's favicon; the start and login screens show the brand block.

## Driving it

- All files come from `design/app-icon/build.mjs` (art module `design/app-icon/art/ai1.mjs`); `node design/app-icon/build.mjs --check` (lint gate) fails when one differs.
- `node design/app-icon/build.mjs --previews` writes `docs/screenshots/385/icon/`: the iOS light, dark and tinted masks, Android masks and themed light and dark, the splash and the small sizes.
- Brand block: the goldens `start-*`, `login-*` and `jh2-invite-sheet-*` in `app/test/design/goldens/`; in the web app, signed out, the start screen at `/start`.

## Gotchas

- No simulator or emulator on the runners: the Home Screen pictures in `docs/screenshots/385/` are drawn by the generator's previews from the same art on a wallpaper, not captured from a phone. iOS 26's Clear look is rendered only by the phone (check on TestFlight).
- Store listings take the icon from the store consoles, not from the build: Ops uploads `marketing/store-icons/*` by hand.
