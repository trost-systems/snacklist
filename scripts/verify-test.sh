#!/usr/bin/env bash
# Tests scripts/verify.sh on a scratch repository with stub gates: the hard stop at the first
# failing gate, the plain last line, the log of each gate run (whole under a burst of output,
# its own beside a leftover writer or a second run), the ledger with its flake and streak notes,
# that a process a gate leaves behind cannot hold the run open, and the recipes a failed gate's
# verdict names (the skill's own included). Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
# A locale the box lacks would put bash's warning into every stub gate's output.
export LC_ALL=C

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

repo="$tmp/repo"
mkdir -p "$repo/scripts/gates"
cp "$REPO_ROOT/scripts/verify.sh" "$REPO_ROOT/scripts/lib.sh" "$repo/scripts/"
# A stub gate does what the file $STUBS/<gate> says: its exit code, default 0.
gate() {
  cat >"$repo/scripts/gates/$1.sh" <<'GATE'
#!/usr/bin/env bash
name="$(basename "$0" .sh)"
echo "$name ran${*:+ with $# arguments: $*}"
echo "$name on stderr" >&2
if [[ -e $STUBS/says ]]; then sleep 2 && cat "$STUBS/says"; fi
echo "$name" >>"$STUBS/ran"
exit "$(cat "$STUBS/$name" 2>/dev/null || echo 0)"
GATE
  chmod +x "$repo/scripts/gates/$1.sh"
}
for name in gitleaks lint flutter e2e; do gate "$name"; done
git -C "$repo" init -q -b work
echo 'port = 54321' >"$repo/config.toml"
printf 'ignored.env\n' >"$repo/.gitignore"
git -C "$repo" add config.toml .gitignore
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m start

export STUBS="$tmp/stubs" VERIFY_LEDGER="$tmp/ledger.tsv" VERIFY_LOG_DIR="$tmp/logs"
# verify.sh --screenshots exports it to every gate, this one included; the cases set their own.
unset SCREENSHOT_DIR
mkdir -p "$STUBS"
# verify <args>: the run's output in $out, its exit code in $code, the gates that ran in $ran.
verify() {
  : >"$STUBS/ran"
  code=0
  out="$("$repo/scripts/verify.sh" "$@" 2>&1)" || code=$?
  ran="$(tr '\n' ' ' <"$STUBS/ran")"
}
last() { tail -n 1 <<<"$out"; }
# Waits for a file a stub gate writes: a verify.sh that never starts its gate fails the test.
wait_for() {
  local tries=0
  until [[ -e $1 ]]; do
    ((++tries < 300)) || { echo "FAIL: no $1 after 30 s" >&2; exit 1; }
    sleep 0.1
  done
}
# The file a FAILED verdict names.
named() { sed -n 's/.*; its output: \([^;]*\.log\).*/\1/p' <<<"${1:-$(last)}"; }
ledger() { cut -f4,5,7 "$VERIFY_LEDGER" | tr '\t\n' ' ;'; }
# What verify.sh itself said in the last run, with seconds, the flake note's time and the log's
# name masked; and what was not from verify.sh, sorted (a gate's two streams have no fixed order).
own() { grep '^\[verify\]' <<<"$out" | sed -e 's/[0-9][0-9]* s/N s/g' -e 's/\( on this same tree at \)[^ ]*\. The/\1T. The/' -e "s|$VERIFY_LOG_DIR/\([a-z0-9]*\)\.[0-9.-]*\.log|LOG/\1.log|"; }
rest() { grep -v '^\[verify\]' <<<"$out" | sort; }
flake() { echo "[verify] flake: $1 had the other result ($2) on this same tree at T. The files git does not ignore are the same, so something else differs: find it and write it down (docs/CI.md, \"The local loop\")"; }

