#!/usr/bin/env bash
# Points a web build's join page (app/web/join, job 169b) at the Supabase project the Flutter app
# in that build was built for: writes <web-build>/join/config.js from SUPABASE_URL and
# SUPABASE_PUBLISHABLE_KEY, the two values every web build passes as --dart-define.
#   SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... scripts/join-config.sh app/build/web
set -euo pipefail
out="${1:?usage: scripts/join-config.sh <web-build-dir>}"
fail() { echo "join-config.sh: $*" >&2; exit 1; }
[[ -d $out/join ]] || fail "$out/join is missing; run it on a flutter build web output"
[[ ${SUPABASE_URL:-} =~ ^https?://[A-Za-z0-9.:-]+$ ]] || fail "SUPABASE_URL '${SUPABASE_URL:-}' is not an origin"
[[ ${SUPABASE_PUBLISHABLE_KEY:-} =~ ^[A-Za-z0-9._-]+$ ]] || fail "SUPABASE_PUBLISHABLE_KEY is empty or not a key"
[[ $SUPABASE_PUBLISHABLE_KEY != sb_secret_* ]] || fail "SUPABASE_PUBLISHABLE_KEY is a secret key"
cat >"$out/join/config.js" <<CONFIG
// Written by scripts/join-config.sh for this build.
export const supabaseUrl = '$SUPABASE_URL';
export const publishableKey = '$SUPABASE_PUBLISHABLE_KEY';
CONFIG
