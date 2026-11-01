#!/usr/bin/env bash
# Workflows (actionlint), shell scripts (shellcheck), the e2e TypeScript (tsc), the gate wiring,
# the landing, e2e gate and release scripts' tests, the structural lints in scripts/lint.sh, and
# the generated files against their source: the design tokens (design/tokens/build.mjs).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$REPO_ROOT"
actionlint
shellcheck scripts/*.sh scripts/gates/*.sh scripts/backup/*.sh scripts/release/*.sh scripts/fg .githooks/*
(cd e2e && { [[ -d node_modules ]] || npm ci; } && npx tsc --noEmit -p .)
scripts/check-gates.sh
scripts/landing-test.sh
scripts/e2e-gate-test.sh
scripts/release/test.sh
scripts/lint.sh
node design/tokens/build.mjs --check
