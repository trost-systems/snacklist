#!/usr/bin/env bash
# The hero from the real app: launches this checkout's verify-snacklist instance with the launch
# flags (marketing/capture-web.sh), films the phone screen (capture-hero.mjs, hero-screen/*.webp)
# and then the scene (film-all.mjs hero: site/public/media/hero-*.webp). See README.md.
#
#   site/scenes/capture-hero.sh [--keep]    --keep leaves the stack and the web server up
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../../.claude/skills/verify-snacklist/helpers/env.sh"
source "$REPO_ROOT/marketing/capture-web.sh"
keep=0
[[ ${1:-} == --keep ]] && keep=1
[[ $keep == 1 ]] || trap '"$VH_HELPERS/cleanup.sh" >/dev/null || true' EXIT

# -o: the web server launch.sh leaves running must not inherit the e2e lock (job 73).
flock -o /tmp/fg-e2e.lock "$VH_HELPERS/launch.sh" --scenario demo-haushalt | tail -1
capture_check_web_build
flock /tmp/fg-e2e.lock node "$here/capture-hero.mjs"
node "$here/film-all.mjs" hero
