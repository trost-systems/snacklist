# Ticking items, "Zuletzt verwendet" and undo

A tap on an item's row ticks it off: a line draws across the item's words, the row turns mint, then it closes and the rows below move up (about 0.4 s). A store or category divider whose last item leaves closes with it. No snackbar appears, so a tick has no „Rückgängig“; screen readers hear „<Name> abgehakt“ / "<Name> ticked off". Ticked items collect in a folded section at the bottom of the list, „Zuletzt verwendet“ (the 20 newest, each thing once, none that is on the list again). A tap on an item there puts it back on the list, in the place it had, without a snackbar. Ticking is how an item leaves the list; the edit sheet has no delete since job 149. Only some other actions carry an undo: a screen reader's delete on a row, the add sheet's „Hinzugefügt“ note, and a merge of duplicates.

## Sub-features

- `tu-tick` a tap on a row ticks it: strike-through across quantity and name (180 ms), the row tints mint, then fades and closes (260 ms); the tick commits 440 ms after the tap and is saved on the server (survives a reload). When the row or the app goes away before that, the tick commits then (job 222): the app goes to the background, the page reloads or its tab closes (the tick is queued on the device and sent at the next start), the row's store is folded, or the list is left for another household. No snackbar. With reduced motion the struck row shows at once, holds 260 ms and goes without the close.
- `tu-tick-a11y` each row is a checkbox (unchecked while open, checked while it leaves) and the tick is announced „<Name> abgehakt“ / "<Name> ticked off". There is no visible check box.
- `tu-used-section` „Zuletzt verwendet“ / "Recently used" is a folded section below the list; it exists only while at least one item is ticked. With several lists it holds the ticks of the list whose tab is shown. A tick also ends every „Ich bringe das“ on that item (lists-and-claims). It holds up to 20 ticked items, newest tick first, one row per thing (the same item or another spelling of it, its newest tick), and none for a thing that is on the list again; each drawn like the list's row (icon, quantity in bold before the name, then brand · details) but faded. It is built from the household's 50 newest ticked rows across all its lists, then filtered to the shown list, so fewer than 20 rows show when many of them are the same thing or were ticked on another list.
- `tu-put-back` a tap on a row under „Zuletzt verwendet“ puts it back on the list in its old store, category and position. No snackbar.
- `tu-delete-undo` the row's screen-reader action „Löschen“ / "Delete" (VoiceOver, TalkBack; the edit sheet's button is gone since job 149) removes the item and shows the snackbar „<Name> gelöscht“ / "<Name> deleted" with the action „Rückgängig“ / "Undo", which brings the item back (the server row is re-created). When the same item is open on the list again by then (a partner added it), Undo shows that item as it is and adds no second one (job 64b, `put_item`). Not drivable on web: Flutter web does not expose custom semantics actions.
- `tu-added-undo` after an add, the add sheet shows „✓ Hinzugefügt: <Name>“ (or „✓ Hinzugefügt: <Name> → <Store>“) with „Rückgängig“ until the next keystroke; Undo removes the item again (and forgets a category picked on that add, see classifier).
- `tu-merge-undo` an add of exactly an open item (same name, brand and details) is not added: the note says „<Name> steht schon auf der Liste“ / "<Name> is already on the list" without a button. When the add is another spelling of an open item, it goes through and the note offers „Zusammenführen“ / "Merge"; afterwards „Zusammengeführt: <item>“ with „Rückgängig“ undoes the merge. Outside the add sheet the same offer is a snackbar „<Name> steht schon auf der Liste“ with „Zusammenführen“ (6 s).
- `tu-no-swipe-delete` a swipe across a row does nothing: it neither deletes, ticks nor edits (job 78; a hold edits).

## How to get to it (user POV)

- Tick: tap an item row on the list tab.
- Put back: scroll to the bottom of the list, tap „Zuletzt verwendet“ / "Recently used" to unfold it, tap the item.
- Add undo: type an item in the add bar and tap „Rückgängig“ in the note under it.
- Screen reader users: a row also offers the actions „Bearbeiten“ and „Löschen“ (delete without the sheet, same snackbar with „Rückgängig“).

## Driving it with Playwright

Preconditions:

- Seeded household „Familie Brandt“, signed in on the list, analytics declined, onboarded; the demo items include Butter, Nudeln and Reis without a quantity and „6× Bananen“ with one.
- Browser locale de-DE, viewport 480x900 or 390x844.

