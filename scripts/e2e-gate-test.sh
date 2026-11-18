#!/usr/bin/env bash
# Tests which playwright arguments scripts/gates/e2e.sh passes on, when it adds the fg sync
# smoke test and that it resets a stack whose migrations are not the checkout's, with the stack,
# the web build and playwright stubbed out. Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

mkdir -p "$tmp/repo/scripts/gates" "$tmp/repo/app" "$tmp/repo/e2e/node_modules" "$tmp/bin"
cp "$REPO_ROOT/scripts/gates/e2e.sh" "$tmp/repo/scripts/gates/"
cat >"$tmp/repo/scripts/lib.sh" <<'LIB'
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { echo "$*"; }
no_posthog_in_ci() { :; }
require_ci_flutter() { :; }
project_id() { echo scratch; }
supabase_up() { echo "supabase up" >>"$CALLS"; }
stack_migrations_diff() { [[ ! -e $STALE.unreadable ]] && { cat "$STALE" 2>/dev/null || true; }; }
db_reset() { echo "db reset" >>"$CALLS"; [[ ! -e $STALE.reset-fails ]]; }
flutter_defines() { :; }
fg_on_repo_stack() { :; }
LIB
printf '#!/usr/bin/env bash\necho "sync smoke" >>"%s/calls"\n' "$tmp" >"$tmp/repo/e2e/sync-smoke.sh"
printf '#!/usr/bin/env bash\n:\n' >"$tmp/repo/scripts/join-config.sh"
cat >"$tmp/bin/flutter" <<FLUTTER
#!/usr/bin/env bash
[[ \${1:-} != build ]] || echo "flutter build" >>"$tmp/calls"
FLUTTER
printf '#!/usr/bin/env bash\necho "npx $*" >>"%s/calls"\n' "$tmp" >"$tmp/bin/npx"
# shellcheck disable=SC2016 # the stub expands NODE_EXIT when it runs
printf '#!/usr/bin/env bash\necho "node $*" >>"%s/calls"\nexit "${NODE_EXIT:-0}"\n' "$tmp" >"$tmp/bin/node"
chmod +x "$tmp/repo/e2e/sync-smoke.sh" "$tmp/repo/scripts/join-config.sh" "$tmp/bin/flutter" "$tmp/bin/npx" "$tmp/bin/node"

# Runs the gate; its exit status is in $status, what it called in $tmp/calls, its output in $tmp/out.
run_gate() {
  : >"$tmp/calls"
  status=0
  PATH="$tmp/bin:$PATH" FG_E2E_LOCK="$tmp/lock" FG_SYNC_SMOKE=auto STALE="$tmp/stale" CALLS="$tmp/calls" \
    "$tmp/repo/scripts/gates/e2e.sh" "$@" >"$tmp/out" 2>&1 || status=$?
}
# The gate passes and has called exactly these after the stack's start.
expect_calls() {
  local want="$1" got
  shift
  run_gate "$@"
  got="$(<"$tmp/calls")"
  [[ $status -eq 0 ]] || fail "e2e.sh $* exited $status"
  [[ $got == $'supabase up\n'"$want" ]] || fail "e2e.sh $*"$'\n'"--- expected"$'\n'"supabase up"$'\n'"$want"$'\n'"--- got"$'\n'"$got"
}
# The gate fails having called exactly these: nothing after the step that failed.
expect_stop() {
  local want="$1" got
  shift
  run_gate "$@"
  got="$(<"$tmp/calls")"
  [[ $status -ne 0 ]] || fail "e2e.sh $* passed"
  [[ $got == "$want" ]] || fail "e2e.sh $* stopped late or early"$'\n'"--- expected"$'\n'"$want"$'\n'"--- got"$'\n'"$got"
}

expect_calls $'flutter build\n'"npx playwright test tests/purchases.spec.ts --workers=1" -- tests/purchases.spec.ts --workers=1
expect_calls $'flutter build\n'"npx playwright test tests/purchases.spec.ts" tests/purchases.spec.ts
# Job 50: integration-lock.spec.ts runs alone after the suite: on full runs and when named.
lock="npx playwright test tests/integration-lock.spec.ts"
expect_calls $'flutter build\nnpx playwright test\n'"$lock"$'\nsync smoke' --
expect_calls $'flutter build\nnpx playwright test\n'"$lock"$'\nsync smoke'
# Job 304: a shard alone runs its part of the split by time; with a spec, Playwright's own --shard.
expect_calls $'flutter build\nnode shards.mjs list 1/2 shard-tests.txt\nnpx playwright test --test-list shard-tests.txt\n'"$lock"$'\nsync smoke' --shard=1/2
expect_calls $'flutter build\nnode shards.mjs list 2/2 shard-tests.txt\nnpx playwright test --test-list shard-tests.txt' --shard=2/2
expect_calls $'flutter build\nnode shards.mjs list 3/4 shard-tests.txt\nnpx playwright test --test-list shard-tests.txt' -- --shard=3/4
expect_calls $'flutter build\n'"npx playwright test tests/list.spec.ts --shard=2/2" tests/list.spec.ts --shard=2/2
# A suite that a test list cannot name test by test (exit 3) runs Playwright's --shard; any other
# failure of the plan stops the gate.
NODE_EXIT=3 expect_calls $'flutter build\nnode shards.mjs list 2/2 shard-tests.txt\nnpx playwright test --shard=2/2' --shard=2/2
NODE_EXIT=1 expect_stop $'supabase up\nflutter build\nnode shards.mjs list 2/2 shard-tests.txt' --shard=2/2
expect_calls $'flutter build\n'"$lock" -- tests/integration-lock.spec.ts
expect_calls $'flutter build\n'"$lock -g English --workers=1" tests/integration-lock.spec.ts -g English --workers=1

