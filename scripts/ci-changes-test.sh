#!/usr/bin/env bash
# Tests which gates scripts/ci-changes.sh asks for, per changed path, in a scratch repository,
# and that a change to a gate's own script, or to a script it runs as "$REPO_ROOT/scripts/...",
# turns on the switch that gate's job in ci.yml runs on. Run by the lint gate.
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
# The same for a script a gate runs: these switches at least.
expect_at_least() {
  local want="$1" got switch
  shift
  got="$(changed "$@")"
  for switch in $want; do
    [[ " $got " == *" $switch=true "* ]] || fail "$* does not turn on '$switch' ($got)"
  done
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

# The lines of a job in ci.yml that decide whether it runs for a change, or could: every line
# that says `needs` (the key, since a job that needs a skipped job is skipped, and the context),
# a YAML merge, and an `if:` whose condition is an alias or sits on the lines after it. A comment
# does not end the job.
asks_of() {
  awk -v job="  $1:" '$0 == job { on = 1; next } on && /^ {0,2}[^ #]/ { exit } on' "$ci" \
    | grep -vE '^ *#' | grep -iE 'needs|<<:|^ *(- )?if:[[:space:]]*([|>*&].*)?$' || true
}
ci="$REPO_ROOT/.github/workflows/ci.yml"
# The switches the jobs read are the filter's, each under its own name.
for switch in $everything; do
  grep -qxF "      $switch: \${{ steps.filter.outputs.$switch }}" "$ci" \
    || fail "ci.yml's changes job no longer hands on the filter's '$switch' as its output '$switch'"
done
grep -qxF "      reuse: \${{ steps.filter.outputs.reuse }}" "$ci" \
  || fail "ci.yml's changes job no longer hands on scripts/ci-main-reuse.sh's 'reuse' as its output 'reuse'"
# A gate's script runs the heavy gates and its own job, and the native gates only when it is theirs.
for file in "$REPO_ROOT"/scripts/gates/*.sh; do
  gate="$(basename "$file" .sh)"
  grep -qx "  $gate:" "$ci" || { fail "ci.yml has no job '$gate'"; continue; }
  asks="$(asks_of "$gate")"
  want=""
  [[ -z $asks ]] && want=heavy # the job does not ask the filter: changelog
  # Job 308: runs for every change, but not on a push to main that reuses its PR's run.
  [[ $asks == "    needs: changes"$'\n'"    if: needs.changes.outputs.reuse != 'true'" ]] && want=heavy
  for switch in $everything; do
    [[ $asks == "    needs: changes"$'\n'"    if: needs.changes.outputs.$switch == 'true'" ]] || continue
    want="heavy $switch"
    [[ $switch == heavy ]] && want=heavy
  done
  if [[ -z $want ]]; then
    fail "ci.yml job '$gate' asks the filter in a way this test cannot read. It reads two lines, the job's own \"    needs: changes\" and \"    if: needs.changes.outputs.<switch> == 'true'\", and found: $asks"
    continue
  fi
  expect "$want" "scripts/gates/$gate.sh"
  # What a gate runs from scripts/ must turn its switch on too (the ios gate's two Python
  # checks ran no build until job 221).
  while read -r path; do
    [[ -z $path ]] || expect_at_least "$want" "$path"
  done < <(grep -vE '^ *#' "$file" | grep -oE 'REPO_ROOT/scripts/[A-Za-z0-9_./-]+' | sed 's|^REPO_ROOT/||' | sort -u)
done
for job in ios ios-storekit; do
  [[ "$(asks_of "$job")" == "    needs: changes"$'\n'"    if: needs.changes.outputs.native == 'true'" ]] || fail "the $job job no longer runs on the native switch"
done

# A file moved out of a native path is a change there.
git checkout -q --detach "$base"
mkdir -p app/ios/Runner docs
printf 'one\ntwo\nthree\n' >app/ios/Runner/Notes.swift
git add -A
git -c user.name=t -c user.email=t@t commit -q -m before
before="$(git rev-parse HEAD)"
git mv app/ios/Runner/Notes.swift docs/notes.md
git -c user.name=t -c user.email=t@t commit -q -m moved
got="$("$REPO_ROOT/scripts/ci-changes.sh" "$before" HEAD | tr '\n' ' ')"
[[ $got == "heavy=true native=true fastlane=false emails=false " ]] || fail "a file moved from app/ios/ to docs/ gives '$got'"

((failures == 0)) || { echo "ci-changes-test: $failures failed" >&2; exit 1; }
log "ci-changes.sh asks for the gates each path needs: all cases pass"
