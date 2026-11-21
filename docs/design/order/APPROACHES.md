# Items in the right order, without the category noise (job 347)

Peter (t1119u, Nov 21 2026): stores and categories add noise and confuse more than they help. He and Lea want the items in the right order and do not care which category an item is in. Other users may feel differently, so one idea is a setting that shows or hides categories.

This page compares the ways to get there: how order works today, five ordering models, how people and agents change order, and what is stored. The prototype round IO (IO1 to IO5) puts each model on a phone: `docs/design/order/io/`. The measurements, the pick and the open questions are in `io/RECOMMENDATION.md`. Nothing here ships.

## Today

Paths ending in `.sql` are under `supabase/migrations/`, and `.dart` files under `app/lib/list/` unless the path says otherwise.

The list is sorted by three keys: the store, then the category in that store's walk order, then a per-item `sort_key`. A person sets every one of them by hand. Nothing learns order, and since job 78 nothing on the list drags.

**Stores.** `stores.sort_order` is the household's store order (`supabase/migrations/20261022150000_foundation.sql:81`). It is changed under List → Edit (`app/lib/list/stores_screen.dart:163`). Every store with an open item is a section with a divider, in that order, and "No store" comes last (`app/lib/list/list_view/sections.dart:27-51`). A divider shows the name and the count. A tap folds the section, and the fold is remembered on the device.

**Categories.** Each household has its own set (`categories`, `foundation.sql:68-79`). The seeds come in the route order Fruit & veg 10, Bread 20, Chilled 30, Meat 40, Pantry 50, Sweets 60, Drinks 70, Frozen 80, Household 90, Drugstore 100, Other 1000 (`20261030120000_onboarding_invites.sql:159-173`). A Baumarkt adds seven DIY categories (`20261106163919_hardware_categories.sql:35`). The insert trigger sets an item's category with `classify_item` (`foundation.sql:180`), which today goes through `classify_item_detail`. That function asks, in order, the household's corrections (`category_memory`, by `item_key` and then by `canonical_key`), then the dictionary, and falls back to Other (`20261117192637_classifier_homographs.sql:181`). The round put its mock list into a local stack and read the categories back (`docs/design/order/tools/capture-today.mjs`). The German names all landed where a German shopper expects. Typed in English, eight of the 29 names landed elsewhere: "Tea lights" in Pantry, and "Pretzels", "Minced meat", "Picture frame", "Wooden spoon", "Napkins", "Plant" and "Birthday card" in Other (`io/real/en-light-100.json`). A person changes a category with the edit sheet's category chip (`app/lib/list/edit_item_sheet.dart:271-280`). The trigger then puts the item at the end of its new group, and the household remembers the correction.

**Walk order.** `store_category_order(store_id, category_id, sort_order)` is the order a store walks the categories (`foundation.sql:93-101`). `walkingOrder` takes that store's rows first and then any category it has no row for, in route order (`app/lib/list/model.dart:561`). Chains get a researched layout (`docs/STORE_LAYOUTS.md`, `apply_store_layout`). A household's own store, IKEA included, starts from the route order. The order is changed by dragging categories on a store's details page under List → Edit (`app/lib/list/store_details_screen.dart:61-72`). For "No store" that page changes the route order.

**Inside a category.** `items.sort_key` (double) orders a group, and a group is (household, category, store) (`20261025212052_item_details.sql:12-14`). An insert, or a change of store or category, puts the item at the group's end, at max + 1024 (`20261121120100_items_created_at_bounds.sql:59-66`). `compareWalk` sorts by the key, then by creation time (`model.dart:711`). `place_item(item, anchor, 'before'|'after')` and `move_item(item, store, category)` exist on the server (`item_details.sql:581, 652`). Since job 78 the app sends neither. It keeps the `PlaceItem` and `MoveItem` ops only to read old offline queues (DECISIONS.md:6882-6886). So the order inside a category is in practice the order the items were added.

