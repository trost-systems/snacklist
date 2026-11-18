#!/usr/bin/env bash
# Job 308 (OC1): may a push to main reuse its PR's CI run? Prints reuse=true or reuse=false for
# $GITHUB_OUTPUT, and why on stderr.
# merge-pr.sh rebase-merges the one commit push-pr.sh pushed, so main's new commit normally has
# the PR head's tree and parent. A PR run tests the PR head merged into the base of that moment;
# with the same parent that base is this parent, so the tree it tested is main's. When that run's
# ci-ok passed, a second run of the same gates on main tests nothing new. Anything else (no PR,
# another tree or parent, ci-ok not green, an API error) answers false: main runs its gates.
# The nightly run on main (ci.yml's schedule) runs every gate, native ones included.
# Usage: scripts/ci-main-reuse.sh <commit>   (GITHUB_REPOSITORY, GH_TOKEN; the commit and its parent local)
set -uo pipefail

no() { echo "reuse=false"; echo "ci-main-reuse: full run: $*" >&2; exit 0; }

commit="$(git rev-parse --verify -q "$1^{commit}")" || no "$1 is not a local commit"
tree="$(git rev-parse "$commit^{tree}")"
parent="$(git rev-parse -q --verify "$commit^1")" || no "$commit has no parent here"

pr="$(gh api "repos/$GITHUB_REPOSITORY/commits/$commit/pulls" \
  --jq '[.[] | select(.merged_at != null and .base.ref == "main")] | first | "\(.number) \(.head.sha)"' 2>&1)" \
  || no "the PR lookup failed: $pr"
read -r number head <<<"$pr"
[[ $number =~ ^[0-9]+$ && $head =~ ^[0-9a-f]{40}$ ]] || no "no merged PR has $commit"

head_commit="$(gh api "repos/$GITHUB_REPOSITORY/commits/$head" --jq '"\(.commit.tree.sha) \(.parents | length) \(.parents[0].sha)"' 2>&1)" \
  || no "reading PR #$number's head $head failed: $head_commit"
read -r head_tree head_parents head_parent <<<"$head_commit"
[[ $head_tree == "$tree" ]] || no "PR #$number's head $head has tree $head_tree, main's commit $tree"
[[ $head_parents == 1 && $head_parent == "$parent" ]] \
  || no "PR #$number's head $head has parent $head_parent ($head_parents parents), main's commit $parent"

# The newest ci-ok of this workflow on the head: a red rerun after a green one does not count.
ci_ok="$(gh api "repos/$GITHUB_REPOSITORY/commits/$head/check-runs?check_name=ci-ok&filter=all&per_page=100" \
  --jq '[.check_runs[] | select(.app.slug == "github-actions" and .status == "completed")]
        | sort_by(.completed_at) | last | if . then "\(.conclusion) \(.html_url)" else "none" end' 2>&1)" \
  || no "reading ci-ok on $head failed: $ci_ok"
[[ $ci_ok == success\ * ]] || no "ci-ok on PR #$number's head $head is ${ci_ok:-none}"

echo "reuse=true"
echo "ci-main-reuse: PR #$number's head $head has main's tree and parent, and its ci-ok passed: ${ci_ok#success }" >&2
