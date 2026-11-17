#!/usr/bin/env bash
# Job 279: what a catalog draft (catalog/drafts/*.tsv, catalog/REVIEW.md) would change, on the local
# stack. In one rolled-back transaction it classifies each draft row's text and the regression set
# (every dictionary term, synonym, wordlist.tsv, sweep.tsv and probe_compounds.txt text), loads the draft's rows into the
# classifier, refreshes the lexicon and classifies them again. Prints a TSV report:
#   draft  <kind> <text> <value> <expected> <before> <before via> <after> <after via> <status>
#   regress <text> <before> <after>        (only texts whose category the draft changes)
# status: gap (the draft fixes a miss or a wrong category), key (category already right, the draft
# joins the canonical's key), redundant (nothing changes), broken (still not the expected category,
# or a synonym whose key does not equal its canonical's),
# listed (the text is already a dictionary term or synonym; the draft row is not loaded).
# --rows accept|all: which rows to load (default all; accept loads only rows reviewed "accept").
# CLASSIFIER_PSQL="psql -h ... -d ..." runs it against another database (default: the local stack).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rows_filter=all
if [[ ${1:-} == --rows ]]; then rows_filter="$2"; shift 2; fi
draft="${1:?usage: probe_drafts.sh [--rows accept|all] <draft.tsv>}"
project_id="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' "$here/../config.toml")"
db() {
  if [[ -n ${CLASSIFIER_PSQL:-} ]]; then $CLASSIFIER_PSQL "$@"; else docker exec -i "supabase_db_$project_id" psql -U postgres "$@"; fi
}
rows="$(python3 -I - "$draft" "$rows_filter" <<'PY'
import json, sys
path, which = sys.argv[1], sys.argv[2]
out, header = [], None
for line in open(path, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    cells = line.split("\t")
    if header is None:
        header = cells
        continue
    row = dict(zip(header, cells))
    if which == "accept" and row.get("review") != "accept":
        continue
    out.append([row["kind"], row["term"], row["value"]])
print(json.dumps(out, ensure_ascii=False))
PY
)"
texts="$(cat "$here/wordlist.tsv" "$here/sweep.tsv" "$here/probe_compounds.txt" | grep -v '^#' | cut -f1 | python3 -I -c 'import sys, json; print(json.dumps(sorted({l.strip() for l in sys.stdin if l.strip()}), ensure_ascii=False))')"
db -q -v ON_ERROR_STOP=1 -At -F $'\t' <<SQL
begin;
create temp table d as
select n, r->>0 as kind, r->>1 as term, r->>2 as value,
  exists (select from public.classifier_terms where term = r->>1)
  or exists (select from public.classifier_synonyms where variant = r->>1) as listed
from json_array_elements(\$rows\$$rows\$rows\$::json) with ordinality t(r, n);
create temp table reg as
select term as text from public.classifier_terms
union select variant from public.classifier_synonyms
union select json_array_elements_text(\$texts\$$texts\$texts\$::json);
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f7', 'drafts@example.com');
grant all on d, reg to authenticated;
create temp table r (phase text, text text, seed_key text, via text, key text);
grant all on r to authenticated;
select set_config('role', 'authenticated', true) \g /dev/null
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000f7", "role": "authenticated"}', true) \g /dev/null
-- With a Baumarkt (job 151), like wordlist.sh: DIY categories show as themselves.
create temp table h as select id from public.create_household('Drafts', false, '{Baumarkt}');
insert into r select 'before', x.text, c.seed_key, c2.via, c2.canonical_key
from (select term as text from d union select value from d where kind = 'synonym' union select text from reg) x
cross join lateral public.classify_item_detail((select id from h), x.text) c2
join public.categories c on c.id = c2.category_id;
reset role;
insert into public.classifier_terms (term, category) select term, value from d where kind = 'term'
on conflict do nothing;
insert into public.classifier_synonyms (variant, canonical) select term, value from d where kind = 'synonym'
on conflict do nothing;
select public.refresh_classifier_lexicon() \g /dev/null
select set_config('role', 'authenticated', true) \g /dev/null
insert into r select 'after', x.text, c.seed_key, c2.via, c2.canonical_key
from (select term as text from d union select value from d where kind = 'synonym' union select text from reg) x
cross join lateral public.classify_item_detail((select id from h), x.text) c2
join public.categories c on c.id = c2.category_id;
select 'draft', d.kind, d.term, d.value, e.expected, b.seed_key, b.via, a.seed_key, a.via,
  case
    when d.listed then 'listed'
    when a.seed_key is distinct from e.expected then 'broken'
    when d.kind = 'synonym' and a.key is distinct from ca.key then 'broken'
    when b.seed_key is distinct from e.expected then 'gap'
    when d.kind = 'synonym' and b.key is distinct from ca.key then 'key'
    else 'redundant'
  end
from d
cross join lateral (
  select case when d.kind = 'term' then d.value
    else (select seed_key from r where phase = 'after' and text = d.value) end as expected
) e
join r b on b.phase = 'before' and b.text = d.term
join r a on a.phase = 'after' and a.text = d.term
left join r ca on ca.phase = 'after' and ca.text = d.value
order by d.n;
select 'regress', b.text, b.seed_key, a.seed_key
from r b join r a on a.text = b.text and a.phase = 'after'
where b.phase = 'before' and b.text in (select text from reg) and a.seed_key <> b.seed_key
  and b.text not in (select term from d)
order by b.text;
rollback;
SQL
