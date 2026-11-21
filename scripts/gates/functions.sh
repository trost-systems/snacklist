#!/usr/bin/env bash
# Edge functions, the classifier dictionary (job 2), the deploy tooling (job 07) and the analytics
# metrics with their HogQL (job 19), the store product scripts (job 25), the Alexa operator
# scripts (job 91), the waitlist invite script (job 82), the DSA decision mail script (job 275) and the
# PostHog flag sync (job 332):
# Deno fmt, lint, tests.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
(cd "$REPO_ROOT/supabase/functions" && deno fmt --check && deno lint && deno test --frozen --allow-env --allow-net --allow-read=../tests)
(cd "$REPO_ROOT/supabase/classifier" && deno fmt --check && deno lint && deno test --frozen --allow-read)
(cd "$REPO_ROOT/supabase/deploy" && deno fmt --check && deno lint && deno test --frozen --allow-read)
(cd "$REPO_ROOT/analytics" && deno fmt --check && deno lint && deno test --frozen --allow-read)
(cd "$REPO_ROOT/scripts/iap" && deno fmt --check && deno lint && deno test --frozen --allow-read)
(cd "$REPO_ROOT/scripts/alexa" && deno fmt --check && deno lint && deno test --frozen --allow-read --allow-run --allow-env --allow-write)
(cd "$REPO_ROOT/scripts/waitlist" && deno fmt --check && deno lint && deno test --frozen)
(cd "$REPO_ROOT/scripts/moderation" && deno fmt --check && deno lint && deno test --frozen)
(cd "$REPO_ROOT/scripts/posthog" && deno fmt --check && deno lint && deno test --frozen --allow-read=../..)
