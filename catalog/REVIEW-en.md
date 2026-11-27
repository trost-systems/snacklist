# Opus review of the 2026-11-26 English draft (job 470)

Claude Opus 5.5 checked every row of `drafts/2026-11-26-en.tsv` and filled its `review` cells. This
is a machine review. The person's review that Legal N-215 requires is Peter's: on 26 Nov 2026 at
20:07 CET (t1388u) he reviewed the rows in PR #761 and approved them, with the suggested answer to
each of EN1 to EN8 below ("reviewed and looks good, go ahead and merge with the suggested
answers"). EN6 is applied: the English rows of `drafts/2026-11-16-claude.tsv` are dropped (see its
header).

## What was checked

Each row was checked for four things:

- **Aisle.** The aisle must follow `dictionary.tsv`'s placement rules.
- **Concept.** The concept must be the same product as the English word. Related is not enough.
- **Word.** The word must be what a US or UK list writes, with the plural for countables. Forms must
  be real variants.
- **N-215.** No brands, no medicines or supplements, and no health claims.

The input was the repo's TSVs and general knowledge only.

The concept rule needed evidence first. A German compound does not take its head's key. With
`/tmp/470/classify.sh` on the job's stack, Griechischer Joghurt, Magermilch, Dijonsenf, Reisnudeln,
Hühnerbrühe, Rote Linsen, Gemahlene Mandeln and Hot Dog Brötchen each keep their own canonical key.
They still land in the head's aisle. So an English kind joined to the generic German term (greek
yogurt to joghurt) would share a key that German keeps apart. The app would then offer to merge
"yogurt" and "greek yogurt". The rule this review applied: a word joins a concept only if it names
the same product, the way a `synonyms.tsv` row does. A kind or variety becomes its own concept.

## Counts

| | Rows |
| --- | --- |
| Drafted | 1052 |
| Added by the review (source `opus-review`) | 24 |
| Now in the draft | 1076 |
| `accept` | 1075 |
| `reject` | 1 |
| Changed (concept or forms) | 35 |

Every change is marked in the row's `note` with the prefix `review:`.

## Evidence

The checks ran on the shared local stack, one probe at a time.

- `deno run --allow-read draft_rows.ts ../../catalog/drafts/2026-11-26-en.tsv accept` exits 0.
- `probe_drafts.sh --rows accept` was run on the final draft, with output in
  `/tmp/470/probe-review.tsv`. It gives 1030 `gap`, 222 `key`, 123 `redundant` and 2 `listed`. No
  row is `broken`. The 2 `listed` rows are `dips` and `smoothies`, as the drafter noted. They are
  already German terms, so they are harmless.
- There are 75 `regress` lines. None is a dictionary term, a synonym, a `wordlist.tsv` word or a
  `sweep.tsv` word, so no German word changes aisle.
- `expected.en.tsv` has 285 rows. All of them land in their expected aisle except `tooth paste` and
  `toiletpaper`, which the lead handles. `paprika` passes.
- The review also used a private copy of the probe with 78 extra texts. They are compounds of the
  changed and added rows and some German look-alikes: toilet roll holder, cough syrup, caustic
  soda, Beet, Zander, Sander. Three findings came from that copy. The first version of the review
  broke `red pepper flakes`. The planned `syrup` row sent cough syrup to pantry. `lotion` is
  already a term. All three are fixed below.

## Changes

| Row | Change | Why |
| --- | --- | --- |
| greek yogurt, red lentils, egg noodles, rice noodles, dijon mustard, ground almonds, lamb chops, pancake mix, brownie mix, cinnamon rolls, cantaloupe, golden syrup, pancake syrup, semi skimmed milk | joined to the generic term → own concept | Each is a kind of the generic product. Its German compound has its own key too. |
| maple syrup | sirup → own concept | Same reason. It should name `ahornsirup` once the German draft ships that term. |
| skimmed milk | milch → own concept, with the form `skim milk` | Same reason. `skim milk` is the US name for the same product. |
| chicken stock, vegetable stock | brühe → own concept, with the forms `chicken broth` and `vegetable broth` | Kinds of stock. The forms are the US names. |
| greek yogurt, vanilla extract | added the forms `greek yoghurt` and `vanilla essence` | UK spelling and UK name. |
| condensed milk | kondensmilch → own concept | German Kondensmilch is evaporated milk. `evaporated milk` keeps kondensmilch. |
| chicken drumsticks | schenkel → own concept | A drumstick is the lower leg only. `chicken thighs` keeps schenkel. |
| hot dog buns | brötchen → own concept | A hot dog bun is not a bread roll. |
| blackcurrants | johannisbeere → own concept | Johannisbeeren on a German list are the red ones. `redcurrants` keeps johannisbeere. |
| crab | krabbe → own concept | German Krabben are North Sea shrimp. |
| octopus | tintenfisch → own concept | Tintenfisch is squid, and `squid` keeps it. An octopus is a Krake or Pulpo. |
| oyster mushrooms | kräuterseitling → own concept | Kräuterseitling is the king oyster mushroom. The oyster mushroom is the Austernpilz. |
| gammon | kasseler → own concept | Gammon is cured leg. Kasseler is smoked loin or neck. |
| cereal bars, granola bars, sandwich bags, vanilla extract | riegel, beutel, aroma → own concept | These German terms are catch-all heads: any bar, any bag, any flavouring. |
| popsicles | wassereis → stieleis | `ice lollies` is stieleis. The US and UK words name one product. |
| earplugs, light bulbs, hairspray, mangetout | added the forms `ear plugs`, `lightbulbs`, `hair spray` and `mangetout peas` | Without them, plug (Stecker) took ear plugs to electrical and peas took mangetout peas to frozen. |
| red peppers, green peppers | kept on paprika, with a note | As an own concept, red peppers took red pepper flakes and crushed red pepper to produce. |

