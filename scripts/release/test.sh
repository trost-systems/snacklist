#!/usr/bin/env bash
# Tests scripts/release/ offline: when a Release run ships or skips (fixture facts), how it finds
# the last upload (fake gh), the failure issue (fake gh), the AAB signer check (throwaway
# keystore), the public release record (record.test.mjs, loc.test.mjs), the changelog collector
# and the TestFlight notes (changelog.test.mjs) and the CI changelog gate (scratch merge
# commits). Run by the lint gate.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
expect_eq() {
  if [[ "$2" != "$3" ]]; then fail "$1"$'\n'"--- expected"$'\n'"$3"$'\n'"--- got"$'\n'"$2"; fi
}
expect_match() {
  if ! grep -qE -- "$3" <<<"$2"; then fail "$1: expected /$3/ in"$'\n'"$2"; fi
}

# --- plan.sh decide -------------------------------------------------------------------------
head=aaaaaaa1111111111111111111111111111111111
mid=ccccccc3333333333333333333333333333333333
prev=bbbbbbb2222222222222222222222222222222222
green='{status: "completed", conclusion: "success", url: "https://ci/1"}'
# facts <jq>: an automatic run (CI went green on main's tip $head, one commit after the last
# upload $prev), changed by the jq filter.
facts() {
  jq -n --arg head "$head" --arg prev "$prev" --argjson green "$(jq -n "$green")" \
    '{event: "workflow_run", force: false, upload: true, main_sha: $head, trigger_sha: $head,
      trigger_shipped: false, build_number: 1010, now: "2026-11-02T03:00:05Z",
      candidates: [{sha: $head, ci: $green, app_changed: true}],
      last_upload: {sha: $prev, created_at: "2026-10-26T03:20:00Z", url: "https://release/9"},
      testflight: {max_build: 1009, installable: true}}' | jq --arg head "$head" --arg mid "$mid" --arg prev "$prev" "$1" >"$tmp/facts.json"
}
decide() { "$here/plan.sh" decide "$tmp/facts.json" 2>&1; }
field() { sed -n "s/^$1=//p" <<<"$2"; }
# Candidates newest first: $1 for $head, $2 for $mid (each a CI conclusion, "running" or "none").
two() {
  # shellcheck disable=SC2016 # $c, $head, $mid and $prev are jq variables, not shell ones
  local ci='def ci($c): if $c == "none" then null elif $c == "running" then {status: "in_progress", conclusion: null, url: "https://ci/r"} else {status: "completed", conclusion: $c, url: "https://ci/\($c)"} end;'
  echo "$ci .candidates = [{sha: \$head, ci: ci(\"$1\"), app_changed: true}, {sha: \$mid, ci: ci(\"$2\"), app_changed: true}]"
}

facts .
out="$(decide)"
expect_eq "green CI on a new commit: ships" "$(field ship "$out")" true
expect_eq "green CI on a new commit: ships that commit" "$(field sha "$out")" "$head"
expect_match "main moved: names both commits" "$(field reason "$out")" 'bbbbbbb -> aaaaaaa'
expect_eq "main moved: notes start after the last upload" "$(field previous_sha "$out")" "$prev"

# shellcheck disable=SC2016 # $c, $head, $mid and $prev are jq variables, not shell ones
facts '.candidates = [] | .main_sha = $prev'
out="$(decide)"
expect_eq "unchanged: skips" "$(field ship "$out")" false
expect_eq "unchanged: not a failure" "$(field blocked "$out")" false
expect_eq "unchanged: the testers are current (closes the issue)" "$(field current "$out")" true
expect_match "unchanged: says so" "$(field reason "$out")" '^main is unchanged since the last upload'

# Merge bursts: CI on main finishes in any order, and GitHub keeps one pending run per group.
# shellcheck disable=SC2016 # $c, $head, $mid and $prev are jq variables, not shell ones
facts '.candidates = [] | .trigger_sha = $mid | .trigger_shipped = true'
out="$(decide)"
expect_eq "newer commit already shipped: the older run skips" "$(field ship "$out")" false
expect_eq "newer commit already shipped: cleanly" "$(field blocked "$out"),$(field current "$out")" false,true
expect_match "newer commit already shipped: says why" "$(field reason "$out")" 'ccccccc, which started this run, is older than the last upload'

facts "$(two running success) | .trigger_sha = \$mid"
out="$(decide)"
expect_eq "newer commit's CI still running: the green older one ships now" "$(field ship "$out"),$(field sha "$out")" "true,$mid"
expect_match "newer commit's CI still running: named" "$(field reason "$out")" 'not shipped: aaaaaaa \(in_progress\)'

