# shellcheck shell=bash
# Shared helpers for scripts/*.sh and scripts/gates/*.sh. Source, don't run.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The Flutter that CI builds and tests with.
ci_flutter_version() { sed -n 's/^ *FLUTTER_VERSION: *//p' "$REPO_ROOT/.github/workflows/ci.yml" 2>/dev/null | head -1; }

# FLUTTER_DIR when set, else an SDK of CI's version next to the default one (~/flutter-<version>,
# where a box keeps it while ~/flutter is older), else ~/flutter.
flutter_dir() {
  local beside
  beside="$HOME/flutter-$(ci_flutter_version)"
  if [[ -n ${FLUTTER_DIR:-} ]]; then
    echo "$FLUTTER_DIR"
  elif [[ -x $beside/bin/flutter ]]; then
    echo "$beside"
  else
    echo "$HOME/flutter"
  fi
}
PATH="$(flutter_dir)/bin:$HOME/.deno/bin:$HOME/.local/bin:$PATH"
export PATH

# The version a flutter command reports, empty when it cannot run.
flutter_version_of() {
  # `|| true`: without that flutter a gate's `set -e` would end it here, before its message.
  { "$1" --version --machine 2>/dev/null || true; } | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p' | head -1
}
# Every gate that runs Flutter starts with this. Another SDK than CI's still runs, but its
# `pub get` resolves other packages into app/pubspec.lock and its analyzer has other rules: on
# 2026-11-13 Flutter 3.47.8 changed 4 packages and found a lint error that 3.50.0 does not.
require_ci_flutter() {
  local want have
  want="$(ci_flutter_version)"
  have="$(flutter_version_of flutter)"
  [[ $have == "$want" ]] && return 0
  echo "$(basename -- "$0" .sh): flutter on PATH is ${have:-missing} ($(command -v flutter || echo none)), CI uses $want (.github/workflows/ci.yml): run scripts/install-flutter.sh (it adds ~/flutter-$want) or set FLUTTER_DIR to an SDK of that version" >&2
  return 1
}
if command -v ruby >/dev/null; then PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"; fi

# Blue on a terminal, plain into a pipe or a file: `grep '^\[verify\] passed'` has to match.
log() {
  if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    printf '\033[1;34m[%s]\033[0m %s\n' "$(basename "$0" .sh)" "$*"
  else
    printf '[%s] %s\n' "$(basename "$0" .sh)" "$*"
  fi
}

# The whole stack is up (API, Auth, Realtime...), not just its database.
stack_running() { (cd "$REPO_ROOT" && supabase status -o env 2>/dev/null | grep -q '^API_URL='); }

project_id() { sed -n 's/^project_id = "\(.*\)"$/\1/p' "$REPO_ROOT/supabase/config.toml"; }

# Linux gives outgoing connections source ports from 32768-60999 (ip_local_port_range), and
# every port block (543xx-561xx) lies inside it. A container that binds its port while some
# outgoing connection holds that number fails with "bind: address already in use", as the db
# did during `supabase db reset` under load (DECISIONS 12b.5). Reserving this checkout's block
# (<API port's first three digits>00-99, the web port included) takes it out of that pool;
# explicit binds still work. Needs root (passwordless sudo on the box and on CI runners).
reserve_port_block() {
  local file=/proc/sys/net/ipv4/ip_local_reserved_ports prefix block have
  [[ -r $file ]] || return 0
  prefix="$(sed -n 's/^port = \([0-9]\{3\}\)[0-9]*$/\1/p' "$REPO_ROOT/supabase/config.toml" | head -1)"
  block="${prefix}00-${prefix}99"
  have="$(<"$file")"
  [[ ",$have," == *",$block,"* ]] && return 0
  if ! sudo -n sysctl -qw "net.ipv4.ip_local_reserved_ports=${have:+$have,}$block" 2>/dev/null; then
    echo "warning: could not reserve ports $block (sudo sysctl net.ipv4.ip_local_reserved_ports): a stack start can fail with \"address already in use\"" >&2
  fi
}

