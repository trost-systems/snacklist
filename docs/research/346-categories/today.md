# Today: how item categories work (main at d3db3273, 2026-11-21)

Paths are repo-relative. "Latest definition" means the newest migration that defines the function
(later migrations override earlier ones). Probe results in section 2 come from a live classifier run on
this job's local stack (port 59122, all migrations through 20261121121147, rolled-back transaction).

## 1. Default category sets and store types

### 1.1 What a new household gets

`public.seed_household(p_household, p_stores)`, latest in
`supabase/migrations/20261030120000_onboarding_invites.sql:160-185`. `create_household` calls it
with `p_stores = coalesce(p_default_stores, false)` and then `add_store` for each picked name
(`supabase/migrations/20261111214106_household_cap_twenty.sql:64-67`). So a new household gets 11
categories and no stores unless the user picks them.

| sort_order | DE name (stored) | seed_key | EN label (ARB) | emoji |
| --- | --- | --- | --- | --- |
| 10 | Obst & Gemüse | produce | Fruit & veg | 🥕 |
| 20 | Brot & Backwaren | bakery | Bread & bakery | 🥖 |
| 30 | Kühlregal | chilled | Chilled | 🥛 |
| 40 | Fleisch/Wurst/Fisch | meat | Meat & fish | 🥩 |
| 50 | Vorrat & Konserven | pantry | Pantry | 🥫 |
| 60 | Süßes & Snacks | sweets | Sweets & snacks | 🍫 |
| 70 | Getränke | drinks | Drinks | 🧃 |
| 80 | Tiefkühl | frozen | Frozen | 🧊 |
| 90 | Haushalt | household | Household | 🧽 |
| 100 | 👶 Drogerie | drugstore | 👶 Drugstore | 👶 (from the name; 🧴 by key) |
| 1000 | Sonstiges | other | Other | 🛒 |

- Names are stored in German. The app shows the EN label only for a seeded category whose name still
  equals the German seed name (`app/lib/list/category_names.dart:10-16`, map at `:20-39`; ARB keys
  `app/l10n/app_de.arb:404-438`, `app/l10n/app_en.arb:384-418`).
- Emoji: the leading symbol of the name, else the seed key's, else 🧺
  (`app/lib/list/list_view/item_icon.dart:178-187`, map `:198-217`). Item rows never show it
  (features `categories.md:7`).
- Schema: `categories (household_id, name 1..60 chars, seed_key, sort_order)`, unique
  `(household_id, seed_key)` (`supabase/migrations/20261022150000_foundation.sql:68-79`).
  `absorbed_seed_keys text[]` added in `20261022233800_classifier_stores.sql:140`. Name unique
  ignoring case and spacing since job 90 (`20261105070000_category_name_key.sql`).
- `Sonstiges` (seed_key `other`) cannot be deleted: trigger `categories_keep_fallback`
  (`20261022150000_foundation.sql:422-434`) and `delete_category`
  (`20261105080000_delete_category_seed_keys.sql:16-18`).
- The seed key is the stable identity across renames (`20261022150000_foundation.sql:72`).

### 1.2 The one per-store-type set: Baumarkt (job 151, #295)

- Registry `public.hardware_categories()`
  (`supabase/migrations/20261106163919_hardware_categories.sql:12-21`): paint Farben & Lacke 🎨,
  plumbing Sanitär 🚿, electrical Elektro & Leuchtmittel 💡, tools Werkzeug 🔨, fasteners Schrauben &
  Befestigung 🔩, building Holz & Baustoffe 🪵, garden Garten & Pflanzen 🌱.
- `seed_hardware_categories` (`:35-52`) adds the missing ones through `create_category` (just before
  Sonstiges in the route and in every store). It adopts an own category of the same name and never
  recreates a seed key the household deleted (absorbed elsewhere).
- Trigger: the first store whose `store_name_key` is `baumarkt`, `heimwerkermarkt`, `hardware store`
  or `diy store` gets `seed_key = 'hardware'` and seeds them (`add_store`, `:102-154`, mapping at
  `:106-110`, seeding at `:147-151`). A rename keeps `hardware` (`rename_store`, `:158-182`); renaming
  another store to "Baumarkt" does not make it one (DECISIONS job 151 item 9, `docs/DECISIONS.md:9766`).