facts "$(two success success) | .trigger_sha = \$mid"
out="$(decide)"
expect_eq "older commit's run starts after the newer one went green: ships the newer" "$(field sha "$out")" "$head"

facts "$(two failure success) | .trigger_sha = \$mid"
out="$(decide)"
expect_eq "red CI: the red commit never ships, the newest green one does" "$(field ship "$out"),$(field sha "$out")" "true,$mid"
expect_match "red CI: named" "$(field reason "$out")" 'aaaaaaa \(failure\)'

facts "$(two none success)"
expect_eq "newest commit without a CI run yet: the green one ships" "$(field sha "$(decide)")" "$mid"

facts "$(two failure failure)"
out="$(decide)"
expect_eq "only red commits since the last upload: skips, nothing red ships" "$(field ship "$out"),$(field blocked "$out")" false,false
expect_eq "only red commits: ships nothing" "$(field sha "$out")" "$prev"
expect_match "only red commits: says so" "$(field reason "$out")" '^no green commit on main is newer than the last upload \(bbbbbbb.*not shipped: aaaaaaa \(failure\), ccccccc \(failure\)$'
expect_eq "only red commits: the testers have the newest green main" "$(field current "$out")" true

facts "$(two failure failure) | .last_upload = null"
out="$(decide)"
expect_eq "no green commit at all: skips" "$(field ship "$out"),$(field sha "$out")" false,
expect_match "no green commit at all: says so" "$(field reason "$out")" '^no green commit on main'

facts '.candidates[0].app_changed = false'
out="$(decide)"
expect_eq "only docs or CI changed since the last upload: skips" "$(field ship "$out")" false
expect_eq "only docs changed: the testers are current" "$(field current "$out")" true
expect_match "only docs changed: says so" "$(field reason "$out")" '^nothing under app/ or release.yml changed'

facts '.candidates[0].app_changed = false | .testflight.installable = false'
expect_eq "only docs changed but TestFlight expired: ships" "$(field ship "$(decide)")" true

facts '.event = "schedule" | .candidates = []'
expect_eq "weekly catch-up with nothing new: skips" "$(field ship "$(decide)")" false
facts '.event = "schedule"'
expect_eq "weekly catch-up with a green commit an event missed: ships it" "$(field ship "$(decide)"),$(field sha "$(decide)")" "true,$head"

# Dispatch: main's tip, green or nothing; force and dry runs as before.
facts '.event = "workflow_dispatch" | .trigger_sha = ""'
expect_eq "dispatch on a new green tip: ships it" "$(field ship "$(decide)"),$(field sha "$(decide)")" "true,$head"

facts '.event = "workflow_dispatch" | .trigger_sha = "" | .candidates = []'
expect_eq "unchanged dispatch without force: skips like an automatic run" "$(field ship "$(decide)")" false

facts '.event = "workflow_dispatch" | .candidates = [] | .force = true'
out="$(decide)"
expect_eq "dispatch force on unchanged main: ships" "$(field ship "$out")" true
expect_eq "dispatch force: ships the last upload's commit again" "$(field sha "$out")" "$prev"
expect_match "force: reason" "$(field reason "$out")" '^forced'

facts '.event = "workflow_dispatch" | .candidates[0].app_changed = false | .force = true'
expect_eq "dispatch force with only docs changed: ships" "$(field ship "$(decide)")" true

facts '.event = "workflow_dispatch" | .candidates = [] | .upload = false'
out="$(decide)"
expect_eq "dry run on unchanged main: still builds" "$(field ship "$out")" true
expect_match "dry run: reason" "$(field reason "$out")" '^dry run'

facts '.event = "workflow_dispatch" | .candidates[0].ci.conclusion = "failure"'
out="$(decide)"
expect_eq "dispatch on a red tip: does not ship" "$(field ship "$out")" false
expect_eq "dispatch on a red tip: blocked" "$(field blocked "$out")" true
expect_match "dispatch on a red tip: links the CI run" "$(field reason "$out")" 'failure on aaaaaaa \(https://ci/1\)'

facts '.event = "workflow_dispatch" | .candidates[0].ci.conclusion = "failure" | .force = true'
expect_eq "dispatch on a red tip: force does not override" "$(field ship "$(decide)")" false

facts '.event = "workflow_dispatch" | .candidates[0].ci = {status: "in_progress", conclusion: null, url: "https://ci/2"}'
out="$(decide)"
expect_eq "dispatch while CI runs: blocked" "$(field blocked "$out")" true
expect_match "dispatch while CI runs: reason" "$(field reason "$out")" 'has not finished'

