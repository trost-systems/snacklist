#!/usr/bin/env bash
# The quick checks of the lint and flutter gates, for what the branch changes against main.
# scripts/push-pr.sh runs this before it pushes, so a slip in format, lint or analyze stops the
# push instead of a CI run (job 307: in the week to 18 November, 29 of 49 failed PR runs failed in
# the lint or flutter job). It runs every check that applies, then names the ones that failed.
# Tests stay in CI and in scripts/verify.sh.
#
# Usage: scripts/push-checks.sh [--list] [base]   (base: origin/main)
#   --list prints the checks the change needs, one per line, and runs none.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

list=0
if [[ ${1:-} == --list ]]; then
  list=1
  shift
fi
base="${1:-origin/main}"
changed="$(git diff --name-only "$base" HEAD)"

touches() { grep -qE "$1" <<<"$changed"; }
changed_shell_scripts() { comm -12 <(shell_scripts | sort) <(sort <<<"$changed"); }

# The checks in order, each with whether the change needs it. lint.sh always: its schema check
# compares the migrations with main's (7 of last week's 17 lint failures deleted one of main's).
checks=(lint.sh)
touches '^\.github/' && checks+=(actionlint)
[[ -n "$(changed_shell_scripts)" ]] && checks+=(shellcheck)
touches '\.(ts|mts|cts|tsx|js|mjs|cjs)$|(^|/)(deno|package(-lock)?|tsconfig[^/]*)\.json$|(^|/)deno\.lock$|^\.dvmrc$' && checks+=(typescript-pack)
touches '^e2e/' && checks+=(e2e-tsc)
touches '^app/' && checks+=(flutter)

if [[ $list == 1 ]]; then
  printf '%s\n' "${checks[@]}"
  exit 0
fi

# format, analyze, tsc and deno read every file in their directories, CI only the committed ones:
# an untracked file would pass here what CI fails (an import of a file never added) or the reverse.
untracked_in() {
  local files
  files="$(git ls-files --others --exclude-standard -- "$@")"
  [[ -z $files ]] && return 0
  echo "untracked files in $*, which CI does not see: git add or remove them" >&2
  echo "$files" >&2
  return 1
}

run_check() {
  case "$1" in
    lint.sh) scripts/lint.sh "$base" ;;
    actionlint) actionlint ;;
    shellcheck)
      local files
      mapfile -t files < <(changed_shell_scripts)
      shellcheck "${files[@]}"
      ;;
    typescript-pack)
      # Its tsc projects need their packages, as in the lint gate.
      untracked_in e2e emails supabase/functions tool &&
        (cd e2e && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; }) &&
        (cd emails && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; }) &&
        deno run --allow-all tool/lint/ts/strict.ts
      ;;
    e2e-tsc) untracked_in e2e && (cd e2e && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; } && npx tsc --noEmit -p .) ;;
    flutter) untracked_in app && scripts/gates/flutter.sh --no-tests ;;
  esac
}

failed=()
for check in "${checks[@]}"; do
  log "push check: $check"
  run_check "$check" || failed+=("$check")
done
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "push-checks: failed: ${failed[*]} (output above). CI's lint or flutter job fails the same way: fix it, commit, and rerun." >&2
  exit 1
fi
log "push checks passed: ${checks[*]}"