# `supabase db reset` on the running stack. The CLI recreates the database and runs a one-shot
# realtime container to migrate and seed it, while the realtime service, which lost its database,
# restarts and migrates and seeds the same database at once; a reset under load failed with
# "error running container: exit 1" (DECISIONS 18.18). Stopping the service first leaves the
# one-shot container alone; the reset starts the service again when it is done. The CLI prints
# its error to stdout, so stdout is kept for a failure.
db_reset() {
  local out
  reserve_port_block
  docker stop "supabase_realtime_$(project_id)" >/dev/null 2>&1 || true
  out="$(mktemp)"
  if ! (cd "$REPO_ROOT" && supabase db reset >"$out"); then
    cat "$out" >&2
    rm -f "$out"
    return 1
  fi
  rm -f "$out"
}

# What a running stack's database has applied against supabase/migrations, one line per version
# that differs; nothing when they match. `supabase start` applies nothing to a running stack or to
# one that comes back from its volume, so one started before a rebase lacks the migrations main
# gained until its database is reset.
stack_migrations_diff() {
  local applied files differ status=0
  applied="$(docker exec "supabase_db_$(project_id)" psql -U postgres -tAc \
    'select version from supabase_migrations.schema_migrations order by 1')" || return 1
  # The CLI's own pattern for a migration: the files it skips are in no database.
  files="$(find -L "$REPO_ROOT/supabase/migrations" -maxdepth 1 -type f -exec basename {} \; \
    | sed -n 's/^\([0-9][0-9]*\)_.*\.sql$/\1/p' | sort)"
  differ="$(diff <(sed '/^$/d' <<<"$applied") <(sed '/^$/d' <<<"$files"))" || status=$?
  [[ $status -le 1 ]] || return 1
  sed -n 's/^< \(.*\)/\1 is applied and has no file/p; s/^> \(.*\)/\1 is not applied/p' <<<"$differ"
}

# Starts the local Supabase stack if it is not running and exports its URLs and publishable key,
# so the e2e tests and the web build talk to this checkout's stack whatever its port block.
# The lock lets CI start the stack in the background early (ci.yml) while this waits for it.
# `supabase start` fails now and then on a runner while docker programs a container's published
# port ("failed to set up container networking: driver failed programming external connectivity",
# issue 517: no test ran, the rerun passed). That error is the docker daemon's, not the stack's:
# stop what half started and start again, twice at most. Any other failure stops the run.
supabase_start_retrying() {
  local attempt out rc
  out="$(mktemp)"
  for attempt in 1 2 3; do
    rc=0
    supabase start >"$out" 2>&1 || rc=$?
    cat "$out"
    if (( rc == 0 )); then rm -f "$out"; return 0; fi
    if (( attempt == 3 )) || ! grep -q 'driver failed programming external connectivity\|failed to set up container networking' "$out"; then
      rm -f "$out"; return "$rc"
    fi
    log "supabase start hit a docker networking error; stopping the half-started stack and starting again (attempt $((attempt + 1)) of 3)"
    supabase stop --no-backup || true
  done
}

supabase_up() {
  reserve_port_block
  # Job 31: the alexa function's test CA and skill id, in supabase/functions/.env before the start.
  "$REPO_ROOT/scripts/alexa-test-ca.sh" >/dev/null
  # Job 43: the purchases function's fake RevenueCat secrets, also in supabase/functions/.env.
  "$REPO_ROOT/scripts/iap-local-env.sh" >/dev/null
  (
    cd "$REPO_ROOT" && flock 7
    stack_running && exit 0
    # `supabase start` leaves a database started alone (`supabase db start`) as it is and
    # starts nothing else, so stop it first. Only this checkout's project is stopped.
    if docker ps -q --filter "name=^supabase_db_$(project_id)$" | grep -q .; then supabase stop --no-backup; fi
    supabase_start_retrying
  ) 7>"/tmp/fg-supabase-start-$(project_id).lock"
  local env
  env="$(cd "$REPO_ROOT" && supabase status -o env 2>/dev/null)"
  SUPABASE_URL="$(sed -n 's/^API_URL="\(.*\)"$/\1/p' <<<"$env")"
  SUPABASE_PUBLISHABLE_KEY="$(sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p' <<<"$env")"
  MAILPIT_URL="$(sed -n 's/^MAILPIT_URL="\(.*\)"$/\1/p' <<<"$env")"
  if [[ -z $SUPABASE_URL || -z $SUPABASE_PUBLISHABLE_KEY || -z $MAILPIT_URL ]]; then
    echo "supabase status did not report API_URL, PUBLISHABLE_KEY and MAILPIT_URL" >&2
    return 1
  fi
  export SUPABASE_URL SUPABASE_PUBLISHABLE_KEY MAILPIT_URL
}

