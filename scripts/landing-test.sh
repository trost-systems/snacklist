#!/usr/bin/env bash
# Tests push-pr.sh and merge-pr.sh against a scratch remote and a fake gh: the landed message is
# the PR title and description with the co-author trailers (MODEL_CO_AUTHOR optional, Peter's
# last), the description's `## Changelog` section (job 39; "none" added when no app build
# changes), MERGE_WAIT_MINUTES takes whole minutes only, merge-pr.sh waits for GitHub's record
# of the PR to name the pushed head (job 218), and its wait for ci-ok goes on when a signal ends
# only its sleep (job 219); push-pr.sh pushes nothing when scripts/push-checks.sh fails (here a
# stub) and marks a draft PR ready only after its push (job 307). Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
expect_eq() {
  if [[ "$2" != "$3" ]]; then fail "$1"$'\n'"--- expected"$'\n'"$3"$'\n'"--- got"$'\n'"$2"; fi
}

git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
mkdir -p "$tmp/work/scripts/release" "$tmp/work/site" "$tmp/bin" "$tmp/pr"
cp "$REPO_ROOT"/scripts/{lib,push-pr,merge-pr}.sh "$tmp/work/scripts/"
cat >"$tmp/work/scripts/push-checks.sh" <<'CHECKS'
#!/usr/bin/env bash
[[ ! -e $FAKE_PR/checks-fail ]] || { echo "lint.sh: a finding" >&2; exit 1; }
CHECKS
chmod +x "$tmp/work/scripts/push-checks.sh"
cp "$REPO_ROOT"/scripts/release/{changelog.mjs,plan.sh} "$tmp/work/scripts/release/"
cp "$REPO_ROOT"/site/releases.mjs "$tmp/work/site/"
mkdir -p "$tmp/work/releases" && cp "$REPO_ROOT"/releases/flags.json "$tmp/work/releases/"
export GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
cd "$tmp/work"
git commit -q --allow-empty -m init
git push -q origin HEAD:main

# The fake gh answers for one open PR, #7, from files in $tmp/pr; merging fast-forwards main.
# While $tmp/pr/stale-heads has lines, each question for the head takes the first as its answer.
cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
pr="$FAKE_PR"
branch="$(cat "$pr/branch")"
case "$1 $2" in
  "pr view")
    fields="$(sed -n 's/.*--json \([^ ]*\).*/\1/p' <<<"$*")"
    case "$fields" in
      number,title,state) echo "7 $(cat "$pr/title")" ;;
      headRefName) echo "$branch" ;;
      headRefOid)
        if [[ -s $pr/stale-heads ]]; then
          sed -n 1p "$pr/stale-heads"
          sed -i 1d "$pr/stale-heads"
        else
          git --git-dir="$FAKE_REMOTE" rev-parse "refs/heads/$branch"
        fi ;;
      title) cat "$pr/title" ;;
      body) cat "$pr/body" ;;
      isDraft) [[ -e $pr/draft ]] && echo true || echo false ;;
      *) echo "fake gh: no answer for $*" >&2; exit 1 ;;
    esac ;;
  "pr checks") cat "$pr/ci" ;;
  "pr ready")
    rm "$pr/draft"
    git --git-dir="$FAKE_REMOTE" rev-parse "refs/heads/$branch" >"$pr/ready-at" ;;
  "pr edit")
    cp "${*: -1}" "$pr/body"
    echo edited >>"$pr/edited" ;;
  "pr merge")
    head="${*: -1}"
    git --git-dir="$FAKE_REMOTE" update-ref refs/heads/main "$head"
    echo "merged $head" >>"$pr/merged" ;;
  *) echo "fake gh: no answer for $*" >&2; exit 1 ;;
esac
GH
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_PR="$tmp/pr" FAKE_REMOTE="$tmp/origin.git"
unset MODEL_CO_AUTHOR MERGE_WAIT_MINUTES

# A branch whose commits carry working-commit leftovers and co-author lines, and a PR
# description as the GitHub API returns it (CRLF line ends).
open_pr() {
  git checkout -q -B "$1" origin/main
  echo "$1" >"$tmp/pr/branch"
  echo "Make lists faster" >"$tmp/pr/title"
  printf 'Lists load in one query.\r\n\r\n## Tests\r\n- list.spec.ts\r\n\r\nCo-authored-by: Bob <bob@example.com>\r\n' >"$tmp/pr/body"
  echo pending >"$tmp/pr/ci"
  echo a >a && git add a && git commit -q -m "wip" -m "Co-authored-by: Alice <alice@example.com>"
  echo b >b && git add b && git commit -q -m "done: PR number" -m "$(printf 'changelog line\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nCo-authored-by: Alice <alice@example.com>')"
  git push -q -u origin HEAD 2>/dev/null
}
body_of() { git --git-dir="$tmp/origin.git" log -1 --format=%B "refs/heads/$1"; }

