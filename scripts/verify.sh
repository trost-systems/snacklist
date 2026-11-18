#!/usr/bin/env bash
# Runs the CI gates (scripts/gates/<gate>.sh, the same scripts the ci.yml jobs run) locally and
# stops at the first that fails. The last line is the verdict in plain text: the gates that
# passed, or the gate that failed and the file its output is in, so `| tail` still shows it.
# "seen before? <recipe>" in it names a known cause this output looks like; the gate has failed
# all the same.
# Each run of a gate writes its own file (VERIFY_LOG_DIR, by default verify/ in the checkout's
# git dir): <gate>.<time>.<pid>.<n>.log, the newest five kept and those of runs still going,
# <gate>.log a link to the newest.
# Usage: scripts/verify.sh [--only <gate>[,<gate>...]] [--skip-e2e] [--screenshots <dir>] [-- <playwright args>]
#   --only e2e -- tests/list.spec.ts   runs one spec file under the box-wide e2e lock
#        scripts/verify.sh --history [<since>]   runs, failures, seconds and flakes per gate, from
#                                                the ledger; <since> is a date like 2026-11-14
#
# Every gate run is a row in the ledger (VERIFY_LEDGER, by default verify-ledger.tsv in the
# clone's .git, which its worktrees share): time, branch, tree, gate, result, seconds, arguments,
# seconds waited. The seconds leave out what the gate says it "waited N s for the lock".
# The tree is the hash of the working tree as it is: uncommitted and untracked files and the
# skip-worktree and assume-unchanged ones (the port block in supabase/config.toml) included,
# ignored files (.env files, build output) not. A gate with both results on one tree and the
# same arguments is a flake by that definition, and the run that sees one says so (docs/CI.md,
# "The local loop").
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Every gate, in the order a local run takes them: cheap and independent first, e2e last.
GATES=(gitleaks lint changelog site site-agent emails db functions nexus fg-cli flutter web-prod fastlane e2e)
# CI-only: iOS needs macOS, and a Gradle build takes more RAM than the shared box spares.
# They still run on request with --only.
CI_ONLY=(android ios ios-storekit)
# A gate that fails this many runs in a row on one branch is past patching: the p90 of such
# streaks was 1 to 4 per gate over 199 jobs (docs/CI.md, "The local loop").
STREAK=3
# The runs of a gate whose output stays.
KEEP=5

# Gate failures seen before whose cause is known, one file each (its README.md has the format).
RECIPES="${VERIFY_RECIPES:-$REPO_ROOT/.cursor/skills/verify-snacklist/recipes}"
LEDGER="${VERIFY_LEDGER:-$(cd "$REPO_ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd)/verify-ledger.tsv}"
LOG_DIR="${VERIFY_LOG_DIR:-$(cd "$REPO_ROOT" && git rev-parse --absolute-git-dir)/verify}"

# Per gate (a subset of e2e apart from the full run): runs, failed runs, the median and p90
# seconds of the runs that passed, and the trees that have both results for the same arguments.
history() {
  [[ -r $LEDGER ]] || { echo "no ledger yet: $LEDGER" >&2; exit 1; }
  awk -F'\t' -v OFS='\t' -v since="${1:-}" '
    $1 >= since { subset = $7; sub(/^--screenshots ?/, "", subset); print $4 (subset == "" ? "" : " (subset)"), $5, $6, $3, $7 }' "$LEDGER" \
    | sort -t$'\t' -k1,1 -k3,3n \
    | awk -F'\t' '
      function flush() {
        if (key == "") return
        printf "%-16s %5d %6d %8s %8s %6d\n", key, runs, failed, n ? took[int((n + 1) / 2)] : "-", n ? took[int(n * 0.9 + 0.999)] : "-", flaky
      }
      $1 != key { flush(); key = $1; runs = failed = n = flaky = 0; split("", saw); split("", both) }
      {
        runs++
        if ($2 == "fail") failed++; else took[++n] = $3
        if ($4 != "unknown" && !saw[$4, $5, $2]++ && saw[$4, $5, $2 == "fail" ? "pass" : "fail"] && !both[$4]++) flaky++
      }
      BEGIN { printf "%-16s %5s %6s %8s %8s %6s\n", "gate", "runs", "failed", "median s", "p90 s", "flaky" }
      END { flush() }'
}

