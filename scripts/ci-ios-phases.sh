#!/usr/bin/env bash
# Where the ios job's time goes: reads the log of each ios job (every attempt) of the given CI
# runs and prints one row per job with its wall clock and the minutes of each phase of
# scripts/gates/ios.sh. Use it before and after a change to the ios gate (docs/CI.md, Measuring).
#
# Usage: scripts/ci-ios-phases.sh <run-id>...
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ $# -gt 0 ]] || { echo "usage: $0 <run-id>..." >&2; exit 2; }

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for run in "$@"; do
  attempts="$(gh api "repos/$repo/actions/runs/$run" -q .run_attempt)"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    while read -r id started conclusion name; do
      [[ $conclusion != skipped ]] || continue
      # A later attempt that didn't rerun ios lists the earlier attempt's job again, under a new id
      # but with its name and start; matrix siblings can start in the same second.
      [[ -e "$tmp/$started $name" ]] && continue
      touch "$tmp/$started $name"
      curl -fsSL -H "Authorization: Bearer $(gh auth token)" \
        "https://api.github.com/repos/$repo/actions/jobs/$id/logs" | sed 's/\x1b\[[0-9;]*m//g' >"$tmp/$id.log"
      python3 - "$tmp/$id.log" "$run#$attempt $name" "$conclusion" <<'PY'
import re, sys
from datetime import datetime

path, job, conclusion = sys.argv[1:]
stamp = lambda line: datetime.fromisoformat(line[:26].rstrip('Z'))
lines = [l for l in open(path, errors='replace') if re.match(r'\d{4}-\d\d-\d\dT', l)]
first, last = stamp(lines[0]), stamp(lines[-1])

# Since job 118 the gate logs "[ios] phase <name>"; before, the phases are found by the output
# of flutter build ios, simctl and xcodebuild test.
markers = [(m.group(1), stamp(l)) for l in lines if (m := re.search(r'\[ios(?:-storekit)?\] phase (\w+( wait)?)', l))]
if not markers:
    legacy = [
        ('pub+pods', r'Run scripts/gates/ios\.sh'),
        ('flutter build', r'Building com\.\S+ for simulator'),
        ('checks', r'Xcode build done'),
        ('boot', r'\[ios\] simulator '),
        ('xcodebuild resolve', r'Command line invocation:'),
        ('test build', r'Writing result bundle at path'),
        ('tests', r"Test Suite '[^']+' started"),
    ]
    for name, pattern in legacy:
        hit = next((l for l in lines if re.search(pattern, l)), None)
        if hit:
            markers.append((name, stamp(hit)))
end = next((stamp(l) for l in lines if re.search(r'\*\* TEST (SUCCEEDED|FAILED) \*\*', l)), last)
step = next((stamp(l) for l in lines if re.search(r'Run scripts/gates/ios(-storekit)?\.sh', l)), first)
mins = lambda a, b: f'{(b - a).total_seconds() / 60:.1f}'
phases = [('setup', first, step)]
for i, (name, at) in enumerate(markers):
    nxt = markers[i + 1][1] if i + 1 < len(markers) else end
    phases.append((name, at, nxt))
print(f'{job} {conclusion}: job {mins(first, last)} min |',
      ', '.join(f'{n} {mins(a, b)}' for n, a, b in phases))
PY
    done < <(gh api "repos/$repo/actions/runs/$run/attempts/$attempt/jobs?per_page=50" \
      -q '.jobs[] | select(.name | test("^ios(-storekit)?( |$)")) | "\(.id) \(.started_at) \(.conclusion) \(.name)"')
  done
done
