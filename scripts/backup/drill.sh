#!/usr/bin/env bash
# Restore drill against the local stack, run by the db gate: fixture data in every backed-up
# table, dump.sh with a throwaway age key, decrypt, reset the database to the migrations,
# restore.sh, and the same row count and content checksum per table as before. Then the restored
# users sign in and the triggers work again. Never touches the real backup key.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$REPO_ROOT"

supabase_up
env="$(supabase status -o env 2>/dev/null)"
db_url="$(sed -n 's/^DB_URL="\(.*\)"$/\1/p' <<<"$env")"
service_key="$(sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p' <<<"$env")"
export PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres PGSSLMODE=disable
PGPORT="$(sed -n 's|^postgresql://[^@]*@[^:]*:\([0-9]*\)/.*$|\1|p' <<<"$db_url")"
export PGPORT

# Key, recipient and dump live outside the repo, so no AGE-SECRET-KEY can be committed.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "drill: FAIL: $*" >&2; exit 1; }
sql() { psql --no-psqlrc -XAt -v ON_ERROR_STOP=1 "$@"; }

# One line per backed-up table: name, row count, md5 of its rows in a fixed order.
snapshot() {
  sql -c "
    select format('select %L, count(*), md5(coalesce(string_agg(t::text, E''\n'' order by t::text), '''')) from %s t;',
                  s || '.' || n, format('%I.%I', s, n))
    from (select schemaname s, tablename n from pg_tables where schemaname = 'public'
          union all values ('auth', 'users'), ('auth', 'identities')) tables
    order by 1" \
    | sql -F ' ' -f -
}

sign_in() {
  curl -sS -o /dev/null -w '%{http_code}' "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H 'Content-Type: application/json' \
    -d "{\"email\": \"$1\", \"password\": \"drill-password-1\"}"
}

log "fixtures"
db_reset
for user in peter:Peter lea:Lea carl:Carl; do
  code="$(curl -sS -o "$work/user.json" -w '%{http_code}' "$SUPABASE_URL/auth/v1/admin/users" \
    -H "apikey: $service_key" -H "Authorization: Bearer $service_key" -H 'Content-Type: application/json' \
    -d "{\"email\": \"${user%%:*}@backup.test\", \"password\": \"drill-password-1\", \"email_confirm\": true,
         \"user_metadata\": {\"full_name\": \"${user#*:}\"}}")"
  [[ $code == 200 ]] || fail "creating ${user%%:*}@backup.test answered $code: $(cat "$work/user.json")"
done
sql -q -f scripts/backup/fixtures.sql >/dev/null
snapshot >"$work/before.txt"
if empty="$(awk '$2 == 0 { print $1 }' "$work/before.txt")" && [[ -n $empty ]]; then
  fail "no fixture rows in: $empty. Add rows for every new table to scripts/backup/fixtures.sql"
fi
max_event="$(sql -c 'select max(id) from public.item_events')"

log "dump with a throwaway key"
age-keygen -o "$work/key.txt" 2>/dev/null
age-keygen -y "$work/key.txt" >"$work/recipient.txt"
scripts/backup/dump.sh "$work/recipient.txt" "$work/backup.sql.age"
[[ "$(head -c 21 "$work/backup.sql.age")" == "age-encryption.org/v1" ]] || fail "no age header"
! grep -aq 'backup.test' "$work/backup.sql.age" || fail "the encrypted file contains plaintext"
age -d -i "$work/key.txt" "$work/backup.sql.age" | grep -q '^-- PostgreSQL database dump complete' \
  || fail "the decrypted dump is not a complete pg_dump"

log "reset to the migrations and restore"
db_reset
[[ "$(sql -c 'select count(*) from auth.users')" == 0 ]] || fail "reset left users behind"
age -d -i "$work/key.txt" "$work/backup.sql.age" | scripts/backup/restore.sh
snapshot >"$work/after.txt"
if ! diff -u "$work/before.txt" "$work/after.txt" >&2; then
  fail "restored data differs from the original (- before, + after)"
fi

log "the restored database works"
for email in peter@backup.test lea@backup.test carl@backup.test; do
  [[ "$(sign_in "$email")" == 200 ]] || fail "$email cannot sign in after the restore"
done
# A new write runs the triggers again (replica mode ended with the restore's session) and the
# item_events sequence continues after the restored ids.
lea="$(sql -c "select id from auth.users where email = 'lea@backup.test'")"
check="$(sql -q -c "
  begin;
  select set_config('request.jwt.claims', json_build_object('sub', '$lea', 'role', 'authenticated')::text, true),
         set_config('role', 'authenticated', true);
  insert into public.items (household_id, name)
    select household_id, 'Butter' from public.household_members where user_id = '$lea';
  update public.items set status = 'bought' where name = 'Butter';
  -- Members no longer read item_events (job 352).
  select set_config('role', 'postgres', true);
  select (bought_by = '$lea')::text
         || ' ' || ((select max(id) from public.item_events) > $max_event)::text
         || ' ' || (category_id is not null)::text
    from public.items where name = 'Butter';
  rollback;" | tail -n 1)"
[[ $check == "true true true" ]] \
  || fail "after the restore: bought_by from the trigger, new item_events id, classified ('$check', expected 'true true true')"

printf '%s\n' "drill: PASS: $(wc -l <"$work/before.txt") tables identical after dump, decrypt and restore:" >&2
awk '{ printf "  %-30s %6s  %s\n", $1, $2, $3 }' "$work/after.txt" >&2
