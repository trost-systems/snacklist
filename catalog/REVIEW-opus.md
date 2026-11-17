# Opus review of the 2026-11-16 draft (job 283)

Claude Opus 5.5 checked every row of `drafts/2026-11-16-claude.tsv` (job 279) against common German
and English grocery usage: the word, what it joins to (synonym rows), and its aisle (term rows). The
rows set nothing else. There is no store field: the store follows from the aisle.

This is a machine review. It does not replace the person's review that Legal N-215 requires, so the
`review` column stays empty on every row. A person still writes `accept` or `reject` per row
(`REVIEW.md`, "How to review").

## Counts

Of the 519 drafted rows:

| Result | Rows |
| --- | --- |
| ok | 496 |
| fixed | 9 |
| dropped | 0 |
| doubtful | 14 |

The doubtful rows are questions CD1 to CD15 below. CD14 asks about the fixed `russ`. Each question
is phrased so that "yes" means accept the row as it stands. The review also added 23 rows. Each one
fixes a wrong aisle that a draft row causes or leaves in place. Fixed and added rows carry the source
`opus-review`, so the TSV alone shows what the review changed. The draft now has 542 rows: 240
dictionary terms and 302 synonyms.

Legal conditions (N-215): no row or note states an allergen, nutrition or health fact. None of
the input was user data or Open Food Facts. The review used the catalog TSVs and general knowledge
only, and it removed nothing on these grounds. The draft left out diet products. `säuglingsmilch`,
`beikost` and `baby food` are infant food, which EU law (609/2013) counts as food for specific
groups. They only set an aisle (drugstore, as `babynahrung` already does on main), but CD11 to CD13
ask about them anyway.

## Evidence

Run on a local stack (job 283's own port block) with `supabase/classifier/probe_drafts.sh`.

- The draft as job 279 left it gives 472 `gap`, 39 `key` and 8 `redundant` (the canonicals), the
  same numbers as in `REVIEW.md`.
- After this review, the 542 rows give 493 `gap`, 39 `key` and 10 `redundant`. No row is `broken`
  or `listed`. The two new `redundant` rows are needed even though their aisle doesn't change.
  `weinschorle` is a term so that it gets its own key. `red pepper flakes` is the canonical for
  `crushed red pepper`, and it keeps both phrases off `red pepper`.
- No dictionary term, synonym, `wordlist.tsv` or `sweep.tsv` word changes aisle.
- `probe_compounds.txt` has 286 more texts, in the section "Job 283". They are words that end in a
  draft row's term or fold close to one (Nussknacker, Thüringer Klöße, fabric conditioner, Pinkel,
  Gruß), and the usual compounds of the English synonyms (red pepper flakes, snow peas, pancake
  mix). The review used them to find the wrong aisles below. With the whole draft loaded, 188 of
  the file's 455 texts change aisle.
- `accept()` from `accept_drafts.ts`, with every row set to `accept`, parses the catalog: 240 terms
  and 302 variants.

## Every change

### Fixed rows

| Row before | Row after | Reason |
| --- | --- | --- |
| `synonym russ → radler` (low) | `term russ → drinks` (low, CD14) | A Russ (Russn) is Weißbier with lemonade. A Radler is Helles with lemonade. They are two drinks, so they must not share a key, which would make the app offer to merge them. As a term, Russ goes to drinks on its own key. Side effect: Gruß and Ruß, which nobody puts on a shopping list, now land in drinks. |
| `synonym platzerl → keks` | `synonym platzerl → plätzchen` | Platzerl is the Bavarian and Austrian word for Plätzchen, not for biscuits in general. The draft lists `plätzchen`, so the variant joins that key. The aisle (sweets) stays the same. |
| `term klöße → pantry` | `synonym klöße → knödel` | Kloß is the northern and central German word for Knödel. It is one dish, so it gets one key. The aisle stays pantry, since `knödel` is pantry. |
| `synonym dunkles → bier` | `term dunkles → drinks` | People buy Dunkles as its own kind next to plain beer, so it shouldn't share Bier's key. |
| `synonym printen → lebkuchen` | `term printen → sweets` | Printen are Aachen's hard gingerbread, not Lebkuchen. |
| `synonym weinschorle → schorle` | `term weinschorle → drinks` | Outside the Palatinate, Schorle alone mostly means Apfelschorle, so a wine spritzer gets its own key. |
| `synonym frizzante → prosecco` | `term frizzante → drinks` | Frizzante is a style (semi-sparkling), and many frizzante wines are not Prosecco. |
| `synonym schampus → champagner` | `synonym schampus → sekt` | Colloquially, Schampus means sparkling wine, mostly Sekt. |
| `synonym apfelmost → cider` | `term apfelmost → drinks` | Most means cider in some regions and apple juice in others, so it gets its own key. Without any row, Apfelmost goes to pantry, so rejecting the row would leave a wrong aisle. |

### Added rows