**On screen.** With `list-declutter` (on for everyone), the list shows a store divider per section. Under it come category dividers: small, faded capitals with a hairline, no emoji, as level-2 headings (`app/lib/list/list_view/dividers.dart:277`). Then come the rows. The flag changes the top bar and the total, not the sort. On a 390 × 844 iPhone at 100 % text, Today shows 9 whole item rows (8 in German) on the first screen of the round's 18-item EDEKA list. Without the category dividers the same screen shows 11 (`io/measured.json`; the replica matches the release web build's row positions to the pixel at 100 %).

**Ticking.** A tap ticks the row. It slides out, and the item shows under "Recently used" (newest first). The item keeps its `sort_key`, so an untick or a re-add puts it back in place (`app/lib/list/list_repository.dart:597`). With `trip-mode`, the first tick asks "Are you shopping right now?". A trip records its start, its pauses and the items planned. It records no tick times and no sequence (`app/lib/trip/model.dart:111-135, 202-240`), and it writes no order.

**Totals (ST3).** The summary block after the last section has a line per store in store order, with "No store" as its own group (`app/lib/list/list_view/summary_block.dart:113`, `app/lib/list/subtotals.dart:160`). A tap on a store's line scrolls to its section. Totals do not depend on categories.

**What could learn order already exists.** Every tick writes an `item_events` row with action `bought`, the actor and a timestamp (`foundation.sql:204-214`; `list_id` since `20261108144409_households_lists.sql:368`). The row has no store. Trip sessions give the time window (`trip_sessions`, `20261114181718_trip_mode.sql:13`). `item_store_memory` already learns an item's store from where it is ticked (`20261115205907_category_usual_store.sql:716-722`). So a tick sequence per trip and store can be rebuilt from data the app already stores. No new kind of data is needed.

**Agents.** API `GET /v1/items` and MCP `list_items` share `openItems` (`supabase/functions/_shared/list.ts:319-361`). It sorts by the store's walk order only when a store filter is given, else by route order. Without the filter, stores mix inside each category. Items carry no `sortKey`. The only write that touches order is MCP `move_item` and its API twin `PATCH /v1/items/{id}` (`supabase/functions/mcp/tools.ts:374-394`, `list.ts:600-615`). Both change the store or the category and put the item at its group's end. `docs/MCP.md:152` still says the drag and drop sets `sort_key`, which has been out of date since job 78.

**Why categories exist at all.** They are the classifier's output, and that drives three things. They give a new item its place before anyone has ordered it. They give a whole store its order through one short list (eleven categories instead of hundreds of items). And store memory uses them to guess a store for a grocery. Hiding categories removes their labels from the screen. It does not remove the need for a default place for an item nobody has placed yet.

## Ordering models

The list Peter wants is, per store, one sequence of items: the order he walks. Categories are one way to guess that sequence. The models differ in who writes it.

### (a) Categories stay, as hidden sort keys

The list keeps today's sort and drops the category dividers. Store dividers stay.

- **Pros:** no new data, no migration, no new rules. It is the smallest build: one switch in `shopping_list_view.dart`. Researched chain layouts keep working, and the API and MCP do not change.
- **Cons:** a wrong place can only be fixed through a category the user no longer sees. "Eggs belong with the flour here" means picking Pantry for eggs. That correction is household-wide and teaches the classifier, so Eggs move to Pantry in every store. Inside a category the order stays the order of adding. A store without a researched layout (IKEA, a market, a pharmacy) keeps the route order, so meatballs and tea lights land in a supermarket's order, which is Peter's IKEA complaint (job 346).
- **New items:** as today. The classifier picks a category, and the item goes to the end of that category's run.
- **Several stores, no store, members who disagree:** as today. One household-wide layout per store, and "No store" uses the route order.
- **Store headers:** still the only grouping.

### (b) Order learned from the household's tick sequence, per store

Each store has an item sequence that the household's own trips write. On a trip, the order of the ticks is the walk.

