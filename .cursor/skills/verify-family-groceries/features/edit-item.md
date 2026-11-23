# Edit an item

An item on the list has a Bezeichnung (name), an optional Marke (brand), Eigenschaften (properties such as "Größe 3" or "1,5 %") and a Menge (quantity). The list row shows the name, and under it "Marke · Eigenschaften" when either is set. A hold that doesn't move or a right click opens the edit sheet from the bottom; a swipe across the row does nothing (job 78; it edited since job 29c and deleted before). A tap ticks the item instead (job 16). The sheet moves the item to another category or store; it has no delete since job 149 (a tick removes an item). Screen readers get edit and delete as actions on the row, the app's only delete. Nothing on the list drags (job 78): a hold opens the sheet as soon as it completes. It is exactly as tall as its content. Each field is prefilled and edits separately. Menge has −/+ buttons that change only the number and keep the unit. The store chip and the category chip fold their options out inline. Fertig saves only the fields that changed, and Abbrechen (bottom left, where Löschen was) discards. No title, no hint line; the chips carry no store or category icon. MCP and Siri entries are split into these fields by the server's parser ("Windeln Pampers Größe 3" gives Windeln, Pampers, Größe 3, Laden dm).

This map describes fg's debug app, which builds with every PostHog flag off. Users today have no category chip (`hide-categories`), Menge as one control with − and + (`add-sheet-compact`) and rounded shapes: `.cursor/skills/verify-snacklist/features/edit-item.md`.

## Sub-features

- `ed-row-details` shows "Marke · Eigenschaften" as the row's second line when either is set, and no added-by initial on any row.
- `ed-open` opens the sheet (key `edit-sheet`) on a hold that does not move or a right click. The row stays where it was. A sideways drag opens nothing, ticks nothing and leaves the row in place. A tap on the row ticks the item.
- `ed-hold-drift` keeps a finger hold that drifts less than 18 px a hold (it edits); a mouse counts as moving past 8 px (job 29c).
- `ed-a11y` gives screen readers "Bearbeiten" and "Löschen" as custom actions on the row, besides the long-press action that edits. Löschen deletes with "<name> gelöscht" and "Rückgängig"; fg has no command for a custom action.
- `ed-prefill` prefills `edit-name`, `edit-brand`, `edit-quantity` and `edit-properties`, sets the store chip (`chip-store`, showing the store such as "dm", or "Ohne Laden") and the category chip (`chip-category`, showing the category such as "👶 Drogerie"). Screen readers name them "Laden: <store>" ("Laden: Ohne Laden" without a store) and "Kategorie: <name>". The edit sheet never shows the add sheet's "Laden: automatisch"; an item whose store was deleted shows "Ohne Laden". An item without a category yet shows "Kategorie: automatisch", which is also its screen-reader name.
- `ed-steppers` changes the Menge with `edit-quantity-minus` and `edit-quantity-plus`: "2" gives "3", "2 l" gives "3 l", "500 g" gives "600 g", and an empty Menge counts as 1. The steppers hide for a Menge that does not start with a number. "−" is disabled when one step down would go below one step: at 1, "1,5 l", "100 g" or "150 g".
- `ed-chips` folds out `store-option-<id>` (plus `store-option-none` and `store-option-new`, `features/stores.md` `st-own-picker`; over five stores `store-search` above them, `st-own-search`) or `category-option-<id>`. A pick folds them back, and the sheet grows and shrinks with them.
- `ed-patch` makes Fertig (`edit-done`) write only the changed columns; a changed store or category also teaches the store or category memory for that name (`features/stores.md`, `features/classifier.md`). An unchanged Fertig writes nothing, and Fertig is disabled while the name is empty.
- `ed-cancel` makes Abbrechen (`edit-cancel`, bottom left next to Fertig) drop every change and close the sheet without writing or a snackbar (a store made there with „+ Neuer Laden“ is created right away and stays).
- `ed-size` keeps the sheet's height equal to its content, with every button at least 44 px (Fertig and Abbrechen 52 px), also on the Linux and web builds.
- `ed-list` (several lists only) „Liste“ (`edit-list`, one option `edit-list-<id>` per list) moves the item to another list of the household (lists-and-claims in verify-snacklist).
- `ed-claim` „Ich bringe das“ (`edit-claim`, a check box) claims the item for the signed-in member, with „Wie viel?“ for an amount; `edit-claim-others` shows who else brings it. A tick ends every claim on the item.
- `ed-parse` makes MCP `add_items`, Siri and `public.add_items` split an entry into the fields and pick the Laden from item→store memory, then the brand's store, then the category's (Drogerie gives dm).

