#!/usr/bin/env bash
# Workflows (actionlint), shell scripts (shellcheck), the e2e TypeScript (tsc), the TypeScript lint
# pack (tool/lint/ts), the gate wiring, the CI change filter, landing, append-log merge driver, e2e gate, verify.sh, Flutter SDK, Vercel ignore step, CI download, stack logs and release scripts' tests, the
# e2e request deadline's test (e2e/deadline.test.mjs), the structural lints in scripts/lint.sh, and
# the generated files against their source: the design tokens (design/tokens/build.mjs) and the
# app icon and splash screens (design/app-icon/build.mjs), the Android widget's hex shapes
# (design/widget/build.mjs) and the item icon table with its samples (tool/item_icons/build.mjs, its
# test build.test.mjs).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$REPO_ROOT"
actionlint
shellcheck scripts/*.sh scripts/gates/*.sh scripts/backup/*.sh scripts/ci/*.sh scripts/release/*.sh scripts/checks/*.sh nexus/scripts/*.sh scripts/fg .githooks/*
(cd e2e && { [[ -d node_modules ]] || npm ci; } && npx tsc --noEmit -p .)
# emails/ is a tsc project of the TypeScript pack below; its tsc needs the package installed.
(cd emails && { [[ -d node_modules ]] || npm ci --no-audit --no-fund; })
# The TypeScript pack (tool/lint/ts/pack.ts, job 101): its own fmt and lint, then every `error` rule.
(cd tool/lint/ts && deno fmt --check && deno lint)
deno run --allow-all tool/lint/ts/strict.ts
scripts/check-gates.sh
scripts/ci-changes-test.sh
scripts/landing-test.sh
scripts/merge-append-log-test.sh
scripts/e2e-gate-test.sh
scripts/verify-test.sh
scripts/flutter-sdk-test.sh
scripts/vercel-ignore-test.sh
scripts/ci/download-test.sh
scripts/ci/stack-logs-test.sh
scripts/release/test.sh
# Node 22 before 22.18 strips the types of e2e/tests/deadline.ts only with the flag; later
# versions take the flag too.
node --experimental-strip-types --test e2e/deadline.test.mjs
scripts/lint.sh
node design/tokens/build.mjs --check
node design/app-icon/build.mjs --check
node design/widget/build.mjs --check
node --test tool/item_icons/build.test.mjs
# CI checks out depth 1 without origin/main; the REVISION rule compares the table with main's.
git rev-parse --verify --quiet 'origin/main^{commit}' >/dev/null ||
  git fetch --quiet --no-tags --depth=1 origin +refs/heads/main:refs/remotes/origin/main
node tool/item_icons/build.mjs --check
