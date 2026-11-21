# Job 346: better default categories for non-grocery stores

Research report, 2026-11-21, main at `d3db3273`. No production code changed. All item data is
mock. Code paths are repo-relative; links point into this directory.

Supporting files:

- [`today.md`](today.md) is the full code walkthrough with file:line for every claim.
- [`research.md`](research.md) is the competitor research with a URL for every claim.
- [`repro/`](repro/) holds the mock items (`items.tsv`), the probe SQL (`repro.sql`,
  `repro_store.sql`) and its output (`classified.tsv`, `guessed.tsv`, `store_orders.txt`).

## Summary

At IKEA, Snacklist sorts with grocery categories. 15 of 32 typical IKEA items land in
„Sonstiges“. Eight more land in grocery-shaped or wrong buckets, for example Bratpfanne in
„Fleisch/Wurst/Fisch“ and Spiegel in „👶 Drogerie“. The IKEA store has no layout of its own,
so its order is the supermarket's route. And no IKEA item defaults to the IKEA store: lamps and
plants go to the Baumarkt, mirrors and coat hangers to dm.

No list app I found ships categories for IKEA or furniture stores. Bring!, Listonic and Apple
Reminders keep one grocery set that the user can reorder per list. AnyList lets each store
bring its own category set, but only as a paid power feature. Small apps learn the walk order
from what you tick, with no categories at all.

**Recommendation: CAT1, store kinds with their own category sets.** It generalizes what job
151 built for the Baumarkt. A store gets a kind (supermarket, drugstore, hardware, home
furnishing, pharmacy, other). The household then gets that kind's categories, and the store
gets its walk order. The add-sheet picker and the dividers show only the categories of the
item's store kind. **Runner-up: CAT4, plain stores.** A store of an unknown or non-grocery kind
shows no category dividers at all. It is cheap, and it removes the confusion at IKEA today. It
does not give an order. Both pair with job 347: whichever list view 347 picks, CAT1 gives it
correct sort keys per store.

Seven classifier misfires (B1 to B7 below) are bugs whatever approach is chosen. They should be
fixed in a small follow-up job of their own.

## 1. Today

The full walkthrough with every reference is [`today.md`](today.md). These are the facts
that decide the IKEA case.

### 1.1 Category sets

- A new household gets 11 categories, stored in German and keyed by `seed_key`
  (`supabase/migrations/20261030120000_onboarding_invites.sql:160-185`): Obst & Gemüse, Brot &
  Backwaren, Kühlregal, Fleisch/Wurst/Fisch, Vorrat & Konserven, Süßes & Snacks, Getränke,
  Tiefkühl, Haushalt, 👶 Drogerie, Sonstiges. The app shows English labels for unrenamed seeds
  (`app/lib/list/category_names.dart:10-39`).
- The only store-type set is the Baumarkt's (job 151). When the household first adds a store
  named Baumarkt, Heimwerkermarkt, "Hardware store" or "DIY store", `add_store` gives it
  `seed_key = 'hardware'` and seeds 7 categories (Farben & Lacke, Sanitär, Elektro &
  Leuchtmittel, Werkzeug, Schrauben & Befestigung, Holz & Baustoffe, Garten & Pflanzen)
  (`supabase/migrations/20261106163919_hardware_categories.sql:12-21`, `:102-154`). The reason
  was not to put 18 categories into every grocery household's picker (`docs/DECISIONS.md:9731`).
  The decision also says "No retailer name is recognized" (`docs/DECISIONS.md:9736`).
- Stores have no kind column. `stores.seed_key` takes one of four values: `dm`, `lidl`, `edeka`
  and `hardware` (`20261106163919_hardware_categories.sql:106-110`). The job 313 retailer
  registry (59 grocery and drug chains, `supabase/retailers/retailers.json`) only opens store
  apps. It sets no layout and has no IKEA, DIY chain or pharmacy.