verify --only gitleaks,lint,flutter
[[ $code == 0 && $ran == "gitleaks lint flutter " ]] || fail "three passing gates: exit $code, ran '$ran'"
[[ "$(last)" == "[verify] passed: gitleaks lint flutter" ]] || fail "last line of a green run: $(last)"
grep -q '^\[verify\] took: gitleaks [0-9]* s, lint [0-9]* s, flutter [0-9]* s ([0-9]* s)$' <<<"$out" || fail "no seconds per gate in: $out"
grep -q $'\033' <<<"$out" && fail "escape codes in piped output"
[[ "$(grep -c 'lint ran\|lint on stderr' <<<"$out")" == 2 ]] || fail "the gate's stdout and stderr are not in the run's output: $out"
[[ "$(cat "$VERIFY_LOG_DIR/lint.log")" == $'lint ran\nlint on stderr' ]] || fail "lint.log: $(cat "$VERIFY_LOG_DIR/lint.log")"
[[ "$(ledger)" == "gitleaks pass ;lint pass ;flutter pass ;" ]] || fail "ledger after a green run: $(ledger)"
[[ "$(cut -f3 "$VERIFY_LEDGER" | sort -u | wc -l)" -eq 1 ]] || fail "one tree, several hashes in the ledger"

echo 7 >"$STUBS/lint"
verify --only gitleaks,lint,flutter,e2e
[[ $code == 7 && $ran == "gitleaks lint " ]] || fail "a failing gate stops the run with its exit code: exit $code, ran '$ran'"
[[ "$(last)" == "[verify] FAILED: lint (exit 7) after "*" s; its output: $VERIFY_LOG_DIR/lint."*".log; not run: flutter e2e" ]] || fail "last line of a red run: $(last)"
[[ "$(cat "$(named)")" == $'lint ran\nlint on stderr' && "$(named)" -ef "$VERIFY_LOG_DIR/lint.log" ]] || fail "the file the verdict names is not the run's output, or lint.log is not it: $(named)"
grep -q '^\[verify\] flake: lint had the other result (pass) on this same tree' <<<"$out" || fail "pass then fail on one tree is not called a flake: $out"

echo change >"$repo/untracked.txt"
verify --only lint
grep -q 'flake:' <<<"$out" && fail "an untracked file changes the tree, yet: $out"
echo change2 >"$repo/untracked.txt"
verify --only lint
grep -q '^\[verify\] lint has failed 3 runs in a row on this branch' <<<"$out" || fail "no streak note at the third failure: $out"
[[ "$(tail -n 1 <<<"$out")" == "[verify] FAILED: lint (exit 7)"* ]] || fail "the streak note is not above the verdict: $(last)"
rm "$STUBS/lint"
verify --only lint
grep -q '^\[verify\] flake: lint had the other result (fail) on this same tree' <<<"$out" || fail "fail then pass on one tree is not called a flake: $out"

verify --only lint,e2e -- tests/list.spec.ts -g 'a b'
grep -q '^e2e ran with 3 arguments: tests/list.spec.ts -g a b$' <<<"$out" || fail "arguments after -- do not reach the e2e gate as they were given: $out"
grep -q '^lint ran$' <<<"$out" || fail "arguments after -- reach a gate other than e2e: $out"
[[ "$(tail -n 1 "$VERIFY_LEDGER" | cut -f4,7)" == $'e2e\ttests/list.spec.ts -g a b' ]] || fail "the ledger row lacks the arguments: $(tail -n 1 "$VERIFY_LEDGER")"
# The e2e gate's wait for the box-wide lock is not the gate's run time: the stub takes 2 s and
# says it waited 2 s, so its seconds are at most the whole call's less 2.
echo '[e2e] got the e2e lock: waited 2 s for the lock' >"$STUBS/says"
began=$SECONDS
verify --only e2e
whole=$((SECONDS - began))
rm "$STUBS/says"
grep -q '^\[verify\] took: e2e [0-9]* s (after 2 s waiting for the lock) ' <<<"$out" || fail "the wait for the lock is not set apart: $out"
[[ "$(tail -n 1 "$VERIFY_LEDGER" | cut -f8)" == 2 && "$(tail -n 1 "$VERIFY_LEDGER" | cut -f6)" -le $((whole - 2)) ]] \
  || fail "the wait is not taken off the seconds (the call took $whole s): $(tail -n 1 "$VERIFY_LEDGER")"