- **Pros:** no work and no new UI. It fits IKEA, markets and every store the researched layouts miss. It also gets the order inside an aisle right, which categories never do. It improves with each trip and needs no category.
- **Cons:**
  - The first trip in a store is ordered by the prior. Rare items learn slowly.
  - Ticks made at home or late ("forgot to tick, ticked at the checkout") teach the wrong thing. So it learns only from ticks inside a trip (`trip-mode`'s "Yes, start a trip"), and only from short gaps.
  - It is opaque when it moves something ("why is milk down here now?").
  - People who never start a trip teach nothing. Without trip mode the prior is all they get.
  - A member who walks differently pulls the order their way.
- **New items:** a key the store has seen takes its learned place. An unseen key goes to the prior: after the last item of its category in this store's sequence, else at its category's rank in the store's walk order. Categories keep working, unseen.
- **Several stores:** one sequence per store. A new store borrows the household's average order over all its stores' trips (fresh goods first, and so on) instead of the route order.
- **No store:** the household's average order over all trips.
- **Members who disagree:** one sequence per store for the household, an average of everyone's trips weighted toward recent ones. The shared list stays one list.
- **Store headers:** still needed. A trip happens in one store, and the header is where the sequence starts.

### (c) Manual drag-to-reorder per store

A person drags an item to its place. Job 78 removed all drag from the list (accidental drags, and a conflict with hold-to-edit), so this model needs a sort mode. A button turns on drag handles, the list stops ticking, and "Done" ends the mode.

- **Pros:** precise and predictable. What you set is what you get, for both members.
- **Cons:** work, item by item. The round's 9-item IKEA list in Today's order takes 3 drags in English and 4 in German, plus the two taps of the mode, and every new item needs its own drag. A mode is an extra step, and drags on a phone with large text are fiddly. Flutter web has no custom semantics actions, so screen readers on the web need another way (a "Move up" button). Nothing helps a new item: it still needs the prior.
- **New items, several stores, no store:** the prior, as in (b). A manual place is remembered per item key and store, so a re-added item returns to it.
- **Members who disagree:** last write wins.
- **Store headers:** a drop onto another store's section changes the item's store. The old drag did this (job 16).

### (d) Hybrid: learned order with manual overrides

Model (b), plus a way to put one item in its place now. A manual place wins over learning until the household's trips contradict it again and again (default: three trips in a row).

- **Pros:** zero effort in the normal case and a fix when needed. A wrong place found mid-trip can be fixed on the spot.
- **Cons:** two writers on one order means a rule for who wins, and a rule users cannot see. It is the most work to build: a learner, a fix interaction, and API and MCP writes.
- **The fix interaction** decides much of the feel. The round tries three: dragging in a sort mode (IO3), "Next to…" in the edit sheet (IO4), and "Move up / Move down" (IO5).
- **New items, several stores, no store, members:** as in (b). A manual place counts as a strong trip.

### (e) A view setting that shows or hides categories

This is a setting, not an order. It works with any of (a) to (d). With categories shown, the list looks as today. With them hidden, rows run on under the store divider. Between two categories there can be a small gap that keeps the aisle rhythm without words.

- **Pros:** cheap to build. It keeps users who like categories (they can see why an item sits where it sits, and fix it with the category chip). It answers "other users might feel differently".
- **Cons:** two looks to design, test and document. It leaves the order exactly as it was, so IKEA stays wrong unless (b) to (d) come with it. And a setting is a decision every user has to find.
- **Per user or per household:** per user. It is how a person reads the list, like the folds, and the list's content does not change. Lea can keep categories while Peter hides them. It is stored on the device like `ListPrefs`. Syncing it across a user's devices is a nice-to-have.
- **Store headers:** stay. With categories hidden, they are the only grouping.

### What store headers still do in every model

They split the list into the places you shop, carry the count, fold, and take the total's jump. Each one also starts its own order, since one sequence per store is the model in (b) to (d). With a single store on the list, the header could go. That is round IO's IO-Q8.

## How users reorder

| Model | Fix one wrong place | Fix a whole store (IKEA) | A new item |
| --- | --- | --- | --- |
| (a) hidden categories | change the category (4 taps; moves it in every store) | not possible item by item | end of its category |
| (b) learned | nothing; it learns on the next trip | one trip | learned place, else its category's place |
| (c) drag | sort mode, drag, done (3 actions) | one drag per misplaced item, plus 2 | the prior |
| (d) hybrid | learns, or one fix (drag, "Next to…" or Move up) | one trip | as (b) |
| (e) setting | as the model it sits on | as the model it sits on | as the model it sits on |

The round measures the exact taps per option in two scenarios: Eggs sit with the flour in this EDEKA, and an IKEA list in Today's order. The measured table is in `io/RECOMMENDATION.md`.

## Agents: API and MCP

An assistant needs to read the list in the order it is walked, put one item somewhere ("put the eggs next to the flour"), and occasionally set a whole store's order ("this is how I walk IKEA: …").

**Order mode, per household.** The household has one order mode: `categories`, as today, or `learned`. It is a column, `households.order_mode`, and the default is `categories`. The app sets `learned` for its household when the PostHog flag `learned-order` is on for a member (IO-Q1). The flag decides the rollout, and the column is what the server reads. The learner runs only for `learned` households, and the migration below seeds a household's sequences when it switches. Everything that follows depends on this one mode, in the app, the API and MCP alike.

**Read.**
- Each item gains `position`, in both modes and at once: a 1-based rank inside its store's section, or inside "No store", in the household's current order. It is a rank, not the stored key, so clients never see floats or gaps. `category` stays in the answer. It is still data, and it is still the prior.
- MCP `list_items` returns items grouped by store in store order, each store in its order, then "No store". In a `learned` household that is the walk order. In a `categories` household it is today's category order inside each store. Today it groups by route category and mixes stores. MCP has no paging, so nothing a client holds can break. Its text answer reads "in walk order" and lists per store.
- `GET /v1/items` keeps its v1 default order (aisle order, `docs/API.md:113`) and its cursor shape, so a client paging across the switch keeps working. A new query value, `order=walk`, returns the store-first order above, paged on (store order, position, id). Its cursors carry the order they belong to. A cursor given with the other `order` is refused with 400 `invalid_cursor`, which only a client that changes `order` mid-paging can cause. In v2 `walk` becomes the default.

**Write.**
- **Place one item.** MCP `place_item(item, before | after: itemRef)` and `POST /v1/items/{id}/place {before|after: id}`. Both reuse the server's `place_item(item, anchor, edge)` from job 15. The anchor must be in the same store section, else 422 `anchor_in_other_store` (moving stores stays `update_item` or `move_item`). In a `categories` household the item also takes the anchor's category, as the old drag did (job 16) and as IO5's Move does. The call is idempotent: placing after the same anchor twice gives the same order. Agents name items, so "next to the flour" resolves through the same `itemRef` matching as `move_item`.
- **Set a store's whole order.** MCP `set_store_order(store, items[])` and `PUT /v1/stores/{id}/order {items: [id…]}`, for `learned` households (a `categories` household gets 409 `order_mode`, and its order is A9's category layout). The listed items take that order in the store. Items not listed keep their places relative to each other, after the listed ones. It is idempotent.
- Both write manual places (the override in (d)).