# Job 19: no CI build ever gets a real PostHog project key. CI builds have analytics off (web-prod,
# flutter) or, for e2e, the stand-in key in app/config/e2e.json pointing at a .invalid host that
# Playwright answers in place of PostHog. The committed production config never carries a key.
no_posthog_in_ci() {
  if [[ -n ${GITHUB_ACTIONS:-} && -n ${POSTHOG_PROJECT_API_KEY:-} ]]; then
    echo "POSTHOG_PROJECT_API_KEY is set in a CI build; CI must never reach PostHog" >&2
    return 1
  fi
  if grep -q POSTHOG "$REPO_ROOT/app/config/auth.json"; then
    echo "app/config/auth.json names a PostHog define; keys come from the build environment" >&2
    return 1
  fi
  local key host
  key="$(sed -n 's/^ *"POSTHOG_PROJECT_API_KEY": *"\([^"]*\)".*/\1/p' "$REPO_ROOT/app/config/e2e.json")"
  host="$(sed -n 's/^ *"POSTHOG_HOST": *"\([^"]*\)".*/\1/p' "$REPO_ROOT/app/config/e2e.json")"
  if [[ $key != phc_e2e_fake_collector || $host != https://*.invalid ]]; then
    echo "app/config/e2e.json must keep the stand-in PostHog key and a .invalid host" >&2
    return 1
  fi
}

flutter_defines() {
  echo "--dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
}

# Commits on main follow one shape (CLAUDE.md, COMMON.md): one commit per PR, subject
# "<PR title> (#n)", the PR description as body, authored with the noreply address GitHub
# accepts, Peter's trailer last.
AUTHOR_NAME="petertrost-bot"
AUTHOR_EMAIL="341616691+petertrost-bot@users.noreply.github.com"
PETER_TRAILER='Co-authored-by: Peter Trost <peter@petertrost.com>'

# Why <head> is not yet the commit main takes for <subject>, or nothing when it is.
# Needs origin/main fetched.
landing_problem() {
  local head="$1" subject="$2"
  if [[ "$(git merge-base origin/main "$head")" != "$(git rev-parse origin/main)" ]]; then
    echo "it is not on top of origin/main"
  elif [[ "$(git rev-list --count "origin/main..$head")" != 1 ]]; then
    echo "it has $(git rev-list --count "origin/main..$head") commits"
  elif [[ "$(git log -1 --format=%ae "$head")" != "$AUTHOR_EMAIL" ]]; then
    echo "its author is $(git log -1 --format=%ae "$head"), not $AUTHOR_EMAIL"
  elif [[ "$(git log -1 --format=%s "$head")" != "$subject" ]]; then
    echo "its subject is not '$subject'"
  elif [[ "$(git log -1 --format=%B "$head" | sed '/^$/d' | tail -n 1)" != "$PETER_TRAILER" ]]; then
    echo "its message does not end with Peter's trailer"
  fi
}

# The co-author trailer for the model that built the PR, from MODEL_CO_AUTHOR ("Name <email>"),
# or nothing when it is unset. Commits that already carry such a trailer keep it anyway.
model_trailer() {
  [[ -z ${MODEL_CO_AUTHOR:-} ]] && return 0
  if [[ ! $MODEL_CO_AUTHOR =~ ^[^\<\>]+\ \<[^\<\>@\ ]+@[^\<\>\ ]+\>$ ]]; then
    echo "MODEL_CO_AUTHOR must look like 'Name <email>', not '$MODEL_CO_AUTHOR'" >&2
    return 1
  fi
  echo "Co-authored-by: $MODEL_CO_AUTHOR"
}

# Prints the id of one commit on origin/main with <head>'s tree, <subject>, the PR <description>
# as body, the noreply author and the trailers. Co-author lines of the description, of the
# branch's commits and model_trailer join the trailer block once each; Peter's comes last.
squash_commit() {
  local head="$1" subject="$2" description body model others
  description="$(tr -d '\r' <<<"$3")"
  model="$(model_trailer)" || return 1
  body="$(grep -vi '^Co-authored-by:' <<<"$description" | sed '/./,$!d' || true)"
  others="$({ grep -i '^Co-authored-by:' <<<"$description"; git log --reverse --format=%b "origin/main..$head" \
    | grep -i '^Co-authored-by:'; echo "$model"; } | sed 's/[[:space:]]*$//' | grep . | grep -vixF "$PETER_TRAILER" \
    | awk '!seen[tolower($0)]++' || true)"
  printf '%s\n\n%s\n\n%s\n' "$subject" "$body" "${others:+$others$'\n'}$PETER_TRAILER" | sed '/^$/N;/^\n$/D' \
    | GIT_AUTHOR_NAME="$AUTHOR_NAME" GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL" \
      GIT_COMMITTER_NAME="$AUTHOR_NAME" GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL" \
      git commit-tree "$(git rev-parse "$head^{tree}")" -p origin/main
}

# Job 39: may a PR whose description (or commit message) is in file $1 and whose changed paths
# are in file $2 land as far as its `## Changelog` section goes (docs/CHANGELOG.md)? Prints "ok",
# or "add-none" when there is no section and the PR changes nothing users could notice, or the
# branch $3 is Dependabot's (then the section is just "none"). Users notice the app builds
# (`plan.sh ships-app`) and the backend they talk to: supabase/ (functions, migrations, the
# classifier) and the Alexa skill (alexa/), which go live from main without an app release.
# Otherwise prints why on stderr, with the format, and fails.
changelog_verdict() {
  local out code=0
  out="$(node "$REPO_ROOT/scripts/release/changelog.mjs" check --file "$1" 2>&1)" || code=$?
  if [[ $code == 0 ]]; then
    echo ok
  elif [[ $code == 3 && ( ${3:-} == dependabot/* || ( "$("$REPO_ROOT/scripts/release/plan.sh" ships-app <"$2")" == false \
    && "$(grep -cE '^(supabase|alexa)/' "$2")" == 0 ) ) ]]; then
    echo add-none
  else
    if [[ $code == 3 ]]; then
      echo "this PR changes the app or its backend: add a ## Changelog section to the PR description (category + de + en, or none), then rerun" >&2
    else
      echo "the PR description's ## Changelog section is invalid: ${out#changelog: }" >&2
    fi
    cat >&2 <<'FORMAT'
Format (docs/CHANGELOG.md): one item per paragraph, a category (new, improved or fixed) and one
sentence per language, in user words; or the single word none when users see no change. An item
users don't get yet adds "flag: <key>" (behind a feature flag) or "hold: <key>" (e.g. Premium
before it is on sale), a key from releases/flags.json.

## Changelog
new
de: Die Liste sortiert sich nach deinem Einkauf.
en: The list sorts itself after your shopping trip.
flag: smart-sort

fixed
de: Die Liste springt beim Abhaken nicht mehr nach oben.
en: The list no longer jumps to the top when you check off an item.
FORMAT
    return 1
  fi
}

# Stores the `append-log` merge driver's command (scripts/merge-append-log.sh, named by
# .gitattributes for the logs every job appends to, job 218) in the repository config, which every
# worktree shares: git reads a driver's command from the config only. Without it a log conflict
# stops the rebase as before. So does one the script does not take, or a checkout without the
# script: the command then merges as git does without a driver.
install_merge_driver() {
  local driver='scripts/merge-append-log.sh %O %A %B || git merge-file -q -L ours -L base -L theirs %A %O %B || exit 1'
  [[ "$(git config --get merge.append-log.driver || true)" == "$driver" ]] ||
    git config merge.append-log.driver "$driver" ||
    echo "could not store the append-log merge driver; a log conflict stops the rebase as before." >&2
}

# Rebases the current branch onto origin/main, carrying local edits of skip-worktree files (a
# checkout's port block in supabase/config.toml, COORDINATION.md) across: git refuses to rebase
# over them once main changes such a file.
rebase_onto_main() {
  local files=() patch
  mapfile -t files < <(git ls-files -v | sed -n 's/^S //p')
  patch="$(mktemp --suffix=.patch)"
  if [[ ${#files[@]} -gt 0 ]]; then
    git update-index --no-skip-worktree "${files[@]}"
    git diff -- "${files[@]}" >"$patch"
    git checkout -- "${files[@]}"
  fi
  install_merge_driver
  if ! git rebase -q origin/main; then
    echo "rebase stopped; resolve it and run git rebase --continue." >&2
    [[ -s $patch ]] && echo "Then restore your local edits: git apply $patch && git update-index --skip-worktree ${files[*]}" >&2
    return 1
  fi
  if [[ ${#files[@]} -gt 0 ]]; then
    git apply "$patch"
    git update-index --skip-worktree "${files[@]}"
  fi
  rm -f "$patch"
}

# Job 18: points scripts/fg at this checkout's own stack (the one supabase_up starts) instead of an
# fg instance's generated one: its port block and project id from supabase/config.toml, and a
# throwaway state dir, so fixture runs from a gate never mix with an agent's fg state.
fg_on_repo_stack() {
  local config="$REPO_ROOT/supabase/config.toml"
  FG_PORT_PREFIX="$(sed -n 's/^port = \([56][0-9][0-9]\)21$/\1/p' "$config" | head -1)"
  FG_PROJECT_ID="$(sed -n 's/^project_id = "\(.*\)"$/\1/p' "$config")"
  FG_STACK_WORKDIR="$REPO_ROOT"
  FG_STATE_DIR="$(mktemp -d)"
  export FG_PORT_PREFIX FG_PROJECT_ID FG_STACK_WORKDIR FG_STATE_DIR
}

# git_fetch <git fetch args...>: git fetch, tried 3 times, 1 s and 3 s apart. Agents share one
# clone; a fetch that updates a ref another fetch is updating fails ("cannot lock ref") and goes
# through on the next try.
git_fetch() {
  local try
  for try in 1 2 3; do
    git fetch "$@" && return 0
    if ((try < 3)); then
      echo "git fetch $* failed (try $try of 3); retrying" >&2
      sleep $((try * 2 - 1))
    fi
  done
  return 1
}

# run_detached <log> <command...>: starts the command in the background, its output appended to
# the log, with no file of the caller open, and returns at once. A command run under a lock
# (merge-lock's flock, its ssh to the Mac) that left a child holding the lock's descriptor would
# keep the lock until that child ends.
run_detached() {
  local log_file="$1" fd
  shift
  (
    for fd in /dev/fd/*; do
      fd="${fd##*/}"
      if ((fd > 2)); then eval "exec $fd>&-" 2>/dev/null || true; fi
    done
    if command -v setsid >/dev/null; then
      exec setsid nohup "$@" </dev/null >>"$log_file" 2>&1
    fi
    exec nohup "$@" </dev/null >>"$log_file" 2>&1
  ) &
  disown 2>/dev/null || true
}

# The shell scripts the lint gate runs shellcheck on, one per line, relative to the repository
# root (scripts/push-checks.sh checks the changed ones).
shell_scripts() {
  (cd "$REPO_ROOT" && printf '%s\n' scripts/*.sh scripts/gates/*.sh scripts/backup/*.sh scripts/ci/*.sh \
    scripts/release/*.sh scripts/checks/*.sh scripts/ios/*.sh nexus/scripts/*.sh scripts/fg .githooks/*)
}
