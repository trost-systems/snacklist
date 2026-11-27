#!/usr/bin/env bash
# hc-tick-untick (job 458): a tick and its undo on a large in-memory list, and the frozen
# correctness fixture (test/list/tick_undo_replay_test.dart). Prints one JSON line on stdout;
# logs go to stderr. Lower score is better:
#   score = n3000 tick p50 + n3000 undo p50 (µs, median over the launches)
#           + 1,000,000 per failure (fixture tests failed, probe errors)
# docs/hillclimb/hc-tick-untick.md has the baseline and noise band.
#
#   tool/hillclimb/hc-tick-untick/measure.sh [runs] [bundle]
#     runs:   launches of the probe, default 5
#     bundle: a built probe (flutter build linux --profile -t test_driver/tick_untick_probe.dart);
#             without it the script builds one
#
# Needs: Flutter, clang/CMake/GTK headers or Docker for `flutter build linux` (unless a bundle is
# given), xvfb-run, python3 with PyYAML.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
runs="${1:-5}"
bundle="${2:-}"
work="$(mktemp -d /tmp/hc458-tick.XXXXXX)"
trap 'rm -rf "$work"' EXIT
# The SDK the gates use (FLUTTER_DIR, else CI's version beside ~/flutter, else ~/flutter).
# shellcheck source=../../../scripts/lib.sh
source "$root/scripts/lib.sh"
# Without CMake on the host (the Hetzner runner), `flutter build linux` runs in a container.
command -v cmake >/dev/null || export PATH="$root/.cursor/skills/verify-family-groceries/linux-build:$PATH"
cd "$root/app"
flutter pub get >/dev/null

echo "measure: correctness fixture" >&2
flutter test --reporter json test/list/tick_undo_replay_test.dart >"$work/fixture.jsonl" 2>"$work/fixture.err" || true
read -r passed failed < <(python3 - "$work/fixture.jsonl" <<'PY'
import json, sys
ok = bad = 0
for line in open(sys.argv[1]):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if e.get("type") == "testDone" and not e.get("hidden"):
        if e.get("result") == "success" and not e.get("skipped"):
            ok += 1
        else:
            bad += 1
print(ok, bad)
PY
)
[[ $passed -gt 0 || $failed -gt 0 ]] || { failed=1; tail -20 "$work/fixture.err" >&2; }

if [[ -z $bundle ]]; then
  echo "measure: building the Linux profile probe" >&2
  flutter build linux --profile -t test_driver/tick_untick_probe.dart >"$work/build.log" 2>&1 ||
    { tail -40 "$work/build.log" >&2; exit 1; }
  bundle="$root/app/build/linux/x64/profile/bundle"
fi

python3 "$here/../hc-ui-perf/fake_supabase.py" dump "$root/test/fixtures/scenarios" >"$work/household.json"
echo "measure: $runs launches under /tmp/fg-hc-measure.lock" >&2
for ((i = 0; i < runs; i++)); do
  LIST_BENCH_FIXTURE="$work/household.json" HOME="$work/home" flock /tmp/fg-hc-measure.lock \
    timeout 300 xvfb-run -a -s "-screen 0 1280x800x24" "$bundle/family_groceries" 2>"$work/run.log" |
    grep '^{' | tail -1 >>"$work/runs.jsonl" || { tail -20 "$work/run.log" >&2; exit 1; }
done

python3 - "$work/runs.jsonl" "$passed" "$failed" "$(cut -d' ' -f1-3 /proc/loadavg)" \
  "$(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- app || echo -dirty)" <<'PY'
import datetime, json, statistics, sys
runs = [json.loads(line) for line in open(sys.argv[1])]
passed, failed = int(sys.argv[2]), int(sys.argv[3])
parts = {}
for size in ("n300", "n3000"):
    for key in ("tick", "undo", "tick_encode", "undo_encode", "offline_tick", "offline_undo"):
        for stat in ("p50_us", "p90_us"):
            values = [r[size][key][stat] for r in runs]
            parts[f"{size}.{key}.{stat}"] = round(statistics.median(values), 1)
    parts[f"{size}.tick.p50_us.runs"] = [r[size]["tick"]["p50_us"] for r in runs]
    parts[f"{size}.undo.p50_us.runs"] = [r[size]["undo"]["p50_us"] for r in runs]
    parts[f"{size}.items"] = runs[0][size]["items"]
    parts[f"{size}.offline_queued"] = runs[0][size]["offline_queued"]
    parts[f"{size}.saves"] = runs[0][size]["saves"]
probe_errors = sum(r[s]["errors"] for r in runs for s in ("n300", "n3000"))
failures = failed + probe_errors
score = parts["n3000.tick.p50_us"] + parts["n3000.undo.p50_us"] + 1_000_000 * failures
print(json.dumps({
    "goal": "hc-tick-untick",
    "score": round(score, 1),
    "higher_is_better": False,
    "failures": failures,
    "fixture": {"passed": passed, "failed": failed},
    "probe_errors": probe_errors,
    "parts": parts,
    "runs": len(runs),
    "loadavg": sys.argv[4],
    "git": sys.argv[5],
    "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}))
PY
