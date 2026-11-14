#!/usr/bin/env bash
# Which CI gates a change needs, as key=value lines for $GITHUB_OUTPUT:
#   heavy     every gate but gitleaks and lint; false only when every file is documentation
#   native    android and ios; only when the native projects or pubspec, these two gates or the
#             checks the ios gate runs on the built app change. They compile the
#             app's Swift and Kotlin and the plugin registrant from pubspec, and android runs
#             the Kotlin's JVM unit tests; the Dart in app/lib
#             is compiled by the flutter, web-prod and e2e gates already.
#   fastlane  only when app/fastlane/, app/Gemfile* or its gate changes
#   emails    only when the mails' sources or outputs change: emails/, supabase/templates/,
#             supabase/config.toml, the design tokens, the mail assets in site/public/email/
#             or its gate
# Without a range (a push to main, a manual run) and when the CI definition itself changes
# (this script, ci.yml, the composite actions it uses, lib.sh, the e2e summary), everything
# runs. A gate's own script is code: it runs the heavy gates, and its own gate where that has a
# switch (job 221: of 120 merged PRs, 6 ran android and ios only for another gate's script).
# The on-demand e2e (e2e.yml, scripts/ci-e2e.sh, job 27) is not part of ci.yml:
# alone it needs only the lint gate (actionlint, shellcheck, check-gates), which always runs.
# Usage: scripts/ci-changes.sh [<base> <head>]
set -euo pipefail

all() { printf 'heavy=true\nnative=true\nfastlane=true\nemails=true\n'; exit 0; }
[[ $# == 2 ]] || all
files="$(git diff --name-only "$1" "$2")"
[[ -n $files ]] || all
grep -qE '^(\.github/workflows/ci\.yml|\.github/actions/|scripts/ci-changes\.sh|scripts/lib\.sh|scripts/e2e-summary\.sh)' <<<"$files" && all

# Documentation: docs/ and Markdown, except the verify skill's files, which its CLI reads.
code="$(grep -vE '^docs/' <<<"$files" | grep -vE '^[^.].*\.md$|^\.github/.*\.md$' \
  | grep -vxE '\.github/workflows/e2e\.yml|scripts/ci-e2e\.sh' || true)"
heavy=false native=false fastlane=false emails=false
[[ -n $code ]] && heavy=true
grep -qE '^app/(ios|android)/|^app/pubspec\.(yaml|lock)$|^scripts/gates/(android|ios)\.sh$|^scripts/(siri-vocabulary|app-shortcuts-bundle)\.py$' <<<"$files" && native=true
grep -qE '^app/(fastlane/|Gemfile)|^scripts/gates/fastlane\.sh$' <<<"$files" && fastlane=true
grep -qE '^(emails/|supabase/templates/|supabase/config\.toml$|design/tokens/|site/public/email/|scripts/gates/emails\.sh$)' <<<"$files" && emails=true
printf 'heavy=%s\nnative=%s\nfastlane=%s\nemails=%s\n' "$heavy" "$native" "$fastlane" "$emails"