open_pr p1
scripts/push-pr.sh >/dev/null
expect_eq "push-pr.sh lands the PR description, not the commit messages" "$(body_of p1)" "Make lists faster (#7)

Lists load in one query.

## Tests
- list.spec.ts

## Changelog
none

Co-authored-by: Bob <bob@example.com>
Co-authored-by: Alice <alice@example.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Co-authored-by: Peter Trost <peter@petertrost.com>"
expect_eq "push-pr.sh pushes one commit by the noreply author" \
  "$(git --git-dir="$tmp/origin.git" log --format=%ae refs/heads/main..refs/heads/p1)" "$AUTHOR_EMAIL"

out="$(scripts/push-pr.sh 2>&1)"
[[ $out == *"nothing to push"* ]] || fail "a second push-pr.sh run was not a no-op: $out"
printf 'Lists load in one query, now cached.\r\n' >"$tmp/pr/body"
scripts/push-pr.sh >/dev/null
expect_eq "push-pr.sh after a description edit lands the new description" "$(body_of p1 | sed -n 3p)" \
  "Lists load in one query, now cached."

open_pr p2
MODEL_CO_AUTHOR="Claude Fable 5.1 <noreply@anthropic.com>" scripts/push-pr.sh >/dev/null
expect_eq "MODEL_CO_AUTHOR joins the trailers ahead of Peter's" "$(body_of p2 | sed '/^$/d' | tail -n 2)" \
  "Co-authored-by: Claude Fable 5.1 <noreply@anthropic.com>
Co-authored-by: Peter Trost <peter@petertrost.com>"

open_pr p3
MODEL_CO_AUTHOR="claude opus 5.5 <noreply@anthropic.com>" scripts/push-pr.sh >/dev/null
expect_eq "a MODEL_CO_AUTHOR a commit already names appears once" \
  "$(body_of p3 | grep -ic 'claude opus 5.5')" 1

open_pr p4
printf '' >"$tmp/pr/body"
scripts/push-pr.sh >/dev/null
expect_eq "an empty description leaves subject, the added changelog and trailers" "$(body_of p4)" "Make lists faster (#7)

## Changelog
none

Co-authored-by: Alice <alice@example.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Co-authored-by: Peter Trost <peter@petertrost.com>"

open_pr p5
before="$(git rev-parse HEAD)"
if MODEL_CO_AUTHOR="Claude" scripts/push-pr.sh >/dev/null 2>"$tmp/err"; then
  fail "push-pr.sh accepted MODEL_CO_AUTHOR=Claude"
fi
grep -q "MODEL_CO_AUTHOR must look like 'Name <email>'" "$tmp/err" || fail "no MODEL_CO_AUTHOR error: $(cat "$tmp/err")"
expect_eq "a bad MODEL_CO_AUTHOR pushes nothing" "$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p5)" "$before"

# Job 307: the checks before the push, and a PR opened as a draft.
open_pr k1
before="$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/k1)"
touch "$tmp/pr/checks-fail"
if scripts/push-pr.sh >/dev/null 2>"$tmp/err"; then fail "push-pr.sh pushed although a check failed"; fi
grep -q 'lint.sh: a finding' "$tmp/err" || fail "the failed check's output is missing: $(cat "$tmp/err")"
grep -q 'push-pr.sh: not pushing #7: the checks above failed' "$tmp/err" || fail "no refusal for a failed check: $(cat "$tmp/err")"
expect_eq "a failed check pushes nothing" "$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/k1)" "$before"
PUSH_PR_SKIP_CHECKS=1 scripts/push-pr.sh >/dev/null || fail "PUSH_PR_SKIP_CHECKS=1 did not push"
[[ "$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/k1)" != "$before" ]] || fail "PUSH_PR_SKIP_CHECKS=1 pushed nothing"
rm "$tmp/pr/checks-fail"
open_pr k2
touch "$tmp/pr/draft"
scripts/push-pr.sh >/dev/null
[[ ! -e $tmp/pr/draft ]] || fail "push-pr.sh left the draft PR a draft"
expect_eq "push-pr.sh marks the draft ready after its push" "$(cat "$tmp/pr/ready-at")" \
  "$(git --git-dir="$tmp/origin.git" rev-parse refs/heads/k2)"
