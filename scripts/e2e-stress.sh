#!/usr/bin/env bash
# Runs Playwright (from e2e/, against the web build and stack already up) while pausing part of the
# system on a duty cycle: job 18c's method for telling a host pause from a race (DECISIONS 18.23,
# job 119). Take the e2e lock yourself: flock /tmp/fg-e2e.lock scripts/e2e-stress.sh ...
#
#   scripts/e2e-stress.sh [--target browser|runner|stack] [--on S] [--every P] [--cpus LIST] -- <playwright args>
#
#   browser  SIGSTOP the Chromium processes only; the runner's clocks keep running.
#   runner   SIGSTOP the Playwright runner and its Chromium together (a phone that sleeps).
#   stack    docker pause this checkout's Supabase containers (a server that stalls).
#   --on S --every P   pause S seconds of every P seconds (default 3 of 8).
#   --cpus LIST        pin the run (runner and browser) to these CPUs with taskset, e.g. 0 or 0,1.
#   --target none      no pauses (with --cpus: CPU starvation alone).
#
# Prints one line per pause and the Playwright exit code. On any exit (Ctrl-C included) nothing stays
# paused, so the next holder of the e2e lock does not inherit a frozen stack or browser.
set -euo pipefail
cd "$(dirname "$0")/.."
target=runner on=3 every=8 cpus=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target=$2; shift 2 ;;
    --on) on=$2; shift 2 ;;
    --every) every=$2; shift 2 ;;
    --cpus) cpus=$2; shift 2 ;;
    --) shift; break ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$target" in browser|runner|stack|none) ;; *) echo "--target is browser, runner, stack or none" >&2; exit 2 ;; esac
(( every > on )) || { echo "--every is the period and must be longer than --on" >&2; exit 2; }

project_id=$(sed -n 's/^project_id = "\(.*\)"$/\1/p' supabase/config.toml)
# e2e/stack.ts asks `supabase status` in every worker otherwise, which refuses while the db is paused.
for _ in $(seq 60); do status=$(supabase status -o env 2>/dev/null) && break; sleep 1; done
[[ -n ${status:-} ]] || { echo "the local stack is not healthy" >&2; exit 1; }
env_of() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" <<<"$status"; }
SUPABASE_URL=$(env_of API_URL) SUPABASE_PUBLISHABLE_KEY=$(env_of PUBLISHABLE_KEY)
MAILPIT_URL=$(env_of MAILPIT_URL) SUPABASE_SECRET_KEY=$(env_of SECRET_KEY)
export SUPABASE_URL SUPABASE_PUBLISHABLE_KEY MAILPIT_URL SUPABASE_SECRET_KEY
cd e2e
descendants() {
  local pid
  for pid in $(pgrep -P "$1"); do echo "$pid"; descendants "$pid"; done
}

pause_once() {
  local pids=()
  case "$target" in
    browser) mapfile -t pids < <(for p in $(descendants "$runner"); do
        [[ $(cat "/proc/$p/comm" 2>/dev/null) == *chrom* ]] && echo "$p"; done) ;;
    runner) mapfile -t pids < <(echo "$runner"; descendants "$runner") ;;
    stack) mapfile -t pids < <(docker ps -q --filter "name=_$project_id\$") ;;
  esac
  [[ ${#pids[@]} -gt 0 ]] || return 0
  echo "[e2e-stress $(date +%T)] $target: ${#pids[@]} paused for ${on}s" >&2
  if [[ $target == stack ]]; then
    docker pause "${pids[@]}" >/dev/null
    sleep "$on"
    docker unpause "${pids[@]}" >/dev/null
  else
    kill -STOP "${pids[@]}" 2>/dev/null || true
    sleep "$on"
    kill -CONT "${pids[@]}" 2>/dev/null || true
  fi
}

# shellcheck disable=SC2317,SC2329 # only the EXIT trap calls it
resume() {
  if [[ -n ${pauser:-} ]]; then kill "$pauser" 2>/dev/null || true; wait "$pauser" 2>/dev/null || true; fi
  local stopped=()
  if [[ $target == stack ]]; then
    mapfile -t stopped < <(docker ps -q --filter "name=_$project_id\$" --filter status=paused)
    [[ ${#stopped[@]} -eq 0 ]] || docker unpause "${stopped[@]}" >/dev/null || true
  elif [[ -n ${runner:-} ]]; then
    mapfile -t stopped < <(echo "$runner"; descendants "$runner")
    kill -CONT "${stopped[@]}" 2>/dev/null || true
  fi
}
trap resume EXIT
trap 'kill "${runner:-}" 2>/dev/null || true; exit 130' INT TERM

if [[ -n $cpus ]]; then taskset -c "$cpus" npx playwright test "$@" & else npx playwright test "$@" & fi
runner=$!
if [[ $target != none ]]; then
  (
    sleep $((every - on))
    while kill -0 "$runner" 2>/dev/null; do pause_once; sleep $((every - on)); done
  ) &
  pauser=$!
fi
rc=0
wait "$runner" || rc=$?
echo "[e2e-stress] playwright exited $rc" >&2
exit "$rc"
