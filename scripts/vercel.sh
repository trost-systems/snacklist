#!/usr/bin/env bash
# Vercel's install and build steps (vercel.json runs `scripts/vercel.sh install|build`).
# Vercel restores node_modules/ between builds, so the Flutter SDK and the pub cache live there.
#
#   scripts/vercel.sh install
#   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/vercel.sh build
# Optional (job 19, docs/ANALYTICS.md): POSTHOG_PROJECT_API_KEY and POSTHOG_HOST turn analytics on;
# with POSTHOG_PERSONAL_API_KEY and POSTHOG_PROJECT_ID the source map goes to PostHog too.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLUTTER_VERSION="$(sed -n 's/^  FLUTTER_VERSION: *//p' .github/workflows/ci.yml)"
FLUTTER_ROOT="$PWD/node_modules/.flutter"
export PUB_CACHE="$PWD/node_modules/.pub-cache"
export PATH="$FLUTTER_ROOT/bin:$PATH"
export CI=true

fail() { echo "vercel.sh: $*" >&2; exit 1; }
trap 'echo "vercel.sh: failed (exit $?) at line $LINENO: $BASH_COMMAND" >&2' ERR

install() {
  [[ -n $FLUTTER_VERSION ]] || fail "no FLUTTER_VERSION in .github/workflows/ci.yml"
  # shellcheck source=/dev/null
  echo "vercel.sh: Flutter $FLUTTER_VERSION, uid $(id -u), $(. /etc/os-release && echo "$PRETTY_NAME")"
  local missing=() tool
  for tool in git curl unzip xz which tar find; do
    command -v "$tool" >/dev/null || missing+=("${tool/#find/findutils}")
  done
  if ((${#missing[@]})); then dnf install -y -q "${missing[@]}"; fi
  # The restored cache belongs to another uid; Flutter reads its version from git.
  git config --global --add safe.directory '*'

  if [[ "$(git -C "$FLUTTER_ROOT" describe --tags --exact-match 2>/dev/null)" != "$FLUTTER_VERSION" ]]; then
    rm -rf "$FLUTTER_ROOT"
    git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
  fi
  flutter --disable-analytics >/dev/null
  flutter precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia
  flutter --version
  (cd app && flutter pub get --enforce-lockfile)
}

build() {
  [[ -n ${SUPABASE_URL:-} ]] || fail "set SUPABASE_URL (https://<ref>.supabase.co) in the Vercel project"
  [[ $SUPABASE_URL == https://*.supabase.co ]] || fail "SUPABASE_URL must be https://<ref>.supabase.co"
  [[ ${SUPABASE_PUBLISHABLE_KEY:-} == sb_publishable_* ]] \
    || fail "set SUPABASE_PUBLISHABLE_KEY to the project's publishable key (sb_publishable_...); never a secret key"
  # Analytics (job 19, docs/ANALYTICS.md): on only when the Vercel project sets the PostHog
  # project key and host; the app accepts only https://eu.i.posthog.com.
  local analytics=()
  local name
  for name in POSTHOG_PROJECT_API_KEY POSTHOG_HOST ANALYTICS_INTERNAL_HOUSEHOLDS; do
    if [[ -n ${!name:-} ]]; then analytics+=("--dart-define=$name=${!name}"); fi
  done
  # Preview deployments (main on preview.app.hummlist.com) are ours: every event internal.
  if [[ ${VERCEL_ENV:-} != production ]]; then analytics+=(--dart-define=ANALYTICS_INTERNAL_BUILD=true); fi
  echo "vercel.sh: analytics $([[ -n ${POSTHOG_PROJECT_API_KEY:-} ]] && echo on || echo off)"
  # Job 67 (docs/PAYWALL_RELEASE.md): the integration settings' Premium card, when the Vercel
  # project sets INTEGRATION_LOCK=true. The web app never sells, so no purchase defines.
  local premium=()
  if [[ ${INTEGRATION_LOCK:-} == true ]]; then premium=(--dart-define=INTEGRATION_LOCK=true); fi
  # Readable web stack traces need the source map in PostHog: only with a personal key (error
  # tracking write, Einkauf only) and the project id in the Vercel project.
  local maps=()
  if [[ -n ${POSTHOG_PROJECT_API_KEY:-} && -n ${POSTHOG_PERSONAL_API_KEY:-} && -n ${POSTHOG_PROJECT_ID:-} ]]; then
    maps=(--source-maps)
  fi
  cd app
  flutter build web --release --no-web-resources-cdn --wasm --base-href / \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
    --dart-define-from-file=config/auth.json ${analytics[@]+"${analytics[@]}"} ${premium[@]+"${premium[@]}"} \
    ${maps[@]+"${maps[@]}"}
  ../scripts/join-config.sh build/web
  if ((${#maps[@]})); then
    # Chunk ids into main.dart.js, the map to PostHog, then the map deleted so it is not served.
    # A failed upload does not stop the deploy: the traces just stay minified.
    if ! POSTHOG_CLI_API_KEY="$POSTHOG_PERSONAL_API_KEY" POSTHOG_CLI_PROJECT_ID="$POSTHOG_PROJECT_ID" \
      npx --yes @posthog/cli@0.19.0 --host https://eu.posthog.com sourcemap process \
      --directory build/web --release-name hummlist-web \
      --release-version "${VERCEL_GIT_COMMIT_SHA:-local}" --delete-after; then
      echo "vercel.sh: source map upload to PostHog failed; web stack traces stay minified" >&2
    fi
    rm -f build/web/*.map
  fi
}

case "${1:-}" in
  install | build) "$1" ;;
  *) fail "usage: scripts/vercel.sh install|build" ;;
esac
