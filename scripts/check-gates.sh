#!/usr/bin/env bash
# CI and verify.sh run the same checks because both only call scripts/gates/<gate>.sh. This keeps
# it that way: every gate has a ci.yml job of its name that runs it and is in ci-ok's needs, and
# is listed in verify.sh; no check command is written into ci.yml or verify.sh directly. Every
# job in every workflow also sets timeout-minutes, and the on-demand e2e.yml sets up its db and
# e2e jobs exactly like ci.yml's (job 27).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

CI=.github/workflows/ci.yml
problems=()
needs="$(sed -n '/^  ci-ok:/,/^  [a-z]/s/^    needs: \[\(.*\)\]$/\1/p' "$CI" | tr -d ' ')"
listed="$(sed -n 's/^\(GATES\|CI_ONLY\)=(\(.*\))$/\2/p' scripts/verify.sh | tr '\n' ' ')"
for file in scripts/gates/*.sh; do
  gate="$(basename "$file" .sh)"
  [[ -x $file && "$(git ls-files -s "$file" | cut -c1-6)" != 100644 ]] || problems+=("$file is not executable (chmod +x, git add)")
  grep -q "^  $gate:$" "$CI" || problems+=("ci.yml has no job '$gate'")
  [[ "$(sed -n "/^  $gate:$/,/^  [a-z]/p" "$CI" | grep -c "run: scripts/gates/$gate.sh")" == 1 ]] \
    || problems+=("ci.yml job '$gate' does not run scripts/gates/$gate.sh once")
  [[ ",$needs," == *",$gate,"* ]] || problems+=("ci-ok does not need '$gate'")
  [[ " $listed " == *" $gate "* ]] || problems+=("verify.sh lists '$gate' in neither GATES nor CI_ONLY")
done
for word in $listed; do
  [[ -f scripts/gates/$word.sh ]] || problems+=("verify.sh lists '$word', which has no scripts/gates/$word.sh")
done

for pattern in 'flutter analyze' 'flutter test' 'flutter build' 'dart format' 'deno test' 'deno lint' \
  'playwright test' 'supabase test' 'db lint' 'gitleaks git' 'fastlane lanes' 'shellcheck ' 'run: actionlint' 'tsc '; do
  for file in "$CI" scripts/verify.sh; do
    if grep -v '^\s*#' "$file" | grep -q -- "$pattern"; then
      problems+=("$file runs '$pattern' itself; put it in a scripts/gates/ script")
    fi
  done
done

# The lines of job <job> in workflow <wf>.
job_block() {
  sed -n "/^jobs:/,\$p" "$1" | sed -n "/^  $2:$/,/^  [a-zA-Z0-9_-]*:$/p" | sed '$!b;/^  [a-zA-Z0-9_-]*:$/d'
}

# A hung job holds a runner (and a deploy or release slot) for GitHub's 6 h default.
for wf in .github/workflows/*.yml; do
  while read -r job; do
    block="$(job_block "$wf" "$job")"
    grep -qE '^    uses:' <<<"$block" && continue
    grep -qE '^    timeout-minutes:' <<<"$block" || problems+=("$wf job '$job' has no timeout-minutes")
  done < <(sed -n '/^jobs:/,$s/^  \([a-zA-Z0-9_-]*\):$/\1/p' "$wf")
done

# Job 27: e2e.yml runs ci.yml's e2e and db jobs on demand. Both workflows pin the same versions,
# and each of the two jobs uses the same actions (the shared ones in .github/actions/), passes
# them the same versions and inputs (by name) and runs its gate script.
E2E=.github/workflows/e2e.yml
pin() { sed -n "/^env:/,/^[a-z]/s/^  $2: *\(.*\)$/\1/p" "$1"; }
for key in FLUTTER_VERSION SUPABASE_CLI_VERSION SUPABASE_INTERNAL_IMAGE_REGISTRY; do
  [[ -n "$(pin "$CI" "$key")" && "$(pin "$CI" "$key")" == "$(pin "$E2E" "$key")" ]] \
    || problems+=("$E2E env $key is '$(pin "$E2E" "$key")', ci.yml's is '$(pin "$CI" "$key")'")
done
for job in db e2e; do
  for what in uses version inputs; do
    case $what in
      uses) pattern='s/^ *-\{0,1\} *uses: \(.*\)$/\1/p' ;;
      version) pattern='s/^ *\([a-z-]*-version: .*\)$/\1/p' ;;
      inputs) pattern='s/^          \([a-z-]*\): .*$/\1/p' ;; # the names under each action's with:
    esac
    ci_lines="$(job_block "$CI" "$job" | sed -n "$pattern")"
    e2e_lines="$(job_block "$E2E" "$job" | sed -n "$pattern")"
    [[ -n $ci_lines && "$ci_lines" == "$e2e_lines" ]] \
      || problems+=("$E2E job '$job' differs from ci.yml's in its '$what' lines: $(diff <(echo "$ci_lines") <(echo "$e2e_lines") | grep '^[<>]' | tr '\n' ' ' || true)")
  done
  job_block "$E2E" "$job" | grep -q "scripts/gates/$job.sh" || problems+=("$E2E job '$job' does not run scripts/gates/$job.sh")
done

# Job 221: ci.yml's e2e job gives Playwright the matrix's own size, since a count written beside
# the list could fall behind it and leave tests unrun, and the on-demand full suite runs in as
# many shards.
# shellcheck disable=SC2016 # the workflow's own expression, as written in ci.yml
shard_arg='--shard=${{ matrix.shard }}/${{ strategy.job-total }}'
job_block "$CI" e2e | grep -qF -- "run: scripts/gates/e2e.sh $shard_arg" \
  || problems+=("ci.yml job 'e2e' must run scripts/gates/e2e.sh $shard_arg")
ci_shards="$(job_block "$CI" e2e | sed -n 's/^        shard: \[\(.*\)\]$/\1/p' | tr -d ' ')"
e2e_shards="$(sed -n 's/^.*else total=\([0-9]*\); fi$/\1/p' "$E2E")"
[[ -n $e2e_shards && $ci_shards == "$(seq -s, 1 "$e2e_shards")" ]] \
  || problems+=("ci.yml's e2e shards are [$ci_shards], but $E2E runs the full suite in '$e2e_shards' (its plan step's 'else total=')")

if [[ ${#problems[@]} -gt 0 ]]; then
  printf 'check-gates: %s\n' "${problems[@]}" >&2
  exit 1
fi
