# Reviewing catalog drafts

`catalog/drafts/` holds rows drafted for the classifier's catalog (`supabase/classifier/dictionary.tsv`
and `synonyms.tsv`) that no person has checked yet. Nothing in a draft reaches the app: a row ships
only after a reviewer accepts it and the accept script moves it into the catalog in its own PR.

The first draft is `drafts/2026-11-16-claude.tsv` (job 279, Legal Review S4, N-215): 519 rows,
229 dictionary terms and 290 synonyms, drafted by Claude. Claude Opus then reviewed it (job 283,
[`REVIEW-opus.md`](REVIEW-opus.md)). That review fixed 9 rows and added 23, all with source
`opus-review`. It asks about 15 rows as questions CD1 to CD15, each with a suggested answer, and
lists the rows to accept or reject together. The draft had 542 rows (240 terms and 302
synonyms); job 470 dropped its 199 English rows (EN6, `REVIEW-en.md`), which leaves 343. The Opus
review is
not the person's review that N-215 requires: every `review` cell is still empty.

## The rules the draft was made under

Legal's GO for S4 (Addendum A of the suggestions review) holds only with these conditions:

- The input was our own catalog TSVs and general knowledge. No user data, no household misses,
  nothing from Open Food Facts, no Wikipedia text, no Commons media.
- No allergen, nutrition or health facts. The schema has no field for them, and the notes name none.
  Medicines, supplements and diet products were left out.
- Brand names only as plain text, never logos. The draft has one brand, `coke` → `cola`, as plain
  text; `brands.tsv` is untouched.
- A person reviews every row before it ships.

Keep to the same rules when you edit a row: don't look a word up on Open Food Facts and copy what it
says. Looking a product up to understand it is fine; copying its name or category is not.

## The format

```
kind	term	value	source	confidence	review	note
```

| Column | Meaning |
| --- | --- |
| `kind` | `term`: a `dictionary.tsv` row (`term`, category in `value`). `synonym`: a `synonyms.tsv` row (variant in `term`, canonical in `value`). |
| `term`, `value` | As in the target file: lowercase, letters and single spaces only. |
| `source` | Who drafted the row: `claude-draft`. |
| `confidence` | `high`: a common word whose aisle follows the dictionary's placement rules. `medium`: a debatable aisle or a less common regional word. `low`: the drafter was unsure (listed below). |
| `review` | Empty until you decide: `accept` or `reject`. |
| `note` | Why: region, UK or US, what the word is, or which wrong aisle it gets today. |

Rows run high, medium, low, and within each the most common words first, so you can stop anywhere.

Every row was probed on a local stack before it went in (`supabase/classifier/probe_drafts.sh`): it
fixes a word the classifier misses or files in the wrong aisle today, joins a variant to its
canonical's key, or is a canonical that another row needs. That is 472 `gap`, 39 `key` and 8
canonicals.

What the probe can and cannot promise: loading the whole draft changes the aisle of no word in its
regression set, which is every dictionary term, synonym, `wordlist.tsv` and `sweep.tsv` word. Other
words can move. `probe_compounds.txt` adds 169 compounds built on the draft's short heads (baby oil,
rubber duck, egg timer, Dinkelmehl), and the probe prints each one whose aisle changes. With the
whole draft, 76 of them move. Most of those are fixes (Radiergummi to household, potato crisps to
sweets, Topfenstrudel to bakery). The ones that go to a wrong aisle are listed under "Short heads"
below.

## How to review

1. Open the draft in an editor or a spreadsheet that keeps tabs.
2. Per row, write `accept` or `reject` in `review`. To change a row, edit `term` or `value` and then
   accept it. A synonym needs its canonical in `dictionary.tsv` already, or its `term` row accepted
   with it (`walnuts` needs `walnuss`).
