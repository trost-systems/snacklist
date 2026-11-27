#!/usr/bin/env bash
# Lands a PR on main as one commit authored with the required noreply email.
# GitHub's squash merge authors the commit with the account's default email
# and rejects the noreply address as --author-email, so the squash happens
# locally and the single commit is rebase-merged, which keeps its author.
#
# Usage: scripts/merge-pr.sh [--wait] [--dry-run] <pr-number>
#   Pushed with scripts/push-pr.sh, the PR head is already that one commit: this checks ci-ok
#   on it and rebase-merges it (with --wait, it first waits for ci-ok to finish).
#   Otherwise (pushed with plain git push), it squashes the PR, force-pushes the PR branch and
#   exits 2: wait for ci-ok on the new head, then rerun. That costs a second CI run.
#   If main moved since the push, the head is no longer on top of main: rerun
#   scripts/push-pr.sh (one rebase, one push, one CI run), then this.
#   Run right after a push, it waits (up to 2 min) until GitHub's record of the PR names the
#   pushed head.
#   If the PR description changed since that push, it stops: rerun scripts/push-pr.sh, which
#   lands the current description.
#   --dry-run checks everything and stops before the merge.
#   --wait gives up after MERGE_WAIT_MINUTES (whole minutes, default 30), so a ci-ok that never
#   reports can't hold the merge lock forever.
#   A PR labelled do-not-merge is refused; the label comes off only by hand (a hold flip waits for
#   Legal's GO and Peter's yes, job 476).
#   After the merge it starts scripts/hold-flip-draft.sh for the PR in the background, with none of
#   this process's files open, so the merge lock is released at once (log in .git/hold-flip-draft.log).
#   A run of it that failed is shown at the start of the next merge-pr.sh, with its rerun command.
#   A signal that ends only the wait's sleep (a kill by name elsewhere on the machine) does not
#   end the wait: it is logged and the wait goes on, up to 20 times.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

wait=0 dry_run=0
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --wait) wait=1 ;;
    --dry-run) dry_run=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
PR="${1:?usage: scripts/merge-pr.sh [--wait] [--dry-run] <pr-number>}"
wait_minutes="${MERGE_WAIT_MINUTES:-30}"
if [[ ! $wait_minutes =~ ^[0-9]+$ ]]; then
  echo "MERGE_WAIT_MINUTES must be a whole number of minutes (like 30), not '$wait_minutes'" >&2
  exit 2
