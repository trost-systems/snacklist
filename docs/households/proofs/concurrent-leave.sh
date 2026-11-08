#!/usr/bin/env bash
# Two leaves race: T2 deletes B and holds; T1 deletes the default A, whose trigger picks B.
# Prints the user's remaining membership per lock clause. Needs Docker; uses a throwaway container.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
name=hh169-race-$$
docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=x public.ecr.aws/supabase/postgres:17.11.0.006 >/dev/null
trap 'docker stop "$name" >/dev/null' EXIT
until docker exec "$name" pg_isready -U postgres -h localhost >/dev/null 2>&1; do sleep 2; done
sleep 3
psql_() { docker exec -i "$name" psql -U postgres -h localhost -q -v ON_ERROR_STOP=1 "$@"; }
race() {
  psql_ -c 'drop table if exists household_members, households cascade' -c 'drop function if exists promote_default cascade' >/dev/null 2>&1
  sed "s/LOCKCLAUSE/$1/" "$here/concurrent-leave-setup.sql" | psql_ -f - >/dev/null
  psql_ -c 'begin; delete from household_members where household_id = 2 and user_id = 7; select pg_sleep(3); commit;' >/dev/null &
  sleep 1
  psql_ -c 'delete from household_members where household_id = 1 and user_id = 7;' >/dev/null
  wait
  psql_ -At -F ' default=' -c 'select household_id, is_default from household_members where user_id = 7;'
}
echo "subquery without a lock: $(race '')"
echo "subquery with for update: $(race 'for update')"