- A pharmacy is a name test (`is_pharmacy_store`,
  `supabase/migrations/20261115110000_trip_mode_skips_docmorris.sql:5-8`). It keeps pharmacies
  out of trip mode and the grocery log and has no effect on categories.

### 1.2 How an item gets its category

- Every add path (app, REST API, MCP, Siri, Alexa) inserts through `items_before_write`, which
  calls `classify_item_detail(household, name)`
  (`supabase/migrations/20261121120100_items_created_at_bounds.sql:14-80`; latest classifier
  `supabase/migrations/20261117192637_classifier_homographs.sql:181-315`).
- The steps run in this order:
  1. household memory (`category_memory`, exact then canonical key)
  2. dictionary phrase, whole word, then word-ends-with-term
  3. fuzzy memory
  4. fuzzy lexicon
  5. word-starts-with-term
  6. map the seed key to the household's category, including `absorbed_seed_keys`
  7. a DIY key without Baumarkt categories goes to Haushalt
  8. anything else goes to Sonstiges (`via = fallback`)
- Classification is per household, never per store. The dictionary speaks seed keys, so a
  category the household creates ("Möbel") only fills through corrections.
- `supabase/classifier/dictionary.tsv` has 1,619 terms: 1,348 grocery and 271 DIY. Drugstore
  has 235 and includes medicines. There is no furniture or home-furnishing term, and none of the
  three word files has an IKEA word.

### 1.3 How categories drive order

- `categories.sort_order` is the household's route. Each store has
  `store_category_order (store_id, category_id, sort_order, hidden)`. `apply_store_layout`
  writes researched orders for `dm`, `lidl`, `edeka` and `hardware`. Every other store, IKEA
  included, gets a copy of the route (`20261106163919_hardware_categories.sql:58-99`,
  `docs/STORE_LAYOUTS.md:9-11`).
- The `hidden` flag (dm hides fresh food, the Baumarkt hides food) is stored but ignored by the
  list since job 16 (`docs/STORE_LAYOUTS.md:92-100`).
- The app groups each store section by category in `walkingOrder`
  (`app/lib/list/model.dart:558-576`, `app/lib/list/list_view/sections.dart:53-78`). Inside a
  category it sorts by `sort_key`, which only appends. No order is learned from ticking. Ticking
  teaches only the item's store (`item_store_memory`).
- A new item's default store comes from, in order:
  1. the remembered store
  2. the brand's store
  3. the category's usual store
  4. `category_store`, which is dm for Drogerie and the Baumarkt for DIY
     (`supabase/migrations/20261115205907_category_usual_store.sql:1-30`)

  The app does the same in `app/lib/list/catalog/suggest_entries.dart:833-851`.

### 1.4 Where categories show

- List dividers (`app/lib/list/list_view/dividers.dart:275-293`).
- „Anpassen“ for the route and per store (`app/lib/list/store_details_screen.dart`).
- The edit sheet's category chip (`app/lib/list/edit_item_sheet.dart:271-280`).
- The add-sheet details (`app/lib/list/add_sheet/compact_details.dart:89-99`).
- Onboarding offers store chips only (`app/lib/list/new_stores_picker.dart:19-31`).

### 1.5 API and MCP

- `GET /v1/categories` returns `id, name, sort_order` (`supabase/functions/api/routes.ts:29-35`,
  `supabase/functions/_shared/list.ts:118-121`). Items carry `category` and `categoryId`
  (`docs/api/openapi.yaml:324-332`). `?category=` filters by id or name. `POST /v1/items` and
  `PATCH /v1/items/{id}` can set a category.
- The MCP tools are `list_items` (category filter), `add_items` (category only when the user
  names one), `move_item` and `list_categories` (`supabase/functions/mcp/tools.ts:293-401`).
- Nothing outside the app creates, renames or reorders categories. Siri says the category of
  each added item (`supabase/functions/voice/handler.ts:50-52`). Alexa reads in route order
  without naming categories.