facts '.event = "workflow_dispatch" | .candidates[0].ci = null'
expect_eq "dispatch on a commit without a CI run: blocked" "$(field blocked "$(decide)")" true

facts '.last_upload = null'
out="$(decide)"
expect_eq "first upload: ships" "$(field ship "$out")" true
expect_eq "first upload: notes from recent history" "$(field previous_sha "$out")" ""

facts '.candidates = [] | .testflight.installable = false'
out="$(decide)"
expect_eq "unchanged but every TestFlight build expired: ships" "$(field ship "$out"),$(field sha "$out")" "true,$prev"
expect_match "expired: reason" "$(field reason "$out")" 'no installable build'

facts '.candidates = [] | .last_upload.created_at = "2026-09-02T03:00:00Z"'
out="$(decide)"
expect_eq "unchanged for 61 days: ships before TestFlight expires it" "$(field ship "$out")" true
expect_match "61 days: reason" "$(field reason "$out")" '61 days old'

facts '.candidates = [] | .last_upload.created_at = "2026-09-04T03:00:00Z"'
expect_eq "unchanged for 59 days: skips" "$(field ship "$(decide)")" false

facts '.candidates = [] | .testflight = null'
expect_eq "unchanged without iOS secrets: skips" "$(field ship "$(decide)")" false

facts '.testflight.max_build = 1010'
if out="$(decide)"; then fail "a build number TestFlight already has must fail the run"; fi
expect_match "stale build number: names the fix" "$out" '^::error::Build number 1010 is not above .*BUILD_NUMBER_OFFSET'

# --- plan.sh gather: main's history, CI per commit, the last upload ---------------------------
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
# Answers `gh api <path> [--jq <filter>]` from $FAKE_API/<path with / and ? as _>.json.
set -euo pipefail
path="$2" filter=.
[[ ${3:-} == --jq ]] && filter="$4"
file="$FAKE_API/$(tr '/?&=' '____' <<<"$path").json"
[[ -f $file ]] || { echo "fake gh: no fixture for $path" >&2; exit 1; }
jq -r "$filter" "$file"
GH
chmod +x "$tmp/bin/gh"
api="$tmp/api" && mkdir -p "$api"
fixture() { cat >"$api/$(tr '/?&=' '____' <<<"$1").json"; }
r=repos/o/r
# main: c0 (shipped by run 40) <- c1 app change <- c2 docs only <- c3 app change (tip).
hist="$tmp/hist"
git init -q -b main "$hist"
hcommit() {
  if [[ -n ${2:-} ]]; then mkdir -p "$hist/$(dirname "$2")" && echo "$1" >>"$hist/$2" && git -C "$hist" add -A; fi
  git -C "$hist" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$1"
  git -C "$hist" rev-parse HEAD
}
c0="$(hcommit c0 app/lib/a.dart)" c1="$(hcommit c1 app/lib/a.dart)" c2="$(hcommit c2 docs/x.md)" c3="$(hcommit c3 app/lib/b.dart)"
ci_fixture() {
  fixture "$r/actions/workflows/ci.yml/runs?head_sha=$1&event=push&per_page=20" <<<"$2"
}
ci_fixture "$c3" '{"workflow_runs": [{"created_at": "2026-11-01T12:00:00Z", "status": "in_progress", "conclusion": null, "html_url": "https://ci/c3"}]}'
ci_fixture "$c2" '{"workflow_runs": [
  {"created_at": "2026-11-01T10:00:00Z", "status": "completed", "conclusion": "failure", "html_url": "https://ci/old"},
  {"created_at": "2026-11-01T11:00:00Z", "status": "completed", "conclusion": "success", "html_url": "https://ci/rerun"}]}'