only=""
skip_e2e=0
e2e_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) only="$2"; shift 2 ;;
    --skip-e2e) skip_e2e=1; shift ;;
    --screenshots) SCREENSHOT_DIR="$(realpath -m "$2")"; export SCREENSHOT_DIR; shift 2 ;;
    --history) history "${2:-}"; exit 0 ;;
    --) shift; e2e_args=("$@"); break ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -n $only ]]; then
  IFS=, read -ra run <<<"$only"
  for gate in "${run[@]}"; do
    [[ -x "$REPO_ROOT/scripts/gates/$gate.sh" ]] || { echo "no gate '$gate'; gates: ${GATES[*]} ${CI_ONLY[*]}" >&2; exit 2; }
  done
else
  run=("${GATES[@]}")
fi

# The working tree's hash through a scratch index: uncommitted and untracked files included, and
# the skip-worktree and assume-unchanged ones, which `git add` would pass over. Ignored files are
# not in it.
tree_id() (
  cd "$REPO_ROOT"
  index="$(mktemp)"
  trap 'rm -f "$index"' EXIT
  # -p: git rereads a file as old as its index, so the copy must not look newer than it is.
  cp -p "$(git rev-parse --git-path index)" "$index" 2>/dev/null || rm -f "$index"
  export GIT_INDEX_FILE="$index"
  git ls-files -v | sed -n 's/^[Ss] //p' | git update-index --no-skip-worktree --stdin
  git ls-files -v | sed -n 's/^[a-z] //p' | git update-index --no-assume-unchanged --stdin
  git add -A >/dev/null 2>&1 && git write-tree
)

# Prints what a gate appends to its log until the gate is done. The gate writes to the file and
# not into a pipe, so a process it leaves behind cannot keep this script from ending. Reading on
# through one open descriptor copies every byte once, however fast the gate writes.
follow() {
  local file="$1" last=0
  exec 3<"$file"
  while :; do
    [[ -e $file.done ]] && last=1
    cat <&3 || true
    ((last)) && break
    kill -0 "$$" 2>/dev/null || break
    sleep 0.2
  done
}

# What the ledger knows about this result before it is added: the other result on this very
# tree with these arguments, or a streak of failures of the gate on this branch.
ledger_note() {
  local gate="$1" result="$2" tree="$3"
  [[ -r $LEDGER ]] || return 0
  ARGS="$4" awk -F'\t' -v branch="$branch" -v gate="$gate" -v result="$result" -v tree="$tree" -v streak_at="$STREAK" '
    $4 != gate { next }
    $3 == tree && tree != "unknown" && $7 == ENVIRON["ARGS"] && $5 != result { other = $1 }
    $2 == branch { streak = ($5 == "fail") ? streak + 1 : 0 }
    END {
      if (other != "")
        printf "flake: %s had the other result (%s) on this same tree at %s. The files git does not ignore are the same, so something else differs: find it and write it down (docs/CI.md, \"The local loop\")\n", gate, result == "fail" ? "pass" : "fail", other
      else if (result == "fail" && streak + 1 >= streak_at)
        printf "%s has failed %d runs in a row on this branch. Stop patching: write down what those fixes assumed and test that first (docs/CI.md, \"The local loop\")\n", gate, streak + 1
    }' "$LEDGER"
}

# The value of a key in a recipe's front matter (from a --- on the first line to the next).
recipe_field() {
  awk -v key="$2: " 'NR == 1 && !/^---$/ { exit } /^---$/ { if (++fence == 2) exit; next } fence == 1 && index($0, key) == 1 { print substr($0, length(key) + 1); exit }' "$1"
}