- Deleting the Baumarkt keeps the seven categories (features `categories.md:8`).
- No other type-specific set exists. There is no drugstore, pharmacy, furniture or IKEA set.

### 1.3 How stores have a "type" at all

- `stores` has no kind/type column. Identity is `stores.seed_key`
  (`20261022150000_foundation.sql:81-91`), one of exactly four values that `add_store` assigns:
  `dm`, `lidl`, `edeka` (chains) and `hardware` (a type)
  (`20261106163919_hardware_categories.sql:106-110`). A second store of the same key gets none
  (`:116-118`).
- Researched walk orders exist only for those four keys, in the `STORE_LAYOUTS` block of
  `apply_store_layout` (`20261106163919_hardware_categories.sql:58-99`). Every other store copies the
  route order with every category shown (`docs/STORE_LAYOUTS.md:9-11`, DECISIONS job 58
  `docs/DECISIONS.md:6092-6094`).
- Onboarding offers EDEKA, REWE, Lidl, Aldi Süd, Aldi Nord, Kaufland, Netto, Penny, dm, Rossmann and
  `l10n.storeHardware` (Baumarkt / "Hardware store")
  (`app/lib/list/new_stores_picker.dart:19-31`). Only EDEKA, Lidl, dm and Baumarkt get a layout;
  REWE, Aldi, Rossmann and the rest get the route order.
- Job 313 added a retailer registry (`supabase/retailers/retailers.json`, 59 entries over 8
  countries; grocery chains plus dm, Rossmann, Kruidvat) and `stores.retailer_chain/country/app`
  columns (`20261119200125_retailers.sql:6-32`). It drives the "open the store's app" key only;
  `apply_store_layout` joins on `seed_key` alone, so a registry match sets no layout and no category
  set. Entries carry no type field. No IKEA, OBI, Hornbach, Bauhaus or pharmacy is in the registry.
- Pharmacy is a name test, not a type: `is_pharmacy_store` matches
  `apotheke|pharmacy|pharmacie|farmacia|apteka|eczane|docmorris`
  (`20261115110000_trip_mode_skips_docmorris.sql:5-8`; app twin `Store.isPharmacy`,
  `app/lib/list/model.dart:113-127`). It only keeps pharmacies out of trip mode and the grocery log
  (Legal GL-2, `docs/DECISIONS.md:13103-13109`). It does not affect categories or order.

## 2. The classifier

### 2.1 Entry points

- `public.classify_item(household, name)` returns `(classify_item_detail(...)).category_id`
  (`supabase/migrations/20261030110000_classifier_variants.sql:480-483`).
- `public.classify_item_detail(household, name, out category_id, out via, out canonical_key)`,
  latest in `supabase/migrations/20261117192637_classifier_homographs.sql:181-315`.
- Insert trigger `items_before_write` (before insert or update,
  `20261022150000_foundation.sql:198-200`), latest body in
  `20261121120100_items_created_at_bounds.sql:14-80`. On insert, or when `category_id` is null, it
  calls `classify_item_detail`, sets `canonical_key`, and fills `category_id` and `categorized_via`;
  a category picked by the caller is kept and marked `picked` when it differs (`:40-48`).
- Every add path (app, MCP, REST API, Siri/voice, Alexa) inserts through this trigger (CLAUDE.md;
  `supabase/functions/_shared/list.ts:425-436`; `supabase/functions/voice/handler.ts:46-47`).

### 2.2 Decision order in `classify_item_detail`

1. Household memory by exact `item_key`, then by `canonical_key` (`category_memory`, latest
   `updated_at`, then most corrections) → `via = household`
   (`20261117192637_classifier_homographs.sql:227-242`).
2. Dictionary strong rules (`dictionary_hit` tiers 5 phrase, 4 whole key, 3 frozen marker, 2 word
   ends with a term), with longer lexicon or typo matches winning over a short compound tail →
   `exact` / `synonym` / `fuzzy` (`20261030110000_classifier_variants.sql:281-288`, `:420-436`).
   Job 282 lets the homograph reading of the typed text beat the dictionary on a shared form.