touch "$tmp/pr/draft"
scripts/push-pr.sh >/dev/null
[[ ! -e $tmp/pr/draft ]] || fail "push-pr.sh with nothing to push left the draft PR a draft"

# Job 39: the changelog section. p1 above had none and only non-app files: "none" was added.
expect_eq "push-pr.sh adds none once, also after a description edit" "$(body_of p1 | grep -c '^## Changelog$')" 1
app_pr() {
  open_pr "$1"
  mkdir -p app && echo x >app/main.dart && git add app && git commit -q -m "app change"
  printf '%s' "$2" >"$tmp/pr/body"
  rm -f "$tmp/pr/edited"
}
expect_refused() {
  local before
  before="$(git --git-dir="$tmp/origin.git" rev-parse "refs/heads/$(git symbolic-ref --short HEAD)")"
  if scripts/push-pr.sh >/dev/null 2>"$tmp/err"; then fail "$1: push-pr.sh pushed"; fi
  grep -qF -- "$2" "$tmp/err" || fail "$1: expected '$2' in: $(cat "$tmp/err")"
  grep -qF -- "en: The list sorts itself after your shopping trip." "$tmp/err" || fail "$1: no format example in: $(cat "$tmp/err")"
  expect_eq "$1: nothing pushed" "$(git --git-dir="$tmp/origin.git" rev-parse "refs/heads/$(git symbolic-ref --short HEAD)")" "$before"
  [[ ! -e $tmp/pr/edited ]] || fail "$1: the PR description was edited"
}
app_pr c1 $'Adds a screen.\r\n'
expect_refused "an app change without a section" "this PR changes the app or its backend: add a ## Changelog section"
open_pr c1b
mkdir -p supabase/functions/alexa && echo x >supabase/functions/alexa/index.ts && git add supabase && git commit -q -m "alexa"
printf 'Alexa learns a word.\n' >"$tmp/pr/body"
rm -f "$tmp/pr/edited"
expect_refused "a backend change without a section" "this PR changes the app or its backend"
app_pr c2 $'Adds a screen.\n\n## Changelog\nnew\nde: Ein neuer Bildschirm.\n'
expect_refused "an item without en:" 'invalid: new item "Ein neuer Bildschirm." has no "en:" line'
app_pr c3 $'Adds a screen.\n\n## Changelog\nnone\n\nfixed\nde: A.\nen: B.\n'
expect_refused "none with items" '"none" and items in one section'
app_pr dependabot/npm/x $'Bumps x.\n'
scripts/push-pr.sh >/dev/null 2>&1 || fail "a Dependabot PR without a section was refused"
expect_eq "a Dependabot PR gets none" "$(body_of dependabot/npm/x | sed -n '3,6p')" "Bumps x.

## Changelog
none"
app_pr c4 $'Adds a screen.\n\n## Changelog\nnew\nde: Ein neuer Bildschirm.\nen: A new screen.\n'
scripts/push-pr.sh >/dev/null
expect_eq "a valid section lands unchanged" "$(body_of c4 | sed -n '3,8p')" "Adds a screen.

## Changelog
new
de: Ein neuer Bildschirm.
en: A new screen."
[[ ! -e $tmp/pr/edited ]] || fail "a valid section: the PR description was edited"

open_pr p6
scripts/merge-pr.sh 7 >/dev/null 2>&1 && status=0 || status=$?
expect_eq "merge-pr.sh squashes a two-commit PR and exits 2" "$status" 2
expect_eq "merge-pr.sh squashes to the PR description too" "$(body_of p6 | sed -n 3p)" "Lists load in one query."

for minutes in 0.5 abc -1 "1 2"; do
  out="$(MERGE_WAIT_MINUTES="$minutes" scripts/merge-pr.sh --wait 7 2>&1)" && status=0 || status=$?
  expect_eq "MERGE_WAIT_MINUTES='$minutes' exits 2" "$status" 2
  [[ $out == *"MERGE_WAIT_MINUTES must be a whole number of minutes (like 30), not '$minutes'"* ]] \
    || fail "MERGE_WAIT_MINUTES='$minutes' gave: $out"
  [[ $out != *"syntax error"* ]] || fail "MERGE_WAIT_MINUTES='$minutes' hit bash arithmetic: $out"