verify --only gitleaks,e2e --skip-e2e
[[ $code == 0 && $ran == "gitleaks " && "$(last)" == "[verify] passed: gitleaks" ]] || fail "--skip-e2e: exit $code, ran '$ran', $(last)"
verify --only nope
[[ $code == 2 && -z $ran ]] || fail "an unknown gate: exit $code, ran '$ran'"

# A server the gate forgot holds the gate's stdout for a minute; the run must not wait for it.
cat >"$repo/scripts/gates/lint.sh" <<'GATE'
#!/usr/bin/env bash
sleep 60 &
echo "$!" >"$STUBS/orphan"
echo "lint done"
GATE
began=$SECONDS
verify --only lint
kill "$(cat "$STUBS/orphan")" 2>/dev/null || true
[[ $code == 0 && $((SECONDS - began)) -lt 20 ]] || fail "a background process of a gate held the run: exit $code after $((SECONDS - began)) s"
grep -q '^lint done$' <<<"$out" || fail "the gate's last line is missing: $out"

history="$("$repo/scripts/verify.sh" --history)"
grep -Eq '^lint +7 +3 +[0-9]+ +[0-9]+ +2$' <<<"$history" || fail "--history, lint (7 runs, 3 failed, 2 flaky trees): $history"
grep -Eq '^e2e \(subset\) +1 +0 ' <<<"$history" || fail "--history, the e2e subset: $history"
grep -Eq '^e2e +1 +0 ' <<<"$history" || fail "--history, the full e2e run: $history"
"$repo/scripts/verify.sh" --history 2999-01-01 | grep -q '^lint' && fail "--history <since> keeps older rows"

# Each case below starts from an empty ledger.
fresh() { VERIFY_LEDGER="$tmp/ledger.$1.tsv"; }
edit() { echo "$1" >"$repo/untracked.txt"; }
gate lint

# The streak: per gate and branch, whatever the arguments, ended by a pass.
fresh streak
echo 1 >"$STUBS/e2e"
edit s1 && verify --only e2e -- -g one
edit s2 && verify --only e2e -- -g two
grep -q 'in a row' <<<"$out" && fail "a streak note at the second failure: $out"
git -C "$repo" checkout -q -b other
edit s3 && verify --only e2e
grep -q 'in a row' <<<"$out" && fail "another branch's failures count into this one's streak: $out"
git -C "$repo" checkout -q work
edit s4 && verify --only e2e -- -g three
grep -q '^\[verify\] e2e has failed 3 runs in a row on this branch' <<<"$out" || fail "three failures with three sets of arguments are no streak: $out"
rm "$STUBS/e2e"
edit s5 && verify --only e2e
echo 1 >"$STUBS/e2e"
edit s6 && verify --only e2e
grep -q 'in a row' <<<"$out" && fail "a pass does not end the streak: $out"
git -C "$repo" checkout -q --detach
verify --only gitleaks
[[ "$(tail -n 1 "$VERIFY_LEDGER" | cut -f2)" == detached:repo ]] || fail "a detached checkout's rows: $(tail -n 1 "$VERIFY_LEDGER")"
git -C "$repo" checkout -q work

