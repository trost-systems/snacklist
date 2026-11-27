#!/usr/bin/env bash
# Tests scripts/hold-flip-draft.sh against a scratch remote, a fake gh and a stub push-pr.sh: legal
# text behind an unreleased hold opens exactly one draft flip PR, with the enable checklist line once;
# a rerun, a released hold and a merge without legal text open nothing; `until` blocks, heading
# gates and two holds in one merge; a PR number for an old merge backfills; a fetch racing another
# in the shared clone, and a failed run that says so with its rerun. Also that run_detached
# (lib.sh), which merge-pr.sh starts it with, leaves no lock held. Run by the lint gate. No network.
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
mkdir -p "$tmp/work/scripts" "$tmp/work/releases" "$tmp/work/site/content/legal" "$tmp/work/docs" "$tmp/bin" "$tmp/gh"
cp "$REPO_ROOT"/scripts/{lib,hold-flip-draft}.sh "$tmp/work/scripts/"
# push-pr.sh's stand-in records its call and pushes the branch as it is.
cat >"$tmp/work/scripts/push-pr.sh" <<'PUSH'
#!/usr/bin/env bash
set -euo pipefail
branch="$(git symbolic-ref --short HEAD)"
echo "push-pr $branch keep-draft=${PUSH_PR_KEEP_DRAFT:-} skip-checks=${PUSH_PR_SKIP_CHECKS:-}" >>"$FAKE_GH/calls"
n="$(cat "$FAKE_GH/open/${branch//\//_}")"
git commit -q --amend -m "$(cat "$FAKE_GH/title-$n") (#$n)"
git push -q -f origin "HEAD:refs/heads/$branch"
PUSH
chmod +x "$tmp/work/scripts/push-pr.sh"
cat >"$tmp/work/releases/flags.json" <<'JSON'
{
  "flags": {
    "some-flag": {
      "rollout": "off",
      "note": "untouched"
    }
  },
  "holds": {
    "push-notifications": {
      "released": false,
      "note": "waits for Legal"
    },
    "native-siri": {
      "released": false,
      "note": "waits for a device test"
    },
    "new-design": {
      "released": true,
      "note": "released on 2026-11-01"
    }
  }
}
JSON
cat >"$tmp/work/site/content/legal/datenschutz.md" <<'MD'
---
title: Datenschutz
updated: 2026-11-20
---

# Datenschutzerklärung

Stand: 20. November 2026

## Allgemein

Text für alle.

::: once push-notifications
Mitteilungen: alt.
:::

::: until native-siri
Kurzbefehl einrichten.
:::

::: once new-design
Neues Aussehen.
:::

## Siri {#siri once=native-siri}

Siri ohne Kurzbefehl.

### Details

Mehr zu Siri.

## Danach

Ohne Gate.
MD
cat >"$tmp/work/site/content/legal/privacy.md" <<'MD'
---
title: Privacy
updated: 2026-11-20
---

# Privacy policy

Last updated: 20 November 2026

::: once push-notifications
Notifications: old.
:::
MD
cat >"$tmp/work/site/content/legal/terms.md" <<'MD'
---
updated: 2026-11-20
---

Last updated: 20 November 2026

Terms without gates.
MD
printf '# Needs lead\n\n## NEEDS_LEAD Job 1: something\n\nText.\n' >"$tmp/work/docs/NEEDS_LEAD.md"
export GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
cd "$tmp/work"
git add -A
git commit -q -m init
git push -q origin HEAD:main

# The fake gh: open PRs are files in $FAKE_GH/open named by branch, merged ones in $FAKE_GH/merged.
cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
d="$FAKE_GH"
arg() { local want="$1"; shift; while [[ $# -gt 0 ]]; do [[ $1 == "$want" ]] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "pr list")
    f="$d/open/$(arg --head "$@" | tr / _)"
    if [[ -e $f ]]; then cat "$f"; fi ;;
  "pr create")
    echo "create $*" >>"$d/calls"
    n=$(($(cat "$d/next" 2>/dev/null || echo 100) + 1)); echo "$n" >"$d/next"
    mkdir -p "$d/open"; echo "$n" >"$d/open/$(arg --head "$@" | tr / _)"
    arg --title "$@" >"$d/title-$n"
    cp "$(arg --body-file "$@")" "$d/body-$n"
    echo "https://github.com/o/r/pull/$n" ;;
  "pr view")
    case "$*" in
      *state,mergeCommit*)
        if [[ -e $d/merged/$3 ]]; then echo "MERGED $(cat "$d/merged/$3")"; else echo "OPEN "; fi ;;
      *body,comments*) cat "$d/body-$3" "$d/comments-$3" 2>/dev/null || true ;;
      *) echo "fake gh: no answer for $*" >&2; exit 1 ;;
    esac ;;
  "pr comment")
    echo "comment $3" >>"$d/calls"
    arg --body "$@" >>"$d/comments-$3" ;;
  *) echo "fake gh: no answer for $*" >&2; exit 1 ;;
