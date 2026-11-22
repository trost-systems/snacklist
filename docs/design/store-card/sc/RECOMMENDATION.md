# Round SC: recommendation

**Pick: SC1 Compact identity. Runner-up: SC3 Recap and undo.**

SC1 gives back exactly what the tick took away, the "Open REWE" key, for the least room (88 px at 100 %, 302 px at 310 %) and needs no deep link, recap data or session, so the launch list stays as simple as today. SC3 is the runner-up: "Undo last tick" fixes the mistick at the till, but it costs 144 px and 498 px, and Recently used already puts an item back with one tap.

## Measured

iPhone 390×844, English, light theme, at scroll top. Rows are whole open item rows between the list's top and the add field. Extra is the card slot (the card plus 8 px above and below), which moves every row down; Extra (c) is the same with REWE and Lidl finished. The last column lists where the primary "Open" button sits under the add field at 310 % until the user scrolls. No card has text or a button outside it, overlapping, or under 44 px, in any state, language, theme, phone or text size (verify.mjs).

| Option | Rows (a) | Rows (b) | Rows (c) | Extra 100 % | Extra 310 % | Extra (c) | Primary under the add field at 310 % |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Today | 9 | 0 | 3 | 0 px | 0 px | 0 px | no card |
| SC1 | 7 | 0 | 3 | 88 px | 302 px | 168 px | Android, (d) in German |
| SC2 | 7 | 0 | 3 | 134 px | 442 px | 190 px | Android, (d) in German |
| SC3 | 7 | 0 | 3 | 144 px | 498 px | 200 px | Android, (d) in English and German |
| SC4 | 7 | 0 | 3 | 140 px | 424 px | 140 px | Android, (d) in German |
| SC5 | 7 | 0 | 3 | 124 px | 386 px | 228 px | none |

The rows are counted on the replica iPhone, which has a 47 px status bar and a 34 px home indicator. The web capture has neither, so the real web build shows 10 rows for Today (a), not 9. Compare the counts between options, not with the web build.

What the numbers say:
- Every card costs the same 2 rows in (a). Today's 9 rows are Lidl's 7 and dm's first 2; any card of 88 px or more pushes dm's 2 out, and Lidl's 7 stay in view under all five. The height is what separates the options, and SC1 is 36 px to 56 px smaller than the rest at 100 %.
- In (b) the list is empty, so the card costs nothing. In (c) dm's 3 rows stay in view under every card.
- In (c) SC1 stacks two cards (168 px, 80 px per store) and SC5 combines them (228 px). SC2 and SC3 grow too, because the button reads "Open Lidl Plus" and wraps the second button. SC4 alone stays at 140 px. SC-Q3 proposes one card for the newest store.
- At 310 % on the small Android phone, the long name in (d) pushes "Open Netto" under the add field for SC1, SC2 and SC4 in German, and for SC3 in both languages. One scroll brings it up. SC5 fits because its title ("Finished at Netto Marken-Discount?") has no button beside it.

Why not the others:
- **SC2** needs a deep link to the customer card. None is verified for any chain (job 314 dropped DL2–DL4; the registry's links open the app's start screen). Without it the build would hide the button, and SC2 becomes SC1 with 46 px more.
- **SC4**'s "Next: Lidl" scrolls nowhere in (a) and (d), where Lidl already starts under the card. It helps only when the next store is below the fold: the storyboard shows Lidl finished while REWE, earlier in the list, is still open, and "Next: dm" jumps past REWE's 9 items to dm under the add field. The auto-dismiss after "Open" removes the key the user may need again if a scan fails.
- **SC5** asks "Finished at REWE?" and offers "I'm done", which writes nothing with trips off. It is a question with no consequence, and it reads like trip mode, which is off at launch.

## Open questions

1. **SC-Q1 Does "Open REWE" also dismiss the card?** Default: no. The card stays after "Open", so a failed scan or a second payment try can open the app again; X or SC-Q6 ends it.
2. **SC-Q2 When does a dismissed card return?** Default: only when that store gets a new open item and the user finishes it again. Until then the dismissal holds, on this device.
3. **SC-Q3 Stacked or combined cards when several stores finish?** Default: one card for the store finished last; it replaces the earlier one. Only one checkout happens at a time, and a stack of SC1 cards grows by 80 px per store.
4. **SC-Q4 Loyalty and payment deep links?** Default: none at launch. No chain has a verified deep link to its customer card or payment screen; the button stays hidden rather than open the app's start screen under a "Customer card" label. A later registry field per chain, filled only after a device test, could add it.
5. **SC-Q5 Recap as a count or with item names?** Default: no recap at launch (SC1). If SC3 is picked: the count only ("9 items bought at REWE"), no names; names took a second line and are dropped from 200 % anyway.
6. **SC-Q6 Does the card go away on its own if the user does not open the app (auto-dismiss)?** Default: yes, 60 minutes after the store's last tick, or at once when the user adds an item to that store (its section and header key are back).
7. **SC-Q7 Flag?** Default: the existing `open-store-app` flag, no new flag. The card shows only where the header key would have shown: a store linked to a chain whose app the registry knows.
8. **SC-Q8 Who sees the card?** Default: only the device that ticked the store's last item. Another household member's tick at home does not put a card on this phone.
9. **SC-Q9 A store without an app link?** Default: no card; its section hides as today.
10. **SC-Q10 The mistick at the till without SC3?** Default: Recently used's "Back on the list" (one tap, already shipped) puts the item and the section back; no undo on the card.
11. **SC-Q11 Analytics?** Default: reuse `store_app_opened` (chain, country, outcome) with a new `source` property (`header` or `card`), which needs an allow-list rule, a test and a row in docs/ANALYTICS.md in the build job (399).
12. **SC-Q12 The long name at 310 % on a small phone?** Default: accept it. The card scrolls with the list, and one scroll shows "Open". Shortening "Netto Marken-Discount is done" to the name alone would save one line at most.
