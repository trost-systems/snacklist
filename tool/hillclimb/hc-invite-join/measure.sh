#!/usr/bin/env bash
# Job 460 (hc-invite-join): one JSON line, lower is better. docs/hillclimb/hc-invite-join.md.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# CI's Flutter (~/flutter-<pin>): another SDK rewrites pubspec.lock and fails tests that pass in CI.
source "$here/../../../scripts/lib.sh"
PATH="$(flutter_dir)/bin:$PATH"
(cd "$here/../../../app" && flutter pub get >/dev/null 2>&1)
exec flock /tmp/fg-hc-measure.lock python3 "$here/measure.py"