## 2. The IKEA case, reproduced

Setup: a new household with the stores IKEA, dm, Baumarkt and Apotheke, created through
`create_household` on a local stack with all migrations up to `20261121121147`. 82 mock items
went through `classify_item_detail` and `guess_store` inside a rolled-back transaction
([`repro/repro.sql`](repro/repro.sql)).

### 2.1 IKEA list as it renders today

Assume the user picks the IKEA store for every item. The IKEA store's walk order is the
household's route, so the section reads top to bottom:

| Divider | Items |
| --- | --- |
| Fleisch/Wurst/Fisch | Bratpfanne |
| Vorrat & Konserven | Preiselbeermarmelade, tea lights |
| Haushalt | Teelichter, Duftkerzen, Bilderrahmen, Pfannenwender, Schneidebrett, Handtücher, Gefrierbeutel, Servietten |
| Drogerie | Kleiderbügel, Spiegel |
| Elektro & Leuchtmittel | LED-Lampe, Glühbirne |
| Garten & Pflanzen | Zimmerpflanze, Übertopf |
| Sonstiges | Köttbullar, Hotdog, Aufbewahrungsbox, Kallax Einsätze, BILLY Regal, Monstera, Trinkgläser, Kissenbezug, Bettwäsche, Teppich, Vorhang, Wäschekorb, meatballs, picture frame, storage box |

What is wrong with it:

1. **Half the trip is „Sonstiges“** (15 of 32). Furniture, textiles, storage and the Swedish food
   have no category, so the biggest block has no order at all.
2. **The names are a supermarket's.** "Fleisch/Wurst/Fisch" and "Drogerie" mean nothing at IKEA,
   and the Market Hall's own areas (kitchen, textiles, lighting, decoration, storage, plants)
   never appear.
3. **The order is a supermarket's.** IKEA's route is showroom, then Market Hall, then the
   self-serve warehouse by aisle and bin, then the checkout and Schwedenshop
   ([`research.md`](research.md) section 10). Today the frames come before the lamps for no
   reason, the meatballs sit in the same block as the shelf, and the warehouse items (BILLY,
   KALLAX) are mixed in with textiles.
4. **The items go to the wrong store.** Without a picked store, 0 of 32 IKEA items default to
   IKEA ([`repro/guessed.tsv`](repro/guessed.tsv)). Zimmerpflanze, Übertopf, LED-Lampe and Glühbirne go to
   the Baumarkt, and Kleiderbügel and Spiegel go to dm. The rest go to „Ohne Laden“.
5. **The view depends on the Baumarkt.** In a household without a Baumarkt, the lamps and
   plants land in „Haushalt“ ([`repro/classified_nohw.tsv`](repro/classified_nohw.tsv)).

### 2.2 The other stores

| Store | Items | Own category right | Defaults to that store | Problems |
| --- | --- | --- | --- | --- |
| dm | 21 | 16 Drogerie, 2 Haushalt, 3 food | 16 of 21 | Waschmittel and Spülmaschinentabs go to „Ohne Laden“ (Haushalt has no store). Hafermilch is Kühlregal, a category dm "hides", but the list ignores `hidden`. Fotoabzüge is Sonstiges. Fine otherwise. |
| Baumarkt | 16 | 16 of 16 | 16 of 16 | Works. This is the job 151 machinery doing its job. Without a Baumarkt all 16 go to Haushalt. |
| Apotheke | 13 | 0: 9 Drogerie, 1 Haushalt, 1 Werkzeug, 2 Sonstiges | 0 of 13 | Medicines go to dm by default (Ibuprofen at dm is wrong in Germany: pharmacy-only). Zeckenzange goes to the Baumarkt. Kühlpack is matched fuzzily to "kühlpad" (Drogerie). |

