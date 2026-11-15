#!/usr/bin/env bash
# hc-ui-perf (job 108): UI frame times and jank, as one score (lower is better). Prints one
# JSON line on stdout; logs go to stderr. docs/hillclimb/hc-ui-perf.md explains the flows,
# the score and the noise band.
#
#   tool/hillclimb/hc-ui-perf/measure.sh [runs]     # runs: measured launches, default 3
#
# Needs: Flutter, clang/CMake/GTK headers for `flutter build linux`, xvfb-run, python3 with
# PyYAML.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
runs="${1:-3}"
port=60881
# CI's SDK when it sits next to the default one (scripts/lib.sh does the same).
export PATH="${FLUTTER_DIR:-$HOME/flutter}/bin:$PATH"

cd "$root/app"
flutter pub get >/dev/null
echo "measure: building the Linux profile probe" >&2
log="$(mktemp /tmp/hc108-build.XXXXXX)"
trap 'rm -f "$log"' EXIT
flutter build linux --profile -t test_driver/ui_perf_probe.dart \
  --dart-define=SUPABASE_URL="http://127.0.0.1:$port" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_probe >"$log" 2>&1 ||
  { tail -40 "$log" >&2; exit 1; }

echo "measure: 1 warm-up and $runs launches under /tmp/fg-hc-measure.lock" >&2
runs_json="$(flock /tmp/fg-hc-measure.lock xvfb-run -a -s "-screen 0 1280x1024x24" \
  python3 "$here/frames.py" build/linux/x64/profile/bundle "$port" "$runs" "$root/test/fixtures/scenarios" |
  tee /dev/stderr | grep '^\[' | tail -1)"

python3 - "$runs_json" \
  "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- app || echo -dirty)" <<'EOF'
import datetime, json, statistics, sys
runs, sha = json.loads(sys.argv[1]), sys.argv[2]
parts = {}
for flow in runs[0]["flows"]:
    parts[flow] = {
        k: statistics.median(r["flows"][flow][k] for r in runs)
        for k in runs[0]["flows"][flow]
    }
parts["run_scores"] = [r["score"] for r in runs]
parts["idle_frames"] = [r["idle_frames"] for r in runs]
parts["seed"] = 0
parts["window"] = "412x892 (linux runner default), Xvfb 1280x1024x24"
print(json.dumps({
    "goal": "hc-ui-perf",
    "score": statistics.median(r["score"] for r in runs),
    "higher_is_better": False,
    "parts": parts,
    "git": sha,
    "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}))
EOF
