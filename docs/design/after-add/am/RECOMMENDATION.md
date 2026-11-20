# Round AM: recommendation

**Pick: AM2 Outcome rows. Runner-up: AM1 Marked rows.**

Peter's clarification (t1077u) applies to all five options. A match shows only inside the sheet, as a suggestion marked apart from one that adds a new item, and the same goes for ticking off. The row on the list behind the sheet is never moved into view or highlighted. After an outcome, the sheet says what happened in the chips' place, with the app's own sentences ("Merged: 2× Pasta", "Pasta ticked off", "Pasta is already on the list"), until the next letter. The list behind the sheet shows only items the sheet added. `am/verify.mjs` checks this in every frame.

## Measured

`am/verify.mjs` measured these in Chromium. Taps count clicks and Enter presses on the live phone after the word is typed. The script replays every path and checks the list afterwards against the reducer. Heights run from the top of the sheet to the keyboard, in English at 100 %, iPhone / Android. AS1 typing with one plain suggestion (Cinnamon) is 135 px on both phones.

| Option | Enter, open match | Enter, ticked match | Tick off | Merge | Separate | Back on the list | Sheet, 1 match | Sheet, 3 matches |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AM1 Marked rows | merges (+1) | back on the list | 1 | 1 | 1 | 1 | 191 / 191 px | 303 / 303 px |
| AM2 Outcome rows | keeps the list, says it is there | back on the list | 1 | 1 | 1 | 1 | 247 / 247 px | 303 / 303 px |
| AM3 Decision keys | merges (+1) | back on the list | 1 | 1 | 1 | 1 | 187 / 187 px | 247 / 247 px |
| AM4 Add, then offer | adds a separate one | adds a separate one | – | 2 | 1 | 2 | 135 / 135 px | 135 / 135 px |
| AM5 Tiles (Bring!) | ticks it off | back on the list | 1 | 1 | 1 | 1 | 171 / 171 px | 271 / 271 px |

AM4 shows nothing while typing, so its sheet is AS1's. Its match shows after Enter, in a sheet of 187 / 237 px. AM2 spends two rows on an open match of the same item (merge and tick off), so with Milk its three rows hold Milk and Oat milk, and the ticked Buttermilk doesn't fit. The other options show all three.

**In view.** Every match, every deciding key and the field must sit above the keyboard and inside the screen, with no sideways swipe and no scrolling in the sheet. This was checked in both languages and both themes.

| Option | One match, iPhone | One match, Android | Three matches, iPhone | Three matches, Android | New UI words |
| --- | --- | --- | --- | --- | --- |
| AM1 | to 200 % | to 200 % | to 200 % | 100 % | none |
| AM2 | to 200 % | to 200 % | to 200 % | 100 % | none |
| AM3 | to 200 % | 100 % | 100 % | no: in German the third name needs a swipe | Merge, New, Back on the list (all in the app already) |
| AM4 | 100 % | 100 % | 100 % | 100 % | Merge, Back on the list (in the app already) |
| AM5 | to 310 % | to 200 % | to 200 % | 100 % | none |

Every option marks the scenarios the same way, at every size, in both languages and both themes:
- exact (Pasta), plural (Apple → Apples 1 kg) and the store-and-brand case each show one match, and Oat milk shows "dm · Hafergold";
- several matches (Milk) show three items, two in AM2;
- a match ticked yesterday (Eggs) shows as ticked;
- no match (Cinnamon) shows plain AS1.

AM4 is the exception: it marks nothing until Enter has added the item. Every key that decides is at least 44 px.

## Why AM2

- **It is Peter's clarification, literally.** Each outcome is its own suggestion, marked apart from the + row that adds:
  - merge shows the item as it would be, 2× Pasta, on honey, with the merge icon;
  - tick off shows the name struck through, on mint, with the tick icon;
  - a ticked match shows Back on the list's icon, on grey.

  Nothing needs reading beyond the item itself, and it adds no new UI words.
- **Every outcome is one tap, and each is in view before the tap.** The user sees what the list will look like (2× Pasta) before choosing. AM1 hides merge behind a tap on the row, and its ✓ is a bare round key.
- **Enter never changes the list by surprise.** The common reason to type something that is already there is that the other person added it, or you forgot you did. Today the app refuses it with "Pasta is already on the list". AM2's Enter does the same, inside the sheet. AM1 and AM3 merge on Enter, which gives 2× Pasta when you wanted one. AM5 ticks the item off, so it leaves the list: that is Bring!'s toggle, and it surprises anyone who types.
- **A ticked match comes back in one tap or Enter,** with its amount, store, brand and details (10× Eggs, Edeka, free range). Today the app adds a new row, and the amount, brand and details of the ticked one don't come back.
- **It holds up at large text as well as AM1.** One match is in view to 200 % on both phones. At 310 % on the iPhone, a match with store and brand (two lines) pushes the field under the keyboard, in AM1 too (AM-Q8). Only AM5's tiles keep one match in view at 310 %.
- **The cost is height.** With one open match it takes three rows, 247 px, against AM1's 191 px. That is still under today's after-add sheet (312 px), and it stays only while typing.

