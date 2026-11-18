#!/usr/bin/env bash
# How long PR runs' jobs waited for a runner (job 309, OC2). GitHub runs at most 20 of our jobs at
# once, so a PR that starts many short jobs makes the e2e shards, which every PR waits on, queue.
# Prints one TSV row per finished pull_request run of ci.yml (first attempt): the jobs that ran
# (skipped ones excluded), the longest queue wait of an e2e shard, and ci-ok's end since the run
# started; then how many runs waited more than 1 and 3 minutes, and the medians.
#
# Usage: scripts/ci-queue.sh [--since ISO-DATE] [--until ISO-DATE] [--limit N]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SINCE="" UNTIL="" LIMIT=100
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
mapfile -t runs < <(gh run list --repo "$repo" --workflow ci.yml --event pull_request -L 500 \
  --json databaseId,createdAt,status \
  -q ".[] | select(.status == \"completed\")
          | select(\"$SINCE\" == \"\" or .createdAt >= \"$SINCE\")
          | select(\"$UNTIL\" == \"\" or .createdAt < \"$UNTIL\") | .databaseId" | head -n "$LIMIT")
[[ ${#runs[@]} -gt 0 ]] || { echo "no finished pull_request runs match" >&2; exit 1; }

# The API answers a long listing with an occasional 502, whose body gh prints too: only a
# successful answer goes on.
api() {
  local try out
  for try in 1 2 3 4; do
    out="$(gh api "$@" 2>/dev/null)" && { printf '%s\n' "$out"; return; }
    sleep $((try * 5))
  done
  echo "ci-queue: gh api $1 failed 4 times" >&2
  return 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for id in "${runs[@]}"; do
  start="$(api "repos/$repo/actions/runs/$id/attempts/1" -q .run_started_at)"
  api "repos/$repo/actions/runs/$id/attempts/1/jobs?per_page=50" | jq --arg id "$id" --arg start "$start" -c '
    def secs: fromdateiso8601;
    [.jobs[] | select(.started_at != null and .conclusion != "skipped")] as $ran
    | ([$ran[] | select(.name | startswith("e2e (")) | (.started_at | secs) - (.created_at | secs)] | max) as $wait
    | ([$ran[] | select(.name == "ci-ok")][0]) as $ok
    | { id: $id, branch: (.jobs[0].head_branch), jobs: ($ran | length), e2e_wait: $wait,
        ok: (if $ok == null or $ok.conclusion != "success" then null else ($ok.completed_at | secs) - ($start | secs) end) }' \
    >"$tmp/$id.json"
done

jq -rs '
  def mmss: if . == null then "-" else "\(. / 60 | floor):\(. % 60 | floor | tostring | if length < 2 then "0" + . else . end)" end;
  def median: sort | if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  (["run", "branch", "jobs", "e2e queue", "ci-ok"] | @tsv),
  (.[] | [.id, .branch, .jobs, (.e2e_wait | mmss), (.ok | mmss)] | @tsv),
  "",
  ([.[] | select(.e2e_wait != null)]) as $e2e
  | "runs: \(length); with e2e: \($e2e | length); e2e waited >1 min: \([$e2e[] | select(.e2e_wait > 60)] | length), >3 min: \([$e2e[] | select(.e2e_wait > 180)] | length)",
  "median jobs per run with e2e: \([$e2e[].jobs] | median); median e2e queue: \([$e2e[].e2e_wait] | median | mmss); median green ci-ok: \([$e2e[] | .ok | select(. != null)] | median | mmss)"
' "$tmp"/*.json
