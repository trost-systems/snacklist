# 470-english-catalog: English as a first-class catalog language

Peter's decision CP4 (26 Nov 2026): English is a first-class language for suggestions, matching
and categorisation, and the catalog follows the app's language. ML1: the fallback is the user's
language, then English; a German user keeps German. Addendum 2: the server classifies every
language the app supports, keeps the phone's category when it does not know a word, and builds
each language's data from the same source as the app's bundle.

## Step 1: audit (main at 82661d9d, 26 Nov 2026)

How it was measured:

- Device: `suggestRows` and `lexiconSeed` over `CatalogIndex.bundled`, the add sheet's own
  ranking, for the brief's words (a throwaway Dart test).
- Server: `public.classify_item_detail` on a fresh local stack (all 138 migrations) for 74
  everyday English items.
- Code: the latest definition of every classifier, catalog and suggest function, the app's
  catalog, add sheet, language and dictation code, the voice, Alexa, MCP and API functions.

### What an English user sees today

Add sheet, app language English, empty household (the device rows; the server's merged rows are
the same German terms):

| Typed | Rows offered | Category guess |
| --- | --- | --- |
| mil | Milch, Schokolade, Milchreis | none |
| milk | Schokolade, Milky Way | chilled |
| tomatoes | Tomate, Gehackte Tomaten, Stückige Tomaten | produce |
| peanut butter | peanut Butternut, peanut Butterkäse | chilled (wrong: pantry) |
| kitchen roll | kitchen Rollmops, kitchen Farbrolle | household |
| oat milk | Schokolade, oat | chilled |
| bana | Banane, Cillit Bang | none |
| brocoli | Broccoli, Brokkoli | produce |
| 1 kg rice | Ricola, Ricotta | pantry |
| bread, cheese, toilet paper, avocados, bell pepper | nothing but the typed line | right |
| eggplant, cilantro, crisps, nappies, egg | nothing | none (Other on the server too) |

Quantities: "2 apples", "two apples", "2x milk" and "1 kg rice" parse into amount and name.
"a dozen eggs" stays one name, and English units (lb, oz, can, bottle, jar, pack) are not units.

Server, 74 items: 59 right, 13 Other (eggplant, courgette, cilantro, crisps, biscuits, nappies,
minced meat, frozen peas, loaves, cat food, dog food, and more), 2 wrong (peanut butter → chilled,
orange juice → produce).

### Findings

Each finding: area, file, symptom in English, root cause, and where it is fixed: **here** (this
job), **NEEDS_LEAD**, or **out of scope**.

