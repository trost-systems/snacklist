#!/usr/bin/env bash
# Tests supabase_start_retrying (scripts/lib.sh) with a stubbed supabase CLI: a docker networking
# error stops the half-started stack and starts again, any other failure stops the run at once,
# and a networking error that keeps coming ends after three starts (issue 517). Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

cat >"$tmp/supabase" <<'STUB'
#!/usr/bin/env bash
echo "$1" >>"$STUB_CALLS"
[[ $1 == start ]] || exit 0
starts="$(grep -c '^start$' "$STUB_CALLS")"
if (( starts <= STUB_FAIL_STARTS )); then echo "$STUB_ERROR" >&2; exit 1; fi
STUB
chmod +x "$tmp/supabase"
export STUB_CALLS="$tmp/calls"

run() {
  : >"$STUB_CALLS"
  code=0
  PATH="$tmp:$PATH" supabase_start_retrying >/dev/null 2>&1 || code=$?
  calls="$(paste -sd' ' "$STUB_CALLS")"
}

net='failed to start docker container "supabase_db_x": failed to set up container networking: driver failed programming external connectivity'
STUB_ERROR="$net" STUB_FAIL_STARTS=1 run
[[ $code == 0 && $calls == "start stop start" ]] || fail "one networking error: exit $code, calls '$calls'"
STUB_ERROR="$net" STUB_FAIL_STARTS=9 run
[[ $code == 1 && $calls == "start stop start stop start" ]] || fail "a networking error that stays: exit $code, calls '$calls'"
STUB_ERROR="migration failed" STUB_FAIL_STARTS=9 run
[[ $code == 1 && $calls == "start" ]] || fail "another failure was retried: exit $code, calls '$calls'"
STUB_ERROR="" STUB_FAIL_STARTS=0 run
[[ $code == 0 && $calls == "start" ]] || fail "a clean start: exit $code, calls '$calls'"

((failures == 0)) || exit 1
echo "[supabase-start-test] supabase_start_retrying retries docker networking errors only: all cases pass"
