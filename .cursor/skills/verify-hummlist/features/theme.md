# Theme (System, light, dark)

Under Mehr → Einstellungen the user picks how the app looks: like the device, light or dark. The pick applies at once to every screen, is stored on the device only (not in the account) and also holds after sign-out and sign-in. The default is "like the device", which follows the browser's or phone's light/dark setting live.

## Sub-features

- `theme-system` „System“ / "System" (default): follows the device's light/dark setting, also when it changes while the app is open.
- `theme-light` „Hell“ / "Light": always light.
- `theme-dark` „Dunkel“ / "Dark": always dark.
- `theme-persist` the pick survives reload and sign-out; it is per device, not per account.

## How to get to it (user POV)

- „Mehr“ / "More" → „Einstellungen“ / "Settings" → section „Darstellung“ / "Appearance" with one segmented control of three hexagonal segments: „System“ / "System", „Hell“ / "Light", „Dunkel“ / "Dark". One tap selects; a honey hex marks the pick.
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

## Gotchas

- Each segment is a radio button of one group (`getByRole('radio', { name: 'System' | 'Hell' | 'Dunkel', exact: true })`); arrow keys and Space/Enter work too. Until job 57 (2026-11-01) the option „System“ was a radio row „Wie Gerät“; old recipes that click „Wie Gerät“ in the theme section are wrong (the language list still says „Wie Gerät“).
- Stored per device (browser storage): a fresh browser context starts on „System“.
- Colour is only visible in pixels or screenshots; semantics give no theme information.
- The wide layout shows Einstellungen beside the More list; the same segments.
- Since job 154b (PR #320) the segments and the „Sprache“ row each sit in a card (the same group card as Mehr's rows), under the overlines DARSTELLUNG and SPRACHE; roles and names are unchanged.
- The section header „Darstellung“ is drawn in capitals („DARSTELLUNG“); its accessible name keeps normal case, so find it by role and name, not by visible text.
