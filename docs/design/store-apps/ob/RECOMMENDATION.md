# Round OB: recommendation

<!-- pick: OB1 -->
<!-- runner-up: OB4 -->

## Recommendation

**Pick: OB1, today's chips from the phone's region, linked as you tap, without the two hint lines (OB-Q1).** The step keeps its place, its look and its taps. The chips now come from the registry for the phone's region, and a tapped chip is a linked store. That removes job 313's follow-up questions on the first list: 3 taps for a new user in Germany, and 5 taps plus two typed names for a new user in Austria. Today's chips are German on every phone, so an Austrian user has to type Hofer and SPAR. "Add your own store" stays and offers matching chains in any country, so "Hofer" on a German phone still finds Austria's. A name that matches nothing stays the user's own store, with no question. A chain with two apps gets its default app. The store's screen changes it later, as job 313 builds it. Joiners do nothing, because links are household data. Without the hint lines, the step shows 10 words instead of 34.

**Runner-up: OB4, no store step, and one card on the first list.** Onboarding has 6 steps instead of 7, and the taps move to the list (4 for a new user in Germany). It is the only option that makes onboarding itself shorter. Three costs keep it second:
- The card fills the first list. Under it, 1 of the user's items is in view at 100 % and none at 200 % (OB1: 4 and 3).
- Until someone answers the card, every item sits under "No store".
- A joiner whose phone is set to another country sees that country's chips for a household in Germany (the joiner scenario).

Not recommended:
- **OB2, type-ahead only.** It has the fewest words (6), and Continue stays in view even at 310 %. But every store costs a typed name: 3 for a new user in Germany, against 0 with chips. Onboarding should be taps, not typing.
- **OB3, top five plus "Other store".** The rows read well at large text. But a common store outside the top five (dm in Germany) costs one more tap and a typed name, and ranking "top five" per country is a judgment the registry would have to carry.
- **OB5, OB1 with a preview of the "Open app" key.** It is the quickest for a chain with two apps (3 taps against 6), and it shows what linking gives. But it adds 37 words and a block per store to the step that should be quickest, for a choice few households need. Job 313's app card covers the choice later.

## Measured

Taps from arriving at the store step until every store with an app is linked, including job 313's questions on the first list and, for two apps, choosing jö Bonus Club. The number in brackets is the difference from today after job 313. The first phone of every walk is live, and `verify.mjs` taps it along the same path and checks the count.

| Option | New in DE | New in AT | Not listed | Skip | Two apps | Joiner | Names typed (DE / AT) | Store screens in onboarding |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Today (main, plus job 313's card) | 7 | 9 | 5 | 1 | 8 | 0 | 0 / 2 | 1 |
| **OB1** Region chips, linked | 4 (−3) | 4 (−5) | 4 (−1) | 1 (0) | 6 (−2) | 0 (0) | 0 / 0 | 1 |
| OB2 Type-ahead in the step | 4 (−3) | 4 (−5) | 3 (−2) | 1 (0) | 6 (−2) | 0 (0) | 3 / 3 | 1 |
| OB3 Top five plus "Other store" | 5 (−2) | 4 (−5) | 4 (−1) | 1 (0) | 6 (−2) | 0 (0) | 1 / 0 | 1 |
| OB4 No step, a card on the list | 4 (−3) | 4 (−5) | 4 (−1) | 1 (0) | 6 (−2) | 0 (0) | 0 / 0 | 0 |
| OB5 OB1 plus a key preview | 4 (−3) | 4 (−5) | 4 (−1) | 1 (0) | 3 (−5) | 0 (0) | 0 / 0 | 1 |

Compared with today's onboarding on main, the store step itself costs the same 4 taps in Germany with OB1, OB2 and OB5, and 2 fewer in Austria. OB3 costs 1 more in Germany. OB4 drops the step, so its 4 taps happen on the list. Every option takes 1 tap to skip, as today. The scenarios are:
- New in DE: Lidl, dm, REWE.
- New in AT: Hofer, SPAR, Lidl. Hofer is ALDI SÜD in Austria, with its own app.
- Not listed: Lidl and "Hofladen Sonnenwiese".
- Skip: no stores.
- Two apps: BILLA, where the household uses jö Bonus Club instead of the default BILLA app.
- Joiner: joining Familie Brandt, whose stores are already linked, from a phone set to Austria.

The screen where a new user in Germany picks, at 390 × 844. Words are the UI words on the screen, with chain and app names not counted. "Scroll" is whether Continue (OB4: Done) is below the fold. The last column counts whole item rows between the top of the first list and the add field: today that list opens with job 313's first question, and OB4's with its card.

| Option | Words on the screen | Scroll to Continue at 100 / 200 / 310 % | Items in view on the first list at 100 / 200 % |
| --- | --- | --- | --- |
| Today | 34 | no / yes / yes | 3 / 2 |
| **OB1** | 34 | no / yes / yes | 4 / 3 |
| OB1-lean (OB1 without the two hint lines, OB-Q1) | 10 | no / yes / yes | 4 / 3 |
| OB2 | 6 | no / no / no | 4 / 3 |
| OB3 | 8 | no / no / yes | 4 / 3 |
| OB4 (the card) | 9 | no / yes / yes | 1 / 0 |
| OB5 | 37 | no / yes / yes | 4 / 3 |

At 200 % OB1 still scrolls, because eleven chips wrap to many rows. OB2 and OB3 fit because they show fewer choices. At 100 % every option shows Continue without scrolling.

## What changes in the app (for the build job, after job 313)

- `popularStores` reads the cached registry for the phone's region instead of a fixed German list, with "Hardware store" kept as a store type. `OnboardingDraft.stores` holds chain keys next to names, and `setup` creates the stores linked, through job 313's `add_store` path.
- `CreateHouseholdScreen` uses the same chips (a second household from the switcher).
- "Add your own store" gets job 313's suggestions (`chain_suggestions.dart`).
- Nothing new for joiners. Nothing is sent to retailers. No location is used: the country is the phone's region.

## Open questions

1. **OB-Q1 Drop the two hint lines on the store step?** Default: yes. The heading asks the question, and Skip says what it does. The step goes from 34 words to 10. The order hint also stands on the Stores page (List › Edit).
2. **OB-Q2 What does a phone show when its region has no registry entries (UK, US)?** Default: no chips, only "Add your own store" with suggestions from every country. No guessing from the app language.
3. **OB-Q3 Chip labels: the registry name ("Netto Marken-Discount") or a short one ("Netto", as today)?** Default: an optional `short` name in the registry for chips and the store's saved name, falling back to the name.
4. **OB-Q4 Keep "Hardware store"?** Default: yes, unlinked, as today. It is a store type, not a chain.
5. **OB-Q5 A chain with two apps in onboarding?** Default: its default app (the loyalty one, Peter's pick 4) with no question. The store's screen changes it (job 313).
6. **OB-Q6 A typed name that is exactly a chip's chain ("lidl")?** Default: it ticks that chip, as today's code already does, so it is linked without a question. Other matches show as suggestions.
7. **OB-Q7 Where does the region come from on the web?** Default: the browser's language region (`de-AT` gives Austria). Without one, OB-Q2 applies. Never location.
8. **OB-Q8 Same chips on `CreateHouseholdScreen`?** Default: yes.
9. **OB-Q9 Behind which flag?** Default: `open-store-app`, the same as job 313. With the flag off, the chips stay as today.
10. **OB-Q10 Households that already went through today's onboarding?** Default: job 313's card asks about them once, unchanged.
11. **OB-Q11 Chip order?** Default: the registry's order per country (most stores first), as today's list is ordered.