fixture "$r/actions/workflows/release.yml/runs?branch=main&status=success&per_page=100" <<'JSON'
{"workflow_runs": [{"id": 41}, {"id": 40}, {"id": 30}]}
JSON
fixture "$r/actions/runs/41/jobs?per_page=100" <<'JSON'
{"jobs": [{"name": "plan", "conclusion": "success"}, {"name": "Uploaded ", "conclusion": "skipped"}]}
JSON
fixture "$r/actions/runs/40/jobs?per_page=100" <<JSON
{"jobs": [{"name": "plan", "conclusion": "success"}, {"name": "Uploaded $c0", "conclusion": "success"}]}
JSON
# The run's own head_sha is main's tip when it started, not what it shipped.
fixture "$r/actions/runs/40" <<JSON
{"head_sha": "$c1", "created_at": "2026-10-26T03:20:00Z", "html_url": "https://release/40"}
JSON
echo '{"max_build": 1009, "installable": true}' >"$tmp/testflight.json"
gather() {
  (cd "$hist" && env PATH="$tmp/bin:$PATH" FAKE_API="$api" GITHUB_REPOSITORY=o/r EVENT=workflow_run \
    FORCE=false UPLOAD=true MAIN_SHA="$c3" TRIGGER_SHA="$c2" BUILD_NUMBER=1010 \
    TESTFLIGHT_JSON="$tmp/testflight.json" "$@" "$here/plan.sh" gather)
}
gathered="$(gather)"
expect_eq "gather: the last upload is the commit in its Uploaded job's name" \
  "$(jq -c .last_upload <<<"$gathered")" "{\"sha\":\"$c0\",\"created_at\":\"2026-10-26T03:20:00Z\",\"url\":\"https://release/40\"}"
expect_eq "gather: candidates from main's tip down to the first green commit" \
  "$(jq -c '[.candidates[] | [.sha, .ci.status, .ci.conclusion]]' <<<"$gathered")" \
  "[[\"$c3\",\"in_progress\",null],[\"$c2\",\"completed\",\"success\"]]"
expect_eq "gather: the newest CI run on a commit counts (a green rerun)" "$(jq -r '.candidates[1].ci.url' <<<"$gathered")" https://ci/rerun
expect_eq "gather: app changes are measured from the last upload" "$(jq -c '[.candidates[].app_changed]' <<<"$gathered")" '[true,true]'
expect_eq "gather: TestFlight state passes through" "$(jq -c .testflight <<<"$gathered")" '{"max_build":1009,"installable":true}'
expect_eq "gather: inputs are typed" "$(jq -c '[.force, .upload, .build_number, .trigger_shipped]' <<<"$gathered")" '[false,true,1010,false]'
"$here/plan.sh" decide <(echo "$gathered") >"$tmp/out"
expect_eq "gather + decide: ships the newest green commit, not the running tip" "$(field sha "$(cat "$tmp/out")")" "$c2"

expect_eq "gather: a dispatch looks at the tip only" "$(gather EVENT=workflow_dispatch TRIGGER_SHA= | jq -c '[.candidates[].sha]')" "[\"$c3\"]"

fixture "$r/actions/runs/40/jobs?per_page=100" <<JSON
{"jobs": [{"name": "Uploaded $c2", "conclusion": "success"}]}
JSON
gathered="$(gather MAIN_SHA="$c2" TRIGGER_SHA="$c1")"
expect_eq "gather: main unchanged since the last upload, no candidates" "$(jq -c .candidates <<<"$gathered")" '[]'
expect_eq "gather: the trigger is older than the last upload" "$(jq .trigger_shipped <<<"$gathered")" true
expect_eq "gather: the trigger is not older when it is the last upload" "$(gather MAIN_SHA="$c2" TRIGGER_SHA="$c2" | jq .trigger_shipped)" false

# A dispatch on c1 (green) waited in the queue while an automatic run shipped c2.
ci_fixture "$c1" '{"workflow_runs": [{"created_at": "2026-11-01T09:00:00Z", "status": "completed", "conclusion": "success", "html_url": "https://ci/c1"}]}'
gathered="$(gather EVENT=workflow_dispatch MAIN_SHA="$c1" TRIGGER_SHA=)"
expect_eq "gather: a dispatch on a commit older than the last upload has no candidates" \
  "$(jq -c '[.candidates, .trigger_sha == $c1, .trigger_shipped]' --arg c1 "$c1" <<<"$gathered")" '[[],true,true]'
"$here/plan.sh" decide <(echo "$gathered") >"$tmp/out"
expect_eq "gather + decide: that dispatch skips, it never ships the older commit" \
  "$(field ship "$(cat "$tmp/out")"),$(field sha "$(cat "$tmp/out")")" "false,$c2"

fixture "$r/actions/runs/40/jobs?per_page=100" <<JSON
{"jobs": [{"name": "Uploaded $c1", "conclusion": "success"}]}
JSON
expect_eq "gather: a docs-only commit is no app change" \
  "$(gather MAIN_SHA="$c2" | jq -c '[.candidates[].app_changed]')" '[false]'

