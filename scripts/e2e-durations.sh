#!/usr/bin/env bash
# Job 304: rewrites e2e/shard-durations.json, the per-test times CI's e2e shards are split by
# (e2e/shards.mjs), as the medians of the last green CI runs on main that ran e2e: the nightly
# ones, and pushes from before job 308 or that did not reuse their PR's run. Run it when the shards'
# times drift apart (the e2e jobs' Playwright lines, "N passed (M m)"), and commit the file.
# A stale file only balances worse: a test it lacks counts as the median one.
#
# Usage: scripts/e2e-durations.sh [runs, default 5]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
runs="${1:-5}"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

found=0
while read -r run; do
  for shard in 1 2 3 4 5 6; do
    gh run download "$run" --repo "$repo" -n "e2e-results-$shard" -D "$tmp/$run/$shard" >/dev/null 2>&1 || true
  done
  if compgen -G "$tmp/$run/*/playwright-results.json" >/dev/null; then
    found=$((found + 1))
    [[ $found -lt $runs ]] || break
  fi
done < <(for event in schedule push; do
  gh run list --repo "$repo" --workflow ci.yml --branch main --event "$event" --status success -L 30 \
    --json databaseId -q '.[].databaseId'
done)
[[ $found -gt 0 ]] || { echo "e2e-durations: no green CI run on main with e2e results" >&2; exit 1; }

node "$REPO_ROOT/e2e/shards.mjs" durations "$tmp"/*/*/playwright-results.json >"$REPO_ROOT/e2e/shard-durations.json"
log "e2e/shard-durations.json from $found runs: $(grep -c ' › ' "$REPO_ROOT/e2e/shard-durations.json") tests"