## Why not the others

- **AM1** (runner-up): every outcome takes one tap, in two rows instead of three. But Enter merges and so does a tap on the row, and nothing on the row says so. Its tick off is a bare round key.
- **AM3**: three equal keys under one match make the clearest single choice. But it is the only option that needs words (Merge, New, Back on the list). In German on the 360 px phone, the third match's name needs a swipe. It keeps every key in view only to 200 % (iPhone) and 100 % (Android). Enter merges.
- **AM4**: today's order. Nothing is marked while typing, so the user sees the match only after the add. Merging takes 2 taps, and ticking off has no key. Its offer row keeps in view only at 100 %.
- **AM5**: Bring!'s tiles look the most like Bring!, but a tap and Enter tick off. Typing "Milk" plus Enter, the most natural add, takes Milk off the list. Merge hides in a corner +.

## Open questions (each with the default the build uses unless Peter says otherwise)

1. **AM-Q1. Flag.** *Default:* a new flag `add-match-rows` in releases/flags.json, rollout off, on for Peter and the testers. It sits on top of `add-sheet-compact` (job 322) and needs it. With the flag off, today's refusal and the "already on the list" note stay.
2. **AM-Q2. What Enter does on an exact or plural match of an open item.** *Default:* nothing changes, and the sheet says "Pasta is already on the list" (AM2, as today). The alternatives are merge (+1, AM1 and AM3), add separately (AM4) or tick off (AM5, Bring!'s toggle).
3. **AM-Q3. Ticked items as matches.** *Default:* yes, the items in the shown list's ticked section, on a grey row with Back on the list's icon. Enter or a tap puts the item back with its amount, store, brand and details. An open match of the same item always comes first. Should the old amount come back (10× Eggs) or be cleared? *Default:* it comes back.
4. **AM-Q4. What counts as the same item.** *Default:* the server's `canonical_key` (plural, umlauts, synonyms, typos), whatever brand and details either item has. "Oat milk" matches the Hafergold Oat milk from dm, and the + row adds a separate one. A part match (Milk while Oat milk is listed) gets only a merge row, and Enter never acts on it.
5. **AM-Q5. Several matches.** *Default:*
   - three rows at most, as in the prototype (AS-Q5's three);
   - an open match of the typed item takes two rows, merge and tick off, and other matches take one each, in this order: the same item, other open ones, ticked ones;
   - the + row comes after them, as a fourth row.

   With Milk, the ticked Buttermilk doesn't fit.
6. **AM-Q6. Merge amounts.** *Default:* today's `merge_quantities`. A typed amount adds up ("2 Nudeln" on top of Pasta gives 3×), and no amount counts as one piece. A weight plus no amount stays as it is (1 kg Apples), and the merge row shows that before the tap. Should the merge row then offer the stepper's step instead (2 kg)?
7. **AM-Q7. What the sheet says after an outcome.** *Default:* one line in the chips' place until the next letter, with no Undo (Peter dropped Undo in AS). It uses the app's sentences: "Merged: 2× Pasta", "Pasta ticked off", "Pasta is already on the list". Back on the list is "Back on the list: 10× Eggs", built from the existing `readd` label. A wrong tick off is undone by tapping the row in the ticked section, and a wrong merge by editing the amount.
8. **AM-Q8. Large text.** In AM2 the rows push the field under the keyboard in two cases: a match with a second line (store and brand) at 310 % on the iPhone, and three matches at 310 % on the iPhone or 200 % on Android. The prototype doesn't solve this. *Default for the build:* the rows scroll above the field, which stays pinned, and the + row moves above the matches, so a separate add is never scrolled away.
9. **AM-Q9. Today's duplicate note in the sheet** ("… is already on the list" with Merge after the add; AS-Q4). *Default:* it goes away in the sheet, because the match is shown before the add. The snackbar for adds from outside the sheet stays: voice, Siri, the API and MCP. Those paths still go through the server's duplicate skip.
10. **AM-Q10. Which list.** *Default:* only the shown list, as today. An open item on another of the household's lists is not a match.
11. **AM-Q11. Analytics.** *Default:* the events `add_match_shown` and `add_match_outcome` (property `outcome`: keep, merge, tick, readd, separate) get rules in `eventCatalog` and rows in docs/ANALYTICS.md. They replace `dedupe_hint_*` for the sheet. No names or text are sent.
