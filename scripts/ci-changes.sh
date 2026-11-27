#!/usr/bin/env bash
# Which CI gates a change needs, as key=value lines for $GITHUB_OUTPUT:
#   heavy     the deno job (functions, nexus, fg-cli); false only when every file is documentation
#   stack     db and e2e, the gates on the local Supabase stack: off when every file is
#             documentation or off the app (the public site, the ops dashboard, marketing,
#             research, the MCP proxy's Vercel project, the hotspot and hill-climb tools)
#   app       flutter and web-prod, which build and test app/: off, in addition, when the rest is
#             the server or the e2e suite (supabase/, alexa/, e2e/); on for the server files,
#             docs and guides the Flutter tests read (ci-changes-test.sh finds those in app/)
#   native    android, ios and ios-storekit; only when the native projects or pubspec, these
#             gates, their iOS build (scripts/ios/build-for-testing.sh) or the checks the ios gate runs on the
#             built app change. They compile the
#             app's Swift and Kotlin and the plugin registrant from pubspec, and android runs
#             the Kotlin's JVM unit tests; the Dart in app/lib
#             is compiled by the flutter, web-prod and e2e gates already.
#   fastlane  only when app/fastlane/, app/Gemfile*, its gate or play-listing.yml changes
#   emails    only when the mails' sources or outputs change: emails/, supabase/templates/,
#             supabase/config.toml, the design tokens, the mail assets in site/public/email/
#             or its gate
# Without a range (the nightly run, a manual run) and when the CI definition itself changes
# (this script, ci.yml, the composite actions it uses, lib.sh, the e2e summary), everything
# runs. A gate's own script is code: it runs the heavy gates, and its own gate where that has a
# switch (job 221: of 136 merged PRs, 10 ran android and ios only for another gate's script).
# The on-demand e2e (e2e.yml, scripts/ci-e2e.sh, job 27) is not part of ci.yml:
# alone it needs only the lint gate (actionlint, shellcheck, check-gates), which always runs.
# A push to main gets its commit's range, unless it reuses its PR's run (scripts/ci-main-reuse.sh).
# releases/flags.json is code, except where a change touches only holds.* and none of APP_HOLDS
# (job 475): the site alone reads those holds (and the changelog gate, in the lint job), so the
# change counts like a site file. A flags.* edit, a hold added or removed, or invalid JSON stays code.
# Usage: scripts/ci-changes.sh [<base> <head>]
set -euo pipefail

all() { printf 'heavy=true\nstack=true\napp=true\nnative=true\nfastlane=true\nemails=true\n'; exit 0; }
[[ $# == 2 ]] || all
# --no-renames: a file moved out of app/ios/ is a change there, and git would name only where it went.
# core.quotePath=false: git would quote a non-ASCII name ("app/ios/\303\244.swift"), which no rule matches.
files="$(git -c core.quotePath=false diff --name-only --no-renames "$1" "$2")"
[[ -n $files ]] || all
grep -qE '^(\.github/workflows/ci\.yml|\.github/actions/|scripts/ci-changes\.sh|scripts/lib\.sh|scripts/e2e-summary\.sh)' <<<"$files" && all
# The holds of releases/flags.json read outside site/ and the lint job: the Fastfile's NATIVE_SIRI_LIVE
# define and the store metadata check. ci-changes-test.sh fails when another file starts reading one.
APP_HOLDS='native-siri integration-lock'
# Whether releases/flags.json differs between $1 and $2 only in holds the app does not read.
site_holds_only() {
  local base head
  base="$(git show "$1:releases/flags.json" 2>/dev/null)" && head="$(git show "$2:releases/flags.json" 2>/dev/null)" || return 1
  BASE="$base" HEAD="$head" node -e '
    const [base, head] = [process.env.BASE, process.env.HEAD].map((text) => JSON.parse(text));
    const holds = (json) => json.holds !== null && typeof json.holds === "object" && !Array.isArray(json.holds) ? json.holds : process.exit(1);
    const rest = (json) => JSON.stringify({ ...json, holds: null });
    const [was, is] = [holds(base), holds(head)];
    const keys = (h) => JSON.stringify(Object.keys(h).sort());
    if (rest(base) !== rest(head) || keys(was) !== keys(is)) process.exit(1);
    const changed = Object.keys(is).filter((key) => JSON.stringify(was[key]) !== JSON.stringify(is[key]));
    process.exit(changed.some((key) => process.argv[1].split(" ").includes(key)) ? 1 : 0);
  ' "$APP_HOLDS" 2>/dev/null
}
site_holds=false
if grep -qx 'releases/flags.json' <<<"$files" && site_holds_only "$1" "$2"; then
  site_holds=true
  files="$(grep -vx 'releases/flags.json' <<<"$files" || true)"
fi

# What the Flutter tests read outside app/ (job 309): parity tables and sources shared with the
# server, the release runbook and consent texts, the guides, the site's app-association files (job 462).
# Documentation or not, it is the app's.
app_reads='^supabase/(classifier/|tests/[^/]*\.(tsv|json)$|functions/_shared/(consent_version|http)\.ts$)|^docs/(RELEASE\.md$|consent/)|^site/content/guides/|^site/public/\.well-known/'
# Documentation the nexus tests read (the hill-climb docs on main).
gate_reads='^docs/hillclimb/'
# Documentation: docs/ and Markdown, except the verify skill's files, which its CLI reads.
code="$( (grep -vE '^docs/' <<<"$files" | grep -vE '^[^.].*\.md$|^\.github/.*\.md$' \
  | grep -vxE '\.github/workflows/e2e\.yml|scripts/ci-e2e\.sh'; grep -E "$app_reads|$gate_reads" <<<"$files") | sort -u || true)"
# Documentation that counts as code here (the two lists above) is off the stack too.
off_app='^(site|nexus|marketing|research|mcp-proxy|docs)/|^tool/(hotspots|hillclimb)/'
stack_only='^(supabase|alexa|e2e)/'
heavy=$site_holds stack=false app=false native=false fastlane=false emails=false
if [[ -n $code ]]; then
  heavy=true
  grep -qvE "$off_app" <<<"$code" && stack=true
  grep -qvE "$off_app|$stack_only" <<<"$code" && stack=true app=true
  grep -qE "$app_reads" <<<"$code" && app=true
fi
grep -qE '^app/(ios|android)/|^app/pubspec\.(yaml|lock)$|^scripts/gates/(android|ios|ios-storekit)\.sh$|^scripts/ios/build-for-testing\.sh$|^scripts/(siri-vocabulary|app-shortcuts-bundle)\.py$' <<<"$files" && native=true
grep -qE '^app/(fastlane/|Gemfile)|^scripts/gates/fastlane\.sh$|^\.github/workflows/play-listing\.yml$' <<<"$files" && fastlane=true
grep -qE '^(emails/|supabase/templates/|supabase/config\.toml$|design/tokens/|site/public/email/|scripts/gates/emails\.sh$)' <<<"$files" && emails=true
printf 'heavy=%s\nstack=%s\napp=%s\nnative=%s\nfastlane=%s\nemails=%s\n' "$heavy" "$stack" "$app" "$native" "$fastlane" "$emails"