3. Optional, on a local stack (`supabase start` with your port block): see what the accepted rows do.

   ```
   supabase/classifier/probe_drafts.sh --rows accept catalog/drafts/2026-11-16-claude.tsv
   ```

   Each row should say `gap` or `key`. `broken` means the row does not get its aisle (a longer term
   wins) or a synonym does not share its canonical's key; `listed` means the word is in the catalog
   already. Each `regress` line is a word whose aisle the accepted rows change: check that the new
   aisle is right.

## How to accept

```
cd supabase/classifier
deno run --allow-read --allow-write accept_drafts.ts ../../catalog/drafts/2026-11-16-claude.tsv
```

The script:

- moves the `accept` rows to the end of `dictionary.tsv` and `synonyms.tsv`, under the heading
  `# Reviewed drafts from catalog/drafts/<file>`, and removes them from the draft;
- leaves `reject` and empty rows in the draft, so a rejection stays on record;
- writes the two migrations that load the new catalog
  (`supabase/migrations/<now>_classifier_dictionary_draft_<file>.sql` and `..._synonyms_...`);
- writes nothing if the catalog would not parse with the accepted rows (a repeated term, a synonym
  whose canonical is missing, an unknown category). The error names the line.

Running it again moves nothing. Then, on a local stack:

```
supabase db reset                               # applies the new migrations
supabase/classifier/client_catalog.sh           # the catalog the app bundles
scripts/verify.sh --only functions,db           # parsing, migrations, wordlist and sweep
```

Open the PR with the TSVs, the two migrations, `app/lib/list/catalog/catalog_index.g.dart` and the shorter
draft. Its `## Changelog` item is `improved` (the app now recognises more words). If main gets a
newer migration before you land, delete the two generated migrations, run `generate.ts` and
`generate_synonyms.ts` into fresh ones (their headers say how), and rerun `client_catalog.sh`.
Delete the draft file once no row waits for review.

## Language drafts (job 470)

A draft of another language's words (English: `drafts/2026-11-26-en.tsv`, reviewed in
[`REVIEW-en.md`](REVIEW-en.md)) has its own header:

```
lang	word	category	concept	forms	source	confidence	review	note
```

Its rows go to `supabase/classifier/dictionary.<lang>.tsv` (format in that file's header and in
`supabase/classifier/languages.ts`): the word the language's catalog offers, its aisle, the
`dictionary.tsv` term it is (`concept`, empty for a concept of its own) and extra spellings. The
same rules hold (N-215, no brands, no medicines), the same review and the same commands:
`probe_drafts.sh` loads the terms and synonyms the words make (`draft_rows.ts`), and
`accept_drafts.ts` moves the accepted rows and writes both migrations from every TSV.
`expected.<lang>.tsv` is the language's exam, written apart from its words; `sweep.sh` (db gate)
and the app's `catalog_language_test.dart` require every row's aisle.

## Rows the drafter was unsure about

Low confidence:

| Row | Why unsure |
| --- | --- |
| `russ` → drinks | Bavarian, more often written "Russn". Job 283 made it a term, because a Russ is not a Radler. Gruß and Ruß land in drinks with it (`REVIEW-opus.md`, CD14). |
| `sauerkirschen` → pantry | Mostly bought in a jar, but fresh sour cherries are produce. |

Medium rows that deserve a second look. `REVIEW-opus.md` turns these into one question per row
and fixes, and that list (CD1 to CD15) is the one to answer:

