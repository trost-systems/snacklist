#!/usr/bin/env bash
# Migrations apply to a fresh database, pgTAP passes, the classifier sweep holds, the classifier's
# word list and latency stay within Spec #8's targets (job 32a), db lint is clean,
# and a backup restores to identical data (scripts/backup/drill.sh, docs/BACKUP.md).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$REPO_ROOT"
if stack_running; then
  db_reset
else
  supabase_up
fi
supabase test db
# Job 21: Peter's Monday feedback queries, exactly as docs/FEEDBACK.md has it, on fake notes.
scripts/feedback-monday.sh
supabase/classifier/sweep.sh
supabase/classifier/wordlist.sh
supabase/classifier/latency.sh
# Jobs 61, 274: the catalog the app bundles (classifier rows, brands, the parser's vocabulary) is current.
supabase/classifier/client_catalog.sh --check
# Job 59: suggest_entries with fuzzy matching stays under 50 ms p95 on a 5000-item household.
supabase/bench/suggest_latency.sh
# The functions' code against this stack: every *_integration_test.ts under supabase/functions, each
# with what it proves in its header. A new one runs without a line here (deno expands the pattern).
# Under another name it would run in no gate: the functions gate skips what reads FG_DB_TEST.
if misnamed="$(git grep -l FG_DB_TEST -- 'supabase/functions/*.ts' | grep -v '_integration_test\.ts$')"; then
  echo "reads FG_DB_TEST, so only the db gate runs it, and only as *_integration_test.ts: $misnamed" >&2
  exit 1
fi
db_port="$(sed -n '/^\[db\]/,/^\[/ s/^port = \([0-9]*\)$/\1/p' supabase/config.toml)"
stack_env="$(supabase status -o env 2>/dev/null)"
stack_value() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" <<<"$stack_env"; }
(cd supabase/functions && FG_DB_TEST=1 SUPABASE_DB_URL="postgresql://postgres:postgres@127.0.0.1:$db_port/postgres" \
  SUPABASE_URL="$(stack_value API_URL)" SUPABASE_ANON_KEY="$(stack_value PUBLISHABLE_KEY)" \
  SUPABASE_SERVICE_ROLE_KEY="$(stack_value SERVICE_ROLE_KEY)" \
  deno test --allow-env --allow-net --allow-read '**/*_integration_test.ts')
supabase db lint --local --fail-on warning
scripts/backup/drill.sh

# Job 18: fixtures against this stack: two scenario runs seed and pass their checks, cannot see
# each other through RLS, and tear down to zero rows; a run with a lost manifest is still removed.
fg_on_repo_stack
(cd .cursor/skills/verify-family-groceries/cli && FG_INTEGRATION=1 deno test --allow-all fixtures_integration_test.ts)