## Rejects

| Row | Why |
| --- | --- |
| skim milk → milch | It is now a form of `skimmed milk`, the same product. |

## Added rows

These are common words that both `dictionary.en.tsv` and the draft lacked, or that a short head
filed in the wrong aisle:

- toilet rolls and loo roll (rolls took them to bakery)
- tea lights (`dictionary.en.tsv` has only the singular)
- hamburger buns, yams, lambs lettuce (feldsalat) and phyllo dough
- tomato sauce, fish sauce (fish took it to meat), beef stock (with the form beef broth) and lard
  (schmalz)
- club soda and seltzer (mineralwasser; soda alone is a soft drink)
- root beer (beer would join it to Bier)
- gift wrap, hand wash (handseife), dishwasher detergent (detergent alone means laundry), foil and
  dryer sheets
- mint sauce and mixed herbs (the fresh herb heads took them to produce)
- soda crystals (with the form washing soda) and caustic soda (both went to drinks)
- peanut butter cups (sweets; chilled on main, pantry with the draft)

## Kept wrong regressions

In each of these, the head word is far more common than the compound. A row for each compound would
cost more than the error.

| Compound | Aisle with the draft | Caused by |
| --- | --- | --- |
| bike oil, motor oil, oil cloth, cod liver oil | pantry | oil |
| fruit bowl, fruit fly trap, fruit knife | produce | fruit |
| herb pots | produce | herbs |
| fennel seeds | produce | fennel |
| pumpkin pie | produce | pumpkin |
| peppermint | produce | mint |
| dried figs | produce | figs |
| red pepper paste | produce | red peppers |
| pea protein | frozen | peas |
| fries seasoning | frozen | fries |
| soup bowls | pantry | soup |
| nutmeg grinder | pantry | nutmeg |
| candles for cake | bakery | cake |
| biscuit mix | sweets | biscuits |
| iced tea powder | drinks | iced tea |
| Sorbetschale | frozen | sorbet (as Weinglas goes to drinks on main) |
| pancake batter | bakery, was household | pancakes (chilled would be right) |

The private copy found two German look-alikes that the official set does not test. German *Beet*
(a garden bed) goes to produce: the generator derives `beet` from `beets`. *Sander*, a rarer name
for the fish Zander, goes to tools. Zander itself stays meat. Neither word appears on a shopping
list.

## Open questions

Each question is phrased so that "yes" means the review's answer stands.

| ID | Question | Suggested answer |
| --- | --- | --- |
| EN1 | Some words mean different things in the US and the UK: chips, soda, biscuits, jelly, pudding, kitchen towels. Keep the sense the draft chose? That is US chips (sweets; the UK chips are `oven chips` and `fries`), US soda (drinks), UK biscuits (sweets), US jelly (pantry), US pudding (chilled), and kitchen towels in household. | Yes. Each word lands in a plausible aisle in both countries, except chips in the UK. |
| EN2 | Is a kind of a product its own concept (greek yogurt, red lentils, chicken stock), and not joined to the generic German term? | Yes. That is how German compounds behave (see "What was checked"). The cost is that German "Hühnerbrühe" and English "chicken stock" do not share a key. |
| EN3 | May popsicles, jello, spackle and allen key ship? They are trademarks that people use as generic words. | Yes, as plain text, like `coke` in the German draft. Otherwise, use ice pops, gelatin dessert, wall filler and hex key. |
| EN4 | May condoms and nappy cream or diaper cream ship? They are medical devices or near-medicines, and the drafter left plasters out. | Yes. They only join concepts that main already has (`kondom`, `wundschutzcreme`). |
| EN5 | May `baby formula` → babymilch ship? It is infant formula (EU 609/2013), the same case as CD11. | Yes. The row only sets an aisle. |
| EN6 | The German draft `2026-11-16-claude.tsv` holds 183 of the same English words. Who wins? Most of them agree. Six point to another concept: shrimp (garnele there, shrimps here), pickles (gewürzgurken or essiggurken), dog biscuits (hundekeks or hundesnack), baby wipes (feuchttücher or babytücher), rocket (rucola or rauke), sweetcorn (mais or zuckermais). Eighteen are own concepts or forms here but terms or synonyms there: pancetta, ginger beer, guacamole, sorbet, salsa, split peas, matcha, pancake syrup, red pepper flakes, crushed red pepper, mince pies, maple syrup, condensed milk, walnuts, hazelnuts, pumpkin seeds, cereal bars and pancake mix. Whichever draft ships second fails `parseWords` or `languageTables` until it is reconciled. | Drop the English rows from the German draft. Keep its German terms (walnuss, haselnuss, kürbiskerne, ahornsirup, müsliriegel) and point the English words at them. English words belong in `dictionary.en.tsv` now. |
| EN7 | Keep red peppers and green peppers on paprika, so they share a key with bell peppers and with each other? | Yes, for now. An own concept breaks red pepper flakes until the matcher prefers a longer synonym over a shorter term. |
| EN8 | Keep `beets` when German *Beet* (a garden bed) then goes to produce, and keep `sander` when *Sander* (the fish) goes to tools? | Yes. Neither German word is written on a shopping list. |

Peter's answers (26 Nov 2026, 20:07 CET, t1388u): yes to every suggested answer, EN1 to EN8. EN1 to
EN5, EN7 and EN8 keep the rows as they are. EN6: the German draft's 199 English rows are dropped; its
German terms stay. Once it is accepted, walnuts, hazelnuts, pumpkin seeds, maple syrup and cereal
bars get walnuss, haselnuss, kürbiskerne, ahornsirup and müsliriegel as their concept (those terms
are not in `dictionary.tsv` yet, so this PR cannot point them there).
