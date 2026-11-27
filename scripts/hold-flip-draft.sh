#!/usr/bin/env bash
# Opens the hold flip as a draft PR the moment legal text behind an unreleased hold lands (job 476).
#
# A merge that adds or changes lines of site/content/legal/*.md inside a `::: once <hold>` or
# `::: until <hold>` block, or under a heading with `once=<hold>` or `until=<hold>` (the gates of
# site/build.mjs), waits for that hold's release in releases/flags.json. For each such hold that
# main still has unreleased and that has no open PR on hold-flip/<hold>, this creates that branch
# from main with the flip Legal reviewed in #710: `holds.<hold>.released` true (the note stays),
# and the date lines (front matter `updated:`, `Stand: <D>. <Monat> <YYYY>`, `Last updated: <D>
# <Month> <YYYY>`) set to today in Europe/Berlin in the legal files that hold a block for it. It
# pushes the branch, opens a draft PR labelled do-not-merge, then adds the enable-checklist line
# to docs/NEEDS_LEAD.md (once per hold) and pushes with scripts/push-pr.sh, keeping the draft.
# It never merges and never touches a rollout. Before #710 the flip of #643's text waited two days
# for an owner.
#
# Idempotent: a rerun finds the open PR and only completes what an earlier run left undone (the
# NEEDS_LEAD line, a comment naming a later merge that changed the hold's text). merge-pr.sh runs
# it after every merge, detached, so the merge lock is released first; by hand it backfills an
# older merge: scripts/hold-flip-draft.sh 643.
#
# Usage: scripts/hold-flip-draft.sh [--dry-run] [--base <rev>] <merged-PR-number-or-commit>
#   --dry-run  prints the holds, the flip's diff and the PR body; pushes and opens nothing
#   --base     the main to check the holds against and flip on (default main, fetched)
# It reads the one commit main took for the PR (merge-pr.sh lands one per PR); a by-hand backfill of
# an older PR landed as several commits sees only the last of them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

dry_run=0 base=""
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --base) base="${2:?--base needs a revision}"; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
target="${1:?usage: scripts/hold-flip-draft.sh [--dry-run] [--base <rev>] <merged-PR-number-or-commit>}"

LEGAL_DIR=site/content/legal
FLAGS=releases/flags.json

# A failure says so in one line with the rerun, on stderr (merge-pr.sh's log) and in
# $FAILED, which merge-pr.sh shows at its next run; a run that gets through clears its line.
FAILED="$(git rev-parse --path-format=absolute --git-common-dir)/hold-flip-draft.failed"
private_refs="refs/hold-flip-run/$$/"
work=""
# shellcheck disable=SC2317,SC2329 # only the EXIT trap calls it
on_exit() {
  local rc=$? line what
  git for-each-ref --format='%(refname)' "$private_refs" | while read -r ref; do git update-ref -d "$ref"; done
  if [[ -n $work ]]; then
    git worktree remove --force "$work/flip" 2>/dev/null || true
    rm -rf "$work"
  fi
  [[ $dry_run == 1 ]] && return
  if [[ $rc != 0 ]]; then
    what="${merged:-${pr:+#$pr}}"
    line="[$(TZ=Europe/Berlin date '+%Y-%m-%d %H:%M %Z')] hold-flip-draft: FAILED for ${what:-$target} (exit $rc): a draft hold flip may be missing; rerun: scripts/hold-flip-draft.sh ${pr:-$target}"
    echo "$line" >&2
    echo "$line" >>"$FAILED"
  elif [[ -s $FAILED ]]; then
    awk -v s="rerun: scripts/hold-flip-draft.sh ${pr:-$target}" 'substr($0, length($0) - length(s) + 1) != s' "$FAILED" >"$FAILED.$$"
    mv "$FAILED.$$" "$FAILED"
  fi
}
trap on_exit EXIT