3. Fuzzy household memory (canonical key 6+ letters, Levenshtein 1 or 2, unanimous) → `fuzzy`.
4. Lexicon fuzzy match (same first letter, 5+ letters, nearby forms must agree)
   (`20261030110000_classifier_variants.sql:95-100`).
5. Dictionary weakest rule (word starts with a 4+ letter term).
6. Map the seed key to the household's category (next section).
7. A DIY seed key in a household without Baumarkt categories goes to the category serving
   `household` (Haushalt) (`20261117192637_classifier_homographs.sql:302-310`).
8. Else `Sonstiges` (seed_key `other`), `via = fallback` (`:311-314`).

### 2.3 Seed key to household category

The dictionary speaks seed keys, never category ids or names. The mapping is
`c.seed_key = v_seed or v_seed = any(c.absorbed_seed_keys)`, preferring the exact seed key
(`20261117192637_classifier_homographs.sql:295-301`). Consequences:

- Renaming a category changes nothing for the classifier (the seed key stays).
- Deleting a seeded category moves its seed key and absorbed keys onto the reassign target
  (`20261105080000_delete_category_seed_keys.sql:32-40`), so its words follow its items there.
- A category the household created has no seed key. The dictionary can never target it; it fills
  only through household corrections (`category_memory`).
- Classification is per household (memory and category set), never per store. The store is chosen
  afterwards from the category (`guess_store`, section 3.4).

### 2.4 Word lists (`supabase/classifier/`)

| File | Format | Size | Loaded by |
| --- | --- | --- | --- |
| `dictionary.tsv` | `term<TAB>seed_key` (`:1`) | 1,619 terms: 1,348 grocery + 271 DIY | generated migration, latest `20261117192842_classifier_dictionary_homographs.sql` (`truncate classifier_terms`, `:4`) |
| `synonyms.tsv` | `variant<TAB>canonical` (`:1`) | 170 rows, regional DE/AT/CH + English | `20261117192843_classifier_synonyms_homographs.sql` |
| `brands.tsv` | `brand<TAB>product<TAB>store` (`:1-9`) | 608 brands; store only `dm` (17), `lidl` (47), `edeka` (8) | `20261025212053_classifier_brands.sql` and later |

Terms per seed key in `dictionary.tsv`: household 246, drugstore 235, pantry 209, produce 159, meat
112, chilled 111, sweets 109, bakery 64, drinks 56, frozen 47; DIY tools 45, garden 41, building 41,
paint 40, fasteners 35, electrical 34, plumbing 34. The allowed seed keys are fixed by a check
constraint on `classifier_terms.category` (`20261106163919_hardware_categories.sql:24-29`) and by
`categories` in `supabase/classifier/generate.ts:6-24`.

Placement rules in the file header: baby and drugstore care are Drogerie, toilet paper, kitchen roll
and pet food are Haushalt (`dictionary.tsv:16-18`); DIY words without a Baumarkt go to Haushalt, and
what a supermarket sells (Batterien, Kerzen, Klebeband) stays Haushalt (`:27-31`).

Section markers: Haushalt `:916`, Drogerie & Baby `:1166`, the DIY sections `:1404-1577`. Medicine
words are Drogerie terms: aspirin `:1174`, hustensaft `:1248`, ibuprofen `:1249`, pflaster `:1302`,
tablette `:1377`, vitamin `:1388`. Home words: teller `:944`, bilderrahmen `:946`, besteck `:999`,
kerze `:1062` (Haushalt); lampe `:1506` (electrical). No furniture term exists (Regal, Schrank, Stuhl,
Tisch, Sofa, Kommode, Matratze, Teppich, Kissen and Vase are absent). No IKEA term exists in any of
the three files.

### 2.5 Keys, memory and learning

- `item_key(name)`: lower case, umlauts and ß folded, quantities and units stripped, words stemmed
  (`20261022233800_classifier_stores.sql:32-52`). `canonical_key` folds spelling and maps synonyms
  (Karotten, Karrotten, Möhren share one key) (`20261030110000_classifier_variants.sql:227-238`).
