#!/usr/bin/env bash
# Seeds the account the AI directory reviewers sign in with (job 415, docs/connectors/README.md):
# one household with the stores dm, Lidl, Edeka and IKEA, each in its usual sections, and synthetic
# sample items. The user must exist already (created confirmed, with a password, by Ops).
# Safe to run again: the household is found by a request id derived from the user id, a store that
# exists is kept, and an item already open on the list is not added twice.
# Never run against production from CI. The lead runs it by hand after merge.
# Usage: AI_REVIEWER_DB_URL=<postgres URL of the target database> scripts/seed-ai-reviewer.sh <user-id>
# The URL carries the database password: pass it in the environment, never on the command line.
set -euo pipefail

[[ $# == 1 && "$1" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "usage: $0 <user-id (uuid)>" >&2; exit 2; }
: "${AI_REVIEWER_DB_URL:?set AI_REVIEWER_DB_URL to the target database URL}"
uid="$1"

[[ "$(psql "$AI_REVIEWER_DB_URL" -Atc "select count(*) from auth.users where id = '$uid'")" == 1 ]] ||
  { echo "no such user: $uid" >&2; exit 3; }

psql "$AI_REVIEWER_DB_URL" -v ON_ERROR_STOP=1 -v uid="$uid" -q -t -A <<'SQL'
begin;
-- Act as the user, like the app does: the functions below read auth.uid().
select set_config('request.jwt.claims',
  json_build_object('sub', :'uid', 'role', 'authenticated')::text, true) \gset
set local role authenticated;

select h.id as household from public.create_household(
  p_request_id => md5('ai-reviewer:' || :'uid')::uuid,
  p_name => 'Haushalt Beispiel (Testkonto)',
  p_default_stores => false
) h \gset

\o /dev/null
select public.add_store(:'household'::uuid, s) from unnest(array['dm', 'Lidl', 'Edeka', 'IKEA']) s;

select public.add_item(:'household'::uuid, i.text, st.id)
from (values
  ('Milch', 'Lidl'), ('Bananen', 'Lidl'), ('Haferflocken', 'Lidl'),
  ('Zahnpasta', 'dm'), ('Shampoo', 'dm'), ('Taschentücher', 'dm'),
  ('Nudeln', 'Edeka'), ('Tomaten', 'Edeka'), ('Brot', 'Edeka'),
  ('Kerzen', 'IKEA'), ('Bilderrahmen', 'IKEA')
) as i (text, store)
join public.stores st on st.household_id = :'household'::uuid
  and public.store_name_key(st.name) = public.store_name_key(i.store);
\o

reset role;
select 'household ' || :'household' || ': ' ||
  (select count(*) from public.stores where household_id = :'household'::uuid) || ' stores, ' ||
  (select count(*) from public.items where household_id = :'household'::uuid and status = 'active')
  || ' open items';
commit;
SQL
