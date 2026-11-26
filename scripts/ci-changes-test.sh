#!/usr/bin/env bash
# Tests which gates scripts/ci-changes.sh asks for, per changed path, in a scratch repository;
# that a change to a gate's own script, or to a script it runs as "$REPO_ROOT/scripts/...",
# turns on the switch of the ci.yml job that runs that gate; and that every file outside app/
# the Flutter tests read turns on the app switch (job 309). Run by the lint gate.
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

# ci-changes.sh's answer for a commit that changes these paths, as "heavy=true stack=false ...".
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
# The switches that are on, in the order heavy stack app native fastlane emails: "heavy stack", or "none".
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
everything="heavy stack app native fastlane emails"
all_on="heavy=true stack=true app=true native=true fastlane=true emails=true "

[[ "$("$REPO_ROOT/scripts/ci-changes.sh" | tr '\n' ' ')" == "$all_on" ]] || fail "without a range everything runs"
[[ "$("$REPO_ROOT/scripts/ci-changes.sh" "$base" "$base" | tr '\n' ' ')" == "$all_on" ]] || fail "an empty range runs everything"

expect none docs/CI.md
expect none README.md site/content/guide.md .github/pull_request_template.md
expect none .github/workflows/e2e.yml scripts/ci-e2e.sh
expect "heavy stack app" .cursor/skills/verify-snacklist/features/list.md
expect "heavy stack app" app/lib/main.dart
expect "heavy stack app" docs/CI.md scripts/fg
# Off the app (job 309): the site, the ops dashboard, marketing, research, the MCP proxy, the
# measuring tools run neither the stack nor the app's gates.
expect heavy site/build.mjs
expect heavy nexus/web/main.ts marketing/videos/README.txt research/x.json mcp-proxy/vercel.json
expect heavy tool/hotspots/history.py tool/hillclimb/hc-tests/measure.sh docs/CI.md
# The server and the e2e suite run db and e2e, not flutter and web-prod.
expect "heavy stack" supabase/migrations/20261114000000_x.sql
expect "heavy stack" docs/CI.md supabase/migrations/20261114000000_x.sql
expect "heavy stack" supabase/functions/voice/parse.ts alexa/skill-package/skill.json
expect "heavy stack" e2e/tests/list.spec.ts site/build.mjs
# Off the app next to the app is the app.
expect "heavy stack app" site/build.mjs app/lib/main.dart
expect "heavy stack app" supabase/functions/voice/parse.ts tool/item_icons/build.mjs
# What the Flutter tests read outside app/, also when it is documentation.
expect "heavy stack app" supabase/tests/suggest_parity.json
expect "heavy stack app" supabase/classifier/synonyms.tsv
expect "heavy app" docs/RELEASE.md
expect "heavy app" docs/ANALYTICS.md
expect "heavy stack app" supabase/functions/_shared/telemetry.ts
expect "heavy app" site/content/guides/de/siri-kurzbefehl.md
# Documentation a gate reads: the nexus tests read the hill-climb docs.
expect heavy docs/hillclimb/hc-tests.md
# A non-ASCII name, which git quotes unless told not to, still matches its rule.
expect "heavy stack app native" "app/ios/Runner/Ä.swift"
expect "heavy stack app native" app/ios/Runner/AppDelegate.swift
expect "heavy stack app native" app/android/app/build.gradle.kts
expect "heavy stack app native" app/pubspec.yaml
expect "heavy stack app native" app/pubspec.lock
expect "heavy stack app native" scripts/siri-vocabulary.py
expect "heavy stack app native" scripts/app-shortcuts-bundle.py
expect "heavy stack app fastlane" app/fastlane/Fastfile
expect "heavy stack app fastlane" app/Gemfile.lock
expect "heavy stack app emails" emails/src/welcome.tsx
expect "heavy stack emails" supabase/templates/invite.html
expect "heavy stack emails" supabase/config.toml
expect "heavy stack app emails" design/tokens/tokens.json
expect "heavy emails" site/public/email/logo.png
expect "heavy stack app native emails" app/ios/Podfile emails/package.json

