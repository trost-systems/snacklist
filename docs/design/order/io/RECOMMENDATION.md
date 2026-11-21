# Recommendation: round IO

**Pick: IO4 Learns, plus “Next to”. Runner-up: IO2 Learns your walk.**

## Measured

Rows are item rows wholly visible at the top of the list, between the top bar and the add field. The window is the release web build's: 390 × 844 or 360 × 640 of app, with no status bar or home indicator inside it. A real iPhone gives the app about 80 px less (an estimate from iOS's 47 px status bar and 34 px home indicator, not measured on a device), so every option there would show about one row fewer, the same for all. `verify.mjs` measures the rows on this page. It checks that Today's replica has the release build's row positions, add field, top bar and whole-row count in all ten captures (`io/real`). Taps count fixing Eggs, which sit with the milk but stand next to the flour in this EDEKA. "Whole IKEA list" means bringing the IKEA list from Today's order into the order the household walks it.

| Option | iPhone 100 % | iPhone 310 % | Android 100 % | Fix Eggs (taps) | Whole IKEA list (taps) |
| --- | --- | --- | --- | --- | --- |
| Today | 9 | 2 (de 3) | 6 | 4 | – |
| IO1 Quiet categories | 12 | 3 | 8 | 4 | – |
| IO2 Learns your walk | 12 | 3 | 8 | 0 | 0, one trip |
| IO3 Drag to order | 12 | 3 | 8 | 3 | 5 (de 6) |
| **IO4 Learns, plus “Next to”** | 12 | 3 | 8 | 4 | 0, one trip |
| IO5 Categories on or off | 11 | 3 | 7 | 6 | 31 (de 27) |

- Leaving out the category headings gives 3 more rows on the iPhone's first screen (9 → 12, in both languages) and 2 more on the small Android (6 → 8). At the largest text the gain is one row in English and none in German, because one item fills a third of the screen there. IO5's gaps cost one row, and with the switch on IO5 is exactly Today.
- In Today and IO1, a category pick moves Eggs only to the end of Pantry (after Passata, not after Flour). It also moves Eggs to Pantry in every store, because the correction is household-wide.
- IO2 and IO4 put IKEA in order after one trip, with no taps. IO3 needs one drag per misplaced item, plus the two taps of the sort mode. IO5's Move up and Move down need 27 to 31 taps for the same list (counted greedily, one item at a time). Today and IO1 cannot do it item by item: Household and Other are whole blocks in one order for every store.
- A new item takes its place without a tap in every option. Ketchup lands next to the pantry items: after Passata in Today's order, and after Flour in the learned order.

## Why IO4

- **Peter's ask, item for item.** The categories are gone from the screen, the order comes from where the household actually walks, and nobody has to maintain it. IKEA, markets and every store without a researched layout get their order from one trip.
- **It is right on the spot when learning is wrong.** "Next to Flour" takes 4 taps at any distance. The menu opens on the item's current neighbour, so a target further away needs a scroll in the menu first. In the 18-item EDEKA, Flour sits at the menu's lower edge. A store list of 40 or more items needs a type-to-filter field at the menu's top (IO-Q12). IO3's drag and IO5's Move carry the same distance cost, and theirs is counted in taps. It works without drag (job 78 took drag off the list, and Flutter web has no custom semantics actions), with a screen reader, and on the web. The chip says where the item goes in item words, not category words.
- **The data already exists.** Every tick is stored with its time (`item_events`), trips are marked (trip mode is on for everyone), and `place_item` exists on the server. The new parts are one table (`item_order_memory`), a learner that runs at a trip's end, and the chip.
- **Agents get the same verb.** MCP `place_item(item, after: "Mehl")` is the chip's action. `list_items` returns the walk.

## Why IO2 is the runner-up

It is IO4 without the chip: it costs less and shows nothing new. It is the right first step if IO4 is too much for one build. It fails exactly where IO4 adds the chip: the list stays wrong until the next trip, and a household that answers "No, just tick it off" never teaches it anything.

