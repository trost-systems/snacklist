#!/usr/bin/env bash
# Job 18 acceptance for fixtures on the local stack of FG_PORT_PREFIX: every shipped scenario
# seeds and passes its checks, two runs coexist without seeing each other (RLS), teardown leaves
# zero rows and a second one is a no-op, an orphaned run (manifest deleted) is swept by
# --stale, and no seeded password reaches stdout. Prints PASS or FAIL: <step>, plus a summary.
set -euo pipefail
fg="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)/scripts/fg"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
nonzero() { jq '[.leftovers // {} | to_entries[] | select(.value != 0)] | length' "$1"; }

runs=()
for s in $("$fg" scenario list | jq -r '.scenarios[].name'); do
  "$fg" seed "$s" >"$out/seed-$s.json" 2>/dev/null || fail "seed $s: $(jq -c .error "$out/seed-$s.json")"
  run="$(jq -r .run "$out/seed-$s.json")"
  runs+=("$run")
  printf '%-22s %s  checks %s/%s  users %s  %ss\n' "$s" "$run" \
    "$(jq '.checks.passed' "$out/seed-$s.json")" "$(jq '.checks.passed + (.checks.failed | length)' "$out/seed-$s.json")" \
    "$(jq '.members | length' "$out/seed-$s.json")" "$(jq .seconds "$out/seed-$s.json")"
done
shipped="$(find "$(dirname "$fg")/../test/fixtures/scenarios" -maxdepth 1 -name '*.yaml' | wc -l)"
[[ ${#runs[@]} -eq $shipped ]] || fail "expected $shipped scenarios (test/fixtures/scenarios), seeded ${#runs[@]}"

# Two runs at once: a member of each sees nothing of the other.
mid="$(jq -r .run "$out/seed-household-3-mid-shop.json")"
heavy="$(jq -r .run "$out/seed-heavy-history.json")"
heavy_home="$(jq -r .households.home.id "$out/seed-heavy-history.json")"
mid_home="$(jq -r .households.home.id "$out/seed-household-3-mid-shop.json")"
count() { "$fg" db query "select count(*)::int as n from items where household_id = '$2'" --as "$1" | jq '.rows[0].n'; }
[[ "$(count "$mid:mia" "$heavy_home")" == 0 && "$(count "$heavy:jo" "$mid_home")" == 0 ]] || fail "RLS across runs"
echo "RLS: $mid:mia sees $(count "$mid:mia" "$mid_home") own items, 0 of $heavy; $heavy:jo sees $(count "$heavy:jo" "$heavy_home") own, 0 of $mid"

# No password on stdout.
runs_dir="${FG_STATE_DIR:-$HOME/.cache/fg/${FG_PORT_PREFIX:-543}}/runs"
for run in "${runs[@]}"; do
  pw_file="$runs_dir/$run.json"
  for pw in $(jq -r '.users[].password' "$pw_file"); do
    if grep -rqF "$pw" "$out"; then fail "a seeded password of $run is in the command output"; fi
  done
  [[ "$(stat -c %a "$pw_file")" == 600 ]] || fail "$pw_file is not mode 600"
done
echo "secrets: no seeded password in any output; manifests are mode 600"

orphan="$(jq -r .run "$out/seed-empty-new-user.json")"
for run in "${runs[@]}"; do
  [[ $run == "$orphan" ]] && continue
  "$fg" teardown "$run" >"$out/down-$run.json" || fail "teardown $run: $(jq -c .error "$out/down-$run.json")"
  [[ "$(nonzero "$out/down-$run.json")" == 0 ]] || fail "leftovers after $run"
  "$fg" teardown "$run" >"$out/again-$run.json" || fail "second teardown $run"
  [[ "$(jq .alreadyClean "$out/again-$run.json")" == true ]] || fail "second teardown of $run was not a no-op"
  printf 'teardown %-20s users %s households %s, 16 leftover counts all 0; second call alreadyClean\n' \
    "$run" "$(jq .deleted.users "$out/down-$run.json")" "$(jq .deleted.households "$out/down-$run.json")"
done

# The orphan: its manifest deleted, so only the test email domain finds it; --stale sweeps it
# (--older-than 0: stale right away instead of after 24 h).
rm "$runs_dir/$orphan.json"
"$fg" runs --stale --older-than 0 | jq -e --arg r "$orphan" '.runs[] | select(.run == $r and .status == "orphaned" and .manifest == false)' >/dev/null \
  || fail "orphan $orphan not listed"
"$fg" teardown --stale --older-than 0 >"$out/stale.json" || fail "teardown --stale: $(jq -c .error "$out/stale.json")"
jq -e --arg r "$orphan" '.runs[] | select(.run == $r and .deleted.users == 1 and ([.leftovers[]] | add) == 0)' "$out/stale.json" >/dev/null \
  || fail "teardown --stale did not remove $orphan cleanly"
echo "orphan: $orphan (manifest deleted) listed as orphaned, removed by teardown --stale, leftovers 0"
[[ "$("$fg" teardown "$orphan" | jq .alreadyClean)" == true ]] || fail "orphan teardown not idempotent"
echo PASS
