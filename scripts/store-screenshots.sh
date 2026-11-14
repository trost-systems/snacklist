#!/usr/bin/env bash
# The Play and App Store screenshots, the Play feature graphic and icon, from the real Snacklist
# web build against this checkout's local stack with the demo household „Unser Haushalt“
# (docs/STORE_SCREENSHOTS.md). Nothing is uploaded anywhere.
#
#   scripts/store-screenshots.sh [--locale de-DE|en-US|all] [--store play|appstore|all]
#                                [--assistants neutral|named|named_siri] [--premium-label]
#                                [--compose-only] [--videos] [--keep]
#     --locale         default all
#     --store          default all
#     --assistants     the voice and assist captions: neutral (default), named (Siri, the Snacklist
#                      skill for Amazon Alexa, MCP; waits for Legal and Alexa's certification) or
#                      named_siri (Siri only, App Store; Play keeps the neutral line)
#     --premium-label  „Mit Snacklist Premium“ on the api shot, for once MCP and the API are paid
#                      (Apple 2.3.2); off while they are free
#     --compose-only   frame the captures of the last run in out/raw again (another variant or
#                      label), without stack, build or browser capture
#     --videos         then re-film the site demo loops add-tick and household-sync (marketing/videos)
#     --keep           leave the stack, the web servers and the seeded runs up afterwards
#
# Writes marketing/store-screenshots/out/ (git-ignored): <locale>/<set>/<n>-<shot>.png,
# <locale>/play/feature-graphic.png and icon-512.png, <locale>/contact-sheet.png, manifest.json,
# summary.md. Exits non-zero when a check fails.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# CI runs on the canonical 543xx ports; locally a job uses its own block (COORDINATION.md).
[[ -n ${CI:-} ]] && export VH_ALLOW_543=1
source "$here/../.claude/skills/verify-snacklist/helpers/env.sh"

usage="store-screenshots.sh [--locale de-DE|en-US|all] [--store play|appstore|all] [--assistants neutral|named|named_siri] [--premium-label] [--compose-only] [--videos] [--keep]"
locales=all stores=all assistants=neutral videos=0 keep=0 premium=0 compose_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale) locales="${2:?$usage}"; shift 2 ;;
    --store) stores="${2:?$usage}"; shift 2 ;;
    --assistants) assistants="${2:?$usage}"; shift 2 ;;
    --premium-label) premium=1; shift ;;
    --compose-only) compose_only=1; shift ;;
    --videos) videos=1; shift ;;
    --keep) keep=1; shift ;;
    *) echo "unknown argument $1 ($usage)" >&2; exit 64 ;;
  esac
