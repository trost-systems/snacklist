#!/usr/bin/env bash
# Tests which checks scripts/push-checks.sh runs for which changed paths (--list), and that a run
# fails when a check fails or untracked files would fool one, in a scratch repository with a copy
# of it and lib.sh and stubs for scripts/lint.sh and the flutter gate. Run by the lint gate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

git init -q -b main "$tmp/repo"
mkdir -p "$tmp/repo/scripts"
cp "$REPO_ROOT"/scripts/{lib,push-checks}.sh "$tmp/repo/scripts/"
mkdir -p "$tmp/repo/scripts/gates"
for stub in scripts/lint.sh scripts/gates/flutter.sh; do
  printf '#!/usr/bin/env bash\n[[ ! -e %q ]] || { echo "%s: a finding" >&2; exit 1; }\n' "$tmp/fail-$(basename "$stub")" "$stub" \
    >"$tmp/repo/$stub"
  chmod +x "$tmp/repo/$stub"
done
cd "$tmp/repo"
git add -A
git -c user.name=t -c user.email=t@t commit -q -m base
base="$(git rev-parse HEAD)"

# The checks push-checks.sh lists for a commit on the base that changes these paths, space-separated.
checks_for() {
  git checkout -q --detach "$base"
  local path
  for path in "$@"; do
    mkdir -p "$(dirname "$path")"
    echo x >"$path"
  done
  git add -A
  git -c user.name=t -c user.email=t@t commit -q -m change
  scripts/push-checks.sh --list "$base" | tr '\n' ' ' | sed 's/ $//'
}
expect() {
  local want="$1"
  shift
  local got
  got="$(checks_for "$@")"
  [[ $got == "$want" ]] || fail "$*: expected '$want', got '$got'"
}

expect "lint.sh" docs/CI.md
expect "lint.sh" supabase/migrations/20990101000000_x.sql
expect "lint.sh actionlint" .github/workflows/ci.yml
expect "lint.sh shellcheck" scripts/gates/lint.sh
expect "lint.sh shellcheck" .githooks/pre-push
expect "lint.sh" site/build.sh
expect "lint.sh typescript-pack" supabase/functions/mcp/index.ts
expect "lint.sh typescript-pack" site/scripts/gate.mjs
expect "lint.sh typescript-pack e2e-tsc" e2e/tests/mcp.spec.ts
expect "lint.sh typescript-pack e2e-tsc" e2e/package.json
expect "lint.sh typescript-pack" supabase/functions/deno.json
expect "lint.sh typescript-pack" emails/tsconfig.json
expect "lint.sh typescript-pack" supabase/functions/deno.lock
expect "lint.sh typescript-pack" .dvmrc
expect "lint.sh flutter" app/lib/main.dart
expect "lint.sh flutter" app/l10n/app_de.arb
expect "lint.sh actionlint shellcheck flutter" .github/workflows/ci.yml scripts/push-pr.sh app/pubspec.yaml

# A run, with the stubs.
checks_for docs/CI.md >/dev/null
scripts/push-checks.sh "$base" >/dev/null 2>&1 || fail "a docs change with lint.sh passing was refused"
touch "$tmp/fail-lint.sh"
if scripts/push-checks.sh "$base" >/dev/null 2>"$tmp/err"; then fail "a failing lint.sh passed"; fi
grep -q '^push-checks: failed: lint.sh ' "$tmp/err" || fail "a failing lint.sh was not named: $(cat "$tmp/err")"
rm "$tmp/fail-lint.sh"
checks_for app/lib/main.dart >/dev/null
touch "$tmp/fail-flutter.sh"
if scripts/push-checks.sh "$base" >/dev/null 2>"$tmp/err"; then fail "a failing flutter gate passed"; fi
grep -q '^push-checks: failed: flutter ' "$tmp/err" || fail "a failing flutter gate was not named: $(cat "$tmp/err")"
rm "$tmp/fail-flutter.sh"
echo x >app/lib/forgotten.dart
if scripts/push-checks.sh "$base" >/dev/null 2>"$tmp/err"; then fail "an untracked file under app/ passed"; fi
grep -q 'app/lib/forgotten.dart' "$tmp/err" || fail "the untracked file was not named: $(cat "$tmp/err")"
rm app/lib/forgotten.dart

if [[ $failures -gt 0 ]]; then
  echo "push-checks-test: $failures failed" >&2
  exit 1
fi
log "push-checks.sh picks its checks by the changed paths: all cases pass"