- **Scripted.** `helpers/drive.sh tick-and-undo` (`journeys/tick-and-undo.mjs`; `--item <name>`, default Butter; `--lang en`) ticks, checks there is no „Rückgängig“ and the stored `bought`, then puts the item back: PASS or FAIL. The steps below use `tick`, `putBack`, `usedRow` and `actionSnackBar` from `e2e/tests/helpers.ts`; `helpers/lib.mjs` has `itemRow` and `reveal`, but not `tick`, `putBack`, `usedRow` or `actionSnackBar`.
- **Tick.** Tap the row. `tick(page, 'Butter')` (reveals the row, clicks `itemRow(page, 'Butter')`). Observable result: `itemRow(page, 'Butter')` count drops by 1; `page.getByRole('button', { name: 'Rückgängig' })` count is 0 and no snackbar group named „Butter abgehakt“ (`actionSnackBar(page, 'Butter abgehakt')` count 0; the same words exist only as the screen-reader announcement).
- **Open the used section.** `page.getByRole('button', { name: 'Zuletzt verwendet', exact: true }).click()` (`reveal` it first if off-screen). Observable result: `usedRow(page, 'Butter')` visible; its accessible name is the item name, then details/quantity, then „Wieder auf die Liste“, for example `Butter Wieder auf die Liste`, or `Bananen 6 Wieder auf die Liste` after ticking „6× Bananen“.
- **Put back.** `putBack(page, 'Butter')` (or `usedRow(page, 'Butter').click()`). Observable result: `itemRow(page, 'Butter')` visible again, `usedRow(page, 'Butter')` count 0, no snackbar (`page.getByRole('button', { name: 'Rückgängig' })` count 0; the old text no longer exists). In a store section the row returns to its old position (`list-walk-order.spec.ts` checks the row order).
- **Persistence.** After tick or put back, `page.reload()` then `expect(addField(page)).toBeFocused()`; the row is gone/back. A second view: the `items` row's `status` is `bought` / `active` through the API as the user.
- **Delete and undo.** Not in the web UI since job 149 (see `tu-delete-undo`); a delete through the API (`deleteItem(api, page, item)` in `e2e/tests/catalog.ts`) shows no snackbar.
- **Hidden while on the list.** Tick Reis, add „Reis“ again in the add bar: `usedRow(page, 'Reis')` count goes from 1 to 0.
- **Add undo.** Type an item that is not on the list with `typeInto(addField(page), 'Joghurt')` and press Enter; the note „✓ Hinzugefügt: Joghurt“ shows with button „Rückgängig“; click it and `itemRow(page, 'Joghurt')` is gone. (A seeded name such as Butter is already on the list: its note has no „Rückgängig“.)
- **Spec coverage.** `e2e/tests/list.spec.ts` (tick without snackbar, put back, reload persistence, duplicate add), `e2e/tests/list-walk-order.spec.ts` ("a tap ticks, a tap under Zuletzt verwendet puts it back in place"), `e2e/tests/already-on-list.spec.ts` (an offline tick replayed onto the partner's item), `e2e/tests/tick-leave.spec.ts` (a reload or a closed tab right after the click keeps the tick; Chromium, WebKit and Firefox), `e2e/tests/dedupe.spec.ts` („Zusammenführen“ and its „Rückgängig“). Scripted: `helpers/drive.sh tick-and-undo [--lang en] [--item Butter]`. Run `scripts/verify.sh --only e2e -- tests/list.spec.ts`.

## Gotchas

- The add field floats over the list's bottom edge: a tap in its band, gutters included, opens the field and never ticks the row under it. `reveal` the row clear of the field first.
- A used row's gestures are off except the tap: no tick, right click or hold. Its accessible name ends in „Wieder auf die Liste“; `itemRow` excludes names ending that way, `usedRow` requires it.
- „Zuletzt verwendet“ is folded by default and the list is long: scroll to it (`reveal`) before clicking.
- The add sheet's rows for an empty field are also named „<Name>, Zuletzt verwendet“; while the sheet is open a `getByRole('button', { name: 'Zuletzt verwendet' })` without `exact: true` can match them (`putBack` in `e2e/tests/helpers.ts` does not pass `exact`).
- In English the used row's name ends in "Back on the list", not a translation of the German; `usedRow`'s pattern is German only.
- `getByText` finds the screen-reader copy of a snackbar only briefly; use `actionSnackBar` for snackbars with an action.
- Putting an item back within 10 minutes of the tick counts as the tick's undo; later it counts as a new add for analytics only. The user sees no difference.
- No code path purges ticked items after a time (none found); the section keeps the 20 newest. unverified (no server job found, not run).
- The „Rückgängig“ in the add note disappears at the next keystroke; click it before typing again.
- Ticking has no undo snackbar since the job 29b release; old recipes that wait for a „Rückgängig“ after a tick are wrong.
- Rows are role `checkbox` since job 57 (2026-11-01): `itemRow` in `e2e/tests/helpers.ts` and `helpers/lib.mjs` find them that way; recipes that look for a row as `button` find nothing. Rows under „Zuletzt verwendet“ stay buttons (`usedRow`).
- `tick` waits for the row to go; the row needs about 440 ms before the tick commits, so an add of the same name right after a click finds it still on the list.
- A reload right after a click keeps the tick since job 222, but the write goes out only after the reload, from the device's queue: `tickSaved` still is the helper that waits for the PATCH. A tick made less than 440 ms before signing out goes with the device's data (by design: sign-out forgets the queue).