| Row | Wrong aisle it fixes | Caused by |
| --- | --- | --- |
| `synonym thüringer klöße → kartoffelklöße` | Thüringer Klöße → meat | `term thüringer → meat`: the longest word of a phrase wins |
| `term nussknacker → household` | Nussknacker → meat (pantry today) | `term knacker → meat` |
| `term mince pie → bakery` | mince pie → meat | `synonym mince → hackfleisch` |
| `synonym mince pies → mince pie` | mince pies → meat | the same; the singular term does not reach the plural |
| `synonym fabric conditioner → weichspüler` | fabric conditioner → drugstore | `synonym conditioner → spülung` |
| `synonym sanitary napkins → binde` | sanitary napkins → household | `synonym napkins → servietten` |
| `synonym dog biscuits → hundekeks` | dog biscuits → sweets | `synonym biscuits → keks` |
| `synonym burger bun → burgerbrötchen` | burger bun → meat (today too) | the draft has only `burger buns`; `burger` alone is meat |
| `synonym figs → feige` | figs → other | the draft has only `fig`, which does not reach the plural |
| `synonym sauerkappes → sauerkraut` | Sauerkappes → produce | `synonym kappes → weißkohl` (Sauerkappes is Rhineland for Sauerkraut) |
| `synonym sugar snap peas → zuckerschoten` | sugar snap peas → frozen (pantry today) | `synonym peas → erbse` |
| `synonym snap peas → zuckerschoten` | snap peas → frozen | `synonym peas → erbse` (US name) |
| `synonym mangetout → zuckerschoten` | mangetout → other | the UK name was missing |
| `synonym snow peas → zuckerschoten` | snow peas → frozen | `synonym peas → erbse` (the usual US name) |
| `synonym mangetout peas → zuckerschoten` | mangetout peas → frozen | `synonym peas → erbse` |
| `synonym kaiserschoten → zuckerschoten` | Kaiserschoten → other | the AT/CH name was missing |
| `term split peas → pantry` | split peas → frozen | `synonym peas → erbse` (split peas are dried) |
| `term red pepper flakes → pantry` | red pepper flakes → produce (pantry today) | `synonym red pepper → paprika` |
| `synonym crushed red pepper → red pepper flakes` | crushed red pepper → produce (pantry today) | `synonym red pepper → paprika` |
| `synonym cake mix → backmischung` | cake mix → bakery | `synonym cake → kuchen` |
| `synonym pancake mix → backmischung` | pancake mix → bakery | `synonym pancakes → pfannkuchen` |
| `term pancake syrup → pantry` | pancake syrup → bakery | `synonym pancakes → pfannkuchen` |
| `term dried figs → pantry` | dried figs → produce | `synonym figs → feige` (dried fruit is pantry) |

### Rows to accept or reject together

These 14 synonyms point to a canonical that is only a draft term. If the term is rejected and the
synonym accepted, `accept_drafts.ts` refuses the whole run (for example: `canonical
"kartoffelklöße" is not in dictionary.tsv`). Decide each pair together:

- `pumpkin seeds` → `kürbiskerne`
- `thüringer klöße` → `kartoffelklöße`
- `mince pies` → `mince pie`
- `maple syrup` → `ahornsirup`
- `walnuts` → `walnuss`
- `hazelnuts` → `haselnuss`
- `dog biscuits` → `hundekeks`
- `cereal bars` → `müsliriegel`
- `platzerl` → `plätzchen`
- `crushed red pepper` → `red pepper flakes`
- `staubzucker` → `puderzucker`
- `powidl` → `pflaumenmus`
- `maroni` → `marone`
- `rübensirup` → `zuckerrübensirup`

### Dropped rows

None. Each row the review was sure about could be made right, so it is fixed above.

## Doubtful rows

These are the rows where the review is not sure. There is one line per row, and "yes" means accept
the row as it stands.

