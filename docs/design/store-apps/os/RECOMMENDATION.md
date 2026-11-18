# Round OS: recommendation

<!-- pick: OS1 -->
<!-- runner-up: OS4 -->

## Recommendation

**Pick: OS1, a key in the store's header, with OS3's app card on the store's screen as its labelled twin.** The key is one tap from the list. It costs no height and no rows, and it is there before the trip, during it and at the checkout. It shows only on stores whose chain has an app, so the market and the farm shop look as they do today. The store's screen says it in words ("App: Lidl Plus, Open"), next to the chain link that round SS adds there.

**Runner-up: OS4, a store menu from a visible key.** It takes two taps, but the action has words ("Open Lidl Plus"). Every header looks the same, and the menu has room for the next per-store actions, such as brochure links (OF1). Choose it if the icon-only key tests badly.

Not recommended:
- **OS2, the trip strip.** It needs trip mode, which is internal only today. It adds 47 px while a trip runs, and the line jumps when you tick at a store without an app.
- **OS5, the done line.** It is the right moment for the checkout, but it never shows before the last tick. At 310 % it grows to +155 px.
- **OS3 alone.** Three taps, in a screen nobody opens while shopping.

## Measured

All numbers come from `verify.mjs` on the phone (390 × 844), comparing each option with today in the same state. OS2 and OS5 are measured during a trip with ticks; the others on the list.

| Option | Taps to the app | Extra height, 100 % | Rows in view, 100 % (today) | Extra, 200 % | Extra, 310 % | Long name's badge 100 % / 310 % (today 220 / 130 px) | Names cut at 310 %, of 5 (today 3) | Shows |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **OS1** Header key | 1 | +0 px | 6 (6) | +0 px | +0 px | 170 / 72 px | 5 | always, on stores with an app |
| **OS2** Trip strip | 1 | +47 px | 5 (5) | +47 px | +47 px | 220 / 130 px | 3 | only during a trip, at the last tick's store |
| **OS3** Store's screen | 3 | +0 px | 6 (6) | +0 px | +0 px | 220 / 130 px | 3 | List › Edit › store |
| **OS4** Store menu | 2 | +0 px | 6 (6) | +0 px | +0 px | 170 / 72 px | 5 | always, on every store |
| **OS5** Done line | 1 | +12 px | 4 (4) | +68 px | +155 px | 220 / 130 px | 3 | only after a store's last tick |

- "Rows in view" counts whole item rows between the top of the list and the add field. At 100 % only OS2 and OS5 change the height; neither drops a whole row there. At 200 % both cost one row: 3 against today's 4 for OS2, 2 against 3 for OS5.
- The key costs the long store name 50 px at 100 % ("ALDI SÜD am Ha…" instead of "ALDI SÜD am Hauptbah…") and 58 px at 310 % ("A…"). Today already cuts it to "AL…" at 310 %. Screen readers always get the full name.
- At 310 % the key (and OS4's menu key) cuts all five names, "dm" and "Lidl" down to their first letter; today cuts three. Shown as a number only ("4" instead of "4 items") at that size, the count leaves room for them: then OS1 cuts two of five, fewer than today (measured in the prototype, English and German).
- No option overflows at 200 % or 310 %, in English or German, light or dark. Every new control is at least 44 × 44 px (`verify.mjs`).

## What a tap does

- **Android:** the button starts the retailer's app (its launcher activity by package). If the app is missing, it opens its Play page.
- **iPhone, with a verified app link** (21 of the registry’s 58 entries, such as ALDI SÜD `/homescreen`, ALDI Nord and REWE `/shop`): the link opens the app. If the app is missing, the button opens the App Store page.
- **iPhone, without one:** this covers Lidl Plus, Mein dm, EDEKA, Kaufland, PENNY, Netto and Rossmann, 37 of the 58 entries. iOS can only open the App Store page, where "Open" starts the installed app. That is one more tap, and it is the price of using no custom URL schemes (DL1 brief).
- The label stays "Open Lidl Plus" either way, because iOS can't know before the tap whether the app is installed.

## Open questions

1. **OS-Q1 An icon-only key, or words?** Default: the icon key (open in new), named "Open Lidl Plus" for screen readers, with a one-time tip line under the first header that has an app. The tip goes outside the control, per Peter's rule for hints.
2. **OS-Q2 Show the app card on the store's screen too (OS3)?** Default: yes. It is the labelled twin, and the chain link from round SS lives there.
3. **OS-Q3 What happens on iPhone for apps without a link to their start screen (Lidl Plus, Mein dm, EDEKA and others)?** Default: open the App Store page, where "Open" starts the app. Lidl's `/prm/` paths and other deep paths stay untested; they would need DL3, which is dropped.
4. **OS-Q4 What happens at large text, where the key cuts even short names?** Default: keep the key, and above 200 % show the count as a number only (the word stays in the screen reader label). Measured at 310 %, OS1 then cuts two of five names instead of all five; today cuts three.
5. **OS-Q5 Should the label differ when the app isn't installed?** Default: no. "Open Lidl Plus" on both platforms; the store page explains itself.
6. **OS-Q6 Should the trip strip (OS2) carry the button once trip mode ships?** Default: not in the first version. Revisit with trip mode's rollout.
7. **OS-Q7 Analytics.** Default: one event, `store_app_opened`, with the registry's chain key, the country, the platform and the outcome (app or store page). It never carries the store's own name. It gets a rule in `eventCatalog`, a test and a row in ANALYTICS.md, all in DL1.
8. **OS-Q8 Can a tap meant for the key fold the section?** Default: the key is 48 px wide with a 10 px gap to the caret, and the header's fold area excludes it. Watch for mis-taps in the internal beta.