| # | Area | File | Symptom in English | Root cause | Fix |
| --- | --- | --- | --- | --- | --- |
| A1 | Catalog language | `app/lib/list/catalog/catalog_index.dart`, `catalog_index.g.dart` | Every catalog row is a German word (Milch, Tomate, Banane) | The bundle has one term list, `public.classifier_terms`, which is German; nothing selects by language | here: per-language word lists, selected by the app language |
| A2 | Catalog language | `app/lib/list/add_sheet/add_sheet_cubit.dart`, `list_screen.dart` | The language setting changes the UI but not the suggestions | The add sheet never reads the app language; only dictation does (`dictation_button.dart`) | here: the sheet reads the resolved app language on every key |
| A3 | Server delta | `public.catalog_delta`, `catalog_loader.dart` | none yet, but any English term added to `classifier_terms` would reach German apps' suggestions through the delta and the bundle | `catalog_rows().terms` is every term; the delta has no language | here: `terms` stays the German list; other languages travel in a new `words` key that released apps ignore |
| A4 | Server suggestions | `public.suggest_entries` (`20261115205907_category_usual_store.sql:356`), `mergeRows` | The server's answer, merged below the device rows, adds German terms (Milch) | `suggest_entries` reads only `classifier_terms` and takes no language | here: `p_lang` (default `de`, so released apps are unchanged); the app sends it for every language but German |
| A5 | Matching | `public.item_key`, `stem_word`; `entry.dart` `itemKey`, `_stemWord` | Singular and plural fold apart: apple → appl, apples → apple; cherries → cherrie; loaves → loave | A German stemmer (-n, -e, -s), and ae/oe/ue → a/o/u also hits English (tomatoes → tomatos) | here, as data: the generator writes every English word's plural (or singular) and listed variants as forms of one concept. The stemmer stays, so German keys and every stored `canonical_key` are unchanged |
| A6 | Matching | `public.dictionary_hit`, `classify_item_detail` | peanut butter → chilled, orange juice → produce | "Ends with" and "later word wins" are German compound rules; a 5-letter German head (`orang`) beats a 4-letter English form (`juic`) | here, as data: multi-word English items are phrases, and a phrase beats a shorter head |
| A7 | Matching | `public.dictionary_hit` tier 3, `category_guess.dart:149` | frozen peas → Other | The frozen markers are German (tk, tiefkühl, gefroren) | here, as data: frozen English items are listed as words. A language-neutral marker list is a follow-up (NEEDS_LEAD) |
| A8 | Coverage | `supabase/classifier/synonyms.tsv` | eggplant, courgette, cilantro, crisps, biscuits, nappies, minced meat, cat food → Other | English is about 110 synonyms of German terms (job 51); no UK/US variants, typos or multi-word items beyond those | here: `dictionary.en.tsv`, drafted and reviewed through `catalog/drafts` |
| A9 | Categorisation | `items_before_write` (`20261122010000_learned_order.sql:526`), `list_repository.dart:629` | A word the device files (from a newer bundle, or the household's own) lands in Other when the server does not know it | The app sends no category for an automatic add (`p_category: null`), so the server's fallback wins. A category the app does send is kept, but marked `picked` and learned as a correction | here: `put_item(p_category_guess)`. The server uses the guess only where it would answer Other, marks it `device` and learns nothing |
| A10 | Categorisation | `category_guess.dart` | none: the device's guess equals the server's | `lexiconSeed` ports `classify_item_detail` over all forms | kept language-independent on purpose (see Design, D3) |
| A11 | Quantities | `public.item_units`, `item_number_words`, `entry.dart` | "a dozen eggs", "2 cans tomatoes", "1 lb beef" keep the amount in the name | Units are German; "a", "an", "dozen" are no number words | out of scope: the parser vocabulary is shared by app, server and the parity tables. NEEDS_LEAD item |
| A12 | Folding | `foldName`, `normalize_item_name` | none for English (no umlauts) | — | no change |
| A13 | Siri | `app/lib/siri/*`, native App Intents | English phrases work; item suggestions come from the household's history only | By design (`siri_suggestions.dart`) | no change; job 467 owns native registration |
| A14 | Alexa | `alexa/skill-package/interactionModels/custom/en-*.json`, `alexa/voices.ts` | English utterances split with `parseEnglish` and keep their English names; their category is the server classifier's | The skill's slot values are free phrases, not catalog words | no skill change needed; English classification comes with the server data (A8) |
| A15 | Voice | `supabase/functions/voice/handler.ts:244` | The Siri Shortcut recipe (no `lang`) and app builds before 15 Nov parse English as German | `lang` missing means German | out of scope (voice contract); the items still classify through the shared classifier |
| A16 | MCP, API | `_shared/list.ts`, `mcp/tools.ts` | Items added in English classify with the server's data; suggestions are household history only | No catalog in these paths | no change; English classification comes with A8 |
| A17 | Category names | `app/lib/list/category_names.dart` | Seeded categories show in English | Names are localised on the device by seed key | no change |
| A18 | Mixed households | — | A German member's "Milch" and an English member's "milk" are one item for duplicates and store memory; each member sees their own language's suggestions | Concepts share the German canonical key; suggestions come from the viewer's language | here, kept and tested |
| A19 | Analytics | `app/lib/analytics/events.dart` | none | No event carries item or catalog text; `catalog_vocabulary_test.dart` is about event names, not the grocery catalog | no change |
| A20 | Tests | `suggest_parity_test.dart`, `category_guess_test.dart`, `catalog_index_test.dart`, `catalog_delta.test.sql` | — | They pin the German catalog and the device/server parity | German expectations kept; parity pins updated where the device now agrees with the server (Topf, To, Schäufele, Catrice, Plim, Grapefr, Schnekel) and three new ones (Grapef, Grapefru, Grapefrui: the server reads them as typos, the device makes no guess); `catalog_delta`'s full-answer count is the German terms. English cases in new files |
| A21 | Language switch | `add_sheet_cubit.dart` (`_cache`) | After a switch with the sheet open, a text typed before shows the rows of the old language | Rows are cached per text, not per language | here: rows and answers from another language are dropped at the next key (found by the widget test) |
| A22 | Device guess | `category_guess.dart` (`_dictionaryHit`) | With English synonyms, German partial words got English aisles on the device ("Toil" → pantry by oil) | The device's copy of `dictionary_hit` counted synonym forms as terms; the server reads `classifier_terms` only | here: the device reads `classifier_terms` by key and the lexicon's homographs, as `classify_item_detail` does |
| A23 | Homographs across languages | `classifier_lexicon.homographs` | pepperoni (meat) and Peperoni (produce) fold alike; paprika means bell pepper in German, the spice in English | One lexicon for every language | pepperoni: here, by the existing homograph pick (each spelling keeps its aisle). paprika: NEEDS_LEAD (needs the language on insert) |
| A24 | Ranking | `suggest_entries`, `suggest_entries.dart` | "toilet p", "olive o", "peanut b" offered no catalog row; "chicken br" offered Chicken brie, "peanut butter" Peanut buttermilk; "Milch" offered Mulch | Catalog rows replace the last typed word only, a German rule for one-word compounds; typo rows also for words the lexicon knows | here (review 0), for other languages only: the text's last words complete a catalog phrase they start and it replaces them; after other words a one-word term only after descriptors ("bio"); no typo rows for a known word. German unchanged (parity table) |

Where the language comes from today: `AppLanguage` (`app/lib/core/language.dart`, de and en), the
user's pick in More › Settings › Language stored in `DeviceCache` (`language`), else the first
device locale that is de or en, else en. `MaterialApp` rebuilds on a switch. The catalog never read
it, so a switch changed nothing in the sheet.

Mixed content: items are stored as typed and never translated. A German household with an
English-UI member shows that member English suggestions and the German member German ones; both
members' items classify the same way, and the same product in either language shares one key.

## Step 2: design

- **D1. One source per language.** `supabase/classifier/dictionary.tsv` stays the German
  dictionary. `dictionary.en.tsv` lists English words: the word as the English catalog shows it,
  its category (one of the same 17 seed keys), optionally the German concept it is (`milk` →
  `milch`), and extra forms (misspellings, irregular plurals). The generators write the classifier
  tables and the per-language word list from these files; `client_catalog.sh` writes the app's
  bundle from the classifier tables. One file is the source for both, and the db gate fails when
  the bundle is not what the migrations give.
- **D2. Concepts are shared.** A word with a German concept becomes a synonym of it, so its
  category and `canonical_key` are the concept's. A word without one is its own concept, a
  `classifier_terms` row with `lang = 'en'`. German terms keep `lang = 'de'`.
- **D3. Classification is language-independent.** The server cannot know which language a name is
  in (MCP, Alexa, voice and released apps send none), and a household mixes languages. So the
  lexicon holds every language's forms, and the device's guess reads the same lexicon. The
  language picks only what the catalog offers.
- **D4. Suggestions follow the app language.** `catalogLanguage`: the app language when the
  catalog has words for it, else English (ML1). German uses the German terms, so German rows are
  unchanged. The sheet reads the language on every key, so a switch applies at the next letter.
- **D5. Server changes are additive.** `catalog_rows().terms` stays German; other languages are a
  new `words` key (`["en:milk", key, category]`), which released apps' `parseCatalogDelta`
  ignores. `suggest_entries` and `put_item` gain defaulted parameters (`p_lang`,
  `p_category_guess`), so every call a released app makes binds as before.
- **D6. Adding a language is data.** A `dictionary.<lang>.tsv` file, its plural rule in the
  generator (or every form listed), and the language in the app's `AppLanguage`.

## Step 2: what was built

**Data (one source per language).** `supabase/classifier/dictionary.en.tsv`: 1,154 English words
on 997 concepts, 1,049 of them on a German concept and 105 of their own, 1,383 more forms
(plurals, US/UK spellings, misspellings), every one of the 17 aisles:

```
de: 1638 terms, 83 synonyms, 17/17 categories
en: 1154 words, 997 concepts (1049 words on a German concept, 105 own), 1383 forms, 17/17 categories
  produce 143, bakery 50, chilled 90, meat 86, pantry 231, sweets 50, drinks 41, frozen 37,
  household 130, drugstore 104, paint 28, plumbing 20, electrical 28, tools 32, fasteners 23,
  building 27, garden 34
```

`generate.ts` prints this report on every run. The 76 English synonyms of job 51 moved from
`synonyms.tsv` into the file (no synonym lost: checked against the last generated migration); the
rest came through `catalog/drafts/2026-11-26-en.tsv` (drafted by Claude, 1,052 rows), an Opus review
(`catalog/REVIEW-en.md`: 24 rows added, 35 changed, 1 rejected, open questions EN1 to EN8) and
`accept_drafts.ts`, plus three phrase rows (banana bread, chicken soup, pepperoni pizza) the same way.
`supabase/classifier/expected.en.tsv` is the exam, 285 everyday entries written apart from the words.

**Tools.** `languages.ts` (parse and check a language file, derive English singulars, make the
classifier rows, the coverage report); `generate.ts` and `generate_synonyms.ts` read every
`dictionary.<lang>.tsv`; `accept_drafts.ts` and `probe_drafts.sh` (via `draft_rows.ts`) take
language drafts; `sweep.sh` checks every `expected.<lang>.tsv`; `client_catalog.sh` bundles the
words as `catalogWords`; the item-icon sweep reads the language files.

**Server** (`20261126170000_catalog_languages.sql`, then the two generated data migrations):
`classifier_terms.lang`, `catalog_words`, `catalog_rows().words`, snapshots and `catalog_delta`
with words, `suggest_entries(p_lang)`, `put_item(p_category_guess)`, `categorized_via` `device`.

**App.** `CatalogIndex.termsIn` / `languageFor` / `classifierTerms`; `suggestEntries(language:)`;
the add sheet reads `Localizations.localeOf` on every key and drops rows made in another language;
the repository sends `p_lang` (not for German) and the device's guess with an automatic add;
`lexiconSeed` reads `classifier_terms` by key and the homographs, as the server does.

## Verification

| Check | Result |
| --- | --- |
| German bundle | `catalogTerms`, `catalogBrands`, units, number words and names, descriptors and DIY keys byte-identical to main; `catalogForms` gained 1,113 English forms, 4 German forms changed shape (dips, drink, smoothies join their English word; peperoni became a homograph of pepperoni: „Peperoni“ stays produce, "pepperoni" meat) |
| German classification | 3,050 texts (every dictionary term, synonym, wordlist, sweep and compound text) before and after: no German text changed aisle. Three German canonical keys moved (Dips → dip, Drink → getrank, Smoothies refolded): spellings of one product now share a key |
| English exam on the server | 285/285 in `sweep.sh` (main: 183/286, 79 in Other) |
| English exam on the device | no wrong guess; 5 typos without a guess (no typo path on the device; the server files them) |
| db gate (`scripts/verify.sh --only db`, fresh reset) | passed (580 s): every pgTAP file incl. `catalog_languages.test.sql` (33), sweep 638/638, wordlist 94.2 % misspellings / 0.18 % false matches, latency p95 0.63 ms vs 2.04 ms, `client_catalog.sh --check`, suggest bench, every integration test incl. the contract test and the outsiders test, db lint, backup drill |
| Contract test | `catalog_languages_contract_integration_test.ts` replays over PostgREST every parameter set the app has sent (put_item ×5 shapes, suggest_entries ×2, catalog_delta from the released version): all bind, answer as before (German catalog rows, delta rows of the old shapes, no English term among released apps' terms); then `p_lang` en and `p_category_guess`. Passed |
| Flutter | full `flutter test` green apart from the four English add-sheet goldens, regenerated (they now type "Milk": Oat milk, Soy milk); new: `catalog_language_test.dart`, `add_sheet_language_test.dart`, repository and analytics tests |
| functions, lint gates | passed |
| Live, release web build | `journeys/catalog-language.mjs` PASS: German "mil" → Milch, Schokolade, Milchreis; switched live to English → Milk, Millet, Oat milk; "tomat" → Tomatoes, Tomato paste, Tomato puree; eggplant, nappies, peanut butter stored as produce, drugstore, pantry (`docs/screenshots/470/`) |

Tests that fail on the old behaviour: the exam (main 64 %), the English rows test, the language
switch (failed until the sheet dropped rows of another language), the repository test (`p_lang`,
`p_category_guess`), the analytics test (`device`), the pgTAP file and the contract test.

## Left for the lead and later jobs (NEEDS_LEAD)

1. **N-215: done.** Peter reviewed and approved the 1,078 drafted rows (26 Nov 2026 20:07 CET,
   t1388u) with the suggested answers to EN1 to EN8 (`catalog/REVIEW-en.md`). The job merges the
   PR itself under merge-lock after a review PASS and ci-ok (Addendum 3).
2. **EN6: done.** The unshipped German draft `2026-11-16-claude.tsv` lost its 199 English rows;
   `accept_drafts_test.ts` checks that it, accepted whole, fits the English words. Once it ships,
   point walnuts, hazelnuts, pumpkin seeds, maple syrup and cereal bars at its terms walnuss,
   haselnuss, kürbiskerne, ahornsirup and müsliriegel (the draft's header says so).
3. **Deploy order:** the app sends `p_lang` (English) and `p_category_guess`. Before the
   migration a server answers `put_item` with PGRST202 and the app sends the add again without the
   guess, so adds never stall; English suggestions then come from the device only. Check that
   `supabase-deploy` passed before testers install the build.
4. **Language-aware classification** (paprika is the German Paprika in English too; English
   phrases where a longer modifier beats the head: pepperoni pizza needed its own row): needs the
   language on insert and a head rule per language. For the multilingual proposal.
5. **English quantities:** "a dozen eggs", "2 cans tomatoes", "1 lb beef" keep the amount in the
   name, and "2 cans tomatoes" files as produce. Needed: the units can/cans, bottle/bottles,
   jar/jars, pack/packs, bag/bags, box/boxes, lb/lbs, oz in `public.item_units()`, in
   `item_key`'s amount pattern and the app's `_amountWords`, and in
   `supabase/tests/number_words.tsv`; "dozen" (12) in `item_number_words()`; rows for them in
   `quantity_parse.tsv`. "a"/"an" as 1 only before a unit ("a dozen", "a can"), never alone
   ("A2 milk"). One parser change across app, server and both parity tables: its own job.
6. **"leaves" alone** stays Other (lettuce leaves, bay leaves are listed); half-typed words like
   "aubergi" get no device guess (no typo path on the device; the server files them).
7. **Item icons in English:** the emoji table (`tool/item_icons`) knows some English forms
   (milk, nappies) but not most English words (millet).
8. **The Siri Shortcut recipe** sends no language and is parsed as German (unchanged).

## Adding a language (Hungarian next)

1. Add the language to the app (`AppLanguage` in `app/lib/core/language.dart` and its ARB file).
2. Write `supabase/classifier/dictionary.<lang>.tsv` through a draft (`catalog/drafts`, header
   `lang word category concept forms ...`), review it, `accept_drafts.ts`; list every plural in
   `forms` or add a rule to `inflections` in `languages.ts`. Write `expected.<lang>.tsv` apart.
3. Regenerate the migrations (`generate.ts`, `generate_synonyms.ts`), `client_catalog.sh`, and the
   parity table (`SUGGEST_PARITY_WRITE=1`). `languageFor` picks the new words once they exist.

## Review 0 fixes (27 Nov 2026)

1. **English phrases.** `suggest_entries` (other languages only) and `suggest_entries.dart`: the
   text's last n words complete a catalog phrase they start ("toilet p" → Toilet paper, "chicken
   br" → Chicken breast, "ice cr" → Ice cream); a one-word term attaches to earlier words only
   after descriptors; no typo rows for a word the lexicon knows ("Milch" → none, not Mulch).
   `suggest_parity.json` gained an `english` table (32 texts): device and server rank them the
   same. Tests that fail on the old code: `catalog_language_test.dart` (phrases), pgTAP 35.
2. **A new language is data.** `20261126170003_item_key_letters.sql`: the classifier tables and
   `catalog_words` take lower-case Latin-1 and Latin Extended-A letters (and ș, ț); `item_key` and
   the app's `itemKey` fold them (őszibarack → oszibarack, smør → smor, Żółty → zolty, İ → i)
   instead of splitting the word. The old fold line keeps its stored quirk (its strings differ in
   length: ù is o, ý u). Items named with such letters get their new canonical key, and their
   household memory moves to the new keys. `supabase/tests/item_keys.tsv` (42 names, nine
   languages) is the table SQL (`item_keys_integration_test.ts`) and the app
   (`item_key_test.dart`) pass; pgTAP inserts Hungarian rows and classifies and suggests them with
   no code change.
3. **Nice to have, done:** `put_item` falls back without `p_category_guess` on PGRST202; the
   contract test replays `catalog_delta` from all seven bundled versions (job 274 to #748); the
   vacuous pgTAP check is gone; `list_screen.dart` reads the locale only while mounted.
