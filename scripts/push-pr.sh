#!/usr/bin/env bash
# Pushes the current branch to its open PR as the one commit main takes: rebased onto
# origin/main, squashed, subject "<PR title> (#n)", the PR description as body, the noreply
# author and the trailers (MODEL_CO_AUTHOR="Name <email>" adds the model's co-author line). The CI
# run on this push is then the one scripts/merge-pr.sh merges on, with no second squash and run.
# Use it for every push once the PR exists, fix rounds included. Before that, push the branch
# once with `git push -u origin HEAD` and open the PR with `gh pr create --draft`: a draft's
# first push runs no CI, and this marks the PR ready after its push.
# The description needs a `## Changelog` section (docs/CHANGELOG.md); when it has none and the PR
# changes nothing in the app builds (or is Dependabot's), this adds "## Changelog\nnone" to the PR first.
# PUSH_PR_KEEP_DRAFT=1 leaves a draft a draft (scripts/hold-flip-draft.sh: its PR waits for Legal).
# Before the push it runs scripts/push-checks.sh (lint.sh, and format and analyze where the branch
# changes the app) and stops when one fails; PUSH_PR_SKIP_CHECKS=1 skips them.
#
# Usage: scripts/push-pr.sh
#   A rebase conflict stops the script; resolve it, `git rebase --continue`, and rerun.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

branch="$(git symbolic-ref --short HEAD)"
if [[ $branch == main ]]; then
  echo "push-pr.sh pushes PR branches only, never main" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "commit or drop your changes first; push-pr.sh pushes commits only" >&2
  exit 1
fi
read -r pr title < <(gh pr view "$branch" --json number,title,state -q 'select(.state == "OPEN") | "\(.number) \(.title)"') || true
if [[ -z ${pr:-} ]]; then
  echo "$branch has no open PR; push it once (git push -u origin HEAD), run gh pr create, then rerun" >&2
  exit 1
fi
subject="$title (#$pr)"

git_fetch -q origin main "$branch"
if [[ "$(git merge-base origin/main HEAD)" != "$(git rev-parse origin/main)" ]]; then
  log "rebasing $branch onto origin/main"
  rebase_onto_main
fi
if [[ "$(git rev-list --count origin/main..HEAD)" == 0 ]]; then
  echo "nothing to push: $branch has no commits on top of origin/main" >&2
  exit 1
fi
description="$(gh pr view "$pr" --json body -q .body)"
# Title and description become the commit message, and GitHub runs no workflow for a commit whose message
# holds a skip marker: the PR would wait for a ci-ok that never comes (job 209).
if marker="$(grep -oiE '\[(skip ci|ci skip|no ci|skip actions|actions skip)\]|skip-checks: *true' <<<"$title"$'\n'"$description")"; then
  echo "#$pr's title or description contains \"${marker%%$'\n'*}\", which would stop CI on the pushed commit; reword it, then rerun scripts/push-pr.sh" >&2
  exit 1
fi
note_dir="$(mktemp -d)"
trap 'rm -rf "$note_dir"' EXIT
printf '%s\n' "$description" >"$note_dir/body"
git diff --name-only origin/main HEAD >"$note_dir/changed"
verdict="$(changelog_verdict "$note_dir/body" "$note_dir/changed" "$branch")" || exit 1
if [[ $verdict == add-none ]]; then
  description="$(tr -d '\r' <<<"$description")"
  description="${description%"${description##*[![:space:]]}"}"$'\n\n## Changelog\nnone'
  printf '%s\n' "$description" >"$note_dir/body"
  gh pr edit "$pr" --body-file "$note_dir/body" >/dev/null
  log "the PR changes no app build and had no ## Changelog section: added \"none\" to #$pr's description"
fi
squashed="$(squash_commit HEAD "$subject" "$description")"
# Also after an edit of the PR description: the commit main takes carries the current one.
if [[ -n "$(landing_problem HEAD "$subject")" || "$(git log -1 --format=%B "$squashed")" != "$(git log -1 --format=%B HEAD)" ]]; then
  git reset -q --soft "$squashed"
  log "squashed $branch into $(git rev-parse --short HEAD): $subject"
fi

# Opened as a draft (step 1 in docs/CI.md), the PR ran no CI on its first push (ci.yml): the run
# on the commit pushed here is its first. Marked ready only after that push, so that
# ready_for_review, which starts no run, follows it.
ready_pr() {
  [[ ${PUSH_PR_KEEP_DRAFT:-} != 1 ]] || return 0
  [[ "$(gh pr view "$pr" --json isDraft -q .isDraft)" == true ]] || return 0
  gh pr ready "$pr" >/dev/null
  log "marked #$pr ready for review"
}

remote="$(git rev-parse "origin/$branch")"
if [[ "$(git rev-parse HEAD)" == "$remote" ]]; then
  log "origin/$branch is already $(git rev-parse --short HEAD); nothing to push"
  ready_pr
  exit 0
fi
if [[ ${PUSH_PR_SKIP_CHECKS:-} == 1 ]]; then
  log "PUSH_PR_SKIP_CHECKS=1: pushing without scripts/push-checks.sh"
elif ! scripts/push-checks.sh; then
  echo "push-pr.sh: not pushing #$pr: the checks above failed. Fix and commit, then rerun scripts/push-pr.sh. Only where a check cannot run (no Flutter of CI's version, say), PUSH_PR_SKIP_CHECKS=1 pushes anyway." >&2
  exit 1
fi
git push -q --force-with-lease="$branch:$remote" origin "HEAD:refs/heads/$branch"
ready_pr
log "pushed $(git rev-parse --short HEAD) to #$pr; once ci-ok passes, scripts/merge-pr.sh $pr merges it"