fi
wait_minutes=$((10#$wait_minutes))

cd "$REPO_ROOT"
hold_flip_failed="$(git rev-parse --path-format=absolute --git-common-dir)/hold-flip-draft.failed"
if [[ -s $hold_flip_failed ]]; then
  echo "warning: a hold-flip-draft.sh run after an earlier merge failed, so a draft hold flip may be missing. Run the rerun it names (a run that gets through removes its line from $hold_flip_failed):" >&2
  cat "$hold_flip_failed" >&2
fi
if gh pr view "$PR" --json labels -q '.labels[].name' | grep -qx do-not-merge; then
  echo "#$PR is labelled do-not-merge; not merging. Remove the label by hand once what it waits for is recorded (a hold flip: Legal's GO and Peter's yes), then rerun" >&2
  exit 1
fi
branch="$(gh pr view "$PR" --json headRefName -q .headRefName)"
title="$(gh pr view "$PR" --json title -q .title)"
subject="$title (#$PR)"
git_fetch -q origin main
git_fetch -q origin "$branch"
head="$(git rev-parse FETCH_HEAD)"
# The head is what the branch holds. For some seconds after a push GitHub's record of the PR still
# names the head before it, and the checks and the merge go by that record: wait until it follows.
# Read from the record, a head pushed a moment ago looked "behind main" (17 lands, job 218).
for ((try = 0; ; try++)); do
  recorded="$(gh pr view "$PR" --json headRefOid -q .headRefOid)"
  [[ $recorded == "$head" ]] && break
  if [[ $try == 24 ]]; then
    echo "GitHub names $recorded as #$PR's head, 2 min after $branch was read as $head; rerun once \`gh pr view $PR --json headRefOid\` shows the branch's head" >&2
    exit 1
  fi
  [[ $try == 0 ]] && log "GitHub names ${recorded:0:8} as #$PR's head, $branch is at ${head:0:8}: waiting for its record"
  sleep 5
done

if [[ "$(git merge-base origin/main "$head")" != "$(git rev-parse origin/main)" ]]; then
  echo "$branch is behind main; run scripts/push-pr.sh on it (rebases and squashes), wait for ci-ok, then rerun" >&2
  exit 1
fi
if [[ "$(git rev-list --count "origin/main..$head")" == 0 ]]; then
  echo "#$PR has no commits on top of main; nothing to merge" >&2
  exit 1
fi
problem="$(landing_problem "$head" "$subject")"
description="$(gh pr view "$PR" --json body -q .body)"
squashed="$(squash_commit "$head" "$subject" "$description")"
if [[ -z $problem && "$(git log -1 --format=%B "$squashed")" != "$(git log -1 --format=%B "$head")" ]]; then
  echo "the PR description changed since the last push; run scripts/push-pr.sh (it lands the current one), wait for ci-ok, then rerun" >&2
  exit 1
fi
if [[ -n $problem ]]; then
  [[ $dry_run == 1 ]] && { log "dry run: would squash and push because $problem"; exit 2; }
  log "squashing $branch into one commit ($problem): $subject"
  git push -q --force-with-lease="$branch:$head" origin "$squashed:refs/heads/$branch"
  log "pushed $squashed; rerun once ci-ok passes on it (scripts/push-pr.sh saves this second CI run)"
  exit 2
fi

# gh pr checks exits 8 while checks are pending; the bucket says the same.
ci_ok() { gh pr checks "$PR" --json name,bucket -q '.[] | select(.name=="ci-ok") | .bucket' || true; }
state="$(ci_ok)"
if [[ $wait == 1 ]]; then
  deadline=$((SECONDS + wait_minutes * 60))
  ended_sleeps=0
  log "waiting for ci-ok on $head (up to $wait_minutes min)"
  while [[ $state != pass && $state != fail && $state != cancel && $state != skipping ]]; do
    if [[ $SECONDS -ge $deadline ]]; then
      echo "ci-ok is still '${state:-missing}' on $head after $wait_minutes min; not merging. Check the run, then rerun (release the merge lock meanwhile)" >&2
      exit 1
    fi
    # A kill by name elsewhere on the machine ends this sleep too (an fg-cli gate's test did,
    # job 219): the land keeps its turn. A sleep that fails any other way, or keeps being ended,
    # stops it: without the pause the loop would spend much of the token's API budget on looks.
    sleep 20 || {
      status=$?
      if ((status <= 128)); then
        echo "the wait's sleep failed (exit $status); not merging" >&2
        exit "$status"
      fi
      if ((++ended_sleeps > 20)); then
        echo "the wait's sleep was ended by a signal $ended_sleeps times (exit $status); not merging" >&2
        exit 1
      fi
      log "the wait's sleep was ended by a signal (exit $status); still waiting for ci-ok"
    }
    state="$(ci_ok)"
  done
fi
# Skipped only in the run of a draft's opening push (ci.yml, job 307): no gate ran on this commit.
if [[ $state == skipping ]]; then
  echo "ci-ok was skipped on $head: no CI ran on it (the run of a PR opened as a draft). Make a new commit (git commit --amend --no-edit), push it with scripts/push-pr.sh, then rerun" >&2
  exit 1
fi
if [[ $state != pass ]]; then
  echo "ci-ok is '${state:-pending or missing}' on $head; not merging" >&2
  exit 1
fi
if [[ $dry_run == 1 ]]; then
  log "dry run: #$PR is $head, one compliant commit on top of main with ci-ok green; would merge it now"
  exit 0
fi
gh pr merge "$PR" --rebase --match-head-commit "$head"
log "merged #$PR as $head ($AUTHOR_EMAIL)"
hold_flip_log="$(git rev-parse --path-format=absolute --git-common-dir)/hold-flip-draft.log"
run_detached "$hold_flip_log" scripts/hold-flip-draft.sh "$PR"
log "scripts/hold-flip-draft.sh $PR runs in the background (a draft flip PR if #$PR changed legal text behind an unreleased hold); log: $hold_flip_log"