done
[[ $locales == all ]] && locales=de-DE,en-US
[[ $stores == all ]] && stores=play,appstore
for l in ${locales//,/ }; do [[ $l == de-DE || $l == en-US ]] || { echo "unknown locale $l ($usage)" >&2; exit 64; }; done
for s in ${stores//,/ }; do [[ $s == play || $s == appstore ]] || { echo "unknown store $s ($usage)" >&2; exit 64; }; done
[[ $assistants =~ ^(neutral|named|named_siri)$ ]] || { echo "unknown assistants variant $assistants ($usage)" >&2; exit 64; }

shots="$REPO_ROOT/marketing/store-screenshots"
started=$SECONDS
args=(--locales "$locales" --stores "$stores" --assistants "$assistants")
[[ $premium == 1 ]] && args+=(--premium-label)
if [[ $compose_only == 1 ]]; then
  [[ -d $shots/out/raw ]] || { echo "no captures in $shots/out/raw: run without --compose-only first" >&2; exit 1; }
  log "compose and check ($assistants$([[ $premium == 1 ]] && echo ', premium label')) from out/raw"
  (cd "$shots" && node compose.mjs "${args[@]}")
  log "done in $((SECONDS - started)) s: $shots/out ($(cd "$shots/out" && echo */contact-sheet.png))"
  exit 0
fi

# The api shot comes from a second build of the same app against the production project's URL,
# so the Zugänge screen shows the hosts users see, with the API section on. capture.mjs routes
# every request to that host to the local stack and fails the run on one it did not answer.
prod_url="$(sed -n "s/^ *static const _productionUrl = '\(.*\)';$/\1/p" "$REPO_ROOT/app/lib/app/environment.dart")"
[[ $prod_url =~ ^https://[a-z0-9]+\.supabase\.co$ ]] || { echo "no production URL in app/lib/app/environment.dart" >&2; exit 1; }
api_dir="$REPO_ROOT/app/build/store-screenshots-api-web"
api_port="${VH_PREFIX}82"
api_pidfile="$VH_STATE_DIR/store-screenshots-api.pid"
api_server_ours() { [[ -f $api_pidfile && -r /proc/$(cat "$api_pidfile")/cmdline ]] && tr '\0' ' ' <"/proc/$(cat "$api_pidfile")/cmdline" | grep -q "serve.mjs $api_dir $api_port"; }

cleanup() {
  [[ $keep == 1 ]] && return
  (cd "$shots" && node teardown.mjs) || true
  if api_server_ours; then kill "$(cat "$api_pidfile")" || true; fi
  rm -f "$api_pidfile"
  "$VH_HELPERS/cleanup.sh" >/dev/null || true
}
trap cleanup EXIT

log "stack, web build and server (verify-snacklist launch.sh)"
first="${locales%%,*}"
scenario=store-screenshots
[[ $first == en-US ]] && scenario=store-screenshots-en
# -o: the web server launch.sh leaves running must not inherit the e2e lock (job 73).
flock -o /tmp/fg-e2e.lock "$VH_HELPERS/launch.sh" --scenario "$scenario" --fresh | tail -1

export VH_DEFINES="FLAGS_ON=public-api"
api_stamp="$(vh_build_stamp)-$prod_url"
if [[ "$(cat "$api_dir/.stamp" 2>/dev/null)" != "$api_stamp" ]]; then
  log "flutter build web for the api shot (SUPABASE_URL $prod_url, FLAGS_ON=public-api)"
  key="$(vh_json publishableKey)"
  defines="$(mktemp --suffix=.json)"
  vh_defines >"$defines"
  (cd "$REPO_ROOT/app" && flutter build web --release --no-web-resources-cdn --wasm \
    --dart-define=SUPABASE_URL="$prod_url" --dart-define=SUPABASE_PUBLISHABLE_KEY="$key" \
    --dart-define-from-file="$defines" >"$VH_STATE_DIR/store-screenshots-api-build.log" 2>&1 \
    && SUPABASE_URL="$prod_url" SUPABASE_PUBLISHABLE_KEY="$key" "$REPO_ROOT/scripts/join-config.sh" build/web) \
    || { rm -f "$defines"; echo "api web build failed; see $VH_STATE_DIR/store-screenshots-api-build.log" >&2; exit 1; }
  rm -f "$defines"
  rm -rf "$api_dir"
  cp -r "$REPO_ROOT/app/build/web" "$api_dir"
  echo "$api_stamp" >"$api_dir/.stamp"
fi
unset VH_DEFINES
if ! api_server_ours; then
  posthog_host="$(sed -n 's/^ *"POSTHOG_HOST": *"\([^"]*\)".*/\1/p' "$REPO_ROOT/app/config/e2e.json")"
  nohup node "$REPO_ROOT/e2e/serve.mjs" "$api_dir" "$api_port" --csp "$prod_url" "$posthog_host" \
    >"$VH_STATE_DIR/store-screenshots-api-serve.log" 2>&1 &
  echo $! >"$api_pidfile"
  for _ in $(seq 50); do curl -fs -o /dev/null "http://127.0.0.1:$api_port/" && break; sleep 0.2; done
  api_server_ours || { echo "the api web server did not come up; see $VH_STATE_DIR/store-screenshots-api-serve.log" >&2; exit 1; }
fi
export STORE_SHOTS_API_WEB="http://127.0.0.1:$api_port"

(cd "$shots" && { [[ -d node_modules ]] || npm ci --no-audit --no-fund >/dev/null; })
# Runs a killed capture left behind are listed in out/runs.txt: remove them before out/ goes.
(cd "$shots" && node teardown.mjs)
rm -rf "$shots/out"
log "capture ($locales; $stores), compose and check ($assistants), Chromium under /tmp/fg-e2e.lock"
(cd "$shots" && flock /tmp/fg-e2e.lock bash -c 'node capture.mjs "$@" && node compose.mjs "$@"' _ "${args[@]}")

if [[ $videos == 1 ]]; then
  log "demo videos (marketing/videos/remake.sh add-tick household-sync)"
  "$REPO_ROOT/marketing/videos/remake.sh" add-tick household-sync
fi
log "done in $((SECONDS - started)) s: $shots/out ($(cd "$shots/out" && echo */contact-sheet.png))"