# A flake is both results on one tree with the same arguments. --screenshots is one of them, and
# the skip-worktree port block is part of the tree.
fresh flake
edit f1
verify --only e2e -- tests/b.spec.ts
rm "$STUBS/e2e"
verify --only e2e -- tests/a.spec.ts
grep -q 'flake:' <<<"$out" && fail "two specs with two results on one tree are called a flake: $out"
verify --only e2e --screenshots "$tmp/shots"
[[ "$(tail -n 1 "$VERIFY_LEDGER" | cut -f7)" == --screenshots ]] || fail "--screenshots is not in the row: $(tail -n 1 "$VERIFY_LEDGER")"
history="$("$repo/scripts/verify.sh" --history)"
grep -Eq '^e2e \(subset\) +2 +1 +[0-9]+ +[0-9]+ +0$' <<<"$history" || fail "--history counts two specs on one tree as a flaky tree: $history"
grep -Eq '^e2e +1 +0 ' <<<"$history" || fail "--history, a full run with --screenshots is no subset: $history"
for bit in skip-worktree assume-unchanged; do
  git -C "$repo" update-index "--$bit" config.toml
  echo 1 >"$STUBS/lint"
  verify --only lint
  echo "port = 61921 # $bit" >"$repo/config.toml"
  rm "$STUBS/lint"
  verify --only lint
  grep -q 'flake:' <<<"$out" && fail "a changed $bit file is the same tree: $out"
  [[ -z "$(git -C "$repo" status --porcelain config.toml)" ]] || fail "the run cleared the $bit bit of config.toml"
  git -C "$repo" update-index "--no-$bit" config.toml
  git -C "$repo" checkout -q config.toml
done

# --history: the median and p90 of the passing runs.
fresh history
for seconds in 30 100 20 90 10 80 60 70 50 40; do
  printf '2026-11-14T10:00:00Z\twork\ttree%s\tdb\tpass\t%s\t\t0\n' "$seconds" "$seconds" >>"$VERIFY_LEDGER"
done
printf '2026-11-14T10:00:00Z\twork\ttree10\tdb\tfail\t900\t\t0\n' >>"$VERIFY_LEDGER"
"$repo/scripts/verify.sh" --history | grep -Eq '^db +11 +1 +50 +90 +1$' || fail "--history, median 50 and p90 90 of ten passing runs: $("$repo/scripts/verify.sh" --history)"

# A gate that keeps writing while the follower copies still has all of its output printed.
fresh burst
cat >"$repo/scripts/gates/lint.sh" <<'GATE'
#!/usr/bin/env bash
line="$(printf '%099d' 0)"
block="$(printf "$line\n%.0s" {1..1000})"
for _ in {1..400}; do cat <<<"$block"; done
echo "burst end"
GATE
printed="$("$repo/scripts/verify.sh" --only lint 2>&1 | grep -c '^0*$\|^burst end$' || true)"
[[ $printed == "$(wc -l <"$VERIFY_LOG_DIR/lint.log")" && $printed == 400001 ]] || fail "a burst of output: $printed lines printed, $(wc -l <"$VERIFY_LOG_DIR/lint.log") in the log"

# What an earlier run of a gate left running writes to that run's file, not into this run's.
cat >"$repo/scripts/gates/lint.sh" <<'GATE'
#!/usr/bin/env bash
echo "lint run $RUN: first line, long enough to lie past the start of the next run's log"
(sleep 1 && echo "left behind by run $RUN") &
if [[ $RUN == 2 ]]; then sleep 2; fi
echo "lint run $RUN: last line"
GATE
RUN=1 verify --only lint
RUN=2 verify --only lint
grep -q '^lint run 2: last line$' <<<"$out" || fail "the last line of the run after a leftover writer is missing: $out"
grep -q 'run 1' <<<"$out" && fail "the run prints what an earlier run left behind: $out"
[[ "$(grep -c . "$VERIFY_LOG_DIR/lint.log")" == 3 && "$(grep -c 'run 2' "$VERIFY_LOG_DIR/lint.log")" == 3 ]] || fail "lint.log is not the newest run's output alone: $(cat "$VERIFY_LOG_DIR/lint.log")"

