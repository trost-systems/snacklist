#!/usr/bin/env bash
# hc-suggest-cpu score: p50 latency in ms of one client-side suggestUsuals call (the add
# sheet's offline ranking), over 30 timed rounds of the 40 frozen queries against 5,000
# usuals (seed 131, app/test/list/suggest_fixture/), lower is better. Allocated bytes per
# query are a secondary part (ties inside the noise band only); cold_p50_ms (the first call
# on freshly loaded Usual objects) is reported, not scored. Prints one JSON line.
# Fails when any query's top 5 differs from expected.json. HC_SUGGEST_USUALS=200 times the
# first 200 usuals only, the most the app loads (the ranked check still covers all
# 5,000). Job 131's climb, ported in job 451: docs/done/451.md.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$root/scripts/lib.sh"
report="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "$report" "$out"' EXIT
cd "$root/app"
flutter pub get >/dev/null 2>&1
if ! flock /tmp/fg-hc-measure.lock env HC_SUGGEST_BENCH="$report" HC_SUGGEST_USUALS="${HC_SUGGEST_USUALS:-}" \
  flutter test --enable-vmservice test/hillclimb/suggest_usuals_bench_test.dart >"$out" 2>&1; then
  cat "$out" >&2
  exit 1
fi
python3 - "$report" "$root/app/test/list/suggest_fixture/expected.json" \
  "$(git -C "$root" rev-parse --short HEAD)" "$(cut -d' ' -f1 /proc/loadavg)" <<'PY'
import json, sys, datetime, statistics
report, expected_path, sha, load = sys.argv[1:]
r = json.load(open(report))
expected = json.load(open(expected_path))
mismatches = [q for q in expected if r["ranked"].get(q) != expected[q]]
s = sorted(r["samples_us"])
def pct(p):
    return s[min(len(s) - 1, int(len(s) * p))] / 1000
if mismatches:
    print(f"rank mismatch for {len(mismatches)} queries: {mismatches[:5]}", file=sys.stderr)
    sys.exit(1)
print(json.dumps({
    "goal": "hc-suggest-cpu",
    "score": round(pct(0.5), 3),
    "higher_is_better": False,
    "parts": {
        "p50_ms": round(pct(0.5), 3),
        "p90_ms": round(pct(0.9), 3),
        "mean_ms": round(statistics.fmean(s) / 1000, 3),
        "cold_p50_ms": round(statistics.median(r["cold_us"]) / 1000, 3),
        "bytes_per_query": None if r["bytes_per_round"] is None else r["bytes_per_round"] // r["queries"],
        "samples": len(s),
        "queries": r["queries"],
        "usuals": r["usuals"],
        "rounds": r["rounds"],
        "warmup_rounds": r["warmup"],
        "rank_mismatches": len(mismatches),
        "seed": 131,
        "loadavg_1m": float(load),
    },
    "git": sha,
    "at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}))
PY
