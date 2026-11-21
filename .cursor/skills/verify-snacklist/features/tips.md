# Tips on the list (hints) and „Erste Schritte“

The List tab has one slot at the top of the list (job 168b, H2 trigger hints; before: job 80's fixed tip queue and the gesture card). While it is open, the slot holds the „Erste Schritte“ card („First steps“), shown only while the list has an active item (while the checklist is open, an empty list stays clean and shows neither the card nor a hint); after that, at most one hint per app start, chosen by what the user has done. A hint is a flat card at the top of the list, or a callout under „Anpassen“ or above the add field. Every hint can be read again under Mehr → „Tipps“.

## Sub-features

- `checklist` the „Erste Schritte“ card (key `list-hint`, as the gesture card it replaces). Flat, 2 px contour, no shadow. Title „Erste Schritte“, progress „1 von 3“, an X (tooltip and screen-reader name „Erste Schritte ausblenden“ / "Hide first steps", key `list-hint-dismiss`). Items, by the household's answer to „Mit wem kaufst du ein?“ (`households.kind`):
  - „Liste angelegt“ (or „Haushalt beigetreten“ for someone who joined), always done;
  - the invite item, titled by kind („Partner einladen“, „Familie einladen“, „Mitbewohner einladen“, „Mitglieder einladen“, else „Jemanden einladen“), with the line „Sieht deine Artikel sofort und kann selbst etwas draufsetzen.“ (club: „Alle sehen dieselbe Liste und können selbst etwas draufsetzen.“; EN "They see your items right away and can add their own." / "Everyone sees the same list and can add to it.") and „Einladen“ (opens the switcher sheet's invite page; on the flag-off build without `list-declutter`, Mehr → Einladungen). Not for „Nur ich“ (solo) and not for a plain member who joined (an admin who joined gets it, and „Liste angelegt“). Done once a second member is in a household the user is in;
  - „Einmal einkaufen“ with the gesture sentence „Tippen hakt ab · Halten bearbeitet“ under it. Done once the user ticks an item off (any tick, also the one that empties the list) or saves a change to an item's own fields in its edit sheet (job 204; before, only a tick that emptied the list did it). A save that only claims the item („Ich bringe das“) or only moves it to another list does not count (driven 2026-11-14: Ida's claim-only save left it open, a brand change did it);
  - clubs only: „KI-Assistenten verbinden“ („Mehr → Zugänge. Er setzt Dinge auf eure Liste.“) with „Öffnen“ (opens Mehr → Zugänge). Done once the user has a connected AI app, an MCP token or an API key (asked once per start while open).
  A done item is struck through and says „…, erledigt“ to a screen reader. The X hides the card for this household on this device until sign-out (the gesture card's flag, `listprefs.<user>.<household>`, wiped on sign-out; driven 2026-11-14: after sign-out and sign-in the card was back). It also leaves once every item is done. While it is open, no hint shows.
- `hint-card` a hint as a flat card (key `tip-<id>`): icon, bold title, one or two sentences, an optional button (key `tip-action-<id>`), and an X (tooltip „Tipp ausblenden“ / "Hide tip", key `tip-dismiss`).
- `hint-callout` a hint as a flat bubble with a tip: under „Anpassen“ pointing up (`store-order`, `add-store`), or above the add field pointing down at the microphone (`dictation`, phones only; hidden while the add sheet is open).
- `hint-dismiss` the X hides the hint for good on this device for this user, and a snackbar says „Alle Tipps unter Mehr → Tipps.“ / "All tips under More → Tips." for 3 s. No other hint shows until the next app start.
- `hint-rules` (`nextHint` in `app/lib/tips/hints.dart`): one hint or the checklist on screen; at most one hint per app start, and a hint that never showed before at most once per 24 h; none in the first 10 s after the start, none while a sheet, dialog or the keyboard is open or the List tab is not on screen, none in the user's first session while the list is empty. A hint retires when its feature is used, on X, on its button, or after three app starts that showed it. Three X in a row pause every hint for 14 days. A hint that showed before comes back before a new one.
- `hint-catalogue` the hints, most useful first:

  | id | DE title | Shows when | Retired by | Where | Platforms |
  | --- | --- | --- | --- | --- | --- |
  | `invite-partner` | „Gemeinsam einkaufen“ + „Einladen“ | the user owns a household (not solo) with one member, 3 open items, a day after their first start | a second member | card | all |
  | `edit-long-press` | „Artikel bearbeiten“ | 5 open items | an edit saved | card | all |
  | `quick-add-amounts` | „Menge gleich mittippen“ | 5 typed adds without an amount | an add with an amount | card | all |
  | `store-order` | „Sortiert wie dein Laden“ | one of the user's own ticks emptied the list once (a trip-mode end does not count), the household has a store | a category reorder | under „Anpassen“ | all |
  | `add-store` | „Noch ein Laden?“ | 3 active days, no store | a store in the household | under „Anpassen“ | all |
  | `dictation` | „Sag einfach, was fehlt“ | 10 typed adds | an add by dictation | above the add field | iOS, Android |
  | `ai-assistant` | „Noch besser mit KI & Automatisierung“ + „Zugriffe verwalten“ | a club, or 7 active days on the web or a computer | an AI app, MCP token or API key | card | all |
  | `siri` | „Mit Siri hinzufügen“ | 3 active days | (not visible to the app) | card | none today: iOS only once the `native-siri` hold is released (a build define the store builds leave off) |
  | `home-widget` | „Liste auf dem Home-Bildschirm“ | 5 active days | a widget placed (asked once per start) | card | iOS, Android |
  | `own-household` | „Deine eigene Liste“ + „Haushalt erstellen“ | the user joined someone's household, 3 active days | owning a household | card | all, once a second household can be made (job 169b) |
  | `second-household` | „Noch eine Liste?“ + „Haushalt erstellen“ | 14 active days | (not visible yet) | card | all, once a second household can be made (job 169b) |

- `tips-page` Mehr → „Tipps“ (`/more/tips`, key `more-tips` on the row, `more-tips-page` on the page): every hint this platform can show, shown or not, hidden or not, with its button and without an X.
- `hint-hide-categories` flag `hide-categories` (job 350): `store-order` („Sortiert wie dein Laden“, about the category order) is not offered, neither on the list nor under Mehr → „Tipps“ (`Hint.aboutCategories`).
- `hint-state` per user on the device under `hints.<user id>` (`UsageLog`: signal counts, active days, each hint's showings, X and button, the X streak and pause). Kept after signing out. Job 80's dismissed tips (`tips.<user id>`) count as hidden hints.

## How to get to it (user POV)

- Checklist: a new household's list, or any list whose gesture card was never dismissed.
- A hint: dismiss the checklist, start the app again, wait 10 s; e.g. a list with 5 or more open items shows „Artikel bearbeiten“.
- Mehr → „Tipps“.

## Driving it with Playwright

Preconditions: `signIn` from helpers/lib.mjs dismisses the checklist („Erste Schritte ausblenden“), which takes that session's slot, so a hint shows only after a reload, 10 s after it.

- **Checklist.** On a fresh account the list shows „Erste Schritte“ once it has an item (add one first); `page.getByText('Tippen hakt ab · Halten bearbeitet')` is visible; `page.getByRole('button', { name: 'Erste Schritte ausblenden' })` hides it.
- **Hint.** After a reload with 5 or more open items, within 15 s the ARIA snapshot contains „Artikel bearbeiten Halte einen Artikel gedrückt …“ (title and text are one merged node). „Tipp ausblenden“ hides it and shows „Alle Tipps unter Mehr → Tipps.“; after another reload no hint comes back for 24 h.
- **Tipps page.** `/more/tips` lists the cards. On the web exactly six (driven 2026-11-09): „Gemeinsam einkaufen“ with „Einladen“, „Artikel bearbeiten“, „Menge gleich mittippen“, „Sortiert wie dein Laden“, „Noch ein Laden?“, „Noch besser mit KI & Automatisierung“ with „Zugriffe verwalten“ (no `dictation`, `siri`, `home-widget`; `own-household` and `second-household` are off on every platform, see Gotchas).
- **Scripted.** `helpers/drive.sh tips [--lang en] [--dark]` (`journeys/tips.mjs`; passed 2026-11-19 on af0287cf, DE and EN dark). „Einmal einkaufen“: `cd .cursor/skills/verify-snacklist && node journeys/tips-first-shop.mjs <dir> [--lang en]` after `launch.sh --fresh` (not through `drive.sh`: no feature has that id) (Mia ticks one item and answers „Kaufst du gerade ein?“ with „Nein, nur abgehakt“, tick-and-undo `tu-shop-ask`; Noah on a fresh device saves one edit; each time the card leaves with items still open).
- Widget and unit tests: `app/test/tips/` (`hints_test.dart` the rules and catalogue, `hints_cubit_test.dart` signals and events, `hint_views_test.dart` the flat card, X and snackbar, the checklist per kind, `tips_page_test.dart`); goldens `app/test/design/hint_card_golden_test.dart`.

## Gotchas

- A phone browser's context (an iPhone or Android `Mobile` user agent, such as Playwright's `devices['iPhone …']`) shows the open-app card above the tip slot on every load (household-invites `open-card`), which pushes the checklist down. The default 390 px `openApp` context is a desktop user agent and never shows it.
- A hint appears 10 s after the start and pushes the list down; let it settle before clicking a row by position, or dismiss the checklist in that session (no hint follows it).
- Which checklist items are done is per user and device, across all the user's households (the usage log `hints.<user>`): a tick in one household shows „Einmal einkaufen“ done in another on the same device. A fresh browser shows the card again on an old household. Only the X is per household.
- `siri` and `second-household` have no use the app can see; they retire on X, their button or three showings. `second-household` and `own-household` stay hidden while `HintHost.addHousehold` is unset in `main.dart` (still so after job 169b; DECISIONS job 168c #5).
- A Siri Shortcut's personal token counts as an assistant for `ai-assistant` and the club item (the app cannot tell an MCP token from a Shortcut's); the credential of Siri without setup does not.
