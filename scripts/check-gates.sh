#!/usr/bin/env bash
# CI and verify.sh run the same checks because both only call scripts/gates/<gate>.sh. This keeps
# it that way: exactly one ci.yml job runs each gate, once, and is in ci-ok's needs (a job may run
# several gates, job 309; a gate after the first one runs `if: ${{ !cancelled() ... }}`, so one
# failure does not hide the next), and every gate is listed in verify.sh; no check command is
# written into ci.yml or verify.sh directly. Every
# job in every workflow also sets timeout-minutes, and the on-demand e2e.yml sets up its db and
# e2e jobs exactly like ci.yml's (job 27).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

CI=.github/workflows/ci.yml
problems=()
needs="$(sed -n '/^  ci-ok:/,/^  [a-z]/s/^    needs: \[\(.*\)\]$/\1/p' "$CI" | tr -d ' ')"
listed="$(sed -n 's/^\(GATES\|CI_ONLY\)=(\(.*\))$/\2/p' scripts/verify.sh | tr '\n' ' ')"
# The lines of job <job> in workflow <wf>.
job_block() {
  sed -n "/^jobs:/,\$p" "$1" | sed -n "/^  $2:$/,/^  [a-zA-Z0-9_-]*:$/p" | sed '$!b;/^  [a-zA-Z0-9_-]*:$/d'
}
ci_jobs="$(sed -n '/^jobs:/,$s/^  \([a-zA-Z0-9_-]*\):$/\1/p' "$CI")"
for file in scripts/gates/*.sh; do
  gate="$(basename "$file" .sh)"
  [[ -x $file && "$(git ls-files -s "$file" | cut -c1-6)" != 100644 ]] || problems+=("$file is not executable (chmod +x, git add)")
  runs="^ *(- )?run: scripts/gates/$gate\.sh( |$)"
  jobs=() count=0
  for job in $ci_jobs; do
    n="$(job_block "$CI" "$job" | grep -cE "$runs" || true)"
    ((n == 0)) || { jobs+=("$job"); count=$((count + n)); }
  done
  if [[ ${#jobs[@]} != 1 || $count != 1 ]]; then
    problems+=("ci.yml must run scripts/gates/$gate.sh in exactly one job, once; it runs it ${count}x in: ${jobs[*]:-no job}")
  else
    [[ ",$needs," == *",${jobs[0]},"* ]] || problems+=("ci-ok does not need '${jobs[0]}', which runs the $gate gate")
  fi
  [[ " $listed " == *" $gate "* ]] || problems+=("verify.sh lists '$gate' in neither GATES nor CI_ONLY")
done
# In a job of several gates, a failed gate must not skip the ones after it.
for job in $ci_jobs; do
  while read -r step; do
    problems+=("ci.yml job '$job': the step that runs $step follows another gate's, so it needs if: \${{ !cancelled() ... }}")
  done < <(job_block "$CI" "$job" | awk '
    /^ *(- )?run: scripts\/gates\// { if (gates++ && prev !~ /^ *- if: \$\{\{ !cancelled\(\)/) print $NF }
    { prev = $0 }')
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

# A matrix job runs its steps once per entry: a gate there would run more than once (the e2e
# shards), and a step that may fail without failing its job hides a gate from ci-ok.
for job in $ci_jobs; do
  block="$(job_block "$CI" "$job")"
  if grep -qE '^    strategy:' <<<"$block" && (($(grep -cE '^ *(- )?run: scripts/gates/' <<<"$block") > 1)); then
    problems+=("ci.yml job '$job' is a matrix, so it may run only its own gate; move the others to a job without a strategy")
  fi
done
grep -qE '^\s*continue-on-error:' "$CI" && problems+=("ci.yml has continue-on-error, which lets a gate fail without failing ci-ok")

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
# the list could fall behind it and leave tests unrun. The shard list is the matrix's only key (a
# second one would multiply job-total), and the on-demand full suite runs in as many shards.
# shellcheck disable=SC2016 # the workflows' own expressions, as written there
shard_arg='--shard=${{ matrix.shard }}/${{ strategy.job-total }}'
job_block "$CI" e2e | grep -qxF -- "      - run: scripts/gates/e2e.sh $shard_arg" \
  || problems+=("ci.yml job 'e2e' must run scripts/gates/e2e.sh $shard_arg and nothing after it")
matrix="$(job_block "$CI" e2e | sed -n '/^      matrix:$/,/^ \{0,6\}[^ ]/{/^ \{8\}/p;}')"
ci_shards="$(sed -n 's/^        shard: \[\([0-9, ]*\)\]$/\1/p' <<<"$matrix" | tr -d ' ')"
[[ -n $ci_shards && $(wc -l <<<"$matrix") -eq 1 ]] \
  || problems+=("ci.yml job 'e2e': the matrix must be the one line 'shard: [1, 2, ...]', it is: $matrix")
e2e_shards="$(sed -n 's/^.*else total=\([0-9]*\); fi$/\1/p' "$E2E")"
[[ -n $e2e_shards && $ci_shards == "$(seq -s, 1 "$e2e_shards")" ]] \
  || problems+=("ci.yml's e2e shards are [$ci_shards], but $E2E runs the full suite in '$e2e_shards' (its plan step's 'else total=')")
# There the list and the count both come from the plan step's one $total: each line on the way.
while IFS=: read -r job line; do
  job_block "$E2E" "$job" | grep -qxF -- "$line" || problems+=("$E2E job '$job' must keep the line '$line': the shard list and Playwright's count both come from the plan step's \$total")
done <<'LINES'
plan:            echo "total=$total"
plan:            echo "shards=$(seq -s, 1 "$total" | sed 's/.*/[&]/')"
plan:      shards: ${{ steps.plan.outputs.shards }}
plan:      total: ${{ steps.plan.outputs.total }}
e2e:        shard: ${{ fromJSON(needs.plan.outputs.shards) }}
e2e:          SHARD: ${{ matrix.shard }}
e2e:          TOTAL: ${{ needs.plan.outputs.total }}
e2e:            args+=("--shard=$SHARD/$TOTAL")
LINES

if [[ ${#problems[@]} -gt 0 ]]; then
  printf 'check-gates: %s\n' "${problems[@]}" >&2
  exit 1
fi