# The recipes of a gate whose signal the failed run's output has. A match is a question, not a
# verdict: the recipe says how to tell, and the gate has failed either way.
seen_before() {
  local gate="$1" output="$2" recipe signal found=()
  for recipe in "$RECIPES"/*.md; do
    [[ -r $recipe && "$(recipe_field "$recipe" gate)" == "$gate" ]] || continue
    signal="$(recipe_field "$recipe" signal)"
    [[ -n $signal ]] || continue
    # -c reads to the end: no closed pipe for sed, whose failure would hide a match.
    if sed $'s/\033\\[[0-9;]*[A-Za-z]//g' "$output" | grep -Ec -- "$signal" >/dev/null 2>&1; then
      found+=("${recipe#"$REPO_ROOT/"}")
    fi
  done
  echo "${found[*]-}"
}

mkdir -p "$LOG_DIR"
# A detached checkout has no branch: its streaks are its own, not every detached worktree's.
branch="$(cd "$REPO_ROOT" && git symbolic-ref -q --short HEAD || echo "detached:$(basename "$REPO_ROOT")")"
started=$SECONDS
passed=()
took=""
for index in "${!run[@]}"; do
  gate="${run[$index]}"
  if [[ $gate == e2e && $skip_e2e == 1 ]]; then
    log "skipping e2e"
    continue
  fi
  log "gate: $gate"
  args=()
  if [[ $gate == e2e ]]; then args=(${e2e_args[@]+"${e2e_args[@]}"}); fi
  # A file per run, so no two runs of a gate share one, nor a run and what an earlier one left
  # running: the file a verdict names holds that run's output, whatever starts next. UTC, so
  # the names sort by age whatever the caller's time zone.
  gate_log="$LOG_DIR/$gate.$(date -u +%Y%m%d-%H%M%S).$$.$index.log"
  : >"$gate_log"
  ln -sfn "$(basename "$gate_log")" "$LOG_DIR/$gate.log"
  # The older files go, except a run's that is still going (the pid in the name): it reads its
  # file when its gate ends.
  logs=("$LOG_DIR/$gate".*.log)
  if ((${#logs[@]} > KEEP)); then
    for old in "${logs[@]:0:${#logs[@]}-KEEP}"; do
      owner="${old%.*.log}"
      kill -0 "${owner##*.}" 2>/dev/null || rm -f "$old"
    done
  fi
  tree="$(tree_id || echo unknown)"
  follow "$gate_log" &
  began=$SECONDS
  rc=0
  "$REPO_ROOT/scripts/gates/$gate.sh" ${args[@]+"${args[@]}"} >>"$gate_log" 2>&1 || rc=$?
  ended=$SECONDS
  : >"$gate_log.done"
  wait $! || true
  rm -f "$gate_log.done"
  waited="$(sed -n 's/^\[[a-z0-9-]*\] .*waited \([0-9][0-9]*\) s for the lock$/\1/p' "$gate_log" | awk '{ sum += $1 } END { print sum + 0 }')"
  seconds=$((ended - began - waited))
  if ((seconds < 0)); then seconds=0; fi
  took="${took:+$took, }$gate $seconds s"
  if ((waited > 0)); then took+=" (after $waited s waiting for the lock)"; fi
  result=pass
  if [[ $rc != 0 ]]; then result=fail; fi
  # --screenshots turns on specs that otherwise skip, so it is part of what the e2e gate ran.
  args_text="${args[*]-}"
  if [[ $gate == e2e && -n ${SCREENSHOT_DIR:-} ]]; then args_text="--screenshots${args_text:+ $args_text}"; fi
  args_text="${args_text//[$'\t\n']/ }"
  note="$(ledger_note "$gate" "$result" "$tree" "$args_text")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$branch" "$tree" "$gate" "$result" "$seconds" "$args_text" "$waited" >>"$LEDGER" || true
  if [[ -n $note ]]; then log "$note"; fi
  if [[ $rc != 0 ]]; then
    not_run=()
    for later in "${run[@]:$((index + 1))}"; do
      if [[ $later != e2e || $skip_e2e != 1 ]]; then not_run+=("$later"); fi
    done
    recipes="$(seen_before "$gate" "$gate_log" || true)"
    log "took: $took"
    log "FAILED: $gate (exit $rc) after $seconds s; its output: $gate_log${recipes:+; seen before? $recipes}${not_run[*]+; not run: ${not_run[*]}}"
    exit "$rc"
  fi
  passed+=("$gate")
done
log "took: $took ($((SECONDS - started)) s)"
log "passed: ${passed[*]-}"