| Row | Question |
| --- | --- |
| `apfelstrudel`, `strudel` → bakery | Frozen strudel is common too. A "TK" in the name sends it to frozen anyway. |
| `macadamia` → sweets | Follows "snack nuts are sweets", but they are also a baking nut. |
| `magenbrot`, `baumkuchen` → sweets | Sold on the sweets shelf in the supermarket, but also at the bakery. |
| `cordon bleu` → meat | Also sold frozen. |
| `guacamole` → chilled, `aioli` → pantry | Fresh dips are chilled, jars pantry. |
| `sauerteig` → pantry | Dry sourdough sits with baking; fresh sourdough is chilled. |
| `hörnchen` → `croissant` | North German. Hörnchen are also crescent pastries of other kinds. |
| `teigwaren` → `nudel` | Broad (CH/AT for pasta in general). |
| `helles`, `dunkles`, `kölsch` → `bier` | Kinds of beer joined to plain beer: they share a key. When one is added while the other is open on the list, the app offers to merge them, MCP, Siri and voice say a similar item is on the list, and they share one store memory. The add sheet shows no hint while typing. |
| `printen`, `honigkuchen` → `lebkuchen` | Regional relatives, not the same biscuit. Same shared-key question. |
| `frizzante` → `prosecco`, `weinschorle` → `schorle` | A style joined to a product. |
| `germ` → `hefe` | AT/Bavarian for yeast, and a short word. The probe found no compound it breaks. |
| `würze`, `dinkel`, `anzünder` | Short heads that will also catch compounds. The compounds the probe measured move only to the right aisle (Speisewürze to pantry, Kaminanzünder to household). |
| `meatballs` → `bällchen`, `buns` → `brötchen` | Loose English words. |
| `insect repellent` → `mückenschutz` | Drugstore by the dictionary; some shops shelve it with household. |
| `bleistift`, `radiergummi`, `klebestift` → household | Stationery has no aisle; household is the nearest. |
| `meisenknödel` → household | Bird food, filed with pet food. |

### Short heads that file some compounds wrongly

These rows are common shopping-list words, so the draft keeps them: the English heads at medium,
`plätzchen` and `pretzel` at high, since the word alone is far more common than these compounds. With them
loaded, the probe measured these compounds, which are `other` today, in a wrong aisle. Where the
dictionary has the right word, the draft pairs the head with a compound row (`baby oil` → `babyöl`,
`body oil`, `hair oil`, `massage oil`, `lamp oil`, `dried fruit` → `trockenobst`, `cake tin` →
`kuchenform`, `pumpkin seeds` → `kürbiskerne`). The rest stay wrong if you accept the head:

| Row | Compounds that land in a wrong aisle |
| --- | --- |
| `oil` → `öl` | motor oil, bike oil, oil cloth → pantry |
| `egg` → `ei` | egg cups, egg timer → chilled (German Eierbecher is chilled on main already) |
| `fruit` → `obst` | fruit bowl, fruit fly trap, fruit knife → produce; fruit gums → produce (sweets is right) |
| `cake` → `kuchen` | candles for cake → bakery; cake mix, pancake mix → bakery (pantry is right) |
| `mint` → `minze` | breath mints, peppermint → produce |
| `pumpkin` → `kürbis` | pumpkin spice, pumpkin pie → produce |
| `fennel` → `fenchel`, `herbs` → `kräuter` | fennel seeds, herb pots → produce |
| `soup` → `suppe`, `nutmeg` → `muskat` | soup bowls, nutmeg grinder → pantry |
| `plätzchen` → sweets | Plätzchenausstecher, Plätzchendose → sweets (household is right). Today Plätzchen itself is drugstore. |
| `pretzel` → `brezel` | pretzel sticks → bakery (Salzstangen are snacks, sweets) |
| `grappa`, `kölsch`, `sorbet` | Grappaglas, Kölsch Glas → drinks, Sorbetschale → frozen. Main does the same for Weinglas and Bierglas (→ drinks): a dish named after what it holds goes to that aisle. |

The draft dropped `duck` → `ente`, which put rubber duck and duck tape in meat.

## What a draft row cannot fix

The probe found words the classifier gets wrong today that no `term` or `synonym` row can fix,
because the word folds to the key of an existing term. They need a change to
`public.classify_item` or the folding rules, not a catalog row:

- `beer` → produce (it folds to `beere`), `rolls` → household (`rolle`), `sage` → tools (`säge`).
- `schäufele` (a Franconian pork shoulder) → garden: it folds to `schaufel`.
- `Rohrnudeln` is pantry in `wordlist.tsv`, but it is a baked yeast bun (bakery). The draft leaves
  it alone because changing it changes the word list's expectation.
