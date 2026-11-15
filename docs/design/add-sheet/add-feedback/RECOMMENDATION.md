# Add feedback: recommendation (job 273, round AF)

Question: after a tap in the add sheet, how does the user see which item went to which store and section, and how do they find or fix it once the sheet is closed? Peter: “the first thing you have to do after closing the sheet is searching for the item in the list.”

## Measured

<!-- table -->
| Option | Item + store + section identifiable while open 100 % / 200 % (worst of 4 scenarios) | Three adds: identifiable while open 100 % / 200 % | Find after the close | Fix store: open / after (taps) | Fix section: open / after (taps) | Correction sticks next time | Extra height vs Today (open, 100 %) | Text cut, spilling or overlapping at 200 %: option / main’s chrome | Whole rows after the close 100 % / 200 % (item among them) | Suggestion rows in view while typing 100 % / 200 % (of) | Suggestion rows in view right after an add 100 % / 200 % (fewest, scenario) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Today** | name only (en first) / name only (en first) | 0/3 / 0/3 | scroll 137 px | — / 4 | — / 4 | yes | 309 px | 0 / 28 | 7 (no) / 7 (no) | 7 / 5 (7) | 3 (One known item) / 1 (Long names) |
| **AF1 Show me on close** | yes / yes | 1/3 / 1/3 | 0 taps (already shows) | 2 / 4 | 2 / 4 | yes | +44 px | 0 / 28 | 6 (yes) / 6 (yes) | 7 / 5 (7) | 3 (One known item) / 1 (Long names) |
| **AF2 Added tray** | yes / name only (en long) | 3/3 / 1/3 | 1 tap (Show) for 5 s, then scroll 137 px | 2 / 4 | 2 / 4 | yes | +20 px | 0 / 28 | 7 (no, “Rewe 6 items” half under it) / 6 (no, “🥣Natural yoghurt” half under it) | 7 / 3 (7) | 3 (One known item) / 2 (Three adds, two stores) |
| **AF3 Confirm in place** | yes / yes | 1/3 / 1/3 | 0 taps (already shows) | 2 / 2 | 2 / 2 | yes | +37 px | 0 / 28 | 6 (yes) / 6 (yes) | 7 / 3 (7) | 3 (One known item) / 1 (Long names) |
| **AF4 Toast with Show and Change** | yes / yes | 0/3 / 0/3 | 1 tap (Show) for 6 s, then scroll 137 px | 2 / 2 for 6 s, then 4 | 2 / 2 for 6 s, then 4 | yes | +13 px | 0 / 28 | 6 (no, “🥣Natural yoghurt” half under it) / 4 (no, “🥛2× Whole milk” half under it) | 7 / 3 (7) | 3 (One known item) / 1 (Long names) |
| **AF5 Split view** | yes / yes | 1/3 / 1/3 | 0 taps (already shows) | 2 / 2 | 2 / 2 | yes | +0 px | 0 / 28 | 6 (yes) / 6 (yes) | 4 / 3 (7) | 2 (Long names) / 1 (Long names) |
<!-- /table -->

Measured by `verify.mjs` in Chromium on the 390 × 844 phone, scenario “One known item” unless the column says otherwise.

- “Identifiable” means the item’s name, its store and its section show together in text a reader sees: inside every clip, not behind an ellipsis, not under the scrim or the sheet, within about three suggestion rows’ height of the name. Each cell is the worst of four scenarios (one known item, long names, first-time grocery, empty section) in English and German, with the scenario where it was worst.
- Taps count each tap, the one that opens a picker included. “Hold” on a row counts as one. A fix with no control of its own goes through the edit sheet: hold, chip, pick, Done (4).
- “Find after the close” is 0 when the item already shows, 1 when one button brings it, else how far the user must scroll. AF2’s bar and AF4’s toast go away after 5 s and 6 s; the cells say what is left then.
- “Text cut, spilling or overlapping at 200 %” counts text that sticks out, spills, is cut by a clipping box or an ellipsis, overlaps, or sits under the home indicator, over every scenario and both frames, English and German. The first number is the option’s own feedback (note, card, tray, toast, chips). The second is main’s chrome, the same 28 in every phone: the household name, “No store” and the market’s long name in the store dividers end in an ellipsis, as they do in the app.
- “Half under it” names list text a floating toast or bar half covers after the close.
- “Suggestion rows” count whole rows in view. While typing: for the letter with the most rows (7, as `suggest_entries` brings up to 8). Right after an add: the fewest over the six scenarios, with the note, card or toast up.
- AF5 runs as a half sheet up to 130 % text. From 130 % it is AF3’s full sheet with the scrim (AF-Q3), so its 200 % cells measure that.

## Pick: AF3 Confirm in place

AF3 answers “what went where” at the finger: the tapped row becomes the item with its store and section chips (identifiable yes at 100 % and 200 %), each fixed in 2 taps while open and, through the new row’s “Lidl · Chilled” chip, 2 taps after the close, where the list already shows the item (find 0). It keeps today’s full sheet, so 7 suggestion rows stay in view while typing at 100 % (3 at 200 %, where the card stays while the next item is typed; Today 7 and 5), for 37 px of extra height while the card shows.

## Runner-up: AF5 Split view

AF5 scores the same on finding (0) and fixing (2 / 2) and shows the new row landing in its store’s section with no extra height, but its half sheet leaves 4 suggestion rows in view while typing instead of 7, and from 130 % text it has to become AF3 anyway. Take it over AF3 if seeing the row land in the list matters more than room for suggestions (AF-Q3).

## What the others showed

- AF1 (Show me on close) finds the item at 0 taps and pulses it, but any fix after the close needs the edit sheet (4 taps), and the grown note costs 44 px.
- AF2 (Added tray) is the only option that keeps all three adds identifiable while open (3/3 at 100 %). At 200 % its tray fits only one (1/3), and a long name pushes the store out of the tray’s view (“name only”). After the close it takes one tap (Show) to find the item for 5 s, then a 137 px scroll, and 4 taps to fix.
- AF4 (Toast) fixes in 2 taps for 6 s, then 4. Several adds collapse to a count (0/3 identifiable), and after the close the toast half covers list rows (“Natural yoghurt” at 100 %, “2× Whole milk” at 200 %).
- Today names the store only when the tapped row knew it, never the section (“name only” for a first-time grocery), and the item sits 137 px below the visible list after the close.

## Open questions

1. AF-Q1: Several adds in one go: AF3’s card shows only the newest (1/3 identifiable while open). Default: the card follows each add, as built; the earlier adds keep their “store · section” chip in the list after the close.
2. AF-Q2: How long do new rows keep their “Lidl · Chilled” chip? Default: until the add sheet opens again, as built.
3. AF-Q3: Is seeing the row land in the list while the sheet is open (AF5) worth 3 fewer suggestion rows while typing (4 instead of 7 at 100 %)? Default: no, ship AF3’s full sheet; if Peter wants AF5, it runs as a half sheet below 130 % text and as AF3 from 130 %, as built.
4. AF-Q4: A long name at 200 % leaves 1 whole suggestion row under the card (table). Default: accept it; the card drops “Added to” from 130 %, as built, and the name is never cut.
5. AF-Q5: Does every correction show “Learned: next time Halloumi goes to Rewe”? Default: yes, under the moved row or in the card, until the next tap; the server already learns every correction (`items_learn`).
6. AF-Q6: Should the card say why a store was chosen (“remembered”, “usual for Chilled”)? Default: yes, small and muted after the chips, so an ST1 guess reads as a guess.