# A public release record commit (record.mjs, pushed by public-release-record.yml) after the
# last upload never starts a store upload.
c4="$(hcommit "Release 1.0.0: public release record" releases/releases.json)"
fixture "$r/actions/runs/40/jobs?per_page=100" <<JSON
{"jobs": [{"name": "Uploaded $c3", "conclusion": "success"}]}
JSON
ci_fixture "$c4" '{"workflow_runs": [{"created_at": "2026-11-01T13:00:00Z", "status": "completed", "conclusion": "success", "html_url": "https://ci/c4"}]}'
gathered="$(gather MAIN_SHA="$c4" TRIGGER_SHA="$c4")"
expect_eq "gather: a release record commit is no app change" "$(jq -c '[.candidates[] | [.sha, .app_changed]]' <<<"$gathered")" "[[\"$c4\",false]]"
"$here/plan.sh" decide <(echo "$gathered") >"$tmp/out"
expect_eq "gather + decide: a release record commit skips, the testers are current" \
  "$(field ship "$(cat "$tmp/out")"),$(field current "$(cat "$tmp/out")")" "false,true"

# Runs from before job 30 named the job "Uploaded" and shipped their head_sha.
fixture "$r/actions/runs/40/jobs?per_page=100" <<'JSON'
{"jobs": [{"name": "Uploaded", "conclusion": "success"}]}
JSON
expect_eq "gather: an old Uploaded job means the run's head_sha" "$(gather | jq -r .last_upload.sha)" "$c1"

fixture "$r/actions/workflows/release.yml/runs?branch=main&status=success&per_page=100" <<<'{"workflow_runs": [{"id": 41}]}'
gathered="$(gather TESTFLIGHT_JSON= EVENT=workflow_dispatch)"
expect_eq "gather: no earlier upload" "$(jq -c '[.last_upload, .testflight]' <<<"$gathered")" '[null,null]'
expect_eq "gather: no earlier upload counts as an app change" "$(jq -c '[.candidates[].app_changed]' <<<"$gathered")" '[true]'

# --- report.sh decide -----------------------------------------------------------------------
report() {
  env -i PATH="$PATH" EVENT="$1" SIMULATE="$2" UPLOAD="$3" PLAN="$4" IOS="$5" ANDROID="$6" UPLOADED="$7" \
    BLOCKED="${8:-false}" REASON="${9:-}" WEB="${10:-}" CURRENT="${11:-false}" "$here/report.sh" decide
}
expect_eq "automatic iOS failure opens the issue" "$(report workflow_run false true success failure success skipped)" open
expect_eq "scheduled iOS failure opens the issue" "$(report schedule false true success failure success skipped)" open
expect_eq "automatic plan failure (no outputs) opens the issue" "$(report workflow_run false '' failure skipped skipped skipped)" open
expect_eq "cancelled Android job opens the issue" "$(report workflow_run false true success success cancelled skipped)" open
expect_eq "dispatch failure leaves the issue alone" "$(report workflow_dispatch false true success failure success skipped)" none
expect_eq "dispatch on red main leaves the issue alone" "$(report workflow_dispatch false true success skipped skipped skipped true 'CI concluded failure')" none
expect_eq "simulated dispatch failure opens the issue" "$(report workflow_dispatch true true failure skipped skipped skipped)" open
expect_eq "green upload closes the issue" "$(report workflow_run false true success success success success)" close
expect_eq "green dispatched upload closes the issue" "$(report workflow_dispatch false true success success skipped success)" close
expect_eq "testers already current closes the issue" "$(report workflow_run false true success skipped skipped skipped false 'main is unchanged since the last upload (x)' '' true)" close
expect_eq "a skip that is not current leaves the issue alone" "$(report workflow_run false true success skipped skipped skipped false 'no green commit on main to ship yet')" none
expect_eq "green dry run leaves the issue alone" "$(report workflow_dispatch false false success success success skipped)" none
expect_eq "green run that uploaded nothing leaves the issue alone" "$(report workflow_run false true success skipped success skipped)" none
expect_eq "simulated web production failure opens the issue" "$(report workflow_dispatch true true success success skipped success false '' failure)" open
expect_eq "green upload and web production closes the issue" "$(report workflow_dispatch false true success success skipped success false '' success)" close

# --- report.sh apply ------------------------------------------------------------------------
cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
# Records issue commands; `issue list` answers with the open issue numbers in $FAKE_OPEN.
echo "$*" >>"$FAKE_LOG"
[[ "$1 $2" == "issue list" ]] && printf '%s\n' $FAKE_OPEN
exit 0
GH
apply() {
  : >"$tmp/gh.log"
  env -i PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/gh.log" FAKE_OPEN="$1" EVENT=workflow_run SIMULATE=false UPLOAD=true \
    PLAN=success IOS="$2" ANDROID=success UPLOADED="$3" GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=o/r \
    GITHUB_RUN_ID=77 GITHUB_SHA="$prev" SHA="$head" "$here/report.sh" apply >/dev/null
  grep -v '^issue list' "$tmp/gh.log" || true
}
expect_match "first failure creates the issue with the run link and platform" "$(apply '' failure skipped)" \
  '^issue create --repo o/r --title Internal release failed --body Release run https://github.com/o/r/actions/runs/77 \(workflow_run\) on aaaaaaa failed: ios \(failure\)'