done
if out="$(MERGE_WAIT_MINUTES=0 scripts/merge-pr.sh --wait 7 2>&1)"; then fail "merged with ci-ok pending"; fi
[[ $out == *"after 0 min; not merging"* ]] || fail "MERGE_WAIT_MINUTES=0 gave: $out"
echo skipping >"$tmp/pr/ci"
out="$(MERGE_WAIT_MINUTES=1 timeout 15 scripts/merge-pr.sh --wait 7 2>&1)" && status=0 || status=$?
expect_eq "merge-pr.sh stops at once on a skipped ci-ok (a draft's opening run)" "$status" 1
[[ $out == *"ci-ok was skipped on"*"no CI ran on it"* ]] || fail "a skipped ci-ok gave: $out"
echo pass >"$tmp/pr/ci"
cp "$tmp/pr/body" "$tmp/pr/body.pushed"
printf 'Edited after the push.\r\n' >"$tmp/pr/body"
out="$(scripts/merge-pr.sh --wait 7 2>&1)" && status=0 || status=$?
expect_eq "merge-pr.sh refuses a head whose body is not the current description" "$status" 1
[[ $out == *"the PR description changed since the last push; run scripts/push-pr.sh"* ]] || fail "edited description gave: $out"
[[ ! -e $tmp/pr/merged ]] || fail "merge-pr.sh merged a stale description"
mv "$tmp/pr/body.pushed" "$tmp/pr/body"
out="$(MERGE_WAIT_MINUTES=08 scripts/merge-pr.sh --wait 7 2>&1)" || fail "MERGE_WAIT_MINUTES=08 did not merge: $out"
expect_eq "MERGE_WAIT_MINUTES=08 merges once ci-ok passes" "$(cat "$tmp/pr/merged" 2>/dev/null)" \
  "merged $(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p6)"

# Job 218: right after push-pr.sh's push GitHub's record still names the head before it, which is
# not on top of main. A sleep that only counts stands in for the 5 s between two looks.
mkdir "$tmp/nosleep"
cat >"$tmp/nosleep/sleep" <<'SLEEP'
#!/usr/bin/env bash
echo "$1" >>"$FAKE_PR/slept"
SLEEP
chmod +x "$tmp/nosleep/sleep"
# A PR opened before main moved (on the first commit), then pushed with push-pr.sh: the head
# before that push is behind main, as in a land that had to rebase.
pushed_pr() {
  git checkout -q -B "$1" "$(git rev-list --max-parents=0 origin/main)"
  echo "$1" >"$tmp/pr/branch"
  echo "$1" >"$1" && git add "$1" && git commit -q -m "wip"
  git push -q -u origin HEAD 2>/dev/null
  before_push="$(git rev-parse HEAD)"
  scripts/push-pr.sh >/dev/null 2>&1 || fail "push-pr.sh did not push $1"
  echo pass >"$tmp/pr/ci"
}
pushed_pr p7
printf '%s\n%s\n' "$before_push" "$before_push" >"$tmp/pr/stale-heads"
out="$(PATH="$tmp/nosleep:$PATH" scripts/merge-pr.sh 7 2>&1)" || fail "a record two looks behind the push stopped the merge: $out"
expect_eq "merge-pr.sh merges the pushed head once GitHub's record names it" "$(tail -n 1 "$tmp/pr/merged")" \
  "merged $(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p7)"
expect_eq "merge-pr.sh looked again twice, 5 s apart" "$(tr '\n' ' ' <"$tmp/pr/slept")" "5 5 "

pushed_pr p8
for _ in $(seq 100); do echo "$before_push"; done >"$tmp/pr/stale-heads"
rm -f "$tmp/pr/slept"
if out="$(PATH="$tmp/nosleep:$PATH" scripts/merge-pr.sh 7 2>&1)"; then fail "merged on a record that never named the pushed head"; fi
[[ $out == *"GitHub names $before_push as #7's head, 2 min after p8 was read as $(git rev-parse HEAD)"* ]] \
  || fail "a record that stays behind gave: $out"
expect_eq "merge-pr.sh gives the record 2 min" "$(wc -l <"$tmp/pr/slept" | tr -d ' ')" 24
expect_eq "nothing merged on the stale record" "$(tail -n 1 "$tmp/pr/merged")" \
  "merged $(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p7)"
rm "$tmp/pr/stale-heads"

