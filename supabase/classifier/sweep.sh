#!/usr/bin/env bash
# Classifies every item in sweep.tsv and in each language's expected.<lang>.tsv (job 470) on the
# local stack and prints the rows whose category differs from the expected one (item, expected,
# actual). Exits 1 if any differ.
# --print writes the file back with the actual categories, to refresh it after a deliberate change:
#   ./sweep.sh --print > sweep.new && mv sweep.new sweep.tsv
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
project_id="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' "$here/../config.toml")"
# A language's rows are classified for a household with a Baumarkt, so DIY words show as themselves.
expected=()
if [[ ${1:-} != --print ]]; then expected=("$here"/expected.*.tsv); fi
rows="$({ grep -v '^#' "$here/sweep.tsv" | sed 's/$/\t0/'; cat "${expected[@]}" /dev/null | { grep -v '^#' || true; } | sed 's/$/\t1/'; } | python3 -I -c 'import sys, json; print(json.dumps([l.rstrip("\n").split("\t") for l in sys.stdin if l.strip()]))')"
result="$(docker exec -i "supabase_db_$project_id" psql -U postgres -v ON_ERROR_STOP=1 -At -F $'\t' <<SQL
begin;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f9', 'sweep@example.com'),
  ('00000000-0000-0000-0000-0000000000fa', 'sweep-diy@example.com');
create temp table rows as
select n, r->>0 as text, coalesce(r->>1, '') as expected, (r->>2)::integer as diy
from json_array_elements(\$rows\$$rows\$rows\$::json) with ordinality t(r, n);
grant select on rows to authenticated;
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000f9", "role": "authenticated"}', true);
create temp table h as select id from public.create_household('Sweep');
select r.text, r.expected, c.seed_key
from rows r join public.categories c on c.id = public.classify_item((select id from h), r.text)
where r.diy = 0 order by r.n;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000fa", "role": "authenticated"}', true);
create temp table hd as select id from public.create_household('Sweep DIY', false, '{Baumarkt}');
select r.text, r.expected, c.seed_key
from rows r join public.categories c on c.id = public.classify_item((select id from hd), r.text)
where r.diy = 1 order by r.n;
rollback;
SQL
)"
if [[ ${1:-} == --print ]]; then
  grep '^#' "$here/sweep.tsv"
  awk -F'\t' 'NF == 3 { print $1 "\t" $3 }' <<<"$result"
  exit 0
fi
diff="$(awk -F'\t' 'NF == 3 && $2 != $3' <<<"$result")"
total="$(awk -F'\t' 'NF == 3' <<<"$result" | wc -l)"
if [[ -n $diff ]]; then
  echo "$diff"
  echo "$(wc -l <<<"$diff") of $total items differ" >&2
  exit 1
fi
echo "$total items match" >&2