expect_match "next failure comments on the open issue" "$(apply 12 failure skipped)" '^issue comment 12 '
expect_eq "green upload closes every open copy" "$(apply '12 13' success success | cut -d' ' -f1-3)" $'issue close 12\nissue close 13'
# The issue body says what reached each store and the web app, whatever mix of jobs failed.
# body KEY=VALUE...: the body of the issue a run creates (defaults: a green automatic upload).
body() {
  : >"$tmp/gh.log"
  env -i PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/gh.log" FAKE_OPEN='' EVENT=workflow_run SIMULATE=false UPLOAD=true \
    PLAN=success IOS=success ANDROID=success ANDROID_UPLOADED=true UPLOADED=success WEB=success \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=77 GITHUB_SHA="$prev" SHA="$head" \
    "$@" "$here/report.sh" apply >/dev/null
  sed -n 's/^issue create .* --body //p' "$tmp/gh.log"
}
outcome_of() {
  body "$@" | sed -E 's/^.* failed: .*\. ((TestFlight|The iOS|Play internal|No Play|The Android|Nothing|This was) )/\1/; s/ docs\/RELEASE.md, section Failures.*$//'
}
expect_match "body: names the failed jobs" "$(body ANDROID=failure)" 'failed: android \(failure\)\. '
expect_match "body: names the commit the run shipped" "$(body ANDROID=failure)" ' on aaaaaaa failed: '
expect_eq "automatic run, iOS uploaded, Android failed" \
  "$(outcome_of ANDROID=failure ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped)" \
  'TestFlight got this build; the Android job stopped, so Play internal may not have this build. The web app (app.snacklist.app) stays on the last store release.'
expect_eq "automatic run, iOS failed, Android built but did not upload" \
  "$(outcome_of IOS=failure ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped)" \
  'The iOS job stopped, so TestFlight may not have this build; no Play upload (the Android job says why). The web app (app.snacklist.app) stays on the last store release.'
expect_eq "automatic run, plan failed: nothing shipped" \
  "$(outcome_of UPLOAD='' PLAN=failure IOS=skipped ANDROID=skipped ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped)" \
  'Nothing new reached TestFlight or the Play internal track from this run. The web app (app.snacklist.app) stays on the last store release.'
expect_eq "automatic run, cancelled Android after the iOS upload" \
  "$(outcome_of ANDROID=cancelled ANDROID_UPLOADED='' WEB=skipped)" \
  'TestFlight got this build; the Android job stopped, so Play internal may not have this build. The web app (app.snacklist.app) was not moved to this commit (release branch, docs/DEPLOY.md, section Web app).'
expect_eq "automatic Android-only run, Android job stopped" \
  "$(outcome_of IOS=skipped ANDROID=failure ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped)" \
  'The Android job stopped, so Play internal may not have this build. The web app (app.snacklist.app) stays on the last store release.'
expect_eq "automatic Android-only run without a Play upload, plan cancelled" \
  "$(outcome_of IOS=skipped ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped PLAN=cancelled)" \
  'No Play upload (the Android job says why). The web app (app.snacklist.app) stays on the last store release.'
expect_eq "dispatch, web-only failure: both stores got it, the web app did not move" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true WEB=failure)" \
  'TestFlight got this build; Play internal got this build. The web app (app.snacklist.app) was not moved to this commit (release branch, docs/DEPLOY.md, section Web app).'
expect_eq "dispatch, cancelled iOS + failed web: only Play got it" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true IOS=cancelled WEB=failure)" \
  'The iOS job stopped, so TestFlight may not have this build; Play internal got this build. The web app (app.snacklist.app) was not moved to this commit (release branch, docs/DEPLOY.md, section Web app).'
expect_eq "dispatch, iOS uploaded, Android failed (no Uploaded, no web job)" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true ANDROID=failure ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped)" \
  'TestFlight got this build; the Android job stopped, so Play internal may not have this build. The web app (app.snacklist.app) stays on the last store release.'
expect_eq "dispatch on red main: nothing shipped" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true BLOCKED=true REASON='CI concluded failure' IOS=skipped ANDROID=skipped ANDROID_UPLOADED='' UPLOADED=skipped WEB=skipped)" \
  'Nothing new reached TestFlight or the Play internal track from this run. The web app (app.snacklist.app) stays on the last store release.'
