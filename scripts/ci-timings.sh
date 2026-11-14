#!/usr/bin/env bash
# Wall-clock of recent CI runs, from the run's start to each job's end (first attempt only,
# so a manual rerun doesn't count). Prints one TSV row per run, then the median and range of
# ci-ok and of every job, and with --steps the median of every step of one job (`e2e` takes the
# steps of every shard, `e2e (1)` those of one).
#
# Usage: scripts/ci-timings.sh [--limit N] [--branch B] [--since ISO-DATE] [--until ISO-DATE] [--steps JOB]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

LIMIT=10 BRANCH="" SINCE="" UNTIL="" STEPS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --steps) STEPS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
mapfile -t runs < <(gh run list --workflow ci.yml -L 200 ${BRANCH:+--branch "$BRANCH"} \
  --json databaseId,createdAt,conclusion \
  -q ".[] | select(.conclusion == \"success\")
          | select(\"$SINCE\" == \"\" or .createdAt >= \"$SINCE\")
          | select(\"$UNTIL\" == \"\" or .createdAt < \"$UNTIL\") | .databaseId" | head -n "$LIMIT")

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for id in "${runs[@]}"; do
  start="$(gh api "repos/$repo/actions/runs/$id/attempts/1" -q .run_started_at)"
  gh api "repos/$repo/actions/runs/$id/attempts/1/jobs?per_page=50" \
    | jq --arg id "$id" --arg start "$start" -c '
        def secs: fromdateiso8601;
        { id: $id, branch: (.jobs[0].head_branch),
          jobs: [.jobs[] | select(.conclusion == "success") | {
            name, end: ((.completed_at | secs) - ($start | secs)),
            run: ((.completed_at | secs) - (.started_at | secs)),
            queue: ((.started_at | secs) - (.created_at | secs)),
            steps: [.steps[] | select(.completed_at != null) | {name, s: ((.completed_at | secs) - (.started_at | secs))}] }] }' \
    > "$tmp/$id.json"
done
[[ ${#runs[@]} -gt 0 ]] || { echo "no successful runs match" >&2; exit 1; }

jq -rs '
  def mmss: "\(. / 60 | floor):\(. % 60 | tostring | if length < 2 then "0" + . else . end)";
  def stats: sort as $s | ($s | length) as $n
    | (if $n % 2 == 1 then $s[$n / 2 | floor] else ($s[$n / 2 - 1] + $s[$n / 2]) / 2 | floor end) as $median
    | "\($median | mmss) (\($s[0] | mmss)-\($s[-1] | mmss), n=\($n))";
  (map(.jobs[].name) | unique) as $names
  | (["run", "branch"] + $names | @tsv),
    (.[] | . as $r | [$r.id, $r.branch] + ($names | map(. as $n | ($r.jobs[] | select(.name == $n) | .end | mmss) // "-")) | @tsv),
    "",
    "median end time since run start (range, n):",
    ($names[] as $n | "  \($n)\t\([.[].jobs[] | select(.name == $n) | .end] | stats)\trunning \([.[].jobs[] | select(.name == $n) | .run] | stats)")
' "$tmp"/*.json

if [[ -n $STEPS ]]; then
  jq -rs --arg slow "$STEPS" '
    def mmss: "\(. / 60 | floor):\(. % 60 | tostring | if length < 2 then "0" + . else . end)";
    "", "median step durations of \($slow):",
      ([.[].jobs[] | select(.name == $slow or (.name | startswith($slow + " ("))) | .steps[]] | group_by(.name)
        | map({name: .[0].name, s: (map(.s) | sort | .[length / 2 | floor])}) | sort_by(-.s)[]
        | "  \(.s | mmss)\t\(.name)")
  ' "$tmp"/*.json
fi
