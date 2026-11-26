# hc-category-sorting: prototype candidates (job 459)

Design changes the climb found but did not build (brief: no new layout, motion or interaction
model without a prototype round and Peter's pick).

## 1. Correcting an item's place inside a store

- **Problem.** Since `hide-categories` went full (22 Nov), a misplaced item cannot be moved within
  its store: no category chip, no drag. Job 455 (`docs/research/competitor-pain-points.md` 2.2,
  item 3) already asks Peter which correction model he wants; it is not repeated here.
- **What to compare.** A „Platz im Laden“ control in the edit sheet, drag inside a store section,
  or accepting the researched order for launch. Measure taps to fix one misplaced item and how
  often a fixed place holds after the next add.

## 2. Where a new item waits while it is being classified

- **Problem.** A new item without a category on the device shows at the top of its store until
  the server classifies it, then moves to its category's place in the walk (usually under a
  second). The app's own guess (`category_guess.dart`, job 272) is used by the add sheet's rows,
  which jobs 457 and 451 own.
- **Idea.** Place the new row at its guessed place right away, with the server correcting it
  only when the guess was wrong; or keep it on top as the "just added" spot on purpose.
- **What to compare.** How often the row moves after the add (guess right vs wrong rates from the
  classifier fixtures), and whether shoppers find a just-added item faster on top or in place.