# Job 219: a running stack whose migrations are not the checkout's gets its database reset after
# the stack's start and before the web build, whichever way it differs.
play="npx playwright test tests/list.spec.ts"
echo '20261101000000 is not applied' >"$tmp/stale"
expect_calls $'db reset\nflutter build\n'"$play" tests/list.spec.ts
echo '20261102000000 is applied and has no file' >"$tmp/stale"
expect_calls $'db reset\nflutter build\n'"$play" tests/list.spec.ts
printf '20261101000000 is not applied\n20261102000000 is applied and has no file\n' >"$tmp/stale"
expect_calls $'db reset\nflutter build\nnpx playwright test\n'"$lock"$'\nsync smoke'
expect_calls $'db reset\nflutter build\n'"$play" tests/list.spec.ts
grep -q "migrations are not this checkout's (20261101000000 is not applied, 20261102000000 is applied and has no file): resetting" "$tmp/out" \
  || fail "the reset does not say which migrations differ: $(<"$tmp/out")"
# A reset that fails stops the gate before the build, and so does a database that cannot be read.
touch "$tmp/stale.reset-fails"
expect_stop $'supabase up\ndb reset' tests/list.spec.ts
rm "$tmp/stale.reset-fails"
touch "$tmp/stale.unreadable"
expect_stop "supabase up" tests/list.spec.ts
grep -q "cannot read which migrations the stack's database has applied (docker exec supabase_db_scratch psql)" "$tmp/out" \
  || fail "the gate does not say that it could not read the applied migrations: $(<"$tmp/out")"
rm "$tmp/stale" "$tmp/stale.unreadable"

# stack_migrations_diff itself, with docker answering for the database.
mkdir -p "$tmp/stack/supabase/migrations" "$tmp/docker"
echo 'project_id = "scratch"' >"$tmp/stack/supabase/config.toml"
# Three migrations, one of them a link to a file, and what the CLI takes for none: no version, no
# name, a version that does not lead or is not all digits or has no underscore after it, another
# suffix, a folder, a link to one, a file in one.
mkdir -p "$tmp/stack/supabase/migrations/old" "$tmp/stack/supabase/migrations/20261107000000_folder.sql"
touch "$tmp/stack/supabase/migrations/"{20261101000000_a,20261102000000_b_c,notes,20261105000000,x_20261106000000_y,1abc_f,20261108000000-g_h,old/20261001000000_e}.sql \
  "$tmp/stack/supabase/migrations/20261101000000_a.sql.orig" "$tmp/stack/d.sql"
ln -s ../../d.sql "$tmp/stack/supabase/migrations/20261103000000_d.sql"
ln -s old "$tmp/stack/supabase/migrations/20261109000000_link.sql"
cat >"$tmp/docker/docker" <<'DOCKER'
#!/usr/bin/env bash
[[ "$1 $2 $3" == "exec supabase_db_scratch psql" ]] || { echo "unexpected: docker $*" >&2; exit 64; }
[[ -r $APPLIED ]] || { echo "Error response from daemon: No such container" >&2; exit 1; }
cat "$APPLIED"
DOCKER
chmod +x "$tmp/docker/docker"
stack_diff() (
  REPO_ROOT="$tmp/${1:-stack}"
  PATH="$tmp/docker:$PATH" APPLIED="$tmp/applied" stack_migrations_diff 2>/dev/null
)
# The stack has applied these versions: stack_migrations_diff succeeds and prints exactly $1.
expect_diff() {
  local want="$1" got status=0
  shift
  printf '%s\n' "$@" >"$tmp/applied"
  got="$(stack_diff)" || status=$?
  [[ $status -eq 0 ]] || fail "stack_migrations_diff exited $status with $* applied"
  [[ $got == "$want" ]] || fail "with $* applied"$'\n'"--- expected"$'\n'"$want"$'\n'"--- got"$'\n'"$got"
}
expect_diff "" 20261101000000 20261102000000 20261103000000
expect_diff $'20261102000000 is not applied\n20261104000000 is applied and has no file' 20261101000000 20261103000000 20261104000000
expect_diff $'20261101000000 is not applied\n20261102000000 is not applied\n20261103000000 is not applied' ""
# A comparison that fails is no match, and a folder without migrations matches an empty table.
printf '#!/usr/bin/env bash\nexit 2\n' >"$tmp/docker/diff"
chmod +x "$tmp/docker/diff"
if stack_diff >/dev/null; then fail "a diff that fails passes for a current stack"; fi
rm "$tmp/docker/diff"
mkdir -p "$tmp/none/supabase/migrations"
cp "$tmp/stack/supabase/config.toml" "$tmp/none/supabase/"
: >"$tmp/applied"
[[ -z "$(stack_diff none)" ]] || fail "no files and nothing applied: $(stack_diff none)"
rm "$tmp/applied"
if stack_diff >/dev/null; then fail "a database that cannot be read passes for a current one"; fi

if [[ $failures -gt 0 ]]; then
  echo "e2e-gate-test: $failures failed" >&2
  exit 1
fi
log "e2e.sh passes a spec on with or without -- and resets a stale stack: all cases pass"
