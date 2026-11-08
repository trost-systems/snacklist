#!/usr/bin/env bash
# Job 59: public.suggest_entries stays well under 50 ms per keystroke on a big household. Seeds one
# household with 5000 items over the last year (names, brands and sizes drawn from the classifier's
# terms), then times the inputs below, 5 rounds, as that member (RLS on), and prints p50/p95/max
# and the plan of the slowest input. Exits 1 when p95 is 50 ms or more. Everything is rolled back.
# --show prints the rows for each input instead. SUGGEST_PSQL="psql ..." runs it against another
# database (default: the local stack).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
project_id="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' "$here/../config.toml")"
db() {
  if [[ -n ${SUGGEST_PSQL:-} ]]; then $SUGGEST_PSQL "$@"; else docker exec -i "supabase_db_$project_id" psql -U postgres "$@"; fi
}
show=false
[[ ${1:-} == --show ]] && show=true
inputs="'Mi', 'Milch', 'milch', 'Hafermlch', 'Hafermi', 'Tomatn', 'Brot', 'Kase', 'Käse', 'Jogurt',
  'Schkolade', 'Zwibeln', 'Toilettenpapir', 'Bananen', 'Eis', 'Rote Bete', 'Spülmittel', '2 l Milch 1,5 %',
  'Windeln Pampers Größe 3', 'Apfl'"
seed="$(cat <<'SQL'
begin;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f9', 'suggest@example.com');
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000f9", "role": "authenticated"}', true);
create temp table h as select id from public.create_household('Suggest');
set local role postgres;
select setseed(0.59);
-- 400 distinct products, the first ones bought far more often, as in a real household.
create temp table products as
select row_number() over () as n, initcap(term) as name from (
  select term from public.classifier_terms order by md5(term) limit 400
) t;
set local session_replication_role = replica;
insert into public.items (household_id, list_id, category_id, name, normalized_name, brand, properties, status, bought_at, updated_at, created_at)
select (select id from h), public.first_list((select id from h)), (select c.id from public.categories c where c.household_id = (select id from h) and c.seed_key = 'other'),
  p.name, public.normalize_item_name(p.name),
  (array[null, null, 'Bio', 'Ja!', 'Alnatura', 'Milsani'])[1 + floor(random() * 6)::int],
  (array[null, null, null, '500 g', '1 l', 'laktosefrei'])[1 + floor(random() * 6)::int],
  'bought', a.at, a.at, a.at
from (select g, now() - random() * interval '364 days' as at, 1 + floor(400 * power(random(), 2.5))::int as n
      from generate_series(1, 5000) g) a
join products p on p.n = a.n;
set local session_replication_role = origin;
analyze public.items;
select set_config('role', 'authenticated', true);
SQL
)"
if $show; then
  db -v ON_ERROR_STOP=1 -q -At -F ' | ' <<SQL
$seed
select t.input, s.source, s.name, coalesce(s.brand, '-'), coalesce(s.properties, '-')
from unnest(array[$inputs]) with ordinality as t (input, o)
cross join lateral public.${SUGGEST_FN:-suggest_entries}((select id from h), t.input, 10) with ordinality as s
order by t.o, s.ordinality;
rollback;
SQL
  exit 0
fi
result="$(db -v ON_ERROR_STOP=1 -q -At -F $'\t' <<SQL
$seed
create temp table timings (input text, ms double precision);
grant all on timings to authenticated;
do \$\$
declare
  v_input text;
  v_at timestamptz;
  v_household uuid := (select id from h);
begin
  for round in 1..5 loop
    foreach v_input in array array[$inputs] loop
      v_at := clock_timestamp();
      perform * from public.${SUGGEST_FN:-suggest_entries}(v_household, v_input);
      insert into timings values (v_input, extract(epoch from clock_timestamp() - v_at) * 1000);
    end loop;
  end loop;
end \$\$;
select 'all', count(*), round(percentile_cont(0.5) within group (order by ms)::numeric, 2),
  round(percentile_cont(0.95) within group (order by ms)::numeric, 2), round(max(ms)::numeric, 2)
from timings;
select 'slowest', input, round(percentile_cont(0.5) within group (order by ms)::numeric, 2), '', ''
from timings group by input order by 3 desc limit 3;
rollback;
SQL
)"
report="$(awk -F'\t' '
  $1 == "all" { n = $2; p50 = $3; p95 = $4; mx = $5 }
  $1 == "slowest" { slow = slow sprintf("  %-26s p50 %6.2f ms\n", $2, $3) }
  END {
    printf "suggest_entries per call, 5000 items over a year, 20 inputs x 5 rounds: n=%d p50 %.2f ms, p95 %.2f ms, max %.2f ms (limit p95 < 50 ms)\n", n, p50, p95, mx
    printf "slowest inputs:\n%s", slow
    if (p95 >= 50) exit 1
  }' <<<"$result")" && status=0 || status=$?
echo "$report"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  { echo '### suggest_entries latency (job 59)'; echo; echo '~~~'; echo "$report"; echo '~~~'; } >>"$GITHUB_STEP_SUMMARY"
fi
exit "$status"
