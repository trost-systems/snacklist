#!/usr/bin/env bash
# Read-only: is this verify-snacklist instance worth driving? One line per check, `ok` or `FAIL`
# with the fix; exit 0 only when every check passes. Writes nothing (a password sign-in is the
# only call that touches the stack; it adds a session row).
#
#   doctor.sh
set -uo pipefail
source "$(dirname "$0")/env.sh"

fails=0
check() { # name, fix, command...
  local name="$1" fix="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then echo "ok    $name"; else echo "FAIL  $name -> $fix"; fails=$((fails + 1)); fi
}

check "instance record $VH_INSTANCE" "run helpers/launch.sh" test -f "$VH_INSTANCE"
[[ -f $VH_INSTANCE ]] || { echo "doctor: no instance; nothing else to check"; exit 1; }
check "supabase stack $VH_PROJECT_ID up (API, Auth, Realtime)" "run helpers/launch.sh" stack_running
migrations_match() {
  local applied files
  applied="$(docker exec "supabase_db_$VH_PROJECT_ID" psql -U postgres -tAc 'select count(*) from supabase_migrations.schema_migrations')"
  files="$(find "$REPO_ROOT/supabase/migrations" -name '*.sql' | wc -l)"
  [[ $applied == "$files" ]]
}
check "migrations applied = files in supabase/migrations" "supabase db reset in the repo, then helpers/launch.sh --fresh" migrations_match
user_switches_on() {
  [[ "$(docker exec "supabase_db_$VH_PROJECT_ID" psql -U postgres -tAc \
    "select count(*) from public.app_switches where key in ($VH_USER_SWITCHES) and not enabled")" == 0 ]]
}
check "server switches users have are on ($VH_USER_SWITCHES)" "helpers/launch.sh (turns them on), or restore what a journey left off" user_switches_on
check "functions answer ($(vh_json apiUrl 2>/dev/null)/functions/v1/health)" "helpers/cleanup.sh, then helpers/launch.sh (restarts the stack)" \
  curl -fsS -m 5 "$(vh_json apiUrl)/functions/v1/health"
own_server() {
  local pid
  pid="$(vh_server_pid)"
  [[ -n $pid && $pid == "$(vh_json serverPid)" ]] && tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q "serve.mjs $VH_BUILD_DIR $VH_WEB_PORT"
}
check "web server on $VH_WEB_URL is ours" "helpers/launch.sh (starts it); if another process holds the port, set VH_WEB_PORT" own_server
check "web build matches the source (app/ at HEAD + local edits)" "helpers/launch.sh (rebuilds)" \
  test "$(cat "$VH_BUILD_DIR/.vh-stamp" 2>/dev/null)" == "$(vh_build_stamp)"
check "web app served (index.html, FontManifest.json)" "helpers/launch.sh --rebuild" \
  bash -c "curl -fsS -m 5 '$VH_WEB_URL/' | grep -q flutter_bootstrap && curl -fsS -m 5 -o /dev/null '$VH_WEB_URL/assets/FontManifest.json'"
check "seeded run $(vh_json run 2>/dev/null) has credentials" "helpers/launch.sh --fresh" test -s "$(vh_json credentials)"
signs_in() {
  node --input-type=module -e "
    import { apiAs, instance, member } from '$VH_HELPERS/lib.mjs';
    const inst = instance(); const user = member(inst);
    const api = await apiAs(inst, user);
    const { data, error } = await api.from('household_members').select('household_id').eq('user_id', user.id);
    if (error || data.length !== 1 || data[0].household_id !== user.householdId) process.exit(1);"
}
check "first member signs in and belongs to the seeded household" "helpers/launch.sh --fresh" signs_in

if [[ $fails -gt 0 ]]; then
  echo "doctor: $fails check(s) failed"
  exit 1
fi
echo "doctor: healthy ($VH_WEB_URL, run $(vh_json run), commit $(vh_json commit))"