## Not picked

- **IO1** is the cheapest change (no headings), but it hides the only handle a user has on the order. A fix is still made through a category nobody sees, it moves the item in every store, and IKEA stays in supermarket order.
- **IO3** is precise and predictable, but someone has to sort every store and every new item. That is the upkeep Peter wants gone. It also brings drag back, in a mode.
- **IO5** answers "other users might feel differently" well. Its switch is IO-Q3 below and is worth keeping on top of IO4 for the people who like categories. On its own it does not order anything better than Today, and Move up and Move down are slow at a distance (6 taps for Eggs).

## Open questions (each with a default)

1. **IO-Q1 Flag.** One new PostHog flag, `learned-order`, to be added to `releases/flags.json` as `off`. It gates the hidden headings and the "Next to" chip in the app. When it is on for a member, the app switches that member's household to the order mode `learned` (`households.order_mode`, APPROACHES.md). The server reads that mode for the learner, the API and MCP. The mode never switches back by itself, and the lead can reset it. At first the flag is on for Peter and Lea only. *Default: yes.*
2. **IO-Q2 Categories hidden by default?** With the flag on, the headings are hidden for everyone, existing households too, and the switch brings them back. *Default: hidden for everyone.* The alternative is hidden only for households created after the change.
3. **IO-Q3 Per user or per household?** The switch "Show categories" is per user and stored on the device, like the folds. It sits on List → Edit, above the stores. *Default: per user, on the device, off.* The alternative is synced per account.
4. **IO-Q4 Which ticks teach?** Only ticks inside a trip ("Yes, start a trip"), split by the items' stores. A tick more than 10 minutes after the previous one is ignored. *Default: yes.* The alternative is all ticks, which also learns from ticks made at home.
5. **IO-Q5 Manual against learned.** A "Next to" place holds until three trips in a row put the item elsewhere. *Default: three trips.*
6. **IO-Q6 Members who walk differently.** One order per store per household, a recent-weighted average of everyone's trips. *Default: one shared order.* The alternative is one order per member, which splits the shared list.
7. **IO-Q7 The chip with categories shown.** With the switch on, the edit sheet shows the category chip and "Next to". With it off, only "Next to". *Default: yes.*
8. **IO-Q8 Store headers.** Keep the store divider even when the list has one store. It carries the count and the fold, and it marks where an order starts. *Default: keep.*
9. **IO-Q9 API and MCP shape.** Every item gains `position`, at once: a 1-based rank in its store's section, in the household's current order. MCP `list_items` returns items by store, each store in the household's order (the walk in a `learned` household). It has no cursor, so nothing breaks. `GET /v1/items` keeps its v1 order and cursors, and `order=walk` opts in to the store-first walk order, which becomes the default in v2. New are MCP `place_item(item, before|after)` with `POST /v1/items/{id}/place`, and MCP `set_store_order(store, items[])` with `PUT /v1/stores/{id}/order` (`learned` households only). A store change through `update_item`, the PATCH or `move_item` puts the item in its place in the new store. A category change alone keeps the item where it is. A1 `update_item` and A9 `set_store_layout`, as designed in jobs 344 and 345, stay; A9 becomes "the default order for new items". *Default: as in APPROACHES.md.*
10. **IO-Q10 Categories underneath.** Categories, the classifier and job 346's better sets stay as the prior for items and stores without trips. *Default: yes.* Nothing is deleted.
11. **IO-Q11 First trip in a new store.** A new store starts from the household's average order over its other stores instead of the route order. *Default: yes.*
12. **IO-Q12 A long store list.** The "Next to" menu gets a type-to-filter field once a store has more than 15 items. *Default: yes.*

The words the options add are "Next to {name}", "At the start", "Show categories" and "Order". They are marked on the phones. They need ARB entries and a Legal-free copy check in the build.