# The wait is for the record only: a main that moved after the push still stops the merge.
pushed_pr p9
git push -q origin "$(git commit-tree -p origin/main -m "main moved" 'origin/main^{tree}'):refs/heads/main"
rm -f "$tmp/pr/slept"
if out="$(PATH="$tmp/nosleep:$PATH" scripts/merge-pr.sh 7 2>&1)"; then fail "merged a head that is behind main"; fi
[[ $out == *"p9 is behind main; run scripts/push-pr.sh"* ]] || fail "main moved after the push gave: $out"
[[ ! -e $tmp/pr/slept ]] || fail "merge-pr.sh waited for a record that was current"
expect_eq "nothing merged behind main" "$(tail -n 1 "$tmp/pr/merged")" \
  "merged $(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p7)"

# Job 219: another checkout's fg-cli gate ended every `sleep 20` on the machine by name, and with
# it a land's wait for CI. The first two sleeps end as that one did, of SIGTERM with ci-ok still
# pending: one every time, the other until ci-ok passes during its second sleep. The third fails
# without a signal (128 is the highest status that is not one). A wait that spins would run to
# its deadline, hence the one minute.
mkdir "$tmp/endedsleep" "$tmp/endedtwice" "$tmp/failedsleep"
cat >"$tmp/endedsleep/sleep" <<'SLEEP'
#!/usr/bin/env bash
echo "$1" >>"$FAKE_PR/slept"
kill -TERM $$
SLEEP
cat >"$tmp/endedtwice/sleep" <<'SLEEP'
#!/usr/bin/env bash
echo "$1" >>"$FAKE_PR/slept"
[[ $(wc -l <"$FAKE_PR/slept") -lt 2 ]] || echo pass >"$FAKE_PR/ci"
kill -TERM $$
SLEEP
cat >"$tmp/failedsleep/sleep" <<'SLEEP'
#!/usr/bin/env bash
echo "$1" >>"$FAKE_PR/slept"
exit 128
SLEEP
chmod +x "$tmp"/{endedsleep,endedtwice,failedsleep}/sleep
pushed_pr p10
echo pending >"$tmp/pr/ci"
rm -f "$tmp/pr/slept"
out="$(PATH="$tmp/failedsleep:$PATH" MERGE_WAIT_MINUTES=1 scripts/merge-pr.sh --wait 7 2>&1)" && status=0 || status=$?
expect_eq "merge-pr.sh stops when its wait's sleep fails without a signal" "$status" 128
[[ $out == *"the wait's sleep failed (exit 128); not merging"* ]] || fail "a wait whose sleep failed gave: $out"
expect_eq "it did not wait on after the failed sleep" "$(tr '\n' ' ' <"$tmp/pr/slept")" "20 "
rm "$tmp/pr/slept"
out="$(PATH="$tmp/endedsleep:$PATH" MERGE_WAIT_MINUTES=1 scripts/merge-pr.sh --wait 7 2>&1)" && status=0 || status=$?
expect_eq "merge-pr.sh stops when a signal ends its wait's sleep every time" "$status" 1
[[ $out == *"the wait's sleep was ended by a signal 21 times (exit 143); not merging"* ]] \
  || fail "a wait whose sleep was ended every time gave: $(tail -n 2 <<<"$out")"
expect_eq "it waited on through 20 ended sleeps" "$(wc -l <"$tmp/pr/slept" | tr -d ' ')" 21
expect_eq "nothing merged after the failed and the ended sleeps" "$(tail -n 1 "$tmp/pr/merged")" \
  "merged $(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p7)"
rm "$tmp/pr/slept"
out="$(PATH="$tmp/endedtwice:$PATH" MERGE_WAIT_MINUTES=1 scripts/merge-pr.sh --wait 7 2>&1)" || fail "a wait whose sleep a signal ended did not merge: $out"
expect_eq "merge-pr.sh says so each time a signal ended its wait's sleep" \
  "$(grep -c "the wait's sleep was ended by a signal (exit 143); still waiting for ci-ok" <<<"$out")" 2
expect_eq "merge-pr.sh waited on while ci-ok was pending, and looked again after each sleep" \
  "$(tr '\n' ' ' <"$tmp/pr/slept")" "20 20 "
expect_eq "merge-pr.sh merges after a wait whose sleeps a signal ended" "$(tail -n 1 "$tmp/pr/merged")" \
  "merged $(git --git-dir="$tmp/origin.git" rev-parse refs/heads/p10)"

if [[ $failures -gt 0 ]]; then
  echo "landing-test: $failures failed" >&2
  exit 1
fi
log "push-pr.sh and merge-pr.sh: all cases pass"
