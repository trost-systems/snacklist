#!/usr/bin/env bash
# Runs the Supabase + Playwright e2e (and the db gate) on GitHub Actions for a pushed branch, via
# .github/workflows/e2e.yml, waits for it and prints the result (docs/CI.md, On-demand e2e).
# Usage: scripts/ci-e2e.sh [--ref <branch>] [--spec "<playwright args>"] [--shards 1..6] [--no-db]
#                          [--sync-smoke | --no-sync-smoke] [--download <dir>]
#   --ref        the branch to test (default: the current one). It must be pushed: the checked
#                out branch must be origin/<ref>'s commit, another local branch must not have
#                commits origin lacks, so the run tests what you have.
#   --spec       Playwright arguments, e.g. tests/stores.spec.ts or '-g "drag"' (default: the
#                full suite). One shard and no fg sync smoke test unless you ask for them.
#   --shards     1 to 6 (default: 4 for the full suite, as in ci.yml, and 1 with --spec)
#   --no-db      skip the db gate (pgTAP, classifier sweep, db lint, backup drill, fixtures)
#   --download   also download the run's artifacts (report, traces, screenshots) into <dir>
# Exits 0 when the run passed, 1 when it failed, was cancelled or ran no test, 2 on a usage or
# setup problem. Needs gh (logged in), git and jq, on Linux or macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "ci-e2e: $*" >&2; exit 2; }

ref="" spec="" shards=auto db=true sync=auto download=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref="${2:?--ref needs a branch}"; shift 2 ;;
    --spec) spec="${2?--spec needs Playwright arguments}"; shift 2 ;;
    --shards) shards="${2:?--shards needs a number from 1 to 6}"; shift 2 ;;
    --no-db) db=false; shift ;;
    --sync-smoke) sync=true; shift ;;
    --no-sync-smoke) sync=false; shift ;;
    --download) download="${2:?--download needs a directory}"; shift 2 ;;
    -h | --help) sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[[ $shards =~ ^(auto|[1-6])$ ]] || die "--shards is a number from 1 to 6, not '$shards'"
for tool in gh git jq; do command -v "$tool" >/dev/null || die "$tool is not on PATH"; done

repo="${FG_CI_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
current="$(git symbolic-ref --short -q HEAD || true)"
ref="${ref:-$current}"
[[ -n $ref ]] || die "HEAD is detached: pass --ref <branch>"

# The run checks out origin's branch, so it must be the commit you have.
if ! git fetch -q origin "+refs/heads/$ref:refs/remotes/origin/$ref" 2>/dev/null; then
  git ls-remote --exit-code --heads origin "$ref" >/dev/null 2>&1 \
    || die "origin has no branch '$ref': push it first (git push -u origin $ref)"
  die "could not fetch origin/$ref (network?)"
fi
remote_sha="$(git rev-parse "refs/remotes/origin/$ref")"
if [[ $ref == "$current" ]]; then
  local_sha="$(git rev-parse HEAD)"
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
    || echo "ci-e2e: note: uncommitted changes are not part of the run" >&2
elif git show-ref -q --verify "refs/heads/$ref" \
  && ! git merge-base --is-ancestor "refs/heads/$ref" "$remote_sha"; then
  # A branch you don't have checked out matters only when it has commits origin lacks.
  local_sha="$(git rev-parse "refs/heads/$ref")"
else
  local_sha="$remote_sha"
fi
if [[ $local_sha != "$remote_sha" ]]; then
  git merge-base --is-ancestor "$local_sha" "$remote_sha" \
    && die "local $ref (${local_sha:0:7}) is behind origin/$ref (${remote_sha:0:7}); pull first, so the run tests what you have"
  die "local $ref is at ${local_sha:0:7} but origin/$ref at ${remote_sha:0:7}; push first (scripts/push-pr.sh on a PR branch, else git push), then rerun"
fi

# e2e.yml puts request_id into its run name; that is how this finds its own run and not one
# someone else started on the same branch a second earlier.
request_id="$(date -u +%Y%m%d%H%M%S)-$$-$RANDOM"
echo "ci-e2e: $repo $ref at ${remote_sha:0:7}: spec '${spec:-full suite}', shards $shards, db $db, sync smoke $sync"
gh workflow run e2e.yml --repo "$repo" --ref "$ref" \
  -f spec="$spec" -f shards="$shards" -f db="$db" -f sync_smoke="$sync" -f request_id="$request_id" \
  || die "dispatch failed (gh finds e2e.yml by name only once it is on the default branch)"