expect_eq "dispatch, cancelled Android after the iOS upload, web moved" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true ANDROID=cancelled ANDROID_UPLOADED='')" \
  'TestFlight got this build; the Android job stopped, so Play internal may not have this build. The web app (app.snacklist.app) moves to this commit.'
expect_eq "dispatch, Android-only run uploaded, web failed" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true IOS=skipped WEB=failure)" \
  'Play internal got this build. The web app (app.snacklist.app) was not moved to this commit (release branch, docs/DEPLOY.md, section Web app).'
expect_eq "dispatch, TestFlight uploaded, no Play upload, web failed" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true ANDROID_UPLOADED='' WEB=failure)" \
  'TestFlight got this build; no Play upload (the Android job says why). The web app (app.snacklist.app) was not moved to this commit (release branch, docs/DEPLOY.md, section Web app).'
expect_eq "dispatch, web job cancelled: it may have pushed already" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true WEB=cancelled)" \
  'TestFlight got this build; Play internal got this build. The web app (app.snacklist.app) may not have moved to this commit (check the release branch, docs/DEPLOY.md, section Web app).'
expect_eq "simulated failure on a dry run" \
  "$(outcome_of EVENT=workflow_dispatch SIMULATE=true UPLOAD=false PLAN=failure IOS=skipped ANDROID=skipped UPLOADED=skipped WEB=skipped)" \
  'This was a dry run: nothing was uploaded and app.snacklist.app did not move.'

# --- check-aab.sh ---------------------------------------------------------------------------
if command -v keytool >/dev/null && command -v jarsigner >/dev/null && command -v jar >/dev/null; then
  for name in upload other; do
    keytool -genkeypair -storetype PKCS12 -keystore "$tmp/$name.p12" -alias "$name" -keyalg RSA -keysize 2048 \
      -validity 1 -dname "CN=$name" -storepass testpass -keypass testpass >/dev/null 2>&1
  done
  fingerprint="$(keytool -list -v -keystore "$tmp/upload.p12" -storepass testpass | sed -n 's/^[[:space:]]*SHA256: //p')"
  (cd "$tmp" && echo x >f && jar cf unsigned.aab f)
  cp "$tmp/unsigned.aab" "$tmp/upload.aab" && cp "$tmp/unsigned.aab" "$tmp/other.aab"
  jarsigner -keystore "$tmp/upload.p12" -storepass testpass "$tmp/upload.aab" upload >/dev/null 2>&1
  jarsigner -keystore "$tmp/other.p12" -storepass testpass "$tmp/other.aab" other >/dev/null 2>&1
  "$here/check-aab.sh" "$tmp/upload.aab" "${fingerprint,,}" >/dev/null || fail "check-aab: the upload key's bundle passes (any case)"
  if out="$("$here/check-aab.sh" "$tmp/other.aab" "$fingerprint" 2>&1)"; then fail "check-aab: another key's bundle must fail"; fi
  expect_match "check-aab: names the signer" "$out" 'is signed by .*, not by the upload key'
  if "$here/check-aab.sh" "$tmp/unsigned.aab" "$fingerprint" >/dev/null 2>&1; then fail "check-aab: an unsigned bundle must fail"; fi
else
  echo "check-aab: skipped, no keytool/jarsigner"
fi

# --- record.mjs -----------------------------------------------------------------------------
node --test "$here/record.test.mjs" >"$tmp/record.log" 2>&1 || fail "record.test.mjs"$'\n'"$(cat "$tmp/record.log")"
node --test "$here/loc.test.mjs" >"$tmp/loc.log" 2>&1 || fail "loc.test.mjs"$'\n'"$(cat "$tmp/loc.log")"

# --- changelog.mjs and gates/changelog.sh -----------------------------------------------------
node --test "$here/changelog.test.mjs" >"$tmp/changelog.log" 2>&1 || fail "changelog.test.mjs"$'\n'"$(cat "$tmp/changelog.log")"