- `category_memory (household_id, item_key, category_id, corrections, updated_at)`
  (`20261022233800_classifier_stores.sql:143-151`) plus `canonical_key`
  (`20261030110000_classifier_variants.sql:78-82`).
- Written by `items_learn` (after update of `category_id, store_id, status`,
  `20261022233800_classifier_stores.sql:274-276`; latest body
  `20261120073857_undo_add_plain_delete.sql:13-60`): a category change upserts memory and counts
  corrections. Deleting a category moves its items with learning switched off
  (`20261105080000_delete_category_seed_keys.sql:28-30`), and the cascade drops memory rows for it.
- Job 282 homographs (#523): `surface_word`, `homograph_pick`, and `classifier_words(key, name)`
  read the typed spelling so beer is Getränke and Beere is Obst
  (`20261117192637_classifier_homographs.sql:1-6`, `:15-41`; DECISIONS `docs/DECISIONS.md:15110-15135`).
  Memory still keys on the folded form (`docs/DECISIONS.md:15132-15135`).
- On-device twin: the app bundles the terms, lexicon and brands
  (`app/lib/list/catalog/catalog_index.g.dart`, from `20261116012830_catalog_version.sql:1-4`) and
  guesses with `guessCategory` (`app/lib/list/category_guess.dart:31-52`), DIY-to-Haushalt included.
  It maps only `seedKey`, not `absorbedSeedKeys` (`:45-46`). The server's answer wins.

### 2.6 Live probe (job 346 stack, rolled back)

| Word | No Baumarkt | With Baumarkt | via |
| --- | --- | --- | --- |
| Regal, Schrank, Stuhl, Tisch, Kissen, Bettwäsche, Teppich, Matratze, Vase, Korb, Pfanne, Aufbewahrungsbox, Köttbullar, Hotdog | Sonstiges | Sonstiges | fallback |
| Handtuch, Kerze, Teelichter, Servietten | Haushalt | Haushalt | exact |
| Lampe, Glühbirne | Haushalt | Elektro & Leuchtmittel | exact |
| Schrauben, Dübel / Wandfarbe / Blumenerde | Haushalt | Schrauben & Befestigung / Farben & Lacke / Garten & Pflanzen | exact |
| Spiegel, Kleiderbügel | 👶 Drogerie (tail `gel`, `dictionary.tsv:1225`) | same | exact |
| Topf | Kühlregal (stem of `topfen`, `:365`) | same | exact |
| Gläser | Vorrat & Konserven | same | fuzzy |
| Medikament | Fleisch/Wurst/Fisch (tail `ent`) | same | exact |
| Salbe, Wundsalbe, Rezept | Sonstiges | Sonstiges | fallback |
| Ibuprofen, Kopfschmerztabletten, Nasenspray, Augentropfen, Fieberthermometer, Hustensaft, Sonnencreme | 👶 Drogerie | same | exact |

## 3. How categories drive sort order

### 3.1 The route (household order)

`categories.sort_order` is the route. It sorts the "Ohne Laden" section and every category a store
has no layout row for (features `categories.md:3`). It is edited under Liste → Anpassen →
Ohne Laden through `reorder_categories` (`20261022233800_classifier_stores.sql`;
app `app/lib/list/store_details_screen.dart:61-71`). A new category goes after the last one, just
before Sonstiges (`insert_before_fallback`, `20261022233800_classifier_stores.sql:397-410`).

### 3.2 Per-store walk order

- `store_category_order (store_id, category_id, sort_order, hidden)`
  (`20261022150000_foundation.sql:93-100`; `hidden` at `20261022233800_classifier_stores.sql:452`).
- Defaults from `apply_store_layout` (section 1.3). Edited with `set_store_layout` on the store's
  details screen (`app/lib/list/store_details_screen.dart:66-70`).
- `hidden` is stored but ignored by the list since job 16 (`docs/STORE_LAYOUTS.md:92-100`,
  `docs/DECISIONS.md:2233-2237`). There is no UI switch for it.

### 3.3 In the app (`app/lib/list/`)

- `sectionsOf` builds one section per store in store `sort_order`, then "Ohne Laden"
  (`list_view/sections.dart:27-51`).
- `_blocks` groups by category in `walkingOrder` order. Unclassified items come first, and items
  whose category is unknown come last (`list_view/sections.dart:53-78`).
- `walkingOrder` puts the store's layout rows first, then any category without a row in route order.
  With no store it uses the route (`model.dart:558-576`).
- Inside a category, items sort by `sort_key`, then `created_at`, then id (`compareWalk`,
  `model.dart:711-724`).

### 3.4 Item order and learned behaviour

- `sort_key` is the end of its (store, category) group plus 1024 on insert or on a store/category
  change (`20261121120100_items_created_at_bounds.sql:59-69`). Nothing on the list drags since job 78
  (features `stores-walk-order.md:13`). No order is learned from ticking.
- What ticking does teach is the store: `item_store_memory` (`items_learn`; features
  `stores-walk-order.md:22`).
- Default store for a new item: remembered store, then the brand's own store, then (app adds with
  flag `input-stable-rows`) the category's usual store, then `category_store`: dm for drugstore
  items, the Baumarkt for DIY items (`20261106163919_hardware_categories.sql:184-196`;
  `20261115205907_category_usual_store.sql:1-30`). Nothing routes to Rossmann or to a pharmacy.

