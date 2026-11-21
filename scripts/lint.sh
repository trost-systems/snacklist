#!/usr/bin/env bash
# Structural lints for mistakes this project already made (CLAUDE.md, "Lint rules"): the Hummlist
# name guard, the ast-grep rules and their tests, then the migration and RLS guards. Runs in CI and
# in verify.sh.
# Usage: scripts/lint.sh [base-ref]   (default origin/main, fetched when missing)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

# The rule snapshots and squawk's findings depend on the exact versions, so the box runs CI's.
for tool in AST_GREP SQUAWK; do
  pinned="$(sed -n "s/^  ${tool}_VERSION: //p" .github/workflows/ci.yml)"
  bin="$(tr '[:upper:]_' '[:lower:]-' <<<"$tool")"
  have="$("$bin" --version 2>/dev/null | awk '{print $2}' || true)"
  if [[ "$have" != "$pinned" ]]; then
    echo "$bin ${have:-missing}, but CI pins $pinned (.github/workflows/ci.yml): run scripts/bootstrap.sh" >&2
    exit 1
  fi
done

log "merge conflict markers"
# A 3-way apply that stopped on a conflict leaves its markers staged (job 169b W2 shipped two
# feature docs with them; no other gate reads those files).
if git grep -nE '^(<<<<<<<|>>>>>>>)( |$)' -- . ':!*.png' ':!*.jpg' ':!*.gif' ':!*.mp4' ':!*.webm' ':!*.woff2' ':!*.ttf'; then
  echo "lint: merge conflict markers above: resolve them (keep both sides' meaning), then git add" >&2
  exit 1
fi
log "no Hummlist"
# The product is Snacklist (job 174); scripts/checks/hummlist-allow.txt lists the files that keep
# the old name and why.
scripts/checks/no-hummlist-test.sh
scripts/checks/no-hummlist.sh
log "ast-grep rule tests"
scripts/ast-grep.sh test
log "ast-grep scan"
scripts/ast-grep.sh

base="${1:-origin/main}"
if ! git rev-parse -q --verify "$base^{commit}" >/dev/null && [[ "$base" == origin/main ]]; then
  git fetch -q --no-tags --depth=1 origin main:refs/remotes/origin/main
fi
log "iOS deployment target"
scripts/ios-deployment-target.py
python3 scripts/ios-deployment-target-test.py
log "Siri phrases"
deno run --allow-read scripts/siri-phrases.ts
log "SiriKit example phrases"
scripts/siri-vocabulary.py app/ios
python3 scripts/siri-vocabulary-test.py
log "App Shortcuts bundle check"
python3 scripts/app-shortcuts-bundle-test.py

log "AI brand names"
deno run --allow-read scripts/brand-names.ts
deno test -q --config scripts/deno.json --allow-read --allow-write scripts/brand-names_test.ts
log "workflow hardening"
deno run --allow-read --config scripts/deno.json scripts/workflow-hardening.ts
deno test -q --config scripts/deno.json --allow-read --allow-write scripts/workflow-hardening_test.ts
log "pinned dependencies"
deno run --frozen --allow-read scripts/pinned-deps.ts
deno test -q --frozen --config scripts/deno.json --allow-read --allow-write scripts/pinned-deps_test.ts
log "retailer registry"
# Job 313: supabase/retailers/retailers.json is valid and the newest retailers migration holds its rows.
deno run --allow-read scripts/retailers.ts --check
deno test -q --config scripts/deno.json --allow-read scripts/retailers_test.ts
log "mcp.snacklist.app routes"
deno test -q --config scripts/deno.json --allow-read scripts/mcp-proxy-routes_test.ts
log "import direction"
# Job 305: core, feature and shell folders in app/lib, with the baseline of older imports.
deno run --allow-read --allow-run=git scripts/import-direction.ts "$base"
deno test -q --config scripts/deno.json --allow-read --allow-write scripts/import-direction_test.ts

log "schema check against $base"
# The check before its unit tests: a bad migration fails the test over the repository's own
# migrations too, and the check's message is the one that says what to do.
deno run --allow-read --allow-run=git,squawk supabase/checks/schema_check.ts "$base"
log "schema check tests"
(cd supabase/checks && deno fmt --check -q && deno lint -q && deno test -q --allow-read --allow-write --allow-run=squawk,git)
log "trip detection simulator tests (job 351)"
(cd docs/research/351-trip-detection && deno fmt --check -q && deno lint -q && deno test -q --allow-read)