## How to get to it (user POV)

- Press and hold an item on the list, then let go without moving.
- Right-click an item (web and desktop).
- Add an entry through Siri or an MCP app and look at its row.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md` with the chain stores dm, Lidl and Edeka, added as in `features/README.md` (Baseline) (the "dm" chip below is the brand default Pampers → dm); peter and lea signed in.
- No active Windeln or Milch: `fg db query "update items set status = 'bought' where status = 'active' and name in ('Windeln', 'Milch')" --write`.

- **Add split entries the way Siri and MCP do.** Run `fg db query "select name, brand, properties, quantity from public.add_items((select household_id from household_members where user_id = auth.uid() and is_default), array['Windeln Pampers Größe 3', '2 l Milch 1,5 %'])" --write --as lea`. The output is `Windeln|Pampers|Größe 3|` and `Milch||1,5 %|2 l`. peter's list shows "Windeln" with "Pampers · Größe 3" under it and no initial (`fg screenshot --name ed-row-details`).
- **A swipe does nothing.** Run `fg swipe --row Windeln --direction left` (300 px right to left along the row's middle). `fg wait --key edit-sheet --timeout 2` fails (no sheet), `fg find --contains Windeln` shows the row at its old bounds, and `fg db query "select status from items where name = 'Windeln' and status = 'active'"` still returns `active`.
- **Open the sheet.** Run `fg marionette -- long-press --text Windeln` (a hold without moving), then `fg wait --key edit-sheet`. `fg marionette -- secondary-tap --text Windeln` (a right click) opens it too. Run `fg screenshot --name ed-prefill`: Bezeichnung Windeln, Marke Pampers, Eigenschaften Größe 3, the chips "dm" and "👶 Drogerie".
- **Step the Menge and save.** Save the row first: `fg db query "select to_jsonb(i) - 'updated_at' from items i where name = 'Windeln' and status = 'active'"`. Run `fg tap --key edit-quantity-plus`: the Menge shows 2. Run `fg tap --key edit-done`, then `fg wait --key edit-sheet --gone`. Query the row again. Only `quantity` differs (null before, "2" now), and the row now reads "2× Windeln": use that text from here on.
- **Fold out a chip.** Open the sheet again (`fg marionette -- long-press --text "2× Windeln"`), run `fg tap --key chip-category` and `fg screenshot --name ed-chips`. The categories show as options under the chips, and the sheet has grown upwards. Run `fg tap --key chip-category` again to fold them back. Then run `fg tap --key edit-cancel`.
- **Check the partner highlight is kept.** Run `fg peer lea add Kaffee`, then `fg wait --text "1 neu von Lea" --timeout 5`. Take a screenshot at once, because the highlight clears after 3 s on screen. Kaffee is tinted, and no row carries an initial.
- **Cancel drops a change.** Open "2× Windeln", run `fg tap --key edit-quantity-plus`, then `fg tap --key edit-cancel` and `fg wait --key edit-sheet --gone`. The row still reads "2× Windeln" and `fg db query "select quantity from items where name = 'Windeln' and status = 'active'"` returns 2.
- **Delete.** Not drivable with fg: the only delete is the row's screen-reader action, and fg cannot trigger a custom action. `app/test/list/list_screen_test.dart` („screen readers get edit and delete as actions“) covers it; report it as skipped.

## Gotchas

- `fg tap` on a row ticks the item. Open the sheet with `fg marionette -- long-press` or `secondary-tap`. The e2e spec `e2e/tests/edit-sheet.spec.ts` covers the long press and the right click on web, and a finger hold and a drifting hold in Chrome as an Android phone (real touch over CDP); `e2e/tests/iphone.spec.ts` covers a hold, and a swipe that opens nothing, in WebKit as an iPhone.
- A swipe that starts as a hold still opens the sheet, by the hold. Marionette's `swipe` moves at once, so it never does.
- On Flutter web a text field's value is empty in the DOM until the field is focused. Read prefilled values after a click (`expectFieldValue` in `e2e/tests/helpers.ts`).
- The chip and the option of the same store show the same text ("dm"). Only the chips' screen-reader names differ ("Laden: …", "Kategorie: …"), which Playwright uses; with fg, tap the option by key (`store-option-<id>`).
- A fresh partner item stops being new 3 s after it is on screen. Screenshot right after `fg wait`.
- The row text starts with the quantity ("2× Windeln", "2 l Milch"); `--text` needs the whole of it.
