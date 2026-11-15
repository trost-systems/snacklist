#!/usr/bin/env bash
# hc-list-cpu (job 221): what the list computes per build and saves per tick, without rendering,
# on the hc-ui-perf household (300 open items, 10 stores). Prints one JSON line on stdout: the
# median over the launches of each of the probe's numbers (µs per call). Logs go to stderr.
# docs/DECISIONS.md (Job 221: the save after a tick) has the numbers it was built for.
#
#   tool/hillclimb/hc-list-cpu/measure.sh [runs] [bundle]
#     runs:   launches, default 3
#     bundle: a built probe (flutter build linux --profile -t test_driver/list_bench_probe.dart);
#             without it the script builds one
#   LIST_BENCH_ENCODE=whole  the cubit's saves encode the whole snapshot, as before job 221
#
# Needs: Flutter, clang/CMake/GTK headers for `flutter build linux` (unless a bundle is given),
# xvfb-run, python3 with PyYAML.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
runs="${1:-3}"
bundle="${2:-}"
work="$(mktemp -d /tmp/hc221-list.XXXXXX)"
trap 'rm -rf "$work"' EXIT

if [[ -z $bundle ]]; then
  # CI's SDK when it sits next to the default one (scripts/lib.sh does the same).
  export PATH="${FLUTTER_DIR:-$HOME/flutter}/bin:$PATH"
  cd "$root/app"
  flutter pub get >/dev/null
  echo "measure: building the Linux profile probe" >&2
  flutter build linux --profile -t test_driver/list_bench_probe.dart >"$work/build.log" 2>&1 ||
    { tail -40 "$work/build.log" >&2; exit 1; }
  bundle="$root/app/build/linux/x64/profile/bundle"
fi

python3 "$here/../hc-ui-perf/fake_supabase.py" dump "$root/test/fixtures/scenarios" >"$work/household.json"
echo "measure: $runs launches under /tmp/fg-hc-measure.lock" >&2
for ((i = 0; i < runs; i++)); do
  LIST_BENCH_FIXTURE="$work/household.json" HOME="$work/home" flock /tmp/fg-hc-measure.lock \
    timeout 120 xvfb-run -a -s "-screen 0 1280x800x24" "$bundle/family_groceries" 2>"$work/run.log" |
    grep '^{' | tail -1 >>"$work/runs.jsonl" || { tail -20 "$work/run.log" >&2; exit 1; }
done

python3 - "$work/runs.jsonl" "$(cut -d' ' -f1-3 /proc/loadavg)" \
  "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- app || echo -dirty)" <<'EOF'
import datetime, json, statistics, sys
runs = [json.loads(line) for line in open(sys.argv[1])]
parts = {}
for key, first in runs[0].items():
    values = [r[key]["median_us"] if isinstance(first, dict) and "median_us" in first else r[key] for r in runs]
    numbers = all(isinstance(v, (int, float)) for v in values)
    parts[key] = statistics.median(values) if numbers else values[0]
print(json.dumps({
    "goal": "hc-list-cpu",
    "unit": "µs per call unless the key says otherwise",
    "parts": parts,
    "runs": len(runs),
    "loadavg": sys.argv[2],
    "git": sys.argv[3],
    "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}))
EOF