# Two runs of one gate at once in one checkout: each prints its own output, and the file a
# failed run's verdict names still holds that run's when the other has ended after it.
cat >"$repo/scripts/gates/lint.sh" <<'GATE'
#!/usr/bin/env bash
echo "lint run $RUN: first line"
: >"$STUBS/started-$RUN"
for _ in {1..600}; do [[ -e $STUBS/release-$RUN ]] && break; sleep 0.1; done
echo "lint run $RUN: last line"
[[ $RUN != A ]]
GATE
rm -f "$STUBS"/started-* "$STUBS"/release-*
RUN=A "$repo/scripts/verify.sh" --only lint >"$tmp/run-A.out" 2>&1 &
first=$!
wait_for "$STUBS/started-A"
RUN=B "$repo/scripts/verify.sh" --only lint >"$tmp/run-B.out" 2>&1 &
wait_for "$STUBS/started-B"
: >"$STUBS/release-A"
wait "$first" || true
: >"$STUBS/release-B"
wait
for name in A B; do
  [[ "$(grep -c 'lint run' "$tmp/run-$name.out")" == 2 && "$(grep -c "lint run $name" "$tmp/run-$name.out")" == 2 ]] || fail "run $name of two at once printed: $(cat "$tmp/run-$name.out")"
done
[[ "$(cat "$(named "$(tail -n 1 "$tmp/run-A.out")")")" == $'lint run A: first line\nlint run A: last line' ]] || fail "the file the failed run names does not hold its output: $(tail -n 1 "$tmp/run-A.out")"
[[ "$(tail -n 1 "$tmp/run-B.out")" == "[verify] passed: lint" ]] || fail "the second of two runs at once: $(cat "$tmp/run-B.out")"

# A run that is still in its gate keeps its file through more later runs than are kept.
fresh overtaken
rm -f "$STUBS"/started-* "$STUBS"/release-*
RUN=A "$repo/scripts/verify.sh" --only lint >"$tmp/run-A.out" 2>&1 &
first=$!
wait_for "$STUBS/started-A"
for run in 1 2 3 4 5 6; do
  : >"$STUBS/release-$run"
  RUN=$run verify --only lint
done
: >"$STUBS/release-A"
wait "$first" || true
kept="$(named "$(tail -n 1 "$tmp/run-A.out")")"
[[ "$(tail -n 1 "$tmp/run-A.out")" == "[verify] FAILED: lint (exit 1) after "* && "$(cat "$kept")" == $'lint run A: first line\nlint run A: last line' ]] || fail "a run that six later runs overtook lost its verdict or its file: $(cat "$tmp/run-A.out")"
[[ "$(cut -f5 "$VERIFY_LEDGER" | grep -c fail)" == 1 ]] || fail "the overtaken run has no row in the ledger: $(ledger)"

# The newest five runs of a gate keep their output.
gate lint
for _ in {1..7}; do verify --only lint,gitleaks; done
[[ "$(find "$VERIFY_LOG_DIR" -name 'lint.*.log' | wc -l)" -eq 5 ]] || fail "the log files kept for lint: $(ls "$VERIFY_LOG_DIR")"
[[ "$(find "$VERIFY_LOG_DIR" -name 'gitleaks.*.log' | wc -l)" -le 5 && -z "$(find "$VERIFY_LOG_DIR" -name '*.done')" ]] || fail "leftovers in the log directory: $(ls "$VERIFY_LOG_DIR")"
[[ "$(cat "$VERIFY_LOG_DIR/lint.log")" == $'lint ran\nlint on stderr' ]] || fail "lint.log after pruning: $(cat "$VERIFY_LOG_DIR/lint.log" 2>&1)"