id=""
for _ in $(seq 1 60); do
  id="$(gh run list --repo "$repo" --workflow e2e.yml --event workflow_dispatch --branch "$ref" -L 50 \
    --json databaseId,displayTitle --jq "map(select(.displayTitle | endswith(\"[$request_id]\"))) | .[0].databaseId // empty" || true)"
  [[ -n $id ]] && break
  sleep 3
done
[[ -n $id ]] || die "no e2e.yml run named [$request_id] appeared within 3 minutes; look at gh run list --repo $repo --workflow e2e.yml"
url="https://github.com/$repo/actions/runs/$id"
echo "ci-e2e: run $id $url"

# gh run watch can return early on a network error; watch until the run is complete, for at
# most 90 min (e2e.yml's jobs time out after 30).
deadline=$((SECONDS + 90 * 60))
until [[ "$(gh run view "$id" --repo "$repo" --json status --jq .status 2>/dev/null || true)" == completed ]]; do
  ((SECONDS < deadline)) || { echo "ci-e2e: gave up waiting after 90 min: $url" >&2; exit 1; }
  gh run watch "$id" --repo "$repo" --interval "${CI_E2E_INTERVAL:-30}" >/dev/null 2>&1 || sleep 10
done

run="$(gh run view "$id" --repo "$repo" --json conclusion,attempt,jobs,headSha)" \
  || { echo "ci-e2e: run $id completed, but gh run view failed: $url" >&2; exit 1; }
conclusion="$(jq -r .conclusion <<<"$run")"
attempt="$(jq -r .attempt <<<"$run")"
echo
echo "e2e.yml run $id (attempt $attempt) on ${remote_sha:0:7}: $conclusion"
jq -r '.jobs[] | "  \(.name): \(.conclusion // .status)\(
    if .conclusion != "skipped" and (.startedAt // "" | startswith("20")) and (.completedAt // "" | startswith("20"))
    then " (\(((.completedAt | fromdate) - (.startedAt | fromdate)) / 60 | floor) min \(((.completedAt | fromdate) - (.startedAt | fromdate)) % 60) s)"
    else "" end)"' <<<"$run"

# The per-shard Playwright results (e2e-report's small artifact): counts and the failed titles.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ran=0
if gh run download "$id" --repo "$repo" -p "e2e-results-*-attempt$attempt" -D "$tmp" >/dev/null 2>&1; then
  # One directory per artifact, named after it (gh 2.x with -p, also for a single match).
  # Job 50: a shard's artifact can also hold playwright-results-integration-lock.json.
  while IFS= read -r dir; do
    shard="${dir##*/e2e-results-}"
    jsons=("$dir"/playwright-results*.json)
    echo "  shard ${shard%-attempt*}: $(scripts/e2e-summary.sh --brief "${jsons[@]}" | sed '2,$s/^/  /')"
    for json in "${jsons[@]}"; do
      ran=$((ran + $(jq '.stats.expected + .stats.unexpected + .stats.flaky' "$json" || echo 0)))
    done
  done < <(find "$tmp" -name 'playwright-results*.json' -exec dirname {} \; | sort -u)
else
  echo "  no Playwright results (the e2e jobs stopped before Playwright, or were skipped)"
fi

if [[ -n $download ]]; then
  mkdir -p "$download"
  gh run download "$id" --repo "$repo" -p "*-attempt$attempt" -D "$download" >/dev/null \
    && echo "ci-e2e: artifacts in $download: $(cd "$download" && echo *)"
fi

echo "  $url"
if [[ $conclusion == cancelled ]]; then
  echo "ci-e2e: cancelled (a newer dispatch of the same ref and spec cancels an older one, or someone cancelled it)" >&2
  exit 1
fi
if [[ $conclusion != success ]]; then
  echo "ci-e2e: failed; why: gh run view $id --repo $repo --log-failed | tail -200" >&2
  exit 1
fi
if [[ $ran == 0 ]]; then
  echo "ci-e2e: the run passed but no test ran; check --spec" >&2
  exit 1
fi