# Every file outside app/ that a Flutter test reads (a '../' path literal in single or double
# quotes, resolved from its package) turns the app switch on; a $variable stands for any file in
# its directory. A path built otherwise (a variable root, join()) is not seen: write it as one literal.
while IFS=$'\t' read -r test literal; do
  package="$(dirname "$test")"
  while [[ ! -f $REPO_ROOT/$package/pubspec.yaml ]]; do package="$(dirname "$package")"; done
  literal="${literal//[\'\"]/}"
  [[ $literal == *'$'* ]] && literal="${literal%%\$*}x"
  path="$(realpath -m --relative-to="$REPO_ROOT" "$REPO_ROOT/$package/$literal")"
  [[ $path == app/* ]] || expect_at_least app "$path"
done < <(cd "$REPO_ROOT" && git grep -n -E "['\"]\.\./[^'\"]*['\"]" -- 'app/*test/*.dart' 'app/*/test/*.dart' \
  | grep -vE '^[^:]+:[0-9]+:\s*(import|export|part) ' | sed -E "s/^([^:]+):[0-9]+:.*/\1/" | sort -u \
  | while read -r test; do grep -oE "['\"]\.\./[^'\"]*['\"]" "$REPO_ROOT/$test" | sed "s|^|$test\t|"; done)

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
# Job 308: a reused main push turns every switch off.
# shellcheck disable=SC2086 # one word per switch
all_off="$(printf '%s=false\\n' $everything)"
grep -qF "printf '$all_off'" "$ci" || fail "ci.yml's reused main push does not print every switch ($everything) as false"
# The ci.yml job that runs a gate's script (check-gates.sh: exactly one).
job_of() {
  awk -v gate="$1" '/^  [a-zA-Z0-9_-]+:$/ { job = substr($1, 1, length($1) - 1) }
    $0 ~ "^ *(- )?run: scripts/gates/" gate "\\.sh( |$)" { print job; exit }' "$ci"
}
# A gate's script is code outside app/ and the stack's paths, so it runs every gate the switches
# heavy, stack and app turn on, and its job's own switch where that is another.
for file in "$REPO_ROOT"/scripts/gates/*.sh; do
  gate="$(basename "$file" .sh)"
  job="$(job_of "$gate")"
  [[ -n $job ]] || { fail "no ci.yml job runs scripts/gates/$gate.sh"; continue; }
  asks="$(asks_of "$job")"
  want=""
  [[ -z $asks ]] && want="heavy stack app" # the job does not ask the filter
  # Job 308: runs for every change, but not on a push to main that reuses its PR's run: lint, site.
  [[ $asks == "    needs: changes"$'\n'"    if: needs.changes.outputs.reuse != 'true'" ]] && want="heavy stack app"
  for switch in $everything; do
    [[ $asks == "    needs: changes"$'\n'"    if: needs.changes.outputs.$switch == 'true'" ]] || continue
    want="heavy stack app"
    [[ " $want " == *" $switch "* ]] || want="$want $switch"
  done
  if [[ -z $want ]]; then
    fail "ci.yml job '$job' asks the filter in a way this test cannot read. It reads two lines, the job's own \"    needs: changes\" and \"    if: needs.changes.outputs.<switch> == 'true'\", and found: $asks"
    continue
  fi
  expect "$want" "scripts/gates/$gate.sh"
  # What a gate runs from scripts/ must turn its switch on too (the ios gate's two Python
  # checks ran no build until job 221).
  while read -r path; do
    [[ -z $path ]] || expect_at_least "$want" "$path"
  done < <(grep -vE '^ *#' "$file" | grep -oE 'REPO_ROOT/scripts/[A-Za-z0-9_./-]+' | sed 's|^REPO_ROOT/||' | sort -u)
done
# Each job runs on the switch whose paths its gates read (docs/CI.md, Jobs and gates); "reuse"
# runs for every change but a reused main push (job 308). Moving db and e2e to app would skip them
# for a migration-only PR.
job_switches="lint reuse
site reuse
deno heavy
db stack
e2e stack
flutter app
web-prod app
emails emails
fastlane fastlane
android native
ios native
ios-storekit native"
while read -r job switch; do
  want="    needs: changes"$'\n'"    if: needs.changes.outputs.$switch == 'true'"
  [[ $switch == reuse ]] && want="    needs: changes"$'\n'"    if: needs.changes.outputs.reuse != 'true'"
  [[ "$(asks_of "$job")" == "$want" ]] || fail "the $job job no longer runs on '$switch', it asks: $(asks_of "$job")"
done <<<"$job_switches"
for file in "$REPO_ROOT"/scripts/gates/*.sh; do
  job="$(job_of "$(basename "$file" .sh)")"
  [[ -z $job ]] || grep -q "^$job " <<<"$job_switches" || fail "the $job job runs a gate but has no switch in this test's job_switches"
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
[[ $got == "heavy=true stack=true app=true native=true fastlane=false emails=false " ]] || fail "a file moved from app/ios/ to docs/ gives '$got'"

((failures == 0)) || { echo "ci-changes-test: $failures failed" >&2; exit 1; }
log "ci-changes.sh asks for the gates each path needs: all cases pass"
