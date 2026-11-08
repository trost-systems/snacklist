#!/usr/bin/env bash
# Tests which playwright arguments scripts/gates/e2e.sh passes on and when it adds the fg sync
# smoke test, with the stack, the web build and playwright stubbed out. Run by the lint gate.
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
log() { :; }
no_posthog_in_ci() { :; }
supabase_up() { :; }
flutter_defines() { :; }
fg_on_repo_stack() { :; }
LIB
printf '#!/usr/bin/env bash\necho "sync smoke" >>"%s/calls"\n' "$tmp" >"$tmp/repo/e2e/sync-smoke.sh"
printf '#!/usr/bin/env bash\n:\n' >"$tmp/repo/scripts/join-config.sh"
printf '#!/usr/bin/env bash\n:\n' >"$tmp/bin/flutter"
printf '#!/usr/bin/env bash\necho "npx $*" >>"%s/calls"\n' "$tmp" >"$tmp/bin/npx"
chmod +x "$tmp/repo/e2e/sync-smoke.sh" "$tmp/repo/scripts/join-config.sh" "$tmp/bin/flutter" "$tmp/bin/npx"

calls_for() {
  : >"$tmp/calls"
  PATH="$tmp/bin:$PATH" FG_E2E_LOCK="$tmp/lock" FG_SYNC_SMOKE=auto \
    "$tmp/repo/scripts/gates/e2e.sh" "$@" >/dev/null 2>&1 || fail "e2e.sh $* exited $?"
  cat "$tmp/calls"
}
expect_calls() {
  local want="$1"
  shift
  local got
  got="$(calls_for "$@")"
  [[ $got == "$want" ]] || fail "e2e.sh $*"$'\n'"--- expected"$'\n'"$want"$'\n'"--- got"$'\n'"$got"
}

expect_calls "npx playwright test tests/purchases.spec.ts --workers=1" -- tests/purchases.spec.ts --workers=1
expect_calls "npx playwright test tests/purchases.spec.ts" tests/purchases.spec.ts
# Job 50: integration-lock.spec.ts runs alone after the suite: on full runs and when named.
lock="npx playwright test tests/integration-lock.spec.ts"
expect_calls $'npx playwright test\n'"$lock"$'\nsync smoke' --
expect_calls $'npx playwright test\n'"$lock"$'\nsync smoke'
expect_calls $'npx playwright test --shard=1/2\n'"$lock"$'\nsync smoke' --shard=1/2
expect_calls "npx playwright test --shard=2/2" --shard=2/2
expect_calls "$lock" -- tests/integration-lock.spec.ts
expect_calls "$lock -g English --workers=1" tests/integration-lock.spec.ts -g English --workers=1

if [[ $failures -gt 0 ]]; then
  echo "e2e-gate-test: $failures failed" >&2
  exit 1
fi
log "e2e.sh passes a spec on with or without --: all cases pass"