# The tip of an origin branch, fetched into a ref of this run only. A fetch that updates origin/*
# fails when another process in the shared clone fetches at the same moment ("cannot lock ref
# 'refs/remotes/origin/main'", the first run after #755).
fetch_tip() { # <branch>
  local ref="$private_refs$1"
  # set -e does not reach into the $(...) this runs in.
  git_fetch -q --no-write-fetch-head --refmap= origin "+refs/heads/$1:$ref" || return 1
  git rev-parse --verify "$ref" || return 1
  git update-ref -d "$ref"
}

main_tip=""
if [[ $target =~ ^#?[0-9]+$ && ${#target} -lt 7 ]]; then
  pr="${target#\#}"
  read -r state commit < <(gh pr view "$pr" --json state,mergeCommit -q '"\(.state) \(.mergeCommit.oid // "")"')
  if [[ $state != MERGED || -z $commit ]]; then
    log "#$pr is ${state:-unknown}, not merged: nothing to flip"
    exit 0
  fi
  main_tip="$(fetch_tip main)"
else
  commit="$(git rev-parse --verify "$target^{commit}")"
  pr="$(git log -1 --format=%s "$commit" | sed -n 's/.*(#\([0-9]*\))$/\1/p')"
fi
if [[ -z $base ]]; then
  base="${main_tip:-$(fetch_tip main)}"
fi
base="$(git rev-parse --verify "$base^{commit}")"
merged="${pr:+#$pr}"
merged="${merged:-${commit:0:9}}"

# For each line of a legal file (or stdin), the holds gating it: "<line> <mode>:<hold> ...". A
# block's opening and closing lines and a gated heading's own line count as inside.
gates_by_line() {
  awk '
    function attrs_gate(text,   inner, n, parts, i) {
      if (text !~ /\{[^{}]*\}[ \t]*$/) return ""
      inner = text; sub(/.*\{/, "", inner); sub(/\}[ \t]*$/, "", inner)
      n = split(inner, parts, /[ \t]+/)
      for (i = 1; i <= n; i++) if (parts[i] ~ /^(once|until)=/) { sub(/=/, ":", parts[i]); return parts[i] }
      return ""
    }
    function current(   out, i) {
      out = ""
      for (i = 1; i <= nb; i++) if (bgate[i] != "") out = out " " bgate[i]
      for (i = 1; i <= nh; i++) if (hgate[i] != "") out = out " " hgate[i]
      return out
    }
    NR == 1 && /^---[ \t]*$/ { front = 1; print NR; next }
    front { if (/^---[ \t]*$/) front = 0; print NR; next }
    fence { print NR current(); if ($0 ~ "^[ \t>]*" fence) fence = ""; next }
    /^[ \t>]*(```|~~~)/ { line = $0; sub(/^[ \t>]*/, "", line); fence = substr(line, 1, 3); print NR current(); next }
    /^[ \t>]*:::+[ \t]*[a-z]/ {
      line = $0; sub(/^[ \t>]*/, "", line); colons = line; sub(/[^:].*/, "", colons)
      rest = substr(line, length(colons) + 1); sub(/^[ \t]+/, "", rest)
      split(rest, w, /[ \t]+/)
      nb++; bcolons[nb] = length(colons)
      bgate[nb] = (w[1] == "once" || w[1] == "until") && w[2] != "" ? w[1] ":" w[2] : ""
      print NR current(); next
    }
    /^[ \t>]*:::+[ \t]*$/ && nb > 0 {
      line = $0; gsub(/[^:]/, "", line)
      print NR current()
      if (length(line) >= bcolons[nb]) nb--
      next
    }
    nb == 0 && /^#{1,6}[ \t]/ {
      depth = $0; sub(/[^#].*/, "", depth); depth = length(depth)
      while (nh > 0 && hdepth[nh] >= depth) nh--
      nh++; hdepth[nh] = depth; hgate[nh] = attrs_gate($0)
    }
    { print NR current() }
  ' "$@"
}

# The new-side line numbers the commit added or changed in a file; for a deletion, the two lines
# around it.
touched_lines() {
  git diff -U0 "$commit^" "$commit" -- "$1" | awk '
    /^@@ / {
      split($3, n, ","); start = substr(n[1], 2); count = (2 in n) ? n[2] : 1
      if (count == 0) print start " " start + 1
      else for (i = start; i < start + count; i++) print i
    }'
}

# "<mode>:<hold>" gates of the lines the commit touched in one file; a deletion counts when both
# lines around it share the gate.
touched_gates() {
  awk '
    NR == FNR { line = $1; $1 = ""; gates[line] = $0 " "; next }
    NF == 1 { m = split(gates[$1], gs, " "); for (j = 1; j <= m; j++) print gs[j] }
    NF == 2 { m = split(gates[$1], gs, " "); for (j = 1; j <= m; j++) if (index(gates[$2], " " gs[j] " ")) print gs[j] }
  ' <(git show "$commit:$1" | gates_by_line) <(touched_lines "$1")
}

# Holds of $FLAGS at a revision, one "<hold> <released>" per line.
holds_at() { git show "$1:$FLAGS" | node -e 'const d = JSON.parse(require("fs").readFileSync(0, "utf8")); for (const [k, v] of Object.entries(d.holds ?? {})) console.log(k, v.released === true)'; }

files_holding() { # <hold>: legal files at HEAD with a block or heading for the hold
  local f
  for f in "$LEGAL_DIR"/*.md; do
    gates_by_line "$f" | grep -qE " (once|until):$1( |$)" && echo "$f"
  done
  return 0
}

mapfile -t legal_files < <(git diff --name-only "$commit^" "$commit" -- "$LEGAL_DIR" | grep '\.md$' || true)
if [[ ${#legal_files[@]} == 0 ]]; then
  log "$merged changed no legal text: no hold to flip"
  exit 0
fi

declare -A unreleased=()
while read -r key released; do [[ $released == false ]] && unreleased[$key]=1; done < <(holds_at "$base")
declare -A wanted=()
for f in "${legal_files[@]}"; do
  git cat-file -e "$commit:$f" 2>/dev/null || continue
  while read -r gate; do
    key="${gate#*:}"
    [[ -n ${unreleased[$key]:-} ]] && wanted[$key]=1
  done < <(touched_gates "$f" | sort -u)
done
if [[ ${#wanted[@]} == 0 ]]; then
  log "$merged changed legal text, but behind no hold that is still unreleased on ${base:0:9}: nothing to flip"
  exit 0
fi

work="$(mktemp -d)"

berlin() { TZ=Europe/Berlin date "$@"; }
today_iso="$(berlin +%Y-%m-%d)"
day="$((10#$(berlin +%d)))"
month="$((10#$(berlin +%m)))"
year="$(berlin +%Y)"
de_months=(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
en_months=(January February March April May June July August September October November December)
stand="$day. ${de_months[month - 1]} $year"
last_updated="$day ${en_months[month - 1]} $year"
stamp="$(berlin '+%Y-%m-%d %H:%M %Z')"

set_dates() { # <file>: the policy's date lines to today
  awk -v iso="$today_iso" -v stand="$stand" -v last="$last_updated" '
    NR == 1 && /^---[ \t]*$/ { front = 1; print; next }
    front && /^---[ \t]*$/ { front = 0; print; next }
    front && /^updated:[ \t]/ { print "updated: " iso; next }
    !front && /^Stand: [0-9]+\. [^ ]+ [0-9][0-9][0-9][0-9][ \t]*$/ { print "Stand: " stand; next }
    !front && /^Last updated: [0-9]+ [A-Za-z]+ [0-9][0-9][0-9][0-9][ \t]*$/ { print "Last updated: " last; next }
    { print }
  ' "$1" >"$1.new" && mv "$1.new" "$1"
}

release_hold() { # <hold>: holds.<hold>.released true in $FLAGS, nothing else
  awk -v key="$1" '
    /^  "holds": \{/ { inholds = 1 }
    inholds && index($0, "    \"" key "\": {") == 1 { inhold = 1 }
    inhold && /^    \}/ { inhold = 0 }
    inhold && /^      "released": false,?$/ { sub(/false/, "true"); done = 1 }
    { print }
    END { if (!done) exit 1 }
  ' "$FLAGS" >"$FLAGS.new" && mv "$FLAGS.new" "$FLAGS"
  node -e 'const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (d.holds[process.argv[2]].released !== true) process.exit(1)' "$FLAGS" "$1"
}

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

checklist_line() { # <hold> <pr>
  echo "- [$stamp] Enable checklist for hold $1: owner Snacklist Engineering Lead; flip PR #$2; open items: Legal GO, Peter yes, live check, device evidence (see docs/PUSH.md)"
}

pr_body() { # <hold>; run in the flip worktree
  local hold="$1" f note
  note="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).holds[process.argv[2]].note ?? "")' "$FLAGS" "$hold")"
  cat <<EOF
**DO NOT MERGE without Legal's GO.** Opened by \`scripts/hold-flip-draft.sh\` right after $merged merged legal text behind the hold \`$hold\`. It waits for Legal; the label \`do-not-merge\` comes off only when Legal's GO is recorded.

## The flip

- Hold: \`$hold\` (\`releases/flags.json\`: \`holds.$hold.released\` false → true; the note stays as it is. #710 rewrote push-notifications' note in Legal's wording at its flip; Legal may want the same here).
- Text it publishes: introduced or changed by $merged.
- Policy dates set to $stand / $last_updated (Europe/Berlin, the day this PR was opened). If it merges on a later day, set the date lines to that day and recompute the hashes for Legal.
- Rollouts, server switches and PostHog flags are not touched.

Legal files with a block for this hold, as on this PR's first head:

| File | sha256 |
| --- | --- |
EOF
  while read -r f; do
    [[ -n $f ]] && printf "| \`%s\` | \`%s\` |\n" "$f" "$(sha256 "$f")"
  done < <(files_holding "$hold")
  if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}\.? [A-Z][a-zä]+ [0-9]{4}' <<<"$note"; then
    printf '\nThe hold note names a date; check that it still holds:\n\n> %s\n' "$note"
  fi
  cat <<EOF

## Before merge

- [ ] Legal's hash-bound GO, or a string-check PASS, on the exact head of this PR
- [ ] Peter's yes recorded in approvals-log.md before publishing
- [ ] Once both are recorded: \`do-not-merge\` removed by hand (merge-pr.sh and legal-go-merge refuse it until then), then \`scripts/push-pr.sh\` and \`scripts/merge-pr.sh --wait <n>\`

## After deploy

- [ ] Legal's live check on snacklist.app

## Changelog
none
EOF
}

# The branch and PR for one hold, converging: open the draft if none is open, then make sure the
# NEEDS_LEAD line is on it (the branch starts from main, so a line main has counts).
flip_hold() {
  local hold="$1" branch="hold-flip/$1" title open remote_sha flip="$work/flip"
  title="Hold flip: $hold (draft, waits for Legal GO)"
  open=""
  if [[ $dry_run == 0 ]]; then
    open="$(gh pr list --head "$branch" --state open --json number -q '.[0].number // empty')"
  fi
  if [[ -n $open ]]; then
    log "$hold: #$open is the open flip PR"
    mention_merge "$hold" "$open"
  fi
  git worktree add -q --detach "$flip" "$base"
  (
    cd "$flip"
    if [[ -z $open ]]; then
      release_hold "$hold" || { echo "$hold: could not set holds.$hold.released in $FLAGS" >&2; exit 1; }
      while read -r f; do [[ -n $f ]] && set_dates "$f"; done < <(files_holding "$hold")
      git add -A
      git commit -q -m "$title" -m "Co-authored-by: Peter Trost <peter@petertrost.com>"
      pr_body "$hold" >"$work/body"
      if [[ $dry_run == 1 ]]; then
        log "dry run: would open the draft PR \"$title\" on $branch from ${base:0:9}"
        git --no-pager show --format= HEAD
        printf -- '--- PR body\n%s\n--- NEEDS_LEAD line (with the PR number)\n%s\n' "$(cat "$work/body")" "$(checklist_line "$hold" "<n>")"
        exit 0
      fi
      remote_sha="$(git ls-remote origin "refs/heads/$branch" | cut -f1)"
      # The lease makes a concurrent run for the same hold lose here instead of opening a second PR.
      git push -q --force-with-lease="refs/heads/$branch:$remote_sha" origin "HEAD:refs/heads/$branch"
      open="$(gh pr create --draft --base main --head "$branch" --title "$title" --body-file "$work/body" --label do-not-merge | sed -n 's|.*/pull/\([0-9]*\).*|\1|p')"
      [[ -n $open ]] || { echo "$hold: gh pr create gave no PR number" >&2; exit 1; }
      log "$hold: opened draft #$open"
    else
      [[ $dry_run == 1 ]] && exit 0
      remote_sha="$(fetch_tip "$branch")"
      git checkout -q --detach "$remote_sha"
    fi
    git checkout -q -B "$branch"
    if git grep -q "Enable checklist for hold $hold:" HEAD -- docs/NEEDS_LEAD.md; then
      log "$hold: the enable checklist line is in docs/NEEDS_LEAD.md already"
    else
      printf '\n## Enable checklist: hold %s\n\n%s\n' "$hold" "$(checklist_line "$hold" "$open")" >>docs/NEEDS_LEAD.md
      git commit -q -am "Enable checklist for hold $hold" -m "Co-authored-by: Peter Trost <peter@petertrost.com>"
    fi
    # A run that ended before this push left the branch as its working commits.
    if [[ "$(git log -1 --format=%s HEAD)" != "$title (#$open)" ]]; then
      # The edit is two generated lines in flags.json and the legal dates; CI runs on this push.
      PUSH_PR_SKIP_CHECKS=1 PUSH_PR_KEEP_DRAFT=1 scripts/push-pr.sh
    fi
    log "$hold: draft #$open carries the flip and the enable checklist line"
  )
  git worktree remove --force "$flip"
  git branch -q -D "$branch" 2>/dev/null || true
}

# A later merge that changes the hold's text again: say so once on the open PR, since Legal's GO
# has to cover it.
mention_merge() {
  local hold="$1" open="$2"
  [[ -n $pr ]] || return 0
  if gh pr view "$open" --json body,comments -q '.body, .comments[].body' | grep -qE "#$pr([^0-9]|$)"; then return 0; fi
  gh pr comment "$open" --body "#$pr changed legal text behind \`$1\` too. Legal's GO has to be on a head that contains it: rerun \`scripts/push-pr.sh\` on this branch to rebase, then recompute the hashes." >/dev/null
  log "$hold: noted #$pr on #$open"
}

status=0
for hold in $(printf '%s\n' "${!wanted[@]}" | sort); do
  log "$merged changed legal text behind the unreleased hold $hold"
  # Not `flip_hold || ...`: bash turns set -e off inside a command list that `||` tests.
  set +e
  (set -e; flip_hold "$hold")
  rc=$?
  set -e
  if [[ $rc != 0 ]]; then
    status=1
    git worktree remove --force "$work/flip" 2>/dev/null || true
    echo "hold-flip-draft: $hold failed; rerun scripts/hold-flip-draft.sh ${pr:-$commit}" >&2
  fi
done
exit "$status"
