#!/usr/bin/env bash
# Playwright drives the release web build against the local stack. Arguments go to
# `playwright test` (a file or -g to run a subset), with or without a leading `--` as verify.sh
# takes them: playwright itself ignores everything after a `--` and runs the whole suite.
#
# One e2e run at a time on the box: two overlapping runs (stack, web build, browsers) froze it
# (COORDINATION.md, Memory). The lock is box-wide, not per checkout, and the kernel drops it
# when the holder exits, however it exits.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
no_posthog_in_ci
if [[ ${1:-} == -- ]]; then shift; fi

case "${FG_SYNC_SMOKE:-auto}" in
  1) sync_smoke=1 ;;
  0) sync_smoke=0 ;;
  auto) if [[ $# -eq 0 || "$*" == --shard=1/* ]]; then sync_smoke=1; else sync_smoke=0; fi ;;
  *) echo "FG_SYNC_SMOKE is '$FG_SYNC_SMOKE'; use 1, 0 or auto" >&2; exit 2 ;;
esac

LOCK="${FG_E2E_LOCK:-/tmp/fg-e2e.lock}"
exec 9>>"$LOCK"
if ! flock -n 9; then
  log "waiting for the box-wide e2e lock $LOCK; last recorded holder (a plain 'flock $LOCK <cmd>' records nothing): $(grep . "$LOCK" || echo none recorded)"
  flock 9
  log "got the e2e lock"
fi
holder="$REPO_ROOT (pid $$, since $(date '+%H:%M:%S'))"
echo "$holder" >"$LOCK"
# Clear the record on the way out, so the next waiter isn't told about a run that has ended.
trap '[[ "$(cat "$LOCK" 2>/dev/null)" == "$holder" ]] && : >"$LOCK"' EXIT

supabase_up
log "web build against the local stack"
cd "$REPO_ROOT/app"
flutter pub get >/dev/null
# shellcheck disable=SC2046 # flutter_defines prints several arguments
flutter build web --release --no-web-resources-cdn --wasm $(flutter_defines) --dart-define-from-file=config/e2e.json
"$REPO_ROOT/scripts/join-config.sh" build/web

log "playwright"
cd "$REPO_ROOT/e2e"
[[ -d node_modules ]] || npm ci
# Job 50: integration-lock.spec.ts turns the server's integration_lock switch on, which every Siri,
# Alexa and MCP spec relies on being off, so it runs alone after the suite: on a full run (CI's
# first shard, or locally without a subset), or with the arguments when they name it (name it on
# its own: in that run only it can match). Its reports get their own names.
case " $* " in
  *integration-lock*)
    log "playwright: integration-lock.spec.ts alone, with the arguments"
    FG_E2E_INTEGRATION_LOCK=1 npx playwright test "$@"
    ;;
  *)
    npx playwright test "$@"
    if [[ $# -eq 0 || "$*" == --shard=1/* ]]; then
      log "playwright: integration-lock.spec.ts alone"
      FG_E2E_INTEGRATION_LOCK=1 npx playwright test tests/integration-lock.spec.ts
    fi
    ;;
esac

# Job 18: a two-client fg sync smoke test on the web build above (one add, one tick, the artifacts
# and the index), once per full run: on CI's first shard, or locally without a subset. It reuses
# this gate's e2e lock (fg sync sees that a parent holds it). FG_SYNC_SMOKE=1 or 0 overrides that
# rule (the on-demand e2e.yml's sync_smoke input, job 27); it is read up front, so a bad value
# fails before the stack starts.
if [[ $sync_smoke == 1 ]]; then
  log "fg sync smoke test"
  fg_on_repo_stack
  export FG_EVIDENCE_DIR="$REPO_ROOT/e2e/sync-evidence"
  "$REPO_ROOT/e2e/sync-smoke.sh" --web-build "$REPO_ROOT/app/build/web"
fi
