#!/usr/bin/env bash
# Starts a verify-hummlist instance from whatever is there: this checkout's Supabase stack
# (migrations applied by `supabase start`), the release web build, its static server and a seeded
# demo household, then signs the first member in through the real login screen.
# Prints `READY <url> run=<run>` as its last line once a signed-in list shows the seeded items.
#
#   launch.sh [--scenario demo-familie] [--fresh] [--rebuild]
#     --scenario  a test/fixtures/scenarios/ name (demo-familie, demo-family-en, heavy-history ...)
#     --fresh     tear the current run down and seed a new one
#     --rebuild   build the web app even if the build matches the source
set -euo pipefail
source "$(dirname "$0")/env.sh"

scenario=demo-familie fresh=0 rebuild=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) scenario="$2"; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --rebuild) rebuild=1; shift ;;
    *) echo "unknown argument $1 (launch.sh [--scenario <name>] [--fresh] [--rebuild])" >&2; exit 64 ;;
  esac
done
[[ -f "$REPO_ROOT/test/fixtures/scenarios/$scenario.yaml" ]] || { echo "no scenario $scenario in test/fixtures/scenarios/" >&2; exit 64; }
if [[ $VH_PREFIX == 543 && -z ${VH_ALLOW_543:-} ]]; then
  echo "supabase/config.toml still has the canonical 543xx ports; set your job's port block first (COORDINATION.md)" >&2
  exit 64
fi
mkdir -p "$VH_STATE_DIR/fg" "$VH_EVIDENCE_DIR"

started_stack=false
[[ -f $VH_INSTANCE && "$(vh_json startedStack)" == true ]] && started_stack=true
if ! stack_running; then
  log "starting the Supabase stack $VH_PROJECT_ID (ports ${VH_PREFIX}xx)"
  started_stack=true
fi
supabase_up >/dev/null

stamp="$(vh_build_stamp)"
if [[ $rebuild == 1 || ! -f $VH_BUILD_DIR/index.html || "$(cat "$VH_BUILD_DIR/.vh-stamp" 2>/dev/null)" != "$stamp" ]]; then
  log "flutter build web (release, wasm) against $SUPABASE_URL"
  defines="$(mktemp --suffix=.json)"
  vh_defines >"$defines"
  (cd "$REPO_ROOT/app" && flutter pub get >/dev/null && flutter build web --release --no-web-resources-cdn --wasm \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
    --dart-define-from-file="$defines" >"$VH_STATE_DIR/build.log" 2>&1 \
    && "$REPO_ROOT/scripts/join-config.sh" build/web) \
    || { rm -f "$defines"; echo "web build failed; see $VH_STATE_DIR/build.log" >&2; exit 1; }
  rm -f "$defines"
  # flutter build web --output leaves out assets/FontManifest.json (no text renders), so the build
  # goes to app/build/web and is copied; the e2e gate's next run rebuilds app/build/web anyway.
  rm -rf "$VH_BUILD_DIR"
  cp -r "$REPO_ROOT/app/build/web" "$VH_BUILD_DIR"
  echo "$stamp" >"$VH_BUILD_DIR/.vh-stamp"
fi

[[ -d $REPO_ROOT/e2e/node_modules ]] || (cd "$REPO_ROOT/e2e" && npm ci >/dev/null)
posthog_host="$(sed -n 's/^ *"POSTHOG_HOST": *"\([^"]*\)".*/\1/p' "$REPO_ROOT/app/config/e2e.json")"
pid="$(vh_server_pid)"
if [[ -n $pid ]] && ! tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q "serve.mjs $VH_BUILD_DIR $VH_WEB_PORT"; then
  echo "port $VH_WEB_PORT is held by pid $pid, which is not this instance's server; set VH_WEB_PORT" >&2
  exit 1
fi
if [[ -z $pid ]]; then
  nohup node "$REPO_ROOT/e2e/serve.mjs" "$VH_BUILD_DIR" "$VH_WEB_PORT" --csp "$SUPABASE_URL" "$posthog_host" \
    >"$VH_STATE_DIR/serve.log" 2>&1 &
  for _ in $(seq 50); do curl -fs -o /dev/null "$VH_WEB_URL/" && break; sleep 0.2; done
  pid="$(vh_server_pid)"
  [[ -n $pid ]] || { echo "the web server did not come up; see $VH_STATE_DIR/serve.log" >&2; exit 1; }
fi

run=""
[[ -f $VH_INSTANCE ]] && run="$(vh_json run)"
if [[ -n $run && ( $fresh == 1 || "$(vh_json scenario)" != "$scenario" || ! -f $FG_STATE_DIR/runs/$run.json ) ]]; then
  "$REPO_ROOT/scripts/fg" teardown "$run" >/dev/null 2>&1 || true
  run=""
fi
if [[ -z $run ]]; then
  run="$("$REPO_ROOT/scripts/fg" seed "$scenario" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(!j.ok){console.error(JSON.stringify(j.error));process.exit(1)}console.log(j.run)})')"
fi

cat >"$VH_INSTANCE" <<JSON
{
  "prefix": "$VH_PREFIX",
  "projectId": "$VH_PROJECT_ID",
  "apiUrl": "$SUPABASE_URL",
  "publishableKey": "$SUPABASE_PUBLISHABLE_KEY",
  "mailpitUrl": "$MAILPIT_URL",
  "webUrl": "$VH_WEB_URL",
  "buildDir": "$VH_BUILD_DIR",
  "buildStamp": "$stamp",
  "commit": "$(git -C "$REPO_ROOT" rev-parse --short HEAD)",
  "serverPid": $pid,
  "startedStack": $started_stack,
  "scenario": "$scenario",
  "run": "$run",
  "credentials": "$FG_STATE_DIR/runs/$run.json",
  "evidenceDir": "$VH_EVIDENCE_DIR/$run"
}
JSON
mkdir -p "$VH_EVIDENCE_DIR/$run"
node "$VH_HELPERS/ready.mjs"
echo "READY $VH_WEB_URL run=$run"