root="$(cd "$here/../.." && pwd)"
gate_repo="$tmp/gate"
mkdir -p "$gate_repo/scripts/gates" "$gate_repo/scripts/release" "$gate_repo/site"
cp "$root/scripts/lib.sh" "$gate_repo/scripts/"
cp "$root/scripts/gates/changelog.sh" "$gate_repo/scripts/gates/"
cp "$root/scripts/release/"{changelog.mjs,plan.sh} "$gate_repo/scripts/release/"
cp "$root/site/releases.mjs" "$gate_repo/site/"
mkdir -p "$gate_repo/releases" && cp "$root/releases/flags.json" "$gate_repo/releases/"
(cd "$gate_repo" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@example.com commit -q -m base)
# gate <changed path> <PR head message> <PR description>: the gate on a pull_request run, on the
# merge commit of a PR head that changes the path.
gate() {
  (
    cd "$gate_repo"
    git checkout -q -B pr main
    mkdir -p "$(dirname "$1")" && echo x >"$1" && git add -A
    git -c user.name=t -c user.email=t@example.com commit -q -m "$2"
    git checkout -q --detach main
    git -c user.name=t -c user.email=t@example.com merge -q --no-ff -m merge pr
    jq -n --arg body "$3" '{pull_request: {body: $body}}' >"$tmp/event.json"
    GITHUB_EVENT_NAME=pull_request GITHUB_EVENT_PATH="$tmp/event.json" scripts/gates/changelog.sh 2>&1
  )
}
broken=$'Title (#9)\n\n## Changelog\nfixd\nde: A.\nen: B.'
if out="$(gate app/a.dart "$broken" '')"; then fail "changelog gate: a broken section on the PR head must fail"; fi
expect_match "changelog gate: names the problem" "$out" 'unknown category "fixd"'
out="$(gate app/b.dart $'Title (#9)\n\n## Changelog\nnone\n\nCo-authored-by: Peter Trost <peter@petertrost.com>' '')" || fail "changelog gate: none on the PR head passes"$'\n'"$out"
expect_match "changelog gate: none" "$out" 'changelog: none'
out="$(gate app/c.dart 'wip' $'## Changelog\r\nfixed\r\nde: A.\r\nen: B.\r\n')" || fail "changelog gate: a head without a section falls back to the PR description"$'\n'"$out"
expect_match "changelog gate: reads the description" "$out" 'changelog: fixed: B\.'
# Job 40: the optional flag: and hold: lines.
out="$(gate app/f.dart $'Title (#9)\n\n## Changelog\nnew\nde: A.\nen: B.\nhold: alexa-certification' '')" || fail "changelog gate: a hold line passes"$'\n'"$out"
expect_match "changelog gate: names the hold" "$out" 'changelog: new \(hold: alexa-certification\): B\.'
if out="$(gate app/g.dart $'Title (#9)\n\n## Changelog\nnew\nde: A.\nen: B.\nflag: Big Lists' '')"; then fail "changelog gate: a malformed flag key must fail"; fi
expect_match "changelog gate: bad key" "$out" 'flag "Big Lists" is not a key'
if out="$(gate app/h.dart $'Title (#9)\n\n## Changelog\nnew\nde: A.\nen: B.\nflag: a\nflag: b' '')"; then fail "changelog gate: two flag lines must fail"; fi
expect_match "changelog gate: duplicate flag" "$out" 'two "flag:" lines'
if out="$(gate app/i.dart $'Title (#9)\n\n## Changelog\nnew\nde: A.\nen: B.\nflag: big-lists' '')"; then fail "changelog gate: a flag missing from releases/flags.json must fail"; fi
expect_match "changelog gate: unknown flag" "$out" 'flag "big-lists" is not in releases/flags.json'
if out="$(gate app/j.dart $'Title (#9)\n\n## Changelog\nfixed\nde: Premium ist da.\nen: Premium is here.' '')"; then fail "changelog gate: an item naming an unreleased hold's word must fail"; fi
expect_match "changelog gate: Premium needs the hold" "$out" 'add the line "hold: premium-launch"'
out="$(gate app/k.dart $'Title (#9)\n\n## Changelog\nfixed\nde: Alexa hört besser zu.\nen: Alexa listens better.' '')" || fail "changelog gate: an Alexa item needs no hold once it is released"$'\n'"$out"
if out="$(gate app/d.dart 'wip' 'No section.')"; then fail "changelog gate: an app change without any section must fail"; fi
expect_match "changelog gate: asks for the section" "$out" 'this PR changes the app or its backend: add a ## Changelog section'
if out="$(gate supabase/functions/voice/parse.ts 'wip' 'No section.')"; then fail "changelog gate: a backend change without any section must fail"; fi
out="$(gate docs/e.md 'wip' 'No section.')" || fail "changelog gate: a docs change without a section passes"$'\n'"$out"
expect_match "changelog gate: push-pr.sh adds none" "$out" 'push-pr.sh adds "none"'

if [[ $failures -gt 0 ]]; then
  echo "release tests: $failures failed" >&2
  exit 1
fi
echo "release tests: all passed"