esac
GH
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_GH="$tmp/gh"

# Lands a change on main as PR #n: merge <n> <sed-expression> <file> [<sed-expression> <file>]...
merge() {
  local n="$1"
  shift
  git fetch -q origin main && git checkout -q --detach origin/main
  while [[ $# -gt 0 ]]; do
    sed -i "$1" "$2"
    shift 2
  done
  git commit -q -am "Change $n (#$n)"
  git push -q origin HEAD:main
  mkdir -p "$FAKE_GH/merged" && git rev-parse HEAD >"$FAKE_GH/merged/$n"
}
calls() { cat "$FAKE_GH/calls" 2>/dev/null || true; }
reset_calls() { rm -f "$FAKE_GH/calls"; }
on_branch() { git --git-dir="$tmp/origin.git" show "refs/heads/hold-flip/$1:$2"; }
run() { scripts/hold-flip-draft.sh "$@" >"$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "hold-flip-draft.sh $* exited non-zero"; }; }

today_iso="$(TZ=Europe/Berlin date +%Y-%m-%d)"
de_months=(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
en_months=(January February March April May June July August September October November December)
day="$((10#$(TZ=Europe/Berlin date +%d)))" month="$((10#$(TZ=Europe/Berlin date +%m)))" year="$(TZ=Europe/Berlin date +%Y)"

# 1. Text added in a `once` block of an unreleased hold: one draft, the flip, the line.
merge 11 's/^Mitteilungen: alt\.$/Mitteilungen: neu, mit FCM./' site/content/legal/datenschutz.md
reset_calls
run 11
expect_eq "a once block opens exactly one draft PR, then pushes it with push-pr.sh as a draft" "$(calls)" \
  "create pr create --draft --base main --head hold-flip/push-notifications --title Hold flip: push-notifications (draft, waits for Legal GO) --body-file $(sed -n 's/.*--body-file \([^ ]*\) .*/\1/p' <<<"$(calls)") --label do-not-merge
push-pr hold-flip/push-notifications keep-draft=1 skip-checks=1"
expect_eq "the flip releases the hold and nothing else in flags.json" \
  "$(git --git-dir="$tmp/origin.git" diff main hold-flip/push-notifications -- releases/flags.json | grep '^[-+] ')" \
  "-      \"released\": false,
+      \"released\": true,"
expect_eq "the flip dates the files with a block for the hold" \
  "$(git --git-dir="$tmp/origin.git" diff --stat=200 main hold-flip/push-notifications -- site | sed -n 's/ *|.*//p' | sed 's/^ *//')" \
  "site/content/legal/datenschutz.md
site/content/legal/privacy.md"
expect_eq "datenschutz.md gets today's dates" \
  "$(on_branch push-notifications site/content/legal/datenschutz.md | grep -E '^(updated|Stand):')" \
  "updated: $today_iso
Stand: $day. ${de_months[month - 1]} $year"
expect_eq "privacy.md gets today's dates" \
  "$(on_branch push-notifications site/content/legal/privacy.md | grep -E '^(updated|Last updated):')" \
  "updated: $today_iso
Last updated: $day ${en_months[month - 1]} $year"
expect_eq "the NEEDS_LEAD line is added once, with the PR number" \
  "$(on_branch push-notifications docs/NEEDS_LEAD.md | grep -c 'Enable checklist for hold push-notifications: owner Snacklist Engineering Lead; flip PR #101; open items: Legal GO, Peter yes, live check, device evidence (see docs/PUSH.md)')" 1
body="$(cat "$FAKE_GH/body-101")"
for want in "DO NOT MERGE without Legal's GO" "#11" "site/content/legal/datenschutz.md" "site/content/legal/privacy.md" \
  "Legal's hash-bound GO" "approvals-log.md" "Legal's live check" "## Changelog"; do
  [[ $body == *"$want"* ]] || fail "the PR body names $want"
done
[[ $body == *"$(on_branch push-notifications site/content/legal/privacy.md | sha256sum | cut -d' ' -f1)"* ]] ||
  fail "the PR body carries privacy.md's sha256 on the branch"
[[ $body != *terms.md* ]] || fail "the PR body lists a legal file without a block for the hold"

# 2. A rerun, by PR number or by commit, opens nothing and adds no second line.
reset_calls
run 11
run "$(cat "$FAKE_GH/merged/11")"
expect_eq "a rerun does nothing" "$(calls)" ""
expect_eq "a rerun adds no second NEEDS_LEAD line" \
  "$(on_branch push-notifications docs/NEEDS_LEAD.md | grep -c 'Enable checklist for hold push-notifications:')" 1

# 3. A later merge changing the same hold's text: one comment on the open PR, once.
merge 12 's/^Notifications: old\.$/Notifications: new./' site/content/legal/privacy.md
reset_calls
run 12
run 12
expect_eq "a later merge for an open flip is noted on it once" "$(calls)" "comment 101"
# PR #1's number is a prefix of #11, which the open flip's body names: it is noted all the same.
merge 1 's/^Notifications: new\.$/Notifications: new, again./' site/content/legal/privacy.md
reset_calls
run 1
expect_eq "a merge whose number prefixes one the flip names is still noted" "$(calls)" "comment 101"

# 4. A released hold, and a merge without legal text: nothing.
merge 13 's/^Neues Aussehen\.$/Neues Aussehen, jetzt live./' site/content/legal/datenschutz.md
merge 14 's/^Terms without gates\.$/Terms, reworded./' site/content/legal/terms.md 's/untouched/still untouched/' releases/flags.json
reset_calls
run 13
[[ "$(cat "$tmp/out")" == *"nothing to flip"* ]] || fail "a released hold says nothing to flip: $(cat "$tmp/out")"
run 14
expect_eq "a released hold and ungated legal text open nothing" "$(calls)" ""

# 5. An `until` block: the flip of the same hold.
merge 15 's/^Kurzbefehl einrichten\.$/Kurzbefehl einrichten, Schritt für Schritt./' site/content/legal/datenschutz.md
reset_calls
run 15
expect_eq "an until block opens the flip of its hold" "$(calls | cut -d' ' -f1-8)" \
  "create pr create --draft --base main --head hold-flip/native-siri
push-pr hold-flip/native-siri keep-draft=1 skip-checks=1"
expect_eq "only the file with the hold's block is dated" \
  "$(git --git-dir="$tmp/origin.git" diff --name-only main hold-flip/native-siri)" \
  "docs/NEEDS_LEAD.md
releases/flags.json
site/content/legal/datenschutz.md"

# 6. Two holds in one merge: two PRs. A heading gate counts down to its section's end.
rm "$FAKE_GH"/open/*
git --git-dir="$tmp/origin.git" branch -q -D hold-flip/push-notifications hold-flip/native-siri
git fetch -q origin main && git checkout -q --detach origin/main
printf '\n## Enable checklist: hold native-siri\n\n- [earlier] Enable checklist for hold native-siri: owner Snacklist Engineering Lead; flip PR #102\n' >>docs/NEEDS_LEAD.md
git commit -q -am "Earlier checklist line" && git push -q origin HEAD:main
merge 16 's/^Mehr zu Siri\.$/Mehr zu Siri, neu./' site/content/legal/datenschutz.md 's/^Notifications: new, again\.$/Notifications: newer./' site/content/legal/privacy.md
reset_calls
run 16
expect_eq "two holds in one merge open two drafts" "$(calls | cut -d' ' -f1-8)" \
  "create pr create --draft --base main --head hold-flip/native-siri
push-pr hold-flip/native-siri keep-draft=1 skip-checks=1
create pr create --draft --base main --head hold-flip/push-notifications
push-pr hold-flip/push-notifications keep-draft=1 skip-checks=1"
expect_eq "a reopened flip adds no second NEEDS_LEAD line when main has one" \
  "$(on_branch native-siri docs/NEEDS_LEAD.md | grep -c 'Enable checklist for hold native-siri:')" 1
merge 17 's/^Ohne Gate\.$/Ohne Gate, geändert./' site/content/legal/datenschutz.md
reset_calls
run 17
expect_eq "a heading gate ends at the next heading of its level" "$(calls)" ""

# 7. An open PR is not merged: nothing; the dry run pushes and opens nothing.
reset_calls
run 99
[[ "$(cat "$tmp/out")" == *"not merged"* ]] || fail "an unmerged PR is skipped: $(cat "$tmp/out")"
rm "$FAKE_GH"/open/*
before="$(git --git-dir="$tmp/origin.git" for-each-ref --format='%(refname) %(objectname)')"
run --dry-run 16
expect_eq "a dry run calls no gh write and no push-pr.sh" "$(calls)" ""
expect_eq "a dry run pushes nothing" "$(git --git-dir="$tmp/origin.git" for-each-ref --format='%(refname) %(objectname)')" "$before"
[[ "$(cat "$tmp/out")" == *'+      "released": true,'* ]] || fail "the dry run prints the flip"

# 8. Another process in the shared clone holds origin/main's lock (it is fetching too): the run
# fetches into a ref of its own and opens the flip all the same, leaving origin/main and no ref behind.
merge 18 's/^Notifications: newer\.$/Notifications: newest./' site/content/legal/privacy.md
git update-ref refs/remotes/origin/main HEAD~1
tracking="$(git rev-parse origin/main)"
lock="$(git rev-parse --git-common-dir)/refs/remotes/origin/main.lock"
touch "$lock"
git fetch -q origin main 2>/dev/null && fail "the held lock does not stop a plain fetch, so case 8 proves nothing"
reset_calls
run 18
run 18
expect_eq "a held origin/main lock still opens the flip, once" "$(calls | cut -d' ' -f1-8)" \
  "create pr create --draft --base main --head hold-flip/push-notifications
push-pr hold-flip/push-notifications keep-draft=1 skip-checks=1"
expect_eq "the run leaves origin/main alone" "$(git rev-parse origin/main)" "$tracking"
expect_eq "the run deletes its private refs" "$(git for-each-ref refs/hold-flip-run)" ""
rm "$lock"

# 9. A fetch that keeps failing: exit non-zero with one line naming the rerun, on stderr and in
# .git/hold-flip-draft.failed, which a later run that gets through clears.
failed="$(git rev-parse --path-format=absolute --git-common-dir)/hold-flip-draft.failed"
git remote set-url origin "$tmp/gone.git"
if scripts/hold-flip-draft.sh 18 >"$tmp/out" 2>&1; then fail "a run whose fetch fails exits 0"; fi
[[ "$(cat "$tmp/out")" == *"hold-flip-draft: FAILED for #18 (exit 1): a draft hold flip may be missing; rerun: scripts/hold-flip-draft.sh 18"* ]] ||
  fail "a failed run names the rerun on stderr: $(cat "$tmp/out")"
[[ "$(cat "$failed")" == *"FAILED for #18"*"rerun: scripts/hold-flip-draft.sh 18" ]] || fail "a failed run is recorded in $failed"
git remote set-url origin "$tmp/origin.git"
echo "[earlier] hold-flip-draft: FAILED for #5 (exit 1): a draft hold flip may be missing; rerun: scripts/hold-flip-draft.sh 5" >>"$failed"
run 18
expect_eq "a run that gets through clears only its own line" "$(cat "$failed")" \
  "[earlier] hold-flip-draft: FAILED for #5 (exit 1): a draft hold flip may be missing; rerun: scripts/hold-flip-draft.sh 5"

# git_fetch (push-pr.sh and merge-pr.sh fetch origin/main itself): a lock released a moment later
# costs a retry, not the run.
git update-ref refs/remotes/origin/main HEAD~1
touch "$lock"
(sleep 0.5; rm "$lock") &
git_fetch -q origin main 2>"$tmp/out" || fail "git_fetch gave up on a lock held for half a second: $(cat "$tmp/out")"
[[ "$(cat "$tmp/out")" == *"(try 1 of 3); retrying"* ]] || fail "git_fetch's first try met the lock: $(cat "$tmp/out")"
expect_eq "git_fetch updated origin/main" "$(git rev-parse origin/main)" "$(git rev-parse HEAD)"
wait

# run_detached: the command outlives the call and keeps no descriptor of the caller's lock.
if command -v flock >/dev/null; then
  cd "$tmp"
  (
    exec 9>"$tmp/lock"
    flock 9
    run_detached "$tmp/detached.log" bash -c 'sleep 3; echo done'
  )
  flock -n "$tmp/lock" true || fail "run_detached kept the caller's lock"
  [[ ! -s $tmp/detached.log ]] || fail "run_detached waited for its command"
  for _ in {1..50}; do [[ -s $tmp/detached.log ]] && break; sleep 0.1; done
  [[ $(cat "$tmp/detached.log") == "done" ]] || fail "run_detached's command did not log"
fi

if [[ $failures -gt 0 ]]; then
  echo "hold-flip-draft-test: $failures failure(s)" >&2
  exit 1
fi
echo "hold-flip-draft-test: all passed"
