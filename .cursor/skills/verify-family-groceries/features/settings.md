# Settings: theme and language

Mehr → Einstellungen (`/more/settings`) holds what belongs to the device, not the account: the theme ("Darstellung": one segmented control, hexagonal in fg's flag-off app and rounded for users (`redesign-rd1`), System / Hell / Dunkel) and the language ("Sprache", a row that opens a list of languages). Both apply at once, are kept on the device and outlive restarts and sign-out. Both default to the device's own setting. Light and dark are the 6b Hex Frische palette (job 52, `docs/DESIGN.md`): every screen, sheet, dialog and snackbar follows it, yellow buttons sink when pressed, the theme picker, switches and radio rows are hex controls (`HexSegmented`, `HexSwitch`, `HexRadio`, job 57), and the store dividers keep their store colour, lightened where it would not read on dark (Aldi, Edeka).

## Sub-features

- `st-open` opens Einstellungen from More (`more-settings`, "Einstellungen", one line since job 85) → `settings-screen`. Back returns to More. From 840 px it opens beside More's list.
- `st-theme` one segmented control `theme-mode` with three segments: `theme-system` ("System", picked by default), `theme-light` ("Hell") and `theme-dark` ("Dunkel"); EN System / Light / Dark. A tap picks a segment, the yellow hex slides to it and the whole app repaints at once. The stored value is still `system`, `light` or `dark` under the same key, so a pick from before job 57 reads 1:1.
- `st-theme-kept` the theme pick survives `fg restart` and sign-out (the login screen shows it too).
- `st-language` the row `settings-language` ("Sprache", its line names the pick: "Deutsch", "English" or "Wie Gerät (Deutsch)") opens `language-screen` (`/more/settings/language`): `language-system` ("Wie Gerät", its line "Gerade Deutsch" names what the device gives) and one hex radio row per language in its own name, `language-de` ("Deutsch"), `language-en` ("English"). A pick switches every text at once; the page stays open. Back returns to Einstellungen.
- `st-language-kept` the language pick survives `fg restart` and sign-out.

## How to get to it (user POV)

- Tap "Mehr", scroll to "Einstellungen" and tap it. Under "Darstellung" tap "System", "Hell" or "Dunkel". Tap "Sprache" and pick a language.

## Driving it with fg

Preconditions: baseline from `features/README.md`; peter signed in on the list. The Linux client's device setting is light, so `theme-system` shows light.

- **`st-open`.** `fg tap --key tab-more`, `fg wait --key more-screen`, `fg marionette -- scroll-to --key more-settings`, `fg tap --key more-settings`, `fg wait --key settings-screen`; `fg find --key theme-mode` counts 1 (the section header's visible text is in capitals, "DARSTELLUNG"). `fg screenshot --name st-settings`.
- **`st-theme`.** `fg screenshot --name st-light` (`theme-system` picked). `fg tap --key theme-dark`, `fg screenshot --name st-dark`: the page is dark at once (compare the two PNGs). `fg tap --key tab-list`, `fg wait --key add-item-field`, `fg screenshot --name st-dark-list`: the list, its store dividers and the add bar are dark too. Open the add sheet (`fg tap --key add-item-field`) and an edit sheet (`features/edit-item.md`) for their dark screenshots.
- **`st-theme-kept`.** With Dunkel picked, `fg restart`, `fg wait --key add-item-field`, `fg screenshot --name st-dark-restart` is dark. `fg logout`, `fg screenshot --name st-dark-login` is dark. `fg login peter`, then back to Einstellungen and `fg tap --key theme-system` restores light.
- **`st-language`.** On Einstellungen, `fg tap --key settings-language`, `fg wait --key language-screen`, `fg screenshot --name st-language`. `fg tap --key language-en`, `fg wait --text Language`: the title and the tabs read English at once ("List", "More"). `fg back` returns to Einstellungen, now "Settings"; `fg find --text English` names the pick.
- **`st-language-kept`.** `fg restart`, `fg wait --key add-item-field`: `fg find --key add-item-field` has the label "What do you need?". `fg logout`, then `fg find --type Text` lists "Sign in". `fg login peter`, Mehr → Einstellungen → Sprache, `fg tap --key language-system`, `fg wait --text Sprache` restores German.
- **Proof.** Screenshots `st-settings`, `st-light`, `st-dark`, `st-dark-list`, `st-dark-restart`, `st-dark-login`, `st-language` and the English UI. The web e2e `e2e/tests/theme.spec.ts` shoots every main screen in both themes and checks the background's luminance; `e2e/tests/shell-more.spec.ts` covers the language list and the English UI.

## Gotchas

- More is a lazy list: `more-settings` is not built until you scroll (`fg marionette -- scroll-to --key more-settings`).
- „Wie Gerät“ follows the app's locale, which fg sets from `FG_LOCALE` (default `de_DE.UTF-8`, the app's `LC_ALL`), not from the host: so `language-system` gives German ("Wie Gerät (Deutsch)") on a `C.UTF-8` host too. With `FG_LOCALE=en_US.UTF-8` it gives English and the German recipes fail. Checked 2026-11-23: „Mehr“ by default, "More" with `FG_LOCALE=en_US.UTF-8`, both from a `C.UTF-8` shell.
- After a language switch every text match changes language; recipes that match German text need `language-system` (or `language-de`) back. Keys stay the same.
- `fg find` does not list text inside the switch and radio rows; tap them by key.
- The theme is per device: peter's and lea's clients each keep their own. Pick `theme-system` again at the end so later recipes' screenshots match.
