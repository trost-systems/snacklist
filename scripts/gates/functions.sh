#!/usr/bin/env bash
# Edge functions, the classifier dictionary (job 2), the deploy tooling (job 07) and the analytics
# metrics with their HogQL (job 19), the store product scripts (job 25) and the waitlist invite
# script (job 82): Deno fmt, lint, tests.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
(cd "$REPO_ROOT/supabase/functions" && deno fmt --check && deno lint && deno test --allow-env --allow-net)
(cd "$REPO_ROOT/supabase/classifier" && deno fmt --check && deno lint && deno test --allow-read)
(cd "$REPO_ROOT/supabase/deploy" && deno fmt --check && deno lint && deno test --allow-read)
(cd "$REPO_ROOT/analytics" && deno fmt --check && deno lint && deno test --allow-read)
(cd "$REPO_ROOT/scripts/iap" && deno fmt --check && deno lint && deno test --allow-read)
(cd "$REPO_ROOT/scripts/waitlist" && deno fmt --check && deno lint && deno test)
