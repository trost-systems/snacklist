# Recommendation

**Pick: RU2, the tinted tray with a peek. Runner-up: RU4, ticked with checkmarks.**

## What the measurement changed

Opening the section by default does not, on its own, show the ticked item arriving. At scroll top no option shows one whole recent row. That holds on the iPhone (390 × 844) and on Android (360 × 640), at 100 % and at the largest text, in English and German, with a short list (5 open) and a long one (11 open). The section comes after the last store and after the shopping total (TE1), and with 5 open items the total alone fills the rest of the screen. So with any open section, a tick still sends the item out of view on a normal list. The user has to scroll 55 to 89 px on the iPhone to see the first recent item with 5 open items, and 343 to 377 px with 11.

RU2 is the only option that shows the landing on the first screen. While the tray is below the screen, a peek sits on top of the add field: "Ticked off · 3" and the newest ticked item as a pill. A tick flies the row into the peek, and one tap on the pill puts that item back. Scrolled down, the tray itself is clearly not the list. It has its own tint, a round check, compact muted rows and an undo arrow on every row.

The peek costs room while it shows. On the long list it costs 1 open row on the iPhone (9 instead of 10) and 2 on Android (6 instead of 8). At 310 % on the short list it costs 1 (2 instead of 3). With no recent items there is no section and no peek, so every option shows the same rows as today.

RU4 is the runner-up. Scrolled down, it gives the clearest signal that the item is ticked and not gone: a filled round check and the name struck through, the classic to-do look. It is also the shortest section with 15 recent items (360 px against RU1's 794 px), because it shows the newest 5 and then "Show all (15)". It does not solve the off-screen landing, though. RU-Q3 below suggests putting RU4's check-and-strike rows inside RU2's tray if Peter likes both.

RU1 is the smallest change to today, but it is the tallest section (794 px with 15), and its faded rows look most like the list itself. RU3's chips are the most compact at the short list (112 px with 3), but pills read as suggestions, not as "what I just ticked". They also lose the order of the list at a glance.

## Measured (iPhone 390 × 844, 100 %, English)

Whole rows at scroll top between the top bar and the add field (or RU2's peek). "To first recent" is how far the list has to scroll until the newest recent item is whole above the add field. "—" means Today's folded tile never shows the item without a tap. With 0 recent items all options show 5 (short) and 10 (long) open rows, the same as today.

<!-- measured: en ios 100 -->
| Option | Short 3: open | Short 3: recent | Short 15: recent | Long 15: open | Long 15: recent | Long 15: to first recent (px) |
| --- | --- | --- | --- | --- | --- | --- |
| today | 5 | 0 | 0 | 10 | 0 | — |
| RU1 | 5 | 0 | 0 | 10 | 0 | 377 |
| RU2 | 5 | 0 | 0 | 9 | 0 | 347 |
| RU3 | 5 | 0 | 0 | 10 | 0 | 359 |
| RU4 | 5 | 0 | 0 | 10 | 0 | 343 |

### Largest text (iPhone, 310 %)

<!-- measured: en ios 310 -->
| Option | Short 3: open | Short 3: recent | Short 15: recent | Long 15: open | Long 15: recent | Long 15: to first recent (px) |
| --- | --- | --- | --- | --- | --- | --- |
| today | 3 | 0 | 0 | 2 | 0 | — |
| RU1 | 3 | 0 | 0 | 2 | 0 | 2844 |
| RU2 | 2 | 0 | 0 | 2 | 0 | 2643 |
| RU3 | 3 | 0 | 0 | 2 | 0 | 2777 |
| RU4 | 3 | 0 | 0 | 2 | 0 | 2636 |

### Android (360 × 640, 100 %)

<!-- measured: en android 100 -->
| Option | Short 3: open | Short 3: recent | Short 15: recent | Long 15: open | Long 15: recent | Long 15: to first recent (px) |
| --- | --- | --- | --- | --- | --- | --- |
| today | 5 | 0 | 0 | 8 | 0 | — |
| RU1 | 5 | 0 | 0 | 8 | 0 | 581 |
| RU2 | 5 | 0 | 0 | 6 | 0 | 551 |
| RU3 | 5 | 0 | 0 | 8 | 0 | 563 |
| RU4 | 5 | 0 | 0 | 8 | 0 | 547 |

## Open questions (each with the default the build takes)

1. **RU-Q1 Flag.** Ship it behind a new PostHog flag `recently-used-open`, on for Peter and the internal testers first. *Default: yes.*
2. **RU-Q2 Can people still fold it?** The tray's header keeps its chevron. Folding is remembered per device, and the tray starts open. A folded tray still shows the peek. *Default: yes, open by default, fold remembered per device.*
3. **RU-Q3 Rows in the tray.** RU2's compact muted rows with an undo arrow, or RU4's full-height rows with a filled check and a struck-through name inside the same tray. *Default: RU2's rows as built. RU4's rows are a one-line swap if Peter prefers them.*
4. **RU-Q4 Is the peek's pill an undo button?** It returns the newest item in one tap, like an undo. Unlike a snackbar it never times out and it belongs to the section: it is the tray's own header, pinned while the tray is out of view. *Default: keep it. A tap on the rest of the peek scrolls to the tray.*
5. **RU-Q5 Whose ticks show in the peek?** Recently used lists the whole household's purchases, so Lea's ticks would land in Peter's peek while she shops. *Default: the peek's pill shows only the newest item ticked on this device. The count and the tray show everyone's, as today.*
6. **RU-Q6 Header word.** "Ticked off" / "Abgehakt" replaces "Recently used" / "Zuletzt verwendet" on the list. The add sheet's suggestions keep "Recently used". *Default: rename on the list only, and update the feature map and FEATURES-FOR-WRITERS in the build PR.*
7. **RU-Q7 Before or after the total?** Moving the tray above the shopping total would bring it closer on a short list by the total's height (about 200 px in the replica's short list, read off the screenshot), but the total then no longer closes the open items. *Default: after the total, as today.*
8. **RU-Q8 How many.** Today's limit of 20 stays, newest first, one row per item. *Default: 20, all shown in the open tray.*
9. **RU-Q9 After a tap-back.** The item returns to its place with a short highlight and the list does not scroll. If its place is above the screen, the screen reader announces "Milk: Back on the list". *Default: no scroll, plus the announcement.*
10. **RU-Q10 Trip mode and the add sheet.** While a trip runs, the peek sits above the trip strip. While the add sheet is open, the peek hides. *Default: as stated. The build measures the rows the peek costs with the trip strip.*
11. **RU-Q11 Reduced motion.** No fly or fold. The row leaves, and the item appears in the peek or the tray at once with the highlight. *Default: yes (built in the prototype).*
12. **RU-Q12 Prices in the tray.** No price chip on recent rows. A price is set again once the item is back on the list. *Default: no prices in the tray.*

## How to check

`node docs/design/list/verify.mjs` ends `all checks passed (N)`. `node docs/design/list/tools/mutate.mjs` runs the mutations in `MUTATIONS.md`, and each one fails named checks.
