# Job 350: categories hidden behind `hide-categories`

Peter (t1119s4855, 21 Nov 2026): remove categories from what users see until someone asks for
them with a good reason; the item order stays.

## What

New PostHog flag `hide-categories` (`app/lib/analytics/flags.dart`; `releases/flags.json` rollout
`off`). Once on main the flag sync creates it with `is_internal = true` at 100 %: Peter's phone and
the internal tester group get it, nobody else. Flag off is unchanged.

With the flag on:

| Where | Before | With the flag |
| --- | --- | --- |
| List (every store section; trip mode, prices and the decluttered list use the same rows) | a small divider per category | none; the rows in the same order, a rule between each, none under a section's last |
| List behind the add sheet, „Gerade hinzugefügt“, „Zuletzt verwendet“ | no category text already | unchanged |
| Add sheet header chips (without add-feedback-list) | store and category chip | store chip |
| Add sheet, the added item's details (add-feedback-list) | store and category chip | store chip |
| Compact add sheet chip row (add-sheet-compact) | Menge, store, category, Details | Menge, store, Details |
| Edit item sheet | store and category chip | store chip; a save keeps the category |
| Anpassen › Läden | hint naming categories, pinned „Ohne Laden“ row („Kategorien für Artikel ohne Laden“) | the stores only („Noch keine Läden …“ still shows without stores) |
| A store's screen | name, chain card, category order, „Kategorie hinzufügen“ | name and chain card |
| `/edit/none` („Ohne Laden“'s category order) | category order | back to Läden |
| Tip „Sortiert wie dein Laden“ (list callout and Mehr › Tipps) | shown after a shop with a store | never offered |

Unchanged on purpose: the classifier and category memory, the API and MCP, the delete-account and
leave-household dialogs (they say the household's categories are deleted, which stays true), the
API key scope text. Searched and free of category text: item rows and their screen-reader labels,
suggestion rows (the category only picks the 🔁 fallback icon), trip summary, Verlauf, totals,
onboarding, home-screen widgets, and there is no list share-as-text.

## How

- `shopping_list_view.dart`: `_entries` takes `categories`; without it a section is one run of
  rows (its blocks joined in order) and no `CategoryDivider`.
- `foldout_chips.dart`: `onCategory` is nullable; null drops the category chip and its fold. The
  edit sheet (`showEditItemSheet(categories:)`), the add sheet's two chip rows and
  `compact_details.dart` pass null under the flag.
- `stores_screen.dart`, `store_details_screen.dart`: see the table.
- `tips/hints.dart`: `Hint.aboutCategories`; `offered(categoriesHidden:)` drops it, used by
  `nextHint` (via `HintContext.categoriesHidden`, which `HintsCubit` fills from `Flags`) and
  `TipsPage`.

No ARB string added or changed.

## Verify

- `app/test/list/hide_categories_test.dart` (14 tests): the list plain, in trip mode with prices,
  and decluttered: same order off and on, no category text painted or in a screen-reader label
  with the flag (also under „Zuletzt verwendet“); the three add-sheet forms and the edit sheet with
  and without the chip; an add and an edit keep their category. 8 of them fail with the flag read
  disabled (checked).
- `stores_screen_test.dart`, `store_details_screen_test.dart`, `app/test/tips/`: the store screens
  and the tip with the flag.
- Web app (`journeys/hide-categories.mjs`, `demo-haushalt`, 4 stores, 12 items): with
  `FLAGS_ON=hide-categories` no category name on the list, add sheet, edit sheet, Läden or a store;
  without it the categories show; `order.json` identical both ways. Screenshots in
  `docs/screenshots/350/` (`on-*` and `off-*`).
- `scripts/verify.sh --only lint,flutter`: passed.

## TestFlight

Ships with the next green main build after the merge. Flag `hide-categories`: on for internal
installs only (the sync's default condition), which includes Peter's account; everyone else off.