## 4. Where the UI shows categories

| Surface | What | Code |
| --- | --- | --- |
| List | Level-2 heading per category inside each store section, name without leading emoji; "Wird einsortiert …" for null | `app/lib/list/list_view/dividers.dart:275-293` |
| Anpassen → Ohne Laden (`/edit/none`) | Route: rename, add, delete with "move items to", drag reorder | `app/lib/list/store_details_screen.dart:27-140`, `:214-312` |
| Anpassen → store (`/edit/<id>`) | Same rows in that store's walk order | same file, `walkingOrder` at `:56` |
| Edit sheet | Chip „Kategorie: …“, options in route order | `app/lib/list/edit_item_sheet.dart:271-280`, `app/lib/list/foldout_chips.dart:273-283` |
| Add sheet | Details after the add (flag `add-feedback-list`), chip before the add when the flag is off | `app/lib/list/add_sheet/compact_details.dart:89-99` |
| Onboarding | Store chips only, no category step | `app/lib/list/new_stores_picker.dart:19-31` |
| Trip mode, grocery log | No category use (pharmacy rule only) | `app/lib/trip/summary.dart:21`, `:107` |

## 5. API, MCP and voice exposure

- REST `GET /v1/categories` → `listCategories`, read scope (`supabase/functions/api/routes.ts:29-35`).
  It returns `id, name, sort_order` in route order (`supabase/functions/_shared/list.ts:118-121`).
  No `seed_key`, no emoji, no store layouts.
- Items carry `category` (name) and `categoryId` (`_shared/list.ts:202-206`;
  `docs/api/openapi.yaml:324-332`). `GET /v1/items?category=` filters by id or name
  (`openapi.yaml:44-46`). The store view orders by `coalesce(store sort_order, route sort_order)`
  (`_shared/list.ts:313-345`).
- Set a category: on add (`POST /v1/items`, `category` "learned like a correction",
  `openapi.yaml:347`; applied as an update after `add_list_item`, `_shared/list.ts:459-474`), or
  `PATCH /v1/items/{id}` `moveItem` (`routes.ts:8-14`, `openapi.yaml:157-171`).
- MCP tools (`supabase/functions/mcp/tools.ts`): `list_items` with optional `category` (`:293-304`),
  `add_items` with `category` "only when the user names one explicitly" (`:340-342`), `move_item`
  (`:375-394`), `list_categories` "in Gang-Reihenfolge" (`:396-401`).
- Nothing creates, renames, reorders or deletes categories outside the app (no API route, no MCP
  tool).
- Siri/voice answers with each added item's category name (`supabase/functions/voice/handler.ts:50-52`).
  Alexa reads the open items in route order without naming categories
  (`supabase/functions/alexa/store.ts:42-44`, `alexa/speech.ts:129-137`).

## 6. Prior decisions and spec

- SPEC #2: the 10 seed categories "in this default store-route order", plus a fallback "e.g.
  Sonstiges shown last" (`docs/SPEC.md:25-30`). Categories editable per household (`:31`).
