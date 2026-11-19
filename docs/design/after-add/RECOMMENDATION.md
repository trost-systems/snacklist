# Round AS: recommendation

**Pick: AS1 Chip row. Runner-up: AS2 Field on top.**

## Measured

`verify.mjs` measured these in Chromium, after the first add. "Editing takes" runs from the top of the sheet to the keyboard. For AS4 it runs from the top of the card on the list, which includes the item's own row. Today's replica measures 312 px, the same as Peter's screenshot (sheet top at 197 px, keyboard at 509 px, at 390 × 844).

| Option | Editing takes, iPhone 390 × 844 | Editing takes, Android 360 × 640 | Taps: store + category | Brand field | Every field and open picker in view | List above, Android, after 2 adds |
| --- | --- | --- | --- | --- | --- | --- |
| Today | 312 px | 312 px | 4 | yes | no: category cut, brand and details off screen | – |
| AS1 Chip row | 131 px | 131 px (German 181 px) | 4 | into details | iPhone to 310 %, Android to 200 % | 43 px |
| AS2 Field on top | 187 px | 187 px (German 239 px) | 3 | kept | iPhone to 200 % (at 310 % the open panel's two lines run under the keyboard), Android to 200 % | 0 px, 1 row under the status bar |
| AS3 Field grid | 243 px | 243 px | 4 | kept | iPhone to 200 % (the field leaves at 310 %), Android to 100 % (at 200 % an open picker pushes the field under the keyboard) | 0 px, 1 row under the status bar |
| AS4 Edit on the row | 247 px | 247 px | 4 | into details | iPhone to 310 %, Android to 200 % | 37 px |
| AS5 One-tap rows | 255 px | 255 px | 2 | into details | iPhone to 310 %, Android to 200 % | 0 px, 1 row under the status bar |

Heights are for English. German is given where it differs: on the 360 px Android, "Getränke" is wider than "Drinks" and wraps a line.

"In view" covers the item's fields with the pickers closed and with each picker open (store, then category), at every text size the phone offers, in both languages. An open picker is one line of options that swipes sideways, and the item's own option is scrolled into view, as `FoldoutChips` does today. In the first version the options wrapped onto several lines and ran under the keyboard at large text; review 1 caught that. With one line, Lidl and Chilled are in view without a swipe on both phones. "List above" is the list left between the status bar and the editing area after two adds. A tap on the list needs 44 px, so where less is left, the sheet closes by a swipe or the back key.

Every option, in every frame, at both sizes, in both languages and both themes:
- shows no close key, no "Just added" header, and no "Added / Undo" row;
- leaves no gap above the field (at most 13 px, which is the 8 px spacing plus the chips' edge; today's gap is 65 px);
- has an empty list behind the sheet before the first add, and then only the last two adds.

## Why AS1

- **It saves the most space of all five.** It takes 131 px, which is 181 px less than today on both phones in English. In German on the 360 px Android the Details chip wraps to a second line (181 px, still 131 px less than today). On the iPhone, the list keeps 164 px above the two new rows.
- **Every field and every open picker is in view at every text size both phones offer.** At 310 % the chips wrap onto three lines, the open picker is one sideways line, and both still sit above the keyboard. AS2 and AS3 don't manage this.
- **The fewest changes to what people know.** The chips, their fold-out options and the field stay where they are today; the options fold out as one sideways line instead of several. Only the things Peter marked go away. Store and category stay at 4 taps, as today.
- **The smallest build.** It reuses `FoldoutChips` and the details line (`ItemDetailFields.inLine`). It deletes `_AddedNote` and the close key in the after-add state, the list's `justAdded` section, and the fixed room for three rows.

Graft from AS2: sending an empty field also closes the sheet. It needs no new UI.

## Why not the others

- **AS2** (runner-up): it is the next smallest (187 px), it keeps Brand, and store plus category take 3 taps. But the field moves to the top of the sheet. It jumps when the sheet opens, and it no longer sits at the keyboard's edge as on the list screen. On the 360 × 640 phone the earlier row slides under the status bar. At 310 % on the iPhone its open panel (stores and categories, two lines) runs under the keyboard.
- **AS3**: every field is a field and it is calm, but it is 112 px taller than AS1. At 310 % the field leaves the screen. On the small Android it cuts a row, and at 200 % an open picker pushes the field under the keyboard.
- **AS4**: the sheet is only 79 px, but the card on the list makes editing 247 px, so the space just moves from the sheet to the list. Editing would also happen in two places, the list for this item and the sheet for the next.
- **AS5**: 2 taps for store and category is the best, but at 255 px it is the tallest after today. On the small Android it cuts a row. Its rows show only part of the stores and categories, so one further along needs a swipe.

## A mistaken add

Undo goes away entirely (Peter, t1071u). To remove a mistaken add, close the sheet, tap the row and choose Delete. The store and category the app learned from it are not rolled back: the next add of that item is corrected in the sheet. Job 315's code stays as it is.

## Open questions (each with the default the build uses unless Peter says otherwise)

1. **AS-Q1. Brand.** *Default:* the after-add sheet has only Details. The edit sheet keeps Brand, an item that has a brand shows "brand, details" on the Details chip, and no data changes. Text typed into Details stays in Details, with no brand parsing.
2. **AS-Q2. Closing without the X.** *Default:*
   - a swipe down on the sheet, or a tap on the list above it;
   - Android's back key (first it hides the keyboard, then it closes the sheet);
   - sending an empty field (the graft from AS2).

   For screen readers, the grabber becomes a button labelled "Close" (the string the X uses today), so no new text is needed.
3. **AS-Q3. The small Android.** With two adds behind the sheet, 43 px of list is left (the second item's category, "Bread & bakery", wraps the chips), and a tap needs 44 px. *Default:* accept it. On such a phone the sheet closes by a swipe or the back key. At 200 % text the rows behind the sheet slide partly under the status bar on both phones (one row in AS1, measured in frames 4 to 8), so there the sheet closes only by a swipe or the back key. At 310 % on the iPhone no list is left to tap in AS1 and AS2 either; there too the sheet closes by a swipe.
4. **AS-Q4. The duplicate note** ("Oat milk is already on the list", with Merge, and Undo after a merge). *Default:* it takes the chip line's place until it is answered or the next letter is typed. The merge keeps its Undo, because no row lets the user take a merge back. That would be the only Undo left in the sheet, while Peter said Undo can go entirely: is that OK, or should a mistaken merge be undone by editing the merged row?
5. **AS-Q5. Typing the next item.** Up to three suggestions replace the chip line. The sheet grows while typing and shrinks again after the add. *Default:* let it grow. Today's fixed room for three rows was the gap Peter marked.
6. **AS-Q6. A tap on one of the two rows behind the sheet.** *Default:* that item's fields come into the sheet, and the row turns honey. This is the way to fix the item before the last one without closing the sheet.
7. **AS-Q7. Reopening the sheet.** *Default:* the list behind it starts empty again. The earlier adds are on the list once the sheet closes.
8. **AS-Q8. Job 313's store picker** (chain type-ahead behind "New store", preferred app). *Default:* the fold-out under the store chip is the same component, so 313's change applies unchanged. AS1 changes only where the chip sits.
9. **AS-Q9. The Details chip with nothing in it shows only its icon.** Its accessible label is "Details". *Default:* yes. In the first draft of AS1, the chips had the word and drop-down arrows, and they wrapped onto a second line on the iPhone. Without both, they fit on one line on both phones in English. A long category name still wraps the Details chip to a second line: "Bread & bakery" on both phones, and German "Getränke" on the 360 px Android. The sheet then grows by one line and no field is hidden.
10. **AS-Q10. An open picker at large text.** *Default:* the options stay one line that swipes sideways, and the sheet never scrolls; the keyboard stays up. The alternative is to let the sheet scroll, as today's `Scrollable.ensureVisible` does, or to hide the keyboard while a picker is open. One line keeps every field in view in AS1 at 310 %, so the default needs neither.
11. **AS-Q11. Rollout.** *Default:* a new flag `add-sheet-compact`, off, and on for Peter and the testers. It sits on top of `add-feedback-list`.