**Consistency with jobs 344 and 345.** Neither job is on main yet: 344 is being built and 345 waits for it. What follows is their design (`jobs/344-api-mcp-item-ops/design.md`, `jobs/331-.../RECOMMENDATIONS.md` A9), not shipped behaviour.
- A1 `update_item` (MCP) and `PATCH /v1/items/{id}` take `name`, `quantity`, `brand`, `properties`, `category`, `store` and the target list. The category and store go through the same `moveOpen` as `move_item` (344 design, `editOpen` step 3). Order is not a field of an item but its place among others, so it gets its own verb (`place_item`) rather than a `position` field on PATCH. A position number from an agent would race with a member's ticks and moves. An anchor does not.
- A store change through `update_item`, the PATCH or `move_item` follows one rule. In a `learned` household the item takes its place in the new store: the place that store's sequence has for its key, else the prior. In a `categories` household it goes to the end of its group, as today.
- A category change alone, in a `learned` household, keeps the item where it is when its store's sequence has a place for it. The category is then only the classifier's lesson and the prior for next time. Without such a place, the item moves to the new category's prior place. In a `categories` household it goes to the end of the new group, as today.
- A9 `set_store_layout` sets a store's category walk order. In a `learned` household that is the prior for items the store has not seen. It stays the whole order for `categories` households and is useful for a new store. Its description should say "the default order for new items" for learned households.
- MCP `move_item` keeps its job (change the store or the category). Its description changes from "comes at the end of its new group" to "takes its place in the new store", with the rule above.

