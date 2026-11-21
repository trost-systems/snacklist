# Totals with missing prices: TE1, only what has a price

**The pick: TE1 “Only what has a price”.** It keeps the ST3 block Peter chose and removes what carries no information. With no price anywhere, the block is gone. With some prices, only the stores that have one get a line, and one count on the total says what is missing (“4 without price”). With every price in, it is today’s block without the “7 with price” count. The ST3 rules stay: “at least” on every amount with an unpriced item behind it, “≈” on every sum holding a planned weight, “No store” as its own line, and bought/open only while a trip runs.

**Why TE1.**

- **It answers the complaint where it happens.** Peter’s screen (five stores, nothing priced) loses 353 px, 7 list rows, on the 390 × 844 iPhone. With some prices it saves 3 rows. Each row already has its own “+ Price” chip, so the per-store “1 without price” lines repeated the list.
- **Nothing Peter chose goes away.** The receipt, the subtotals, the floor, the ≈ mark and “No store” stay as job 237 built them. Only empty lines and one count go. With every price in, the block is unchanged (0 rows saved, 4 px less).
- **No new words.** Every string is in the app already (“Shopping total”, “Total”, “4 without price”, “at least”, “all bought”).
- **The smallest build.** It is a filter in `summaryOf`’s caller and two conditions in `SummaryBlock`. No new control, no new state.

**Its cost.** With every price in, it is still a five-line block (353 px, the same as Today). If that is also too long, TE2 is the next step.

**Runner-up: TE2 “One line, opens on tap”.** It is one total line in every state with a price (70 to 75 px, 5 rows saved), and nothing without one. The store lines are one tap away and come back folded. It is shorter than TE1 when everything is priced. But Peter asked for the per-store subtotals in view (ST round), and TE2 puts them behind a tap. Round ST’s ST4 (`expandable-total`) was the same trade, and it was not picked.

**The others.**

- **TE3 “Sums on the store dividers”** is as short as TE2 at the end, and each store’s sum sits where you shop it. But the dividers show a count only by ST-Q5, and ST1 (the subtotal on the divider) lost round ST. At 310 % the dividers wrap, and it saves fewer rows than TE2 (2 to 7).
- **TE4 “Total and the next price”** is the only option that does something with an unpriced list: “7 without price ›” jumps to the next item without a price and opens its editor. It still costs 70 px when nothing is priced, and it hides the store lines until every item has a price, so the partial state loses the subtotals. Its link could go onto TE1’s total line (TE-Q4).
- **TE5 “Total in the top bar”** adds nothing to the list and keeps the amount in view. But it needs a new notation for the floor (“≈ €6.38+”, TE-Q8), and in German and on the 360 px Android the pill squeezes the switcher until the list name is cut (“Shopping …”). The subtotals are in a sheet. It moves the total away from where job 229 put it.

## Measured: what the block adds to the list, iPhone 390 × 844

Pixels the option adds against no total at all (block, taller dividers or top bar). The number in brackets is list rows saved against Today: 48 px at 100 %, at 310 % a row of 151 px. 310 % is the iPhone’s largest size. Android 360 × 640 at 100 % and 200 % is in the page’s table. The Today replica matches the release web build within 3 px at 100 % (353/357 against 354/359 px) and within 12 % at 310 % (`te/real/heights.json`).

| Option | Text | (a) No prices | (b) Some | (c) All | (d) Trip |
| --- | --- | --- | --- | --- | --- |
| Today | 100 % | 353 | 357 | 357 | 357 |
| Today | 310 % | 954 | 1423 | 993 | 1543 |
| **TE1 Only what has a price** | 100 % | 0 (+7) | 213 (+3) | 353 (0) | 213 (+3) |
| **TE1 Only what has a price** | 310 % | 0 (+6) | 872 (+3) | 936 (0) | 975 (+3) |
| TE2 One line, opens on tap | 100 % | 0 (+7) | 75 (+5) | 70 (+5) | 75 (+5) |
| TE2 One line, opens on tap | 310 % | 0 (+6) | 504 (+6) | 340 (+4) | 456 (+7) |
| TE3 Sums on the store dividers | 100 % | 0 (+7) | 75 (+5) | 70 (+5) | 75 (+5) |
| TE3 Sums on the store dividers | 310 % | 0 (+6) | 685 (+4) | 586 (+2) | 456 (+7) |
| TE4 Total and the next price | 100 % | 70 (+5) | 110 (+5) | 357 (0) | 115 (+5) |
| TE4 Total and the next price | 310 % | 155 (+5) | 509 (+6) | 993 (0) | 461 (+7) |
| TE5 Total in the top bar | 100 % | 0 (+7) | 0 (+7) | 0 (+7) | 0 (+7) |
| TE5 Total in the top bar | 310 % | 0 (+6) | 0 (+9) | 0 (+6) | 0 (+10) |

## Open questions

1. **TE-Q1 The flag.** `list-declutter` and `prices-and-trip-total` are at full rollout, so changing the block in place changes it for every user. Default: a new PostHog flag `total-priced-only` on top of both, on for Peter and the testers first.
2. **TE-Q2 A list with no price at all.** Default: nothing, not even a line (TE1). Alternatives: one line “Shopping total · 7 without price ›” with TE4’s link (70 px), or the bare “Shopping total” rule.
3. **TE-Q3 Wording of the missing count.** Default: the total’s second line says “4 without price” / „4 ohne Preis“ (the existing string), and the store lines say nothing; their “at least” marks a store that is short. Alternatives: no count at all (the floor says it), or “+ 4 without price” after the amount.
4. **TE-Q4 TE4’s link on TE1.** Should “4 without price” on the total line be a link to the next unpriced item and its price editor? Default: no; every row has its “+ Price” chip already. It would be a new action with no string change.
5. **TE-Q5 The “with price” count.** TE1 drops “3 with price” / „3 mit Preis“ from the total line in every state; the amount says it. Default: drop it.
6. **TE-Q6 One store priced.** With prices in one store only, TE1 shows one “Shopping total” line and no store line, as ST3 does with one store (a line would repeat the total). Default: keep that rule; it counts stores with a price, not stores on the list.
7. **TE-Q7 A store bought without prices on a trip.** A store bought in full with no price gets no line; its items count in “without price”. Default: as shown. Alternative: keep an “all bought” line without an amount.
8. **TE-Q8 TE5’s floor mark.** If TE5 is preferred: the pill has no room for “at least”, so the prototype writes “€6.38+”, a new notation. Default: not needed with TE1.
9. **TE-Q9 Amounts at the largest text.** At 310 % the real app breaks an amount inside the number (“€6.3 / 8”, seen in the release web build), in Today and in every option. Default: fix it in the build: an amount that does not fit goes on its own line under the name. It is one more line, but the number stays whole.

## What is not decided here

This is a prototype. Nothing in the app changed. The build follows Peter’s pick, behind the flag of TE-Q1.
