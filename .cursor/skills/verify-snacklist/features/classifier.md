# Automatic category (the classifier)

Every new item gets a category without the user choosing one: the server looks at the name and files it under a category divider. In the app the add sheet already shows the server's guess while the name is typed, and the new row shows under it at once. Unless the user picked a category, the server classifies the item again when it saves the add, after the user's earlier edits, so a correction made just before counts (job 126); an add without a guess (offline) is classified then too. It uses what the household taught it, then a built-in German word list of about 1,350 terms (compound words, plurals, umlauts, quantities in front of the name), then synonyms and typos, and finally „Sonstiges“. The same server logic runs for every way of adding: typing in the app, voice dictation, the MCP assistant connection, Siri (voice endpoint) and Alexa. A user can override the guess; the household remembers the correction.

## Sub-features

- `cl-auto` an item without a category lands under the matching divider, e.g. Hafermilch → „Kühlregal“, Apfelsaft → „Getränke“, Zahnbürste → „👶 Drogerie“, Vollkornbrot → „Brot & Backwaren“, Spülmaschinentabs → „Haushalt“, Fischstäbchen → „Tiefkühl“, Gummibärchen → „Süßes & Snacks“, Kichererbsen → „Vorrat & Konserven“, Rinderhack → „Fleisch/Wurst/Fisch“, „Aepfel 2 kg“ → „Obst & Gemüse“ (name „Aepfel“, quantity „2 kg“). The word list is German; English words work only where they are synonyms ("toilet paper" → „Haushalt“).
- `cl-baumarkt` about 270 DIY words (job 151). In a household with a Baumarkt (feature categories, `cat-baumarkt`) they land in its seven categories: Schrauben, Dübel → „Schrauben & Befestigung“, Glühbirne, Kabelbinder → „Elektro & Leuchtmittel“, Wandfarbe, Pinsel, Abdeckband → „Farben & Lacke“, Duschkopf, Silikon → „Sanitär“, Akkuschrauber → „Werkzeug“, Blumenerde, Dünger → „Garten & Pflanzen“, Holzlatten → „Holz & Baustoffe“; the store guess is the Baumarkt. Without a Baumarkt they land in „Haushalt“ (as Glühbirne, Kabelbinder and Blumenerde did before; Schrauben, Dübel and Pinsel were „Sonstiges“ until job 151), and the add sheet's catalogue does not suggest them. Batterien, Grillkohle, Klebeband and Rohrreiniger stay „Haushalt“ in both.
- `cl-fallback` an unknown word lands under „Sonstiges“ / "Other" (the household's fallback category), shown last unless the household reordered its categories.
- `cl-preview` while typing, the add sheet's category chip shows the guess, muted with an "A" mark (accessible name „Kategorie: automatisch, 👶 Drogerie“ for „Zahnbürste“), and the store chip the store guess („Laden: automatisch, dm“); with nothing guessed the chip shows „Kategorie“, named „Kategorie: automatisch“ / "Category: automatic".
- `cl-sorting` an item added without a category (offline, or Enter before the sheet had an answer) shows at the top of its section under a divider „Wird einsortiert …“ / "Sorting…", then moves under its category. Online adds arrive categorized and skip it.
- `cl-learn-edit` the user moves an item to another category in the edit sheet (chip „Kategorie: …“, pick, „Fertig“); the list itself has no drag since job 78. The household learns it: the next add of that item (and its plural, e.g. „Zahnbürste“ → „Zahnbürsten“) lands there, also right after the correction while it is still on its way to the server (job 126).
- `cl-learn-pick` a category chosen on the add sheet's category chip (before a pick named „Kategorie: automatisch, <guess>“ / "Category: automatic, <guess>", or „Kategorie: automatisch“ without a guess) is learned when it differs from the guess; „Rückgängig“ on that add removes the item and the lesson again.
- `cl-variants` spelling variants, regional and English synonyms and typos land with the word they mean, the name stays as typed: „Karrotten“ → „Obst & Gemüse“ (Möhren), „Paradeiser“ → „Obst & Gemüse“, „Semmeln“ → „Brot & Backwaren“, „Mlich“ → „Kühlregal“, „Schokolde“ → „Süßes & Snacks“, "toilet paper" → „Haushalt“.
- `cl-variant-learn` a correction for one spelling holds for the word's synonyms and spellings in that household only: „Karrotten“ moved to „Getränke“, then „Möhren“ lands in „Getränke“.
- `cl-household-only` learning is per household; another household with the same word still gets the default category.
- `cl-delete-category` deleting a category moves its items and forgets what was learned for it; the move itself teaches nothing.
- `cl-same-everywhere` the app, the MCP assistant connection, Siri and Alexa all add through the same server logic (categories and learned corrections apply the same).
- `cl-store` a new item also gets a store: the one the household remembers for that name, else the store of a store's own brand (Balea → dm), else dm for drugstore items when the household has dm. The add sheet and the server add path (MCP, Siri, Alexa, dictation) guess the same way; "Windeln Größe 4" lands in dm.

## How to get to it (user POV)

- Type an item in the floating add field at the bottom (the list scrolls on under it) and add it: it appears under its category divider (in the guessed store's section, see `cl-store`, otherwise under „Ohne Laden“).
- To correct: hold the item (or right click it) to open „Bearbeiten“, tap the chip „Kategorie: …“, pick a category, tap „Fertig“.
- To choose before adding: tap the category chip in the add sheet.

## Driving it with Playwright

Preconditions:

- A fresh account in its own household: `signUpWithHousehold(page, newEmail('learn'), { stores: chainStores })` (dm, Lidl, EDEKA; without `stores` the household has none, since job 64). Learning is per household and persistent, so do not reuse a household for first-guess checks.
- Seeded categories untouched (a renamed category changes the divider text).

- **Preview.** Type `Zahnbürste` into the add field without Enter: `addSheet(page).getByRole('button', { name: 'Kategorie: automatisch, 👶 Drogerie' })` and `{ name: 'Laden: automatisch, dm' }` show in the sheet (with no stores, as on the demo-familie baseline, the store chip reads „Laden: automatisch“; driven 2026-11-04).
- **Auto-categorize.** `addItem(page, 'Hafermilch')`, then `expectGroup(page, 'Hafermilch', 'Kühlregal')` (nearest level-2 heading above the row, `e2e/tests/catalog.ts`). Observable: also `groupHeadings(page)`. A word not in the list (`Quietscheentchen`) → heading „Sonstiges“.
- **Correct in the edit sheet.** `setCategory(page, 'Hafermilch', 'Getränke')` (`e2e/tests/catalog.ts`). Observable: `expectGroup(page, 'Hafermilch', 'Getränke')` (add `Apfelsaft` first so Getränke has a divider).
- **Correct in the sheet.** `openEdit(page, 'Zahnbürste')`, `pickInSheet(page, 'Kategorie', 'Haushalt')`, `saveEdit(page)`; heading becomes „Haushalt“.
- **Learn.** `tick(page, 'Zahnbürste')` then `addItem(page, 'Zahnbürsten')` → `expectGroup(page, 'Zahnbürsten', 'Haushalt')`. Or delete the first item (`deleteItem`) and add `2 Hafermilch` → „Getränke“.
- **Variants.** `addItem` for `Karrotten`, `Paradeiser`, `Semmeln`, `Mlich`, `Schokolde`, `toilet paper`; headings as in `cl-variants`; the row names stay as typed. Second view: `api.from('items').select('name, categorized_via')` returns exact / synonym / exact / fuzzy / fuzzy / synonym for those names.
- **Variant learn.** Move `Karrotten` to „Getränke“ in the sheet, then `addItem(page, 'Möhren')` → „Getränke“. A second account adding `Möhren` gets „Obst & Gemüse“.
- **API view.** `apiAs(email)` then `rpc('add_items', { p_household, p_names: ['Hafermilch', '1 Packung Kaffee'] })` returns name and quantity split (`Kaffee`, `1 Packung`).
- **Spec.** `e2e/tests/classifier.spec.ts` (three tests: learning, dictionary spot checks, spelling variants). Run `scripts/verify.sh --only e2e -- tests/classifier.spec.ts`.

## Gotchas

- The divider shows its category without a leading emoji, but the heading's accessible name keeps the full name ("👶 Drogerie"); Playwright `getByRole('heading', { level: 2 })` reads the full name, as the specs assert.
- Online adds show under the sheet's guessed category at once, so „Wird einsortiert …“ usually never shows; the server's answer can still move the row (a correction just before). Wait for the heading with `expectGroup`, which polls.
- The add sheet's guess is not sent with an add; only a category picked on the chip is. Dictated adds send none either. A probe that delays the correction's request by 3 s (`page.route` on the items PATCH) shows the re-add still lands in the corrected category (job 126).
- Typo matching is deliberately shy: never under 5 letters, same first letter; only neighbouring-letter swaps for 5-letter words, one edit for longer words, two edits from 8 letters up; and only when nearby words agree on a category. „Mehk“ or „Kaffe“ stay in „Sonstiges“ on purpose.
- Matching folds case, umlauts and one plural ending. Names with numbers fold the numbers away: a learned „Xylophon“ also catches „Xylophon-123“. Use distinct words in tests.
- Household learning beats the word list. A test that moves an item changes later adds in the same household; use a new household per test.
- Dictionary-matched compounds prefer the head word: „Ziegenmilch“ → „Kühlregal“, „Milchschokolade“ → „Süßes & Snacks“.
- Shown category names follow the app language only for seeded, unrenamed categories; the harness runs German.
- A brand that stands for a product becomes that product: „Pampers“ is the item Windeln with the brand Pampers, so it lands in „👶 Drogerie“. Own brands of dm, Lidl and Edeka also guess that store.
- Renaming an item in the edit sheet keeps its category; the classifier runs on adds only.
- Typed (online or offline, job 104), a number or count word at the end („Karotten 2“, „Karotten drei“) becomes the quantity only when the name is known to the word list or the household; a count word up front („zwei Gurken“, „two lemons“) always does, except in names such as „Drei Glocken Spaghetti“; see quick-add. Said (dictation, Siri, Alexa), a count after the item is always the quantity unless a size word comes before it („Gurken zwei“, job 89), and a count word up front is the quantity except in the same names as typed („Drei Glocken Nudeln“, „Seven Up“; job 159).
- Offline (add with no network, `cutOff` from the e2e helpers): the item shows under „Wird einsortiert …“ until the connection is back, then under its category (driven 2026-11-02: Linsen → „Vorrat & Konserven“; no spec).