- SPEC #3: dm, Lidl and Edeka with their own category orders, and "dm shows its relevant
  categories" (`docs/SPEC.md:32`).
- Job 16: the hidden switch is gone; `hidden` stays only as data (`docs/DECISIONS.md:2233-2237`).
- Job 58: a new store's layout is "a full copy of the household's route order"; renaming dm/Lidl/
  Edeka clears the chain (`docs/DECISIONS.md:6092-6099`).
- Job 151: "Seeding them into all households would put 18 categories into every grocery-only
  household's add-sheet picker" (`docs/DECISIONS.md:9731-9733`). DIY words fall back to Haushalt
  (`:9743-9747`). "No retailer name is recognized or shown (Legal Addendum D)" (`:9736`). Baumarkt is
  "a type, not a chain" (`:9751-9755`).
- STORE_LAYOUTS: dm hides fresh food (`docs/STORE_LAYOUTS.md:59-74`). The Baumarkt order is mostly
  inferred (`:76-90`).
- Job 246/251: a pharmacy is a name test, kept out of trip mode; "dm, Rossmann and Müller are not"
  pharmacies (`docs/DECISIONS.md:13103-13109`, `:13867-13872`).
- Job 282: homographs read the typed text, memory stays on the folded key
  (`docs/DECISIONS.md:15110-15135`).
- Job 313: seeded chains are not linked to registry chains automatically (`docs/DECISIONS.md:16204`).
- `docs/DECISIONS.md` has no mention of IKEA or furniture (grep: 0 hits).

## Facts that matter for IKEA, drugstore, hardware and pharmacy

1. Store "type" is the `stores.seed_key` with four values: `dm`, `lidl`, `edeka`, `hardware`. Only
   names in `add_store`'s CASE assign one (`20261106163919_hardware_categories.sql:106-110`). Adding a
   type means editing that CASE, `apply_store_layout`'s table, and `category_store`.
2. The Baumarkt is the only precedent for "a store brings its own categories". It uses a SQL registry,
   seeding through `create_category`, a CHECK on `classifier_terms.category`, ARB names, emoji by seed
   key, and a Haushalt fallback when the categories are absent.
3. There is no furniture or home category and no IKEA word. Regal, Schrank, Stuhl, Tisch, Kissen,
   Teppich, Matratze, Vase, Korb, Pfanne and Köttbullar land in Sonstiges. Kerze, Teelichter,
   Servietten and Handtuch land in Haushalt. Lampe lands in Haushalt, or in Elektro with a Baumarkt.
4. Known misfires for home words: Spiegel and Kleiderbügel → Drogerie (`gel`), Topf → Kühlregal
   (`topfen`), Gläser → Vorrat (fuzzy). An IKEA set would need guards like job 151's.
5. Unknown words go to Sonstiges, via `fallback`. A DIY word without the Baumarkt categories goes to
   Haushalt.
6. Drugstore: one category `👶 Drogerie` with 235 terms. Its default store is dm only
   (`category_store`). A Rossmann or Müller store gets the route order and never gets drugstore
   items by default; brands only route to dm, lidl or edeka (`brands.tsv:8-9`).
7. Pharmacy: no category and no store type. Medicines are Drogerie terms (Ibuprofen, Tabletten,
   Nasenspray). Salbe and Rezept fall to Sonstiges, and Medikament misfires to Fleisch. A store named
   "...Apotheke" only changes trip mode and the log.
8. The dictionary maps to seed keys. A household-made category ("Möbel") gets items only from
   corrections, and corrections are per household and keyed by the folded name.
9. A new category, own or seeded, goes before Sonstiges in the route and in every store's layout,
   so a type-specific set does not disturb the grocery order.
10. API and MCP can read categories (id, name, order) and set an item's category, but cannot create
    one. Clients see no seed key or type.
11. The `hidden` flag (dm hides fresh food, the Baumarkt hides food) is stored but has no effect on
    the list. Hiding grocery categories in an IKEA store would be the same no-op today.
12. The retailer registry (job 313) is grocery and drug chains for apps only. It has no type and no
    hardware, furniture or pharmacy chains, and it does not set layouts.
