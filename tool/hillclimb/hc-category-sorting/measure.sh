#!/usr/bin/env bash
# hc-category-sorting (job 459): the list's store sections and walk order with categories hidden.
# Prints one JSON line on stdout; logs go to stderr. Frozen metric, docs/hillclimb/hc-category-sorting.md.
#
#   tool/hillclimb/hc-category-sorting/measure.sh [runs]
#     runs: launches of the bench, default 5; score is the median of their regroup p50s
#
# score: regroup p50 in µs (lower is better), valid only while correctness_failures and
# stability_failures are 0 ("valid": false otherwise; a failure outranks any speed).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
runs="${1:-5}"
work="$(mktemp -d /tmp/hc459-sections.XXXXXX)"
trap 'rm -rf "$work"' EXIT
# shellcheck source=../../../scripts/lib.sh
source "$root/scripts/lib.sh"
require_ci_flutter
cd "$root/app"
flutter pub get >/dev/null
echo "measure: $runs runs under /tmp/fg-hc-measure.lock" >&2
for ((i = 0; i < runs; i++)); do
  SECTIONS_BENCH=1 flock /tmp/fg-hc-measure.lock \
    flutter test test/list/sections_bench_test.dart --reporter expanded >"$work/run$i.log" 2>&1 ||
    { tail -40 "$work/run$i.log" >&2; exit 1; }
  grep -o 'SECTIONS_BENCH {.*' "$work/run$i.log" | sed 's/^SECTIONS_BENCH //' >>"$work/runs.jsonl"
done
python3 - "$work/runs.jsonl" "$(cut -d' ' -f1-3 /proc/loadavg)" \
  "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- app || echo -dirty)" <<'PY'
import datetime, json, statistics, sys
runs = [json.loads(line) for line in open(sys.argv[1])]
first = runs[0]
p50s = [r["regroup_p50_us"] for r in runs]
failures = first["correctness_failures"] + first["stability_failures"]
parts = {k: v for k, v in first.items() if not k.endswith("_us")}
for key in ("add_p50_us", "add_p95_us", "change_p50_us", "change_p95_us", "regroup_p50_us"):
    parts[key] = statistics.median(r[key] for r in runs)
print(json.dumps({
    "goal": "hc-category-sorting",
    "score": statistics.median(p50s),
    "higher_is_better": False,
    "valid": failures == 0,
    "parts": parts,
    "regroup_p50_runs": p50s,
    "runs": len(runs),
    "loadavg": sys.argv[2],
    "git": sys.argv[3],
    "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}, ensure_ascii=False))
PY