**What changes for existing integrations.**
- `GET /v1/items` without `order=walk` answers as today, cursors included. `position` is a new field, and no field is removed, so v1 stays compatible.
- MCP `list_items` changes its order to store-first, for every household. Within a store it uses the household's mode. The einkauf connector and other MCP clients read it without a change, because MCP has no cursor.
- `docs/MCP.md:152` ("the order the app's drag and drop sets") gets corrected either way.

## Data, migration and sync

**Stored.** One new table, `item_order_memory`, in the shape of `category_memory` and `item_store_memory`:

| Column | Meaning |
| --- | --- |
| `household_id` | RLS `is_household_member(household_id)` |
| `store_id` (null = "No store") | whose sequence |
| `item_key` | the canonical key, so plurals and synonyms share a place (job 32a) |
| `position` double | place in the store's sequence |
| `source` `learned` \| `manual` | who wrote it last |
| `trips` int | how many trips agreed, for the override rule |
| `updated_at` | |

The open list keeps one source of truth: `items.sort_key`. Its meaning widens from "inside a (store, category) group" to "inside a store". The items trigger fills it from `item_order_memory`, or from the prior when the key is new, on insert and on a store change. The memory outlives the item, so a re-add returns to its place.

**Learning.** When a trip ends (or after 20 minutes without a tick), a server function reads that trip's `bought` events, splits them by the items' stores, and drops ticks more than 10 minutes after the previous one. It then moves each key's position toward its rank in the trip: an average weighted toward recent trips (weight 0.5). A manual position moves only after three contradicting trips. This runs in Postgres on data the household already has, and nothing leaves the database. `item_events` gains `store_id` so a later store change does not rewrite history.

**Migration of existing households.** It happens when a household switches to `learned`, and nothing is lost. A household that never switches keeps today's order.
1. Each store's current order becomes its first sequence: category walk rank × 1,000,000 plus the item's rank by `sort_key` inside its group, written as `learned` with `trips = 0`.
2. Categories, `category_memory`, `store_category_order` and the classifier stay as they are. They are the prior, and they are what users see when the setting shows categories.
3. Job 346's better categories improve the prior for new items and new stores.

**Compatibility with old app builds (TestFlight and Play lag main).** Old builds sort by category, then `sort_key`. With a store-wide `sort_key` they still show their category groups, ordered inside by the learned order. Nothing is dropped or renamed, so the squawk rules hold.

**Sync.** A learned or manual change rewrites `sort_key` on the open items. That is an item update, so realtime brings it to every member's screen. A manual place from the app is the existing `PlaceItem` op (`app/lib/list/model.dart`): it is idempotent by anchor, works offline and is retried until acknowledged, as the conventions want for item writes. Learning runs on the server at a trip's end, so two phones never learn different orders. While a member is mid-trip, nothing reorders under their thumb: a running trip holds the order until it ends.

**Privacy.** Tick times are already stored (`item_events`). The learned order is derived household data in the same database under the same RLS. `docs/PRIVACY_DATA_MAP.md:41` ("Sorting the list") gains one table. No third party is involved.

## Recommendation

See `io/RECOMMENDATION.md` for the measured pick, the runner-up and IO-Q1 to IO-Q12. In short, the round recommends (d), the hybrid. The order learns from trips. One fix, "Next to…" in the edit sheet (IO4), works without drag, on the web and with a screen reader. Categories are hidden by default, and a per-user setting (e) brings them back.
