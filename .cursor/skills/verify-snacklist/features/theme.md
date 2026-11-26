# Theme (System, light, dark)

Under Mehr → Einstellungen the user picks how the app looks: like the device, light or dark. The pick applies at once to every screen, is stored on the device only (not in the account) and also holds after sign-out and sign-in. The default is "like the device", which follows the browser's or phone's light/dark setting live.

## Sub-features

- `theme-system` „System“ / "System" (default): follows the device's light/dark setting, also when it changes while the app is open.
- `theme-light` „Hell“ / "Light": always light.
- `theme-dark` „Dunkel“ / "Dark": always dark.
- `theme-persist` the pick survives reload and sign-out; it is per device, not per account.
- `theme-rd1` the look without hexagons (flag `redesign-rd1`, job 368; full since 2026-11-22 for beta and launch, N-355, so this is what users get): every hexagon is a soft rounded rectangle (check boxes 6 px corners, chips 8, buttons, fields and tabs 12, cards, groups and the tab bar 20, sheets and dialogs 24; radios round), and only buttons keep their hard drop edge. Light and dark alike; layout and words unchanged. The look is chosen at start: a build that forces the flag (this skill's plain launch does, as it forces every full flag) starts soft; from PostHog, the flag's value shows from the next start, so a real new install shows today's hexagons on its very first start and the soft look from the second. `VH_FLAGS_OFF=redesign-rd1` builds the hexagon look.

## How to get to it (user POV)

- „Mehr“ / "More" → „Einstellungen“ / "Settings" → section „Darstellung“ / "Appearance" with one segmented control of three rounded segments: „System“ / "System", „Hell“ / "Light", „Dunkel“ / "Dark". One tap selects; a honey rounded marker marks the pick (hexagons on a `VH_FLAGS_OFF=redesign-rd1` build).
- Deep link `/more/settings`. (The old `/settings` link goes to Zugänge, `/more/access`, or with `?section=account` to Konto, `/more/account`; never here.)

## Driving it with Playwright

Preconditions:

- Seeded household, signed in, on the list. Browser colour scheme is light by default; `page.emulateMedia({colorScheme:'dark'})` simulates a dark device.

- **Open settings.** `openMore(page, 'Einstellungen')`. Observable: URL `/more/settings`, `getByRole('heading',{name:'Einstellungen'})` visible, `getByRole('radio',{name:'System', exact:true})` is checked.
- **Pick a theme.** Click `getByRole('radio',{name:'Dunkel', exact:true})`. Observable: that radio `toBeChecked()`; the page background turns near black at once. Proof is pixels, not DOM: read the screenshot pixel at x=2, mid-height (luminance below 0.05 dark, above 0.7 light); `luminanceAt`/`expectTheme` in `e2e/tests/theme.spec.ts`.
- **Persist.** `page.reload()`, go to the list: still dark. Back („Zurück“) to More, then `openMore(page, 'Abmelden')` (it wheels the lazy list to the row): the login screen is dark too.
- **Device follows.** Pick „System“, then `page.emulateMedia({colorScheme:'dark'})` and back to `light`: the background changes live.
- **Hell beats a dark device.** Emulate dark, pick „Hell“: stays light.
- Spec: `scripts/verify.sh --only e2e -- tests/theme.spec.ts`.
- **RD1 look (`theme-rd1`).** A plain launch (the users' build), then `cd .cursor/skills/verify-snacklist && node journeys/theme-rd1.mjs <evidence dir> [--lang en] [--dark]`: the list, a tick's question (taken back; only with `trip-mode`, off for users), the switcher sheet, the add sheet, Mehr, Einstellungen, Läden and the list at 200 % text, as PNGs. The proof is pixels: no hexagon, no shadow under cards, groups, the add field or the tab bar; buttons sit on their edge. The same journey on a `VH_FLAGS_OFF=redesign-rd1` build shows the old hexagons.

## Gotchas

- Each segment is a radio button of one group (`getByRole('radio', { name: 'System' | 'Hell' | 'Dunkel', exact: true })`); arrow keys and Space/Enter work too. Until job 57 (2026-11-01) the option „System“ was a radio row „Wie Gerät“; old recipes that click „Wie Gerät“ in the theme section are wrong (the language list still says „Wie Gerät“).
- Stored per device (browser storage): a fresh browser context starts on „System“.
- Colour is only visible in pixels or screenshots; semantics give no theme information.
- The wide layout shows Einstellungen beside the More list; the same segments.
- Since job 154b (PR #320) the segments and the „Sprache“ row each sit in a card (the same group card as Mehr's rows), under the overlines DARSTELLUNG and SPRACHE; roles and names are unchanged.
- The section header „Darstellung“ is drawn in capitals („DARSTELLUNG“); its accessible name keeps normal case, so find it by role and name, not by visible text.
- With the flag `learned-order` (off for users, job 352) Einstellungen has a section „Einkäufe“ / "Shopping trips" with the switch „Einkäufe aus meinen Häkchen erkennen“ / "Detect trips from my ticks" (learned-order `lo-settings`); `getByRole('switch', { name: /^Einkäufe aus meinen Häkchen erkennen/ })`.
- Under `redesign-rd1` (users' build) the three segments and their honey marker are rounded rectangles, not hexagons; roles and names are unchanged. The goldens of every screen in that look are `app/test/design/goldens/rd1/`.
- Einstellungen in order (more-help has the same line): on the web DARSTELLUNG and SPRACHE; on iPhone and Android then FEEDBACK. Built but off for users, between SPRACHE and FEEDBACK: „Einkäufe“ (`learned-order`). The push switches are not here since job 463: they have their own More row „Mitteilungen“ (household-add-alert, shopping-day-reminder).
- On iPhone and Android Einstellungen has a third section FEEDBACK with the switch „Schütteln für Feedback“ / "Shake to send feedback" (feedback `fb-shake`); the web build does not show it.