The drugstore case works because Drogerie is a grocery-adjacent category with a dm layout. The
hardware case works because job 151 built a kind with its own set. IKEA and pharmacy fail
because they are neither.

### 2.3 Classifier misfires (bugs whatever approach is chosen)

| # | Word | Gets | Why | Source |
| --- | --- | --- | --- | --- |
| B1 | Spiegel, Kleiderbügel | 👶 Drogerie | ends with the term `gel` | `supabase/classifier/dictionary.tsv:1225` |
| B2 | Bratpfanne | Fleisch/Wurst/Fisch | starts with `braten` stem | `dictionary.tsv:380` |
| B3 | Topf | Kühlregal | stem of `topfen` (quark) | `dictionary.tsv:365` |
| B4 | Medikament | Fleisch/Wurst/Fisch | tail `ent` (job 346 code probe, [`today.md`](today.md) 2.6) | |
| B5 | tea lights | Vorrat & Konserven | synonym `tea` → `tee` | `supabase/classifier/synonyms.tsv:163` |
| B6 | Kühlpack | 👶 Drogerie | fuzzy to `kühlpad` | `dictionary.tsv:1259` |
| B7 | Zeckenzange | Werkzeug, routed to Baumarkt | tail `zange` | `dictionary.tsv:1572` |

Also, `category_store` sends every Drogerie item to dm, medicines included. That is a routing
rule question, CAT-Q6 below.

## 3. What other apps do

Full sources are in [`research.md`](research.md).