# A failed gate whose output has a recipe's signal names the recipe in its verdict, every recipe
# that matches, and fails as before: the gate's exit code, a fail row in the ledger. Not named: a
# recipe of another gate, a file without front matter, a signal that is no pattern, and none for
# a run that passed or for other output.
says() {
  cat >"$repo/scripts/gates/$1.sh" <<'GATE'
#!/usr/bin/env bash
basename "$0" .sh >>"$STUBS/ran"
cat "$STUBS/output"
exit "$(cat "$STUBS/exit")"
GATE
  chmod +x "$repo/scripts/gates/$1.sh"
}
says lint
fresh recipes
export VERIFY_RECIPES="$tmp/recipes"
mkdir -p "$VERIFY_RECIPES"
printf '%s\n' --- 'gate: lint' 'signal: ^ +[0-9]+ files? left unformatted$' --- '# Known' >"$VERIFY_RECIPES/known.md"
printf '%s\n' --- 'gate: flutter' 'signal: unformatted' --- >"$VERIFY_RECIPES/other-gate.md"
printf '%s\n' '# Recipes' --- 'gate: lint' 'signal: unformatted' --- >"$VERIFY_RECIPES/README.md"
printf '%s\n' --- 'gate: lint' 'signal: (unformatted' --- >"$VERIFY_RECIPES/no-pattern.md"
{ echo checking; printf 'lib/file_%s.dart\n' {1..40}; printf '\033[31m  2 files left unformatted\033[0m\ndone\n'; } >"$STUBS/output"
echo 3 >"$STUBS/exit"
verify --only lint,flutter
[[ $code == 3 && "$(last)" == "[verify] FAILED: lint (exit 3) after "*" s; its output: $VERIFY_LOG_DIR/lint."*".log; seen before? $VERIFY_RECIPES/known.md; not run: flutter" ]] || fail "a failure with a recipe's signal: exit $code, $(last)"
[[ $ran == "lint " ]] || fail "a failure with a recipe's signal ran its gate again or went on: '$ran'"
grep -q '^\[verify\] took: lint [0-9]* s$' <<<"$out" || fail "no seconds for the gate next to a recipe: $out"
[[ "$(cat "$(named)")" == "$(cat "$STUBS/output")" ]] || fail "the verdict with a recipe no longer names the run's output: $(named)"
[[ "$(ledger)" == "lint fail ;" ]] || fail "the ledger after a failure with a recipe's signal: $(ledger)"
printf '%s\n' --- 'gate: lint' 'signal: ^checking$' --- '# Also known' >"$VERIFY_RECIPES/also.md"
verify --only lint
[[ $code == 3 && "$(last)" == *"; seen before? $VERIFY_RECIPES/also.md $VERIFY_RECIPES/known.md" ]] || fail "two recipes with a signal in the output: exit $code, $(last)"
[[ $ran == "lint " ]] || fail "a failure with two recipes ran its gate again: '$ran'"
rm "$VERIFY_RECIPES/also.md"
echo 0 >"$STUBS/exit"
verify --only lint
[[ $code == 0 && "$(last)" == "[verify] passed: lint" ]] || fail "a recipe's signal in a run that passed: exit $code, $(last)"
grep -q 'seen before\|known\.md' <<<"$out" && fail "a run that passed names a recipe: $out"
[[ "$(own)" == "[verify] gate: lint"$'\n'"$(flake lint fail)"$'\n[verify] took: lint N s (N s)\n[verify] passed: lint' && "$(rest)" == "$(sort "$STUBS/output")" ]] || fail "a run that passed with a recipe's signal says more than gate, flake note, took and passed: $out"
# A gate that passed with the signal is not looked at when a later gate fails.
echo 1 >"$STUBS/flutter"
verify --only lint,flutter
[[ $code == 1 && $ran == "lint flutter " && "$(last)" == "[verify] FAILED: flutter (exit 1) after "*" s; its output: $VERIFY_LOG_DIR/flutter."*".log" ]] || fail "a later gate's failure after a pass with a recipe's signal: exit $code, ran '$ran', $(last)"
[[ "$(own)" == "[verify] gate: lint"$'\n'"$(flake lint fail)"$'\n[verify] gate: flutter\n[verify] took: lint N s, flutter N s\n[verify] FAILED: flutter (exit 1) after N s; its output: LOG/flutter.log' && "$(rest)" == "$({ cat "$STUBS/output"; printf '%s\n' 'flutter ran' 'flutter on stderr'; } | sort)" ]] || fail "a later gate's failure after a pass with a recipe's signal says more than without recipes: $out"
rm "$STUBS/flutter"
echo 3 >"$STUBS/exit"
verify --only lint
grep -q '^\[verify\] flake: lint had the other result (pass) on this same tree' <<<"$out" || fail "a recipe took the flake note's place: $out"
[[ $code == 3 && "$(last)" == *"; seen before? $VERIFY_RECIPES/known.md" ]] || fail "a flake with a recipe's signal: exit $code, $(last)"
[[ $ran == "lint " ]] || fail "a flake with a recipe ran its gate again: '$ran'"
printf 'checking\nno files left unformatted\n' >"$STUBS/output"
echo 1 >"$STUBS/exit"
verify --only lint
[[ $code == 1 && "$(last)" == "[verify] FAILED: lint (exit 1) after "*" s; its output: $VERIFY_LOG_DIR/lint."*".log" ]] || fail "a failure without a recipe's signal: exit $code, $(last)"
[[ "$(own)" == "[verify] gate: lint"$'\n'"$(flake lint pass)"$'\n[verify] took: lint N s\n[verify] FAILED: lint (exit 1) after N s; its output: LOG/lint.log' && "$(rest)" == "$(sort "$STUBS/output")" ]] || fail "a failure without a recipe's signal says more than without recipes: $out"
# A grep that exits before sed has written everything leaves sed a closed pipe: a signal that is not
# a regex (no-pattern.md above), or /dev/null as its stdout. With SIGPIPE ignored, as in some CI
# shells, sed's error lands in the verdict (job 446).
cp "$VERIFY_LEDGER" "$tmp/ledger.before"
{ echo checking; seq 1 200000; } >"$STUBS/output"
echo 1 >"$STUBS/exit"
(trap '' PIPE; verify --only lint; printf '%s\n' "$out" >"$tmp/closed-pipe.out")
if grep -q 'Broken pipe\|flush stdout' "$tmp/closed-pipe.out"; then fail "sed wrote a closed-pipe error into the verdict: $(grep 'Broken pipe\|flush stdout' "$tmp/closed-pipe.out")"; fi
cp "$tmp/ledger.before" "$VERIFY_LEDGER"
printf 'checking\nno files left unformatted\n' >"$STUBS/output"
# Without VERIFY_RECIPES the recipes are the skill's, named by their path in the checkout.
unset VERIFY_RECIPES
mkdir -p "$repo/.cursor/skills/verify-snacklist/recipes"
printf '%s\n' --- 'gate: lint' 'signal: ^checking$' --- '# In the checkout' >"$repo/.cursor/skills/verify-snacklist/recipes/in-checkout.md"
verify --only lint
[[ $code == 1 && "$(last)" == *".log; seen before? .cursor/skills/verify-snacklist/recipes/in-checkout.md" ]] || fail "the checkout's own recipes: exit $code, $(last)"
[[ $ran == "lint " ]] || fail "a failure with exit 1, a recipe and no gate left ran its gate again: '$ran'"
[[ "$(ledger)" == "lint fail ;lint fail ;lint pass ;lint pass ;flutter fail ;lint fail ;lint fail ;lint fail ;" ]] || fail "the ledger after a failure with exit 1 and a recipe: $(ledger)"
grep -q '^\[verify\] lint has failed 3 runs in a row on this branch' <<<"$out" || fail "a recipe took the streak note's place: $out"

