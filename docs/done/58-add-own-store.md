# Job 58: add your own store (inline in the store picker, Mehr → Läden)

Decisions: [DECISIONS.md](../DECISIONS.md) "Job 58". Screenshots and the clip:
[`docs/screenshots/58/`](../screenshots/58/). PR: #176.

## What changed for users

- **A new store while adding an item.** The store options of the add sheet and the edit sheet end
  in "+ Neuer Laden". Tapping it turns the row into a hex field with a check and a close button.
  Enter or the check creates the store for the household and picks it for the item in one step;
  screen readers hear "Rewe angelegt und ausgewählt". Escape, back or the close button cancel
  and put focus back on the row. A name the household has already (any case, extra spaces)
  picks that store instead of making a second one. From six stores a search field sits above the
  options; Enter there picks the store of that name or opens the new-store field with the text.
- **Mehr → Läden** adds stores ("+ Neuer Laden" below the rows), renames one in its row (menu ⋮
  → Umbenennen) and deletes one with a confirmation that says how many open items move to "Ohne
  Laden". Reorder and the walking order stay as they were. A household without stores sees
  "Noch keine Läden. …" and the add row, so the onboarding hint ("Du kannst sie später unter Mehr
  anlegen") and hummlist.com's "Eigene Läden legst du dazu" are true.
- **A new store's walking order** is the household's route order with every category, editable
  like dm's, Lidl's and Edeka's. Its badge is job 57's `StoreBadge` with the full name.
- **Preset stores** can be renamed and deleted too. "dm" renamed to "Rossmann" stops being dm
  (no dm brand defaults).
- **Online only**, like reordering: offline the app says "Läden lassen sich nur mit Verbindung
  anlegen, umbenennen oder löschen."
- **The other member** sees a new, renamed or deleted store at once (realtime, no change needed).
- **MCP** (`list_stores`, `store` on add, move and list) works with own stores by name in any case;
  a deleted or renamed-away name gets the usual "Laden „…“ nicht gefunden. Vorhanden: …".

## Where

- `supabase/migrations/20261101160000_add_own_stores.sql`: `store_name_key`, the unique index
  per household, `store_name`, `add_store`, `rename_store`, `delete_store`. Tests:
  `supabase/tests/stores.test.sql`, three cases in `rls.test.sql`.
- `app/lib/list/`: `model.dart` (`storeNameKey`, `Catalog.storeNamed/withStore/withStoreName/
  withoutStore`), `list_repository.dart`, `list_cubit.dart` (`addStore`, `renameStore`,
  `deleteStore`, `StoreNameTaken`, `StoreNeedsConnection`), `store_name_field.dart` (the inline
  field), `foldout_chips.dart` (`_StoreOptions`: search, + row, field), `edit_item_sheet.dart`,
  `add_sheet/add_sheet.dart`; `app/lib/more/stores_screen.dart`.
- `supabase/functions/mcp/list.ts` (`resolve`: exact name in any case first), `tools.ts`.
- Tests: `test/list/store_picker_test.dart`, `test/more/stores_screen_test.dart`, cubit and
  edit-sheet and list-screen cases, goldens `add-sheet-new-store-*` and `stores-*`, Widgetbook
  stories (FoldoutChips "Läden offen", "Viele Läden (Suche)", StoreNameField), Playwright
  `e2e/tests/stores-add.spec.ts` and the MCP case in `mcp.spec.ts`.
- Verify skill: `features/stores.md` (`st-own-*`), `quick-add.md`, `edit-item.md`.

## How to verify

- `supabase test db` (1518 pgTAP tests), `flutter test` in `app/` and `app/widgetbook/`,
  `deno test` in `supabase/functions`.
- `scripts/verify.sh --only e2e -- tests/stores-add.spec.ts tests/mcp.spec.ts`.
- By hand: add an item, open "Laden", "+ Neuer Laden", type Rewe, Enter: the chip says Rewe and
  the item lands under a Rewe divider. Mehr → Läden: Rewe is there; ⋮ renames or deletes it.

## Server paths checked

| Path | Own store | Renamed / deleted |
| --- | --- | --- |
| MCP `list_stores` | listed | gone / new name |
| MCP `add_items`, `move_item`, `list_items` with `store` | found by name, any case | "nicht gefunden" with the list |
| Siri / voice endpoint | no store words; memory picks it once used | memory goes with the store |
| Alexa | reads items, no store slot | unaffected |
| AI chat | none in the app; MCP clients use the MCP rows above | as MCP |

## Not done / open

- Retailer logos: none, waiting for the legal check (Peter). `StoreBadgeStyle.logo` is the slot.