| App | Model | Non-grocery | Unknown item |
| --- | --- | --- | --- |
| Bring! | 13 fixed catalog sections; order and visibility per list ([help](https://getbring.com/help-center-main-categories/items-lists), [catalog](https://web.getbring.com/locale/catalog.de-DE.json)) | "Baumarkt & Garten" with 15 items; no furniture, lamps, cushions or frames | auto category, else "own item" |
| AnyList | Per-list categories; per-store **category sets**, paid ([help](https://help.anylist.com/articles/category-sets/)) | user builds them | list's default category ("Other") |
| OurGroceries | One global user-editable set ([guide](https://ourgroceries.com/user-guide)) | only what the user adds | guess, ask, or "Uncategorized" |
| Listonic | Auto categories + custom; one list per store ([page](https://listonic.com/custom-grocery-list-categories)) | custom categories | unverified |
| Apple Reminders | Fixed grocery sections, corrections remembered ([Apple](https://support.apple.com/en-ae/105086), [MacRumors](https://www.macrumors.com/2023/06/07/ios-17-reminders-grocery-sorting/)) | Household Items, Personal Care & Health only | stays uncategorized |
| Todoist | User sections ([template](https://www.todoist.com/templates/grocery-list)) | manual | no grouping |
| Grocery - Smart Shopping List and others | Walk order learned from check-offs per store ([App Store](https://apps.apple.com/au/app/id1195676848?l=en-au)) | any store | placed by learned position |
| IKEA, OBI, Hornbach, Bauhaus apps | Retailer's own aisle, shelf or bin per product (e.g. [heyOBI](https://apps.apple.com/DE/app/id1331431911), [Bauhaus](https://apps.apple.com/DE/app/id1615566534)) | native | n/a; no public API found |

Takeaways:

1. **No list app has an IKEA or furniture set.** Snacklist's Baumarkt set already goes further
   than Bring!.
2. **"One list per store, reorder the sections" fixes order but not names.** Bring!, Listonic and
   Apple do this. An IKEA list there still says "Pflege & Gesundheit", which is exactly Peter's
   complaint.
3. **AnyList's category sets are the only general per-store vocabulary.** They are paid and need
   a lot of setup, so most households never use them.
4. **Every auto-sorting app has an honest fallback** ("Uncategorized", "Other", ask). A clean
   "no section" beats a wrong grocery section.
5. **Learned walk order needs no vocabulary.** It works for any store, but only from the second
   visit to that store.
6. **IKEA's Market Hall areas are documented only in English store guides** (India, Singapore,
   Korea), and IKEA says the order varies by store. The German area names are unverified, so a
   Snacklist IKEA set should use its own neutral names.

## 4. Approaches

Effort is measured against job 151 (the Baumarkt set: one migration with registry, seeding,
layout and classifier rule, about 270 dictionary terms, ARB names, emoji, tests, several review
rounds). S is under half of that, M is about that, L is twice that or more.

### CAT1: Store kinds with their own category sets (generalize the Baumarkt)

A store gets a kind. The kinds are `supermarket` (default), `drugstore`, `hardware`, `home`
(Einrichtungshaus, IKEA-like), `pharmacy` and `other`. Each kind brings a category set and a
walk order. The household gets a kind's categories the first time it has a store of that kind,
as today with the Baumarkt. The list, the add-sheet picker and the edit chip show only the
categories of the item's store kind plus Sonstiges, which reuses `store_category_order.hidden`
for what it was meant to do.

Example `home` set, in the walk order of a typical IKEA visit (names are ours, not IKEA's):

| Order | Category | Mock items |
| --- | --- | --- |
| 1 | Möbel | BILLY Regal, Kallax Einsätze |
| 2 | Küche & Essen | Pfannenwender, Schneidebrett, Trinkgläser, Bratpfanne |
| 3 | Textilien | Kissenbezug, Bettwäsche, Handtücher, Teppich, Vorhang |
| 4 | Lampen | LED-Lampe, Glühbirne |
| 5 | Deko & Bilder | Teelichter, Duftkerzen, Bilderrahmen, Spiegel |
| 6 | Aufbewahrung | Aufbewahrungsbox, Kleiderbügel, Wäschekorb |
| 7 | Pflanzen | Zimmerpflanze, Monstera, Übertopf |
| 8 | Lebensmittel (grocery categories, collapsed into one place at the exit) | Köttbullar, Hotdog, Preiselbeermarmelade, Servietten, Gefrierbeutel |

The `pharmacy` set could be just Rezept & Medikamente, Pflege and Sonstiges, or no categories
at all (CAT-Q5). `drugstore` reuses the dm layout for Rossmann and Müller.

How a store gets its kind:
- generic words in the name: Baumarkt, Möbelhaus, Einrichtungshaus, Apotheke, Drogerie, and
  their English forms
- the existing dm, Lidl and Edeka seeds
- otherwise a one-tap kind question when the user adds a store, defaulting to Supermarkt

Recognizing chain names like IKEA, OBI or Rossmann is CAT-Q2. Job 151 deliberately recognized
none.

How words that fit two kinds are handled: Kerzen are Haushalt at REWE and Deko at IKEA. The
dictionary gets an optional per-kind seed key column (`kerze → household`,
`kerze@home → home_decor`). The classifier picks the reading for the item's store kind and falls
back to the grocery reading. So the classifier now takes the store into account. To avoid a
circle (today the store is picked from the category), an item first gets its store, then its
category. The order to pick the store:

1. the store the user picked
2. the remembered store
3. the brand's store
4. a kind-specific term (Regal → the household's `home` store)

- **Effort:** L.
  - A `stores.kind` column and an `add_store` rule.
  - A kind registry replacing `hardware_categories()`, plus layouts per kind.
  - About 250 home terms and about 30 pharmacy terms, plus guards against B1 to B7-style tail
    matches.
  - A per-kind dictionary reading.
  - The order change in `items_before_write` (store before category), mirrored in the app's
    `guessCategory`/`guessStore`.
  - Filtering the picker and dividers by kind.
  - ARB names and emoji, the store setup UI for the kind question, and the feature map.
- **Migration:**
  - Backfill `kind` from `seed_key` (`hardware` → hardware, `dm` → drugstore, `lidl`/`edeka` →
    supermarket) and from the name rule. Every other existing store becomes `supermarket`
    unless its name matches.
  - Households with an IKEA store get the `home` set on the next `add_store` or in a one-time
    backfill (CAT-Q3).
  - Existing items keep their category. Only open items in a `home`-kind store are
    re-classified, and never an item whose category the household picked by hand.
- **Classifier:** a new dimension (kind), a new step order (store first), about 280 new terms,
  and `category_memory` scoped by kind so an IKEA correction does not leak into REWE. That
  means adding a column to the memory key.
- **API/MCP:** only additive changes.
  - `GET /v1/categories` gains `kind` per category, or a `?store=` filter returning that
    store's categories.
  - Stores gain `kind`.
  - `add_items` with a store gets kind-aware categories for free, because it goes through the
    trigger.
  - Old clients see more categories in `list_categories`. Nothing is removed or renamed, so
    names used as filters keep working.

### CAT2: Fewer, broader categories

Shrink the default set, for example to 6 groups: Frisch (produce, bakery, chilled, meat), Vorrat
& Süßes, Getränke, Tiefkühl, Haushalt & Drogerie, Sonstiges. The 7 DIY categories become 2:
Werkstatt and Garten. Fewer dividers means less noise, which is what Peter and Lea report.

- **Effort:** M. Mostly a data migration through the existing `delete_category` reassign path.
  `absorbed_seed_keys` already lets one category serve several seed keys, so the dictionary
  stays unchanged.
- **Migration:**
  - This is the risky part. Merging deletes categories that households may have renamed,
    reordered or taught. A rule: only merge unrenamed seeds, never touch own categories, and
    keep the household's route position of the first merged member.
  - Store layouts collapse with them.
  - TestFlight and Play builds that cache category ids keep working, because items move to
    surviving ids.
- **Classifier:** no change. Seed keys survive as absorbed keys.
- **API/MCP:**
  - Category ids and names disappear. A client filtering `?category=Kühlregal` or caching an id
    gets nothing back.
  - The squawk compat rules do not catch this (it is data, not schema).
  - `docs/API.md` needs a changelog entry, and the MCP tool descriptions don't change.
- **Does it fix IKEA?** No. IKEA items still land in Haushalt or Sonstiges, with fewer wrong
  names. It is complementary to CAT1, not an alternative.

### CAT3: Order learned from the household's ticking, categories only as a cold start

Each store keeps a learned position per item key (or per canonical key) from the order the
household ticks items there. The list sorts a store section by learned position. A new item
borrows its category's position until it has been ticked once. Categories stop being the
primary sort key, and dividers become optional.

- **Effort:** L.
  - A new table, e.g. `item_store_position (household_id, store_id, item_key, position, ticks)`,
    with RLS and a pgTAP cross-household case.
  - A learning rule in `items_learn` on tick: a robust rank such as a running median of the
    tick index, ignoring trips that tick everything at once at home.
  - Sorting in `walkingOrder`/`compareWalk` and the API's store view.
  - Trip mode is a natural signal source.
- **Migration:** none for items. Learning starts empty, and `item_store_memory` already holds
  which store an item was bought at but not when within the trip.
- **Classifier:** unchanged. Its job shrinks to cold start and grouping.
- **API/MCP:**
  - `list_items` in walk order can return learned order with no shape change.
  - A `position` field is additive.
  - Setting order (`move_item_before`) is job 347's API question.
- **Overlap:** this is job 347's ordering model (b). This job does not size it further. CAT1 is
  what 347's cold start would read.

### CAT4: Plain stores: no category dividers outside grocery-shaped stores

A store whose kind is not grocery-shaped (`home`, `pharmacy`, `other`, or simply any store
without a researched layout, CAT-Q4) shows its items as one flat block in insertion order (or
job 347's order), with no dividers. `category_store` never routes into it. The classifier still
writes a category, because every caller and the API expect one, but the store section ignores
it. Sonstiges stops being the biggest heading at IKEA because there is no heading.

- **Effort:** S.
  - A per-store `plain` flag or kind.
  - `sections.dart` skips grouping for that store.
  - `apply_store_layout` stops copying the route into plain stores.
  - A toggle in the store's „Anpassen“ page.
  - No dictionary work.
- **Migration:**
  - Existing stores without a seed layout (REWE, Aldi, Kaufland, IKEA) could be plain by
    default. That would change REWE's view for everyone, so the default is probably "plain
    only for non-grocery kinds" (CAT-Q4).
  - Items are untouched.
- **Classifier:** no change. B1 to B7 are still worth fixing for grocery stores.
- **API/MCP:**
  - No change in shape.
  - The store view ordering in `_shared/list.ts:313-345` skips the category order for plain
    stores.
  - `list_categories` stays.
- **Does it fix IKEA?** It removes the wrong labels and the Sonstiges pile. It gives no walk
  order until job 347 or CAT3 provides one.

### CAT5: Per-store category sets (the AnyList model)

Each store has its own categories, and an item has a category per store. This is the most
general model. A household could build „Markthalle / SB-Lager“ for IKEA.

- **Effort:** L+.
  - `categories.store_id`, and `items.category_id` becomes per store or derived.
  - The dictionary has no seed key to map to for user-made sets.
  - Every surface that shows a category needs a store context.
- **Migration:** every store copies the household set, so the data size multiplies by the
  number of stores. Renames diverge.
- **Classifier:** only memory can fill user-made sets. The dictionary covers the seeded set.
- **API/MCP:** `categoryId` on an item becomes ambiguous. That is a breaking change for
  `GET /v1/items`, `?category=`, `move_item` and Siri's read-back.
- **Assessment:** AnyList sells it as a paid power feature. For a two-person household that
  finds categories noisy, it adds setup, not clarity. It is not recommended, and it is listed
  so the option is on record.

### Comparison

| | Fixes IKEA names | Fixes IKEA order | Less noise | Effort | Item migration | API change |
| --- | --- | --- | --- | --- | --- | --- |
| CAT1 store kinds | yes | yes, from the first visit | yes, picker filtered by kind | L | re-classify open items in new-kind stores | additive |
| CAT2 fewer categories | no | no | yes | M | merge categories | removes ids and names |
| CAT3 learned order | n/a | yes, from the second visit | yes, if dividers hide | L | none | additive |
| CAT4 plain stores | yes, by dropping names | no | yes | S | none | none |
| CAT5 per-store sets | if the user builds them | if the user builds them | no | L+ | multiply sets | breaking |

## 5. Recommendation

**CAT1, store kinds with their own category sets, staged.**

Why: it is the only approach that makes the first IKEA trip right without the user teaching
anything. Peter's complaint was the first trip ("I used Snacklist for IKEA today"). It reuses
machinery the team has already built and debugged once (job 151: registry, seeding via
`create_category`, `absorbed_seed_keys`, the Haushalt fallback, per-store layouts). Its API
change is additive. It also gives job 347 correct sort keys per store kind, whether 347 shows
categories or hides them.

Suggested stages, each a PR that ends in a verifiable state:

1. **B1 to B7 classifier fixes** (S, independent, can start now). Guards for the `gel`, `ent`
   and `braten` tails, Topf ≠ topfen, `tea lights` before `tea`, Kühlpack, and Zeckenzange. The
   sweep tooling for this already exists (`supabase/classifier/sweep.sh`, `probe_drafts.sh`).
2. **Store kind** (M): `stores.kind`, backfill, `add_store` rule, the kind question on add, and
   `category_store` per kind (pharmacy items to the pharmacy, not dm).
3. **`home` and `pharmacy` sets** (M): registry, layouts, about 280 terms, picker and dividers
   filtered by kind.
4. **Per-kind dictionary readings and kind-scoped memory** (M): the store-first classifier step.

**Runner-up: CAT4, plain stores.** Pick it if job 347 lands on "categories hidden by default".
In that world, a richer vocabulary for IKEA serves a sort order the user never sees labelled,
and a plain store plus learned order (CAT3) is cheaper and just as good from the second visit.
CAT4 is also the right stopgap if stage 2 of CAT1 is more than two weeks away. It removes the
nonsense at IKEA in one small PR.

CAT2 is worth doing only after 347 decides whether dividers stay. If they stay, fewer of them is
good. If they go, the count no longer matters.

## 6. Open questions (each with the default I would apply)

- **CAT-Q1.** CAT1 or CAT4 first? Default: the B1 to B7 fixes now, then CAT1. Switch to CAT4 if
  job 347 recommends hiding categories by default.
- **CAT-Q2.** May `add_store` recognize chain names (IKEA, OBI, Bauhaus, Hornbach, Rossmann,
  Müller) to set the kind? Job 151 deliberately did not (`docs/DECISIONS.md:9736`), while dm,
  Lidl and Edeka are recognized. Default: recognize generic words only, and ask for the kind in
  one tap. Chain recognition needs a legal yes on Addendum D, since names are only matched and
  never shown.
- **CAT-Q3.** Do existing households with an IKEA-like store get the `home` set automatically?
  Default: no backfill. The set comes when the user sets the store's kind or adds a new store of
  that kind, as job 151 did for the Baumarkt.
- **CAT-Q4.** What does a store without a known kind look like (REWE, Aldi, Kaufland today)?
  Default: `supermarket` with the route order, as today. Only `other` is plain (CAT4 behaviour).
- **CAT-Q5.** Does a pharmacy get categories? Default: no. A `pharmacy` store is plain (a short
  list at a counter), medicines default to it instead of dm, and Drogerie stays at dm.
- **CAT-Q6.** Where do medicines go when the household has no pharmacy? Default: Drogerie at dm
  as today, since dm sells the OTC basics (vitamins, plasters). Ibuprofen and Paracetamol
  default to „Ohne Laden“ unless an Apotheke exists.
- **CAT-Q7.** Is IKEA's food (Köttbullar, Schwedenshop) part of the `home` set? Default: no
  separate category. Food items keep their grocery category, and the `home` layout puts all
  grocery categories last, at the exit where the Schwedenshop is.
- **CAT-Q8.** Should the add-sheet picker hide other kinds' categories? Default: yes. It shows
  the item's store kind plus Sonstiges, with "Alle Kategorien" behind one tap. This is the noise
  fix that makes 25+ categories bearable.
- **CAT-Q9.** Do category corrections stay household-wide or become per kind? Default: per kind
  for words with a per-kind reading (Kerzen), household-wide for everything else, so today's
  learning keeps working.
- **CAT-Q10.** Does the API expose `kind`? Default: yes, additive, on stores and categories, with
  no new write routes. Creating categories from the API stays out of scope.
- **CAT-Q11.** Should the B1 to B7 fixes wait for this decision? Default: no. They are bugs in
  today's grocery classifier, so queue them as their own small job.

## 7. Method and limits

- The classifier results are real: the local stack (port block 591xx) ran all migrations on
  main at `d3db3273`, and `create_household`, `classify_item_detail` and `guess_store` were
  called as an authenticated mock user. Every transaction was rolled back. No production data
  was read.
- The "list as it renders" table is derived from the store's `store_category_order` and the
  app's grouping rule (`app/lib/list/list_view/sections.dart:53-78`). It is not a screenshot of
  the running app.
- The competitor facts come from public help pages and store listings. ikea.com, bauhaus.info
  and outofmilk refused page fetches, so claims about them rest on search excerpts and are
  marked "snippet" in `research.md`.
- The IKEA Market Hall area order is from English store guides. German area names and plant
  placement are unverified. The proposed `home` set uses our own names for that reason.
