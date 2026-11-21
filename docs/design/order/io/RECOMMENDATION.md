# Recommendation: round IO

**Pick: IO4 Learns, plus “Next to”. Runner-up: IO2 Learns your walk.**

## Measured

Rows are item rows wholly visible at the top of the list. They are measured in this page by `verify.mjs`, and the Today replica sits where the release web build puts its rows (`io/real`). Taps count fixing Eggs, which sit with the milk but stand next to the flour in this EDEKA. "Whole IKEA list" means bringing the IKEA list from Today's order into the order the household walks it.

| Option | iPhone 100 % | iPhone 310 % | Android 100 % | Fix Eggs (taps) | Whole IKEA list (taps) |
| --- | --- | --- | --- | --- | --- |
| Today | 9 (de 8) | 2 | 5 (de 6) | 4 | – |
| IO1 Quiet categories | 11 | 2 (de 3) | 7 | 4 | – |
| IO2 Learns your walk | 11 | 2 (de 3) | 7 | 0 | 0, one trip |
| IO3 Drag to order | 11 | 2 (de 3) | 7 | 3 | 5 (de 6) |
| **IO4 Learns, plus “Next to”** | 11 | 2 (de 3) | 7 | 4 | 0, one trip |
| IO5 Categories on or off | 10 | 2 (de 3) | 7 | 6 | 31 (de 27) |

- Leaving out the category headings gives 2 to 3 more rows on the first screen of the iPhone (9 → 11 in English, 8 → 11 in German) and 1 to 2 more on the small Android. At the largest text the gain is a row at most, because one item fills a third of the screen there. IO5 with the switch on is exactly Today.
- In Today and IO1, a category pick moves Eggs only to the end of Pantry (after Passata, not after Flour). It also moves Eggs to Pantry in every store, because the correction is household-wide.
- IO2 and IO4 put IKEA in order after one trip, with no taps. IO3 needs one drag per misplaced item, plus the two taps of the sort mode. IO5's Move up and Move down need 27 to 31 taps for the same list (counted greedily, one item at a time). Today and IO1 cannot do it item by item: Household and Other are whole blocks in one order for every store.
- A new item takes its place without a tap in every option. Ketchup lands next to the pantry items: after Passata in Today's order, and after Flour in the learned order.

## Why IO4

- **Peter's ask, item for item.** The categories are gone from the screen, the order comes from where the household actually walks, and nobody has to maintain it. IKEA, markets and every store without a researched layout get their order from one trip.
- **It is right on the spot when learning is wrong.** "Next to Flour" takes 4 taps at any distance. It works without drag (job 78 took drag off the list, and Flutter web has no custom semantics actions), with a screen reader, and on the web. The chip says where the item goes in item words, not category words.
- **The data already exists.** Every tick is stored with its time (`item_events`), trips are marked (trip mode is on for everyone), and `place_item` exists on the server. The new parts are one table (`item_order_memory`), a learner that runs at a trip's end, and the chip.
- **Agents get the same verb.** MCP `place_item(item, after: "Mehl")` is the chip's action. `list_items` returns the walk.

## Why IO2 is the runner-up

It is IO4 without the chip: it costs less and shows nothing new. It is the right first step if IO4 is too much for one build. It fails exactly where IO4 adds the chip: the list stays wrong until the next trip, and a household that answers "No, just tick it off" never teaches it anything.

## Not picked

- **IO1** is the cheapest change (no headings), but it hides the only handle a user has on the order. A fix is still made through a category nobody sees, it moves the item in every store, and IKEA stays in supermarket order.
- **IO3** is precise and predictable, but someone has to sort every store and every new item. That is the upkeep Peter wants gone. It also brings drag back, in a mode.
- **IO5** answers "other users might feel differently" well. Its switch is IO-Q3 below and is worth keeping on top of IO4 for the people who like categories. On its own it does not order anything better than Today, and Move up and Move down are slow at a distance (6 taps for Eggs).

## Open questions (each with a default)

1. **IO-Q1 Flag.** One PostHog flag, `learned-order` (in `releases/flags.json` as `off`), gating the learned order, the hidden headings and the "Next to" chip. At first it is on for Peter and Lea only. *Default: yes.*
2. **IO-Q2 Categories hidden by default?** With the flag on, the headings are hidden for everyone, existing households too, and the switch brings them back. *Default: hidden for everyone.* The alternative is hidden only for households created after the change.
3. **IO-Q3 Per user or per household?** The switch "Show categories" is per user and stored on the device, like the folds. It sits on List → Edit, above the stores. *Default: per user, on the device, off.* The alternative is synced per account.
4. **IO-Q4 Which ticks teach?** Only ticks inside a trip ("Yes, start a trip"), split by the items' stores. A tick more than 10 minutes after the previous one is ignored. *Default: yes.* The alternative is all ticks, which also learns from ticks made at home.
5. **IO-Q5 Manual against learned.** A "Next to" place holds until three trips in a row put the item elsewhere. *Default: three trips.*
6. **IO-Q6 Members who walk differently.** One order per store per household, a recent-weighted average of everyone's trips. *Default: one shared order.* The alternative is one order per member, which splits the shared list.
7. **IO-Q7 The chip with categories shown.** With the switch on, the edit sheet shows the category chip and "Next to". With it off, only "Next to". *Default: yes.*
8. **IO-Q8 Store headers.** Keep the store divider even when the list has one store. It carries the count and the fold, and it marks where an order starts. *Default: keep.*
9. **IO-Q9 API and MCP shape.** `GET /v1/items` and MCP `list_items` return items by store in walk order and add `position`, a 1-based rank in the store's section. New are MCP `place_item(item, before|after)` with `POST /v1/items/{id}/place`, and MCP `set_store_order(store, items[])` with `PUT /v1/stores/{id}/order`. `move_item`, A1 `update_item` and A9 `set_store_layout` stay; A9 becomes "the default order for new items". *Default: as in APPROACHES.md. The read order changes with the flag's full rollout, and `position` ships at once.*
10. **IO-Q10 Categories underneath.** Categories, the classifier and job 346's better sets stay as the prior for items and stores without trips. *Default: yes.* Nothing is deleted.
11. **IO-Q11 First trip in a new store.** A new store starts from the household's average order over its other stores instead of the route order. *Default: yes.*

The words the options add are "Next to {name}", "At the start", "Show categories" and "Order". They are marked on the phones. They need ARB entries and a Legal-free copy check in the build.