# The skill's own recipes: each names a gate and has every section, the README lists it, its
# Example gets it named and its Not this does not.
export VERIFY_RECIPES="$REPO_ROOT/.cursor/skills/verify-snacklist/recipes"
section() { awk -v title="## $2" '$0 == title { on = 1; next } /^## / { on = 0 } on && /^```/ { fenced = !fenced; next } on && fenced' "$1"; }
count=0
for recipe in "$VERIFY_RECIPES"/*.md; do
  name="$(basename "$recipe" .md)"
  [[ $name != README ]] || continue
  count=$((count + 1))
  [[ $name =~ ^[a-z0-9-]+$ ]] || fail "recipe '$name': lower-case letters, digits and hyphens only, so the verdict stays one line of names"
  of="$(awk '/^gate: / { print $2; exit }' "$recipe")"
  [[ -n $of && -x "$REPO_ROOT/scripts/gates/$of.sh" ]] || { fail "recipe $name: gate '$of' is not one of scripts/gates"; continue; }
  for title in Condition Mechanism "Do" "Do not" Evidence Example "Not this"; do
    grep -qx "## $title" "$recipe" || fail "recipe $name has no section '$title'"
  done
  grep -qF "($name.md)" "$VERIFY_RECIPES/README.md" || fail "recipes/README.md does not list $name"
  says "$of"
  echo 1 >"$STUBS/exit"
  section "$recipe" Example >"$STUBS/output"
  [[ -s $STUBS/output ]] || fail "recipe $name has no example"
  rows="$(wc -l <"$VERIFY_LEDGER")"
  verify --only "$of"
  [[ "$(last)" == *"; seen before? "*"/$name.md"* ]] || fail "recipe $name: its example does not get it named: $(last)"
  [[ $code == 1 && $ran == "$of " ]] || fail "recipe $name: its example's failure ran the gate again or lost its exit code: exit $code, ran '$ran'"
  [[ "$(wc -l <"$VERIFY_LEDGER")" == "$((rows + 1))" && "$(ledger)" == *"$of fail ;" ]] || fail "recipe $name: the ledger after its example: $(ledger)"
  # Where the example is Playwright's summary, each of its test lines alone gets the recipe
  # named, and the same tests as passed lines of the list do not: with a number of one, two and
  # three digits, the last without its time.
  while IFS= read -r line; do
    [[ $line == "    ["* ]] || continue
    printf '%s\n' "$line" >"$STUBS/output"
    verify --only "$of"
    [[ $code == 1 && $ran == "$of " && "$(last)" == *"; seen before? "*"/$name.md"* ]] || fail "recipe $name: this line of its example alone does not get it named, with the gate run once and its exit code: $line"
  done < <(section "$recipe" Example)
  section "$recipe" Example | sed -n 's/^    \(\[.*[^ ]\) *$/  ✓  1 \1 (1.0s)\n  ✓  12 \1 (12.3s)\n  ✓  123 \1/p' >"$STUBS/output"
  if [[ -s $STUBS/output ]]; then
    verify --only "$of"
    [[ "$(last)" == "[verify] FAILED: $of "* && "$(last)" != *"$name.md"* ]] || fail "recipe $name: named when the tests of its example pass: $(last)"
  fi
  section "$recipe" "Not this" >"$STUBS/output"
  [[ -s $STUBS/output ]] || fail "recipe $name has no 'Not this' output"
  verify --only "$of"
  [[ "$(last)" == "[verify] FAILED: $of "* && "$(last)" != *"$name.md"* ]] || fail "recipe $name: named for output that is not its failure: $(last)"
done
[[ $count -gt 0 ]] || fail "no recipes in $VERIFY_RECIPES"

if [[ $failures -gt 0 ]]; then
  echo "verify-test: $failures failed" >&2
  exit 1
fi
log "verify.sh stops at the first failure, ends on a plain verdict, names known causes and keeps its ledger: all cases pass"
