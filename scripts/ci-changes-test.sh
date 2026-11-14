#!/usr/bin/env bash
# Tests which gates scripts/ci-changes.sh asks for, per changed path, in a scratch repository,
# and that a change to a gate's own script always runs that gate's job (its switch in ci.yml's
# `if:`). Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

git init -q -b main "$tmp/repo"
cd "$tmp/repo"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
base="$(git rev-parse HEAD)"

# ci-changes.sh's answer for a commit that changes these paths, as "heavy=true native=false ...".
changed() {
  git checkout -q --detach "$base"
  local path
  for path in "$@"; do
    mkdir -p "$(dirname "$path")"
    echo x >"$path"
  done
  git add -A
  git -c user.name=t -c user.email=t@t commit -q -m change
  "$REPO_ROOT/scripts/ci-changes.sh" "$base" HEAD | tr '\n' ' ' | sed 's/ $//'
}
# The switches that are on, in the order heavy native fastlane emails: "heavy native", or "none".
expect() {
  local want="$1" got on
  shift
  got="$(changed "$@")"
  on="$(tr ' ' '\n' <<<"$got" | sed -n 's/=true$//p' | tr '\n' ' ' | sed 's/ $//')"
  [[ ${on:-none} == "$want" ]] || fail "$* turns on '${on:-none}', want '$want' ($got)"
}
everything="heavy native fastlane emails"

[[ "$("$REPO_ROOT/scripts/ci-changes.sh" | tr '\n' ' ')" == "heavy=true native=true fastlane=true emails=true " ]] \
  || fail "without a range everything runs"
[[ "$("$REPO_ROOT/scripts/ci-changes.sh" "$base" "$base" | tr '\n' ' ')" == "heavy=true native=true fastlane=true emails=true " ]] \
  || fail "an empty range runs everything"

expect none docs/CI.md
expect none README.md site/content/guide.md .github/pull_request_template.md
expect none .github/workflows/e2e.yml scripts/ci-e2e.sh
expect heavy .cursor/skills/verify-snacklist/features/list.md
expect heavy app/lib/main.dart
expect heavy docs/CI.md supabase/migrations/20261114000000_x.sql
expect "heavy native" app/ios/Runner/AppDelegate.swift
expect "heavy native" app/android/app/build.gradle.kts
expect "heavy native" app/pubspec.yaml
expect "heavy native" app/pubspec.lock
expect "heavy native" scripts/siri-vocabulary.py
expect "heavy native" scripts/app-shortcuts-bundle.py
expect "heavy fastlane" app/fastlane/Fastfile
expect "heavy fastlane" app/Gemfile.lock
expect "heavy emails" emails/src/welcome.tsx
expect "heavy emails" supabase/templates/invite.html
expect "heavy emails" supabase/config.toml
expect "heavy emails" design/tokens/tokens.json
expect "heavy emails" site/public/email/logo.png
expect "heavy native emails" app/ios/Podfile emails/package.json

# The CI definition runs everything.
for path in .github/workflows/ci.yml .github/actions/deno/action.yml scripts/ci-changes.sh scripts/lib.sh scripts/e2e-summary.sh; do
  expect "$everything" "$path"
  expect "$everything" docs/CI.md "$path"
done

# A gate's script runs the heavy gates and its own job, and the native gates only when it is theirs.
switch_of() {
  sed -n "/^  $1:$/,/^  [a-zA-Z0-9_-]*:$/s/^    if: needs\.changes\.outputs\.\([a-z]*\) == 'true'$/\1/p" "$REPO_ROOT/.github/workflows/ci.yml"
}
[[ "$(switch_of ios)" == native && "$(switch_of e2e)" == heavy && -z "$(switch_of lint)" ]] \
  || fail "ci.yml's jobs no longer name their switch as \"if: needs.changes.outputs.<switch> == 'true'\""
for file in "$REPO_ROOT"/scripts/gates/*.sh; do
  gate="$(basename "$file" .sh)"
  switch="$(switch_of "$gate")"
  case "$switch" in
    "" | heavy) want=heavy ;;
    native) want="heavy native" ;;
    fastlane) want="heavy fastlane" ;;
    emails) want="heavy emails" ;;
    *) fail "ci.yml job '$gate' runs on the switch '$switch', which this test does not know"; continue ;;
  esac
  expect "$want" "scripts/gates/$gate.sh"
done

((failures == 0)) || { echo "ci-changes-test: $failures failed" >&2; exit 1; }
log "ci-changes.sh asks for the gates each path needs: all cases pass"
