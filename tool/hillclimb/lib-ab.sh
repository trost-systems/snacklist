#!/usr/bin/env bash
# Paired A/B of one hill-climb measure: app/lib from <base-ref> (A) against HEAD's (B), every
# other file (the measure, its fixtures and benches) from HEAD, so a harness that main does not
# have yet still measures main's code. Alternates A and B in a detached worktree under /tmp,
# waiting up to AB_LOAD_WAIT_S (default 180) seconds before each run for a 1-minute load below 10
# (the noise rule of job 130).
#
#   tool/hillclimb/lib-ab.sh <base-ref> <pairs> <measure script, repo-relative> [label]
#
# Appends "<label>-a<i>|b<i> load=<before>/<after> <json>" lines to $AB_RUNS (default
# /tmp/lib-ab-<label>-<time>.jsonl) and prints each side's median score and the pair deltas
# (a measure without a top-level "score" key: compare its lines by hand).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
base="$1"
pairs="$2"
measure="$3"
label="${4:-$(basename "$(dirname "$measure")")}"
runs="${AB_RUNS:-/tmp/lib-ab-$label-$(date +%Y%m%d-%H%M%S).jsonl}"
tree="$(mktemp -d /tmp/lib-ab.XXXXXX)"
trap 'git -C "$root" worktree remove --force "$tree" >/dev/null 2>&1 || true' EXIT
git -C "$root" worktree add --detach "$tree" HEAD >/dev/null 2>&1
git -C "$root" diff --quiet HEAD -- app tool ||
  echo "lib-ab: uncommitted changes under app/ or tool/ are not measured" >&2

run() {
  for _ in $(seq $(( ${AB_LOAD_WAIT_S:-180} / 5 ))); do
    awk '{exit !($1 < 10)}' /proc/loadavg && break
    sleep 5
  done
  local before out
  before="$(cut -d' ' -f1 /proc/loadavg)"
  out="$("$tree/$measure")"
  echo "$1 load=$before/$(cut -d' ' -f1 /proc/loadavg) $out" | tee -a "$runs"
}

for i in $(seq "$pairs"); do
  git -C "$tree" checkout -q "$base" -- app/lib
  run "$label-a$i"
  git -C "$tree" checkout -q HEAD -- app/lib
  git -C "$tree" clean -qfd -- app/lib
  run "$label-b$i"
done

python3 - "$label" "$runs" <<'PY'
import json, statistics, sys
label, path = sys.argv[1], sys.argv[2]
a, b = [], []
for line in open(path):
    name, _, js = line.split(" ", 2)
    side = a if name.startswith(label + "-a") else b if name.startswith(label + "-b") else None
    if side is not None and "score" in json.loads(js):
        side.append(json.loads(js)["score"])
if not a or not b:
    sys.exit(f"no scores in {path}: compare its lines")
ma, mb = statistics.median(a), statistics.median(b)
print(f"a (base) {a} median {ma}")
print(f"b (HEAD) {b} median {mb} ({100 * (mb / ma - 1):+.1f} %)")
print("pair deltas", [round(y - x, 4) for x, y in zip(a, b)])
PY
