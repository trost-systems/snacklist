# shellcheck shell=bash
# Sourced after verify-snacklist's env.sh by the web captures (scripts/store-screenshots.sh,
# site/scenes/capture-hero.sh): the build gets exactly the launch flags of
# marketing/capture-flags.mjs, whatever releases/flags.json rolls out.
capture_flags="$(node "$REPO_ROOT/marketing/capture-flags.mjs")"
export VH_FLAGS_FULL=0 VH_FLAGS_OFF="" VH_DEFINES="FLAGS_ON=$capture_flags ${VH_DEFINES:-}"

# Fails unless the FLAGS_ON compiled into the served web build is the launch build's.
capture_check_web_build() {
  node "$REPO_ROOT/marketing/capture-flags.mjs" --check-build "$VH_BUILD_DIR/main.dart.wasm" "$VH_BUILD_DIR/main.dart.js"
}
