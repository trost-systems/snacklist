# shellcheck shell=bash
# Sourced by the verify-snacklist helpers. The instance is this checkout's own Supabase stack (its
# port block in supabase/config.toml), a static server for the web build on <prefix>81 and one
# fg seed run of demo users. Override with VH_* variables; never point them at another job's stack.
VH_HELPERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VH_SKILL="$(dirname "$VH_HELPERS")"
# shellcheck source=../../../../scripts/lib.sh
source "$VH_HELPERS/../../../../scripts/lib.sh"
# shellcheck disable=SC1091 # the Hetzner runner's PATH (flutter, supabase, node); absent elsewhere
[[ -f $HOME/groceries-ops/env.hz ]] && source "$HOME/groceries-ops/env.hz"
# env.hz resets PATH to ~/flutter: the SDK scripts/lib.sh chose (flutter_dir) goes first again.
PATH="$(flutter_dir)/bin:$PATH"
export PATH

VH_PREFIX="$(sed -n 's/^port = \([56][0-9][0-9]\)21$/\1/p' "$REPO_ROOT/supabase/config.toml" | head -1)"
VH_PROJECT_ID="$(project_id)"
VH_STATE_DIR="${VH_STATE_DIR:-$HOME/.cache/verify-snacklist/$VH_PREFIX}"
VH_EVIDENCE_DIR="${VH_EVIDENCE_DIR:-$HOME/snacklist-evidence}"
VH_WEB_PORT="${VH_WEB_PORT:-${VH_PREFIX}81}"
VH_WEB_URL="http://127.0.0.1:$VH_WEB_PORT"
VH_BUILD_DIR="$REPO_ROOT/app/build/verify-snacklist-web"
VH_INSTANCE="$VH_STATE_DIR/instance.json"
# Server switches (public.app_switches) production has on for everyone; launch.sh turns them on,
# doctor.sh checks them. The migrations seed every switch off.
VH_USER_SWITCHES="'public_api', 'unified_keys'"
export VH_HELPERS VH_SKILL VH_PREFIX VH_PROJECT_ID VH_STATE_DIR VH_EVIDENCE_DIR VH_WEB_PORT VH_WEB_URL VH_BUILD_DIR VH_INSTANCE VH_USER_SWITCHES

# fg (seed, teardown, db query) on this checkout's stack, with its run files in our state dir.
export FG_PORT_PREFIX="$VH_PREFIX" FG_PROJECT_ID="$VH_PROJECT_ID" FG_STACK_WORKDIR="$REPO_ROOT" \
  FG_STATE_DIR="$VH_STATE_DIR/fg" FG_EVIDENCE_DIR="$VH_EVIDENCE_DIR"

# What a production build gets (app/config/auth.json minus the hosted Google client and APP_URL),
# with the e2e stand-in PostHog host so nothing reaches a real PostHog project.
# VH_DEFINES adds space-separated NAME=value pairs, e.g. "FLAGS_ON=hide-categories LEGAL_DRAFTS=true".
# FLAGS_ON always holds the flags releases/flags.json rolls out to everyone ("full"), because users
# get them and this build reaches no PostHog; VH_FLAGS_FULL=0 leaves them out (the sheet a new
# install sees before PostHog's first answer), VH_FLAGS_OFF (comma-separated) leaves out only those.
vh_defines() {
  local extra="" pair flags=""
  if [[ ${VH_FLAGS_FULL:-1} != 0 ]]; then flags="$(vh_full_flags)" || return 1; fi
  for pair in ${VH_DEFINES:-}; do
    if [[ ${pair%%=*} == FLAGS_ON ]]; then [[ -z ${pair#*=} ]] || flags="${flags:+$flags,}${pair#*=}"; else extra+="$(printf ',\n  "%s": "%s"' "${pair%%=*}" "${pair#*=}")"; fi
  done
  [[ -z $flags ]] || extra+="$(printf ',\n  "FLAGS_ON": "%s"' "$flags")"
  cat <<JSON
{
  "GOOGLE_WEB_CLIENT_ID": "family-groceries-e2e",
  "SIGN_IN_WITH_APPLE": "true",
  "POSTHOG_PROJECT_API_KEY": "phc_e2e_fake_collector",
  "POSTHOG_HOST": "https://posthog.invalid"$extra
}
JSON
}

# The source the web build comes from: app/'s tree at HEAD plus any uncommitted change under app/,
# and the Flutter version CI builds with (launch.sh refuses any other).
vh_build_stamp() {
  { git -C "$REPO_ROOT" rev-parse HEAD:app; git -C "$REPO_ROOT" diff HEAD -- app; vh_defines; vh_flutter_version; } | sha256sum | cut -c1-16
}

vh_full_flags() {
  node -e 'const f=require(process.argv[1]).flags;const full=Object.keys(f).filter(k=>f[k].rollout==="full");const off=process.argv[2].split(",").map(s=>s.trim()).filter(Boolean);const bad=off.filter(k=>!full.includes(k));if(bad.length){console.error(`VH_FLAGS_OFF: not a full-rollout flag in releases/flags.json: ${bad.join(", ")}`);process.exit(1)}console.log(full.filter(k=>!off.includes(k)).join(","))' "$REPO_ROOT/releases/flags.json" "${VH_FLAGS_OFF:-}"
}

vh_flutter_version() { sed -n 's/^ *FLUTTER_VERSION: *//p' "$REPO_ROOT/.github/workflows/ci.yml" | head -1; }

# The Flutter on PATH, or "unknown" when there is none or it prints no version.
vh_flutter_have() {
  { flutter --version --machine 2>/dev/null || true; } |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s.slice(s.indexOf("{"))).frameworkVersion)}catch{console.log("unknown")}})'
}

vh_json() { node -e 'const s=require(process.argv[1]);console.log(process.argv[2].split(".").reduce((o,k)=>o?.[k],s)??"")' "$VH_INSTANCE" "$1"; }

# The pid listening on the web port, if any.
vh_server_pid() { ss -ltnpH "sport = :$VH_WEB_PORT" 2>/dev/null | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1; }
