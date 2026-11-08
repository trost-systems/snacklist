# Categories

Liste → "Anpassen" → "Ohne Laden" (job 78; before, Mehr → "Kategorien verwalten") opens the "Ohne Laden" details (route `/edit/none`, key `store-details`): the household's route order, which sorts the "Ohne Laden" section and the categories a store's layout leaves out. A store's details (`/edit/<id>`) show the same category rows in that store's order, with the same rename, add and delete. A tap on a category renames it. "Kategorie hinzufügen" adds one before "Sonstiges", in the route and in every store. The trash icon deletes a category after asking where its items go. "Sonstiges" can't be deleted. The drag handle reorders the route; nothing on the list drags (job 78).

## Sub-features

- `cat-open` lists the household's categories in route order under the title "Ohne Laden" and the hint "In dieser Reihenfolge stehen die Kategorien unter „Ohne Laden“ …". It opens from the list header's "Anpassen" (`list-edit`) → the pinned "Ohne Laden" row (`store-row-none`) only; a hold or right click on a list divider does nothing (job 171). Each row shows the category's emoji and its name, no step number (job 148); its semantics hint is its place, "2 von 11" ("2 of 11"); the label stays the name.
- `cat-add` adds a category ("Kategorie hinzufügen", the button `category-add` bottom right on any store's details too; field "Name", `name-dialog-field`, at most 60 characters) just before "Sonstiges" and into every store's order.
- `cat-duplicate` names are unique per household ignoring case and spacing (job 90). Adding one the household has, or renaming onto another category's name, keeps the dialog open with "Eine Kategorie „<existing name>“ gibt es schon." under the field; typing clears it. A category may change its own case.
- `cat-rename` renames a category ("Kategorie umbenennen").
- `cat-delete` deletes a category ("<name> löschen"; the dialog says "Sie verschwindet aus allen Läden.", since categories belong to the household) and moves its items to the category chosen in "Artikel verschieben nach" (default "Sonstiges"). It teaches the classifier nothing, and the learned corrections that pointed at the deleted category go with it.
- `cat-other-fixed` gives "Sonstiges" no delete button.
- `cat-reorder` reorders the route by dragging a handle ("<name> verschieben").

## How to get to it (user POV)

- On the list, tap "Anpassen" top right, then "Ohne Laden" (last row). A store's row opens the same category actions in that store's order.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`; peter signed in on the list. No category named "Baby" or "Babysachen" (`fg up --fresh` restores the seeded 11).

- **Open.** Run `fg tap --key list-edit`, `fg wait --key stores-screen`, `fg tap --key store-row-none` and `fg wait --key store-details`. `fg find --type Text` lists the 11 seeded categories in route order. `fg find --tooltip "Sonstiges löschen"` counts 0, and `fg find --tooltip "Haushalt löschen"` counts 1. The second entry point: `fg back`, `fg tap --key tab-list`, `fg marionette -- scroll-to --key store-none`, `fg marionette -- secondary-tap --key store-none` and `fg wait --key store-details` (no menu; the hold opens the details directly). "Ohne Laden" shows only while items have no store; add one first if the list has none.
- **Add.** Run `fg tap --key category-add`, `fg wait --label Name`, `fg type --label Name --input Baby --submit` and `fg wait --text Baby`. `fg db query "select name from categories order by sort_order desc limit 2" --as peter` returns Sonstiges, then Baby. `fg db query "select count(*) from store_category_order o join categories c on c.id = o.category_id where c.name = 'Baby'" --as peter` returns 3.
- **Duplicate.** Add „baby“ the same way (any case). `fg wait --contains "gibt es schon"` matches, and the dialog is still open (`fg find --label Name` counts 1).
- **Rename.** Run `fg tap --text Baby`, `fg wait --text "Kategorie umbenennen"`, `fg type --label Name --input Babysachen --submit` and `fg wait --text Babysachen`. `fg type` replaces the pre-filled name. `fg db query "select name from categories where name like 'Baby%'" --as peter` returns Babysachen.
- **Delete.** Put an item in it first. The dialog reads "Sie verschwindet aus allen Läden." The baseline list is empty, so add one: `fg back`, `fg type --key add-item-field --input Äpfel --submit`, `fg wait --text Äpfel`, then open "Ohne Laden" again as in **Open**. Then run `fg db query "update items set category_id = (select id from categories where name = 'Babysachen' and household_id = items.household_id) where name = 'Äpfel' and status = 'active' and household_id = (select id from households where name = 'Familie Test')" --write`. Run `fg tap --tooltip "Babysachen löschen"`, `fg wait --text "Babysachen löschen"`, `fg tap --text Löschen` and `fg wait --text Babysachen --gone`. The item's category query (`select c.name from items i join categories c on c.id = i.category_id where i.name = 'Äpfel' and i.status = 'active'`, `--as peter`) returns Sonstiges, and `fg db query "select count(*) from category_memory m join categories c on c.id = m.category_id where c.name = 'Sonstiges'" --as peter` did not grow.
- **Reorder.** The handle starts a drag at once (no long press), so a coordinate swipe drives it. `fg find --contains verschieben` lists the handles ("<name> verschieben") top to bottom with their bounds, below the screen's intro text; the rows are hex pills about 68 px apart and the list is centred (at most 640 px wide), so take x and y from the find output. Run `fg marionette -- swipe --start-x <x+24> --start-y <y+24> --end-x <x+24> --end-y <third row's y+24>`: from the first handle's centre to just past the third row. `fg find --contains verschieben` now starts with "Brot & Backwaren", "Kühlregal", "Obst & Gemüse", and `fg db query "select name from categories order by sort_order limit 3" --as peter` returns the same order (repeat it if it lags a second). Restore the route with the reverse swipe: from the third handle's centre to just above the first row.
- **Proof.** Screenshot the screen after each step and save the category queries. Run `fg back` twice: the stores screen, then the list.

## Gotchas

- A taken name keeps the dialog open: `fg back` closes the dialog first.
- "Kategorie hinzufügen" is both the button and the open dialog's title. Wait for the field (`--label Name`) instead of the text.
- The delete dialog's "Artikel verschieben nach" dropdown is not listed by `fg find`. Leave it on "Sonstiges" or check the result in the database.
- A precondition written with `fg db query --write` that changes an item's category counts as a correction: the household learns it, like a move in the edit sheet. Deleting the category removes that learned row again.
- Category changes survive `fg up` and change the divider order in "Ohne Laden" and in every store in other recipes. Restore with `fg up --fresh`.
- `fg back` on "Ohne Laden" returns to the stores screen (`/edit`), a second one to the list; a third closes the Linux app.
- Seeded scenario runs share the stack. A query without `--as peter` (or a household filter) also counts their categories and items.
