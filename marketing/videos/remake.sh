#!/usr/bin/env bash
# Films the demo videos again and writes their site files (site/public/media): the Linux profile
# build when the app or the stack changed, one take per video and language, then build.mjs and
# the REVIEW.md tables (report.mjs).
#
#   marketing/videos/remake.sh [video ...]     default: add-tick household-sync
#
# The stack is fg's instance on FG_PORT_PREFIX (FG_PROJECT_ID), started with `fg up --only stack`
# when it is not running. With FG_STACK_WORKDIR set (a caller's own stack, verify-snacklist's
# env.sh) that stack must already run. Needs README.md's toolchain: Xvfb, ffmpeg, Deno, Node 22+,
# xdotool ($XDOTOOL, else on PATH, else ~/tools/xdo/xdotool), the marionette CLI and Docker
# where CMake is missing (flutter build linux then runs in the linux-build container).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../scripts/lib.sh
source "$here/../../scripts/lib.sh"
videos=("$@")
[[ ${#videos[@]} -gt 0 ]] || videos=(add-tick household-sync)

export FG_SURFACE=linux PATH="$HOME/.pub-cache/bin:$PATH"
if [[ -z ${XDOTOOL:-} ]]; then
  XDOTOOL="$(command -v xdotool || echo "$HOME/tools/xdo/xdotool")"
  export XDOTOOL
fi
[[ -x $XDOTOOL ]] || { echo "remake: no xdotool (set XDOTOOL)" >&2; exit 1; }
for tool in Xvfb ffmpeg deno node marionette; do
  command -v "$tool" >/dev/null || { echo "remake: $tool is not on PATH (marketing/videos/README.md)" >&2; exit 1; }
done

if [[ -n ${FG_STACK_WORKDIR:-} ]]; then
  workdir="$FG_STACK_WORKDIR"
else
  log "fg up --only stack (ports ${FG_PORT_PREFIX:-543}xx)"
  "$REPO_ROOT/scripts/fg" up --only stack >/dev/null
  workdir="${FG_STATE_DIR:-$HOME/.cache/fg/${FG_PORT_PREFIX:-543}}/stack"
fi
status="$(supabase status -o env --workdir "$workdir" 2>/dev/null)" || true
api_url="$(sed -n 's/^API_URL="\(.*\)"$/\1/p' <<<"$status")"
key="$(sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p' <<<"$status")"
[[ -n $api_url && -n $key ]] || { echo "remake: no running stack in $workdir" >&2; exit 1; }

# The bundle has the stack's URL and key built in: rebuild when they or app/ changed.
bundle="$REPO_ROOT/app/build/linux/x64/profile/bundle"
stamp="$( { git -C "$REPO_ROOT" rev-parse HEAD:app; git -C "$REPO_ROOT" diff HEAD -- app; echo "$api_url $key"; flutter_dir; } | sha256sum | cut -c1-16)"
if [[ "$(cat "$bundle/.capture-stamp" 2>/dev/null)" != "$stamp" ]]; then
  command -v cmake >/dev/null || PATH="$REPO_ROOT/.cursor/skills/verify-family-groceries/linux-build:$PATH"
  build_log="$(mktemp -t remake-linux-build.XXXXXX)"
  log "flutter build linux --profile (Marionette entry point) against $api_url; log: $build_log"
  (cd "$REPO_ROOT/app" && flutter build linux --profile -t test_driver/main_marionette.dart \
    --dart-define=SUPABASE_URL="$api_url" --dart-define=SUPABASE_PUBLISHABLE_KEY="$key" \
    --dart-define=FAKE_STORE=ok >"$build_log" 2>&1) \
    || { echo "remake: linux build failed; see $build_log" >&2; exit 1; }
  echo "$stamp" >"$bundle/.capture-stamp"
fi

export CAPTURE_BUNDLE="$bundle/family_groceries"
for v in "${videos[@]}"; do
  for lang in de en; do
    log "take: $v $lang"
    deno run -A "$here/capture/take.ts" "$v" "$lang"
  done
done
cd "$here"
[[ -d node_modules ]] || npm ci --no-audit --no-fund >/dev/null
node build.mjs "${videos[@]}"
# The file, seam and latency tables in each <video>/REVIEW.md.
node report.mjs "${videos[@]}" >/dev/null