| ID | Row | Question | Suggested answer |
| --- | --- | --- | --- |
| CD1 | `helles` → `bier` | Keep Helles on Bier's key, so the app offers to merge the two on one list? | yes, because in Bavaria Helles is the plain beer. |
| CD2 | `kölsch` → `bier` | Keep Kölsch on Bier's key? | yes, because in Cologne Kölsch is the plain beer. |
| CD3 | `pancakes` → `pfannkuchen` | Keep English pancakes on Pfannkuchen's key, when Pfannkuchen means Berliner in Berlin and the east? | yes, because most of the country means pancakes. |
| CD4 | `weinbeeren` → `rosine` | Keep Weinbeeren as raisins (south, AT and CH), when it means grapes elsewhere? | yes, because on a list grapes are written Trauben. |
| CD5 | `korinthen` → `rosine` | Keep currants on the raisins' key, so the app offers to merge Korinthen and Rosinen? | yes, because they go on the same shelf. Recipes tell them apart, though. |
| CD6 | `macadamia` → sweets | Keep macadamias in sweets (the snack-nut rule), when "Macadamianüsse" stays pantry and Macadamiaöl goes to sweets with it? | yes, because they mostly sell as a snack nut. |
| CD7 | `morchel` → produce | Keep morels in produce like `steinpilz` on main, when most are sold dried? | yes, to stay consistent with main. |
| CD8 | `sauerkirschen` → pantry | Keep sour cherries in pantry (the jar) rather than produce? | yes. |
| CD9 | `strudel` → bakery | Keep Strudel in bakery, when it is common frozen too? | yes, because "TK Strudel" still goes to frozen. |
| CD10 | `aioli` → pantry | Keep Aioli in pantry (jars), when "Aioli Dip" then moves from chilled to pantry? | yes. |
| CD11 | `säuglingsmilch` → drugstore | May the catalog file infant formula (EU 609/2013 food for specific groups) when Legal ruled out diet products? | yes, because the row only sets an aisle. |
| CD12 | `beikost` → drugstore | May the catalog file baby food under the same rule? | yes, for the same reason as CD11. |
| CD13 | `baby food` → `babynahrung` | May the English name join `babynahrung`, which is already on main? | yes, for the same reason as CD11. |
| CD14 | `russ` → drinks (fixed, low) | Keep Russ as a drinks term, when Ruß and Gruß then join its key? | yes, because neither goes on a shopping list. |
| CD15 | `apfelstrudel` → bakery | Keep Apfelstrudel in bakery? | yes, for the same reason as CD9. |

These rows count as ok:

- **The 14 short heads.** `oil`, `egg`, `fruit`, `cake`, `mint`, `pumpkin`, `fennel`, `herbs`, `soup`,
  `nutmeg`, `plätzchen`, `pretzel`, `grappa` and `sorbet` file some compounds in a wrong aisle
  (`REVIEW.md`, "Short heads"), but the plain words are far more common.
- **`pistazienkerne` → sweets.** Main already files plain Pistazien in sweets. Rejecting the row
  would put Pistazien and Pistazienkerne in different aisles.
- **`honigkuchen` → `lebkuchen`, `hörnchen` → `croissant`, `germ` → `hefe`, `sauerteig` → pantry,
  `sourdough` → `sauerteigbrot` and `kabis` → `weißkohl`.** Their side effects are minor:
  Eichhörnchen goes to bakery, wheat germ joins Hefe's key, sourdough starter goes to bakery, and
  Rotkabis joins white cabbage's key.
- **The rows `REVIEW.md` listed as unsure.** `magenbrot` and `baumkuchen` (supermarkets shelve them
  with sweets), `cordon bleu` ("TK" still sends the frozen kind to frozen), `guacamole`, `teigwaren`
  (Eierteigwaren now goes to pantry too), `würze`, `dinkel` and `anzünder` (every measured compound
  lands right), `meatballs` (the singular joins too), `buns`, `insect repellent`, the stationery
  rows, and `meisenknödel`.

Compounds that still land in a wrong aisle with the draft, all rare on a German list: cod liver oil
→ pantry, "Schweineohren für Hunde" → bakery, red pepper paste and roasted red peppers → produce,
cherry pie filling → produce, egg replacer → chilled, fries seasoning → frozen, and mushy peas →
frozen.

## Wrong matches for job 282 (the matcher)

These need a change to `public.classify_item`, not a catalog row. They are reported here and not
fixed (job 282 owns the matcher):

- **Folding onto another word**, as already in `REVIEW.md`: beer → produce (beere), rolls →
  household (rolle), sage → tools (säge), schäufele → garden (schaufel). The same fold sends
  cinnamon rolls and fig rolls to household.
- **A fuzzy match beats the exact head.** Macadamiaöl goes to sweets by a fuzzy match on
  `macadamia`, although it ends in `öl` (pantry). Kloßteig goes to household by a fuzzy match on
  main today.
- **A fuzzy match on main that the draft only hides.** Pinkel goes to paint (Pinsel), and black
  bean goes to paint. Black eyed peas goes to paint even with the draft, and pancake batter goes to
  household. The draft's rows fix both words, but the fuzzy distance that caused them
  stays.
- **The longest word of a phrase wins, wherever it stands.** Thüringer Klöße goes to meat by
  `thüringer`, and the review added a row to fix it. Macadamia Nüsse goes to sweets while
  Macadamianüsse goes to pantry. Several English phrases get the aisle of their first word instead
  of their head: grapefruit juice → produce, cocoa butter → chilled, coriander seeds → produce,
  peanut butter cups → pantry.

## Forms the draft does not reach

These English singular forms fall back to `other`, because their plural row does not reach them:
baby wipe, wet wipe, razor blade, cotton bud, cotton pad, stock cube, ice cube, bin bag, bun, pea,
pickle, nappy, fry. They are not wrong, only missing. People mostly type the plural on a list.
The review added only `burger bun` (which goes to meat today) and `figs`. The rest are for the next
draft.
