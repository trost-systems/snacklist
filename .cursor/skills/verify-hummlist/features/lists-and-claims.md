# Several lists and „Ich bringe“

A household can keep several lists (job 169b K): „Wocheneinkauf“ next to „Baumarkt“, a club's „Vereinsheim“ next to „Sommerfest“. Stores, categories, their order and the classifier stay the household's; each item is on one list. Members say what they bring with „Ich bringe das“ / "I'll bring it" (job 169b L), and the row shows who brings what.

## Sub-features

- `lc-tabs` with two or more lists a raised hex track sits under the list's header: one tab per list in the household's order, the shown list on the honey hex, „+“ (accessible name „Neue Liste“ / "New list") at the end, always in view. The lists' tabs are a tab bar (role `tablist`, each tab `tab`, the shown one selected); the track's group is named „Listen“ / "Lists". Wider than the row (the 358 px compact design, many or long names), the tabs scroll sideways under the fixed „+“, and an end with more tabs past it fades out. Picking another list scrolls its tab clear of the fade. With one list there is no track.
- `lc-shown` the list shows the shown list's items only; the shown list is remembered per device, household and user (`listprefs.<user>.<household>`, `shown_list`). A shown list deleted elsewhere falls back to the first. „Zuletzt verwendet“ is the shown list's. The household switcher counts open items on every list.
- `lc-add` an add goes to the shown list. The open-item duplicate rule is per list: „Milch“ may be open on two lists, and the add sheet's „steht schon auf der Liste“ looks at the shown list only.
- `lc-new` „+“ on the track or „Neue Liste“ on the household page asks for a name („Name der Liste“ / "List name", 60 characters) and „Erstellen“ / "Create". The new list shows right away (screen readers hear „Liste „<name>“ angelegt“). Offline it is refused: „Listen lassen sich nur mit Verbindung anlegen, umbenennen, sortieren oder löschen.“
- `lc-move` with two or more lists the edit sheet has „Liste“ / "List" with one option per list, the item's own picked (honey). Another one and „Fertig“ moves the item there (works offline; sent when back). An item open there already under the same name, brand and details stays: „„<name>“ steht schon auf „<list>“.“ / "“<name>” is already on “<list>”."
- `lc-manage` the household page (Mehr, the household's row) has „Listen“ / "Lists": each list with „<n> offen“, and a menu „Aktionen für „<name>““ with „Umbenennen“, „Nach oben“, „Nach unten“ and „Löschen“ (not for the last list; no „Nach oben“ on the first, no „Nach unten“ on the last). „Löschen“ asks „„<name>“ löschen?“ naming the open items that go with it („Die 2 offenen Artikel darauf werden mit gelöscht.“). Below them „Neue Liste“.
- `lc-claim` the edit sheet of an open item has „Ich bringe das“ (a hex check box); who else brings it shows under it („Lea bringt 1“). Ticked, „Wie viel?“ / "How much?" takes an optional amount („z. B. 2“). „Fertig“ saves the claim, a changed amount, or taking it back (works offline; sent when back). Ticking or deleting the item ends every claim on it.
- `lc-claim-row` a claimed row has a line in bold cobalt under the name and details: „Mia bringt“, „Mia bringt 2 · Tom bringt 1“, „Du bringst“ / "You bring" for your own claim, oldest first. It is part of the row's accessible name, after the quantity. Claims from other phones arrive live.
- `lc-old-builds` (server side, not in the app) old store builds see every list's items as one list and add to the first list; Siri, Alexa and voice add to the default household's first list.

## How to get to it (user POV)

- Lists: the track under the list's header (two or more lists); tab „Mehr“, the household's row, section „Listen“.
- Claims and moving: press and hold a row (or right-click), the edit sheet.

## Driving it with Playwright

Not driven yet: it needs the W3 server (`lists`, `items.list_id`, `item_claims`, `create_list`, `claim_item`). Until then the behaviour is proved by widget and unit tests:

- `app/test/list/lists_and_claims_test.dart` (shown list, adds per list, a move offline then sent, lists added, renamed, moved and deleted, offline refusal, the device copy from before lists, claims optimistic, retried, ended by a tick, live).
- `app/test/list/list_tabs_test.dart` (no tabs with one list, three lists and a tap, „+“, 358 px scrolling, the claim line).
- `app/test/list/edit_sheet_lists_claims_test.dart` (the „Liste“ picker, „Ich bringe das“ with an amount, taking it back).
- `app/test/household/lists_section_test.dart` (counts, rename, move, delete with its confirm).
- Goldens: `list-tabs-{light,dark}`, `list-tabs-compact-{light,dark}`, `household-lists-{light,dark}`, `edit-sheet-{light,dark}` in `app/test/design/goldens/`.

Once the server is there, a recipe: seed a household, `apiAs(...).rpc('create_list', { p_household, p_name: 'Sommerfest', p_id })`, reload; the track shows with `getByRole('tab', { name: 'Sommerfest' })`; click it, add an item, read its `list_id` through the API.

## Gotchas

- Flutter's test font is wide: in widget tests the last tabs sit past the row; `tester.ensureVisible` before tapping them.
- The tabs' `+` is not a tab (outside the `tablist`): find it with `getByRole('button', { name: 'Neue Liste' })`.
