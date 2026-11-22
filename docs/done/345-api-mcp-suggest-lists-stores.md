# Job 345: API and MCP additions A4, A8, A9

Merged as: the next commit on main after #605 (job 344, merged as 649493e7).

## What was built

For people who connect scripts or AI assistants to Snacklist. An integration can now ask what the
household usually buys and what was ticked lately, make and rename lists, add and rename stores and
set a store's aisle order, all through the app's own database functions.

| | API (key with the scope) | MCP |
| --- | --- | --- |
| A4 recent | `GET /v1/items/recent?list=&limit=` (read) | `list_recent` |
| A4 usuals | `GET /v1/suggestions?prefix=&limit=` (read), `public.suggest_items` | `suggest_items` |
| A8 lists | `POST /v1/lists`, `PATCH /v1/lists/{id}` (name, position) (write) | `create_list`, `rename_list` (switch, off) |
| A9 stores | `POST /v1/stores`, `PATCH /v1/stores/{id}` (write) | `add_store`, `rename_store` (switch, off) |
| A9 walk order | `GET /v1/stores/{id}/layout` (read), `PUT /v1/stores/{id}/layout` (write) | `list_categories` with `store`; `set_store_layout` (switch, off) |

- Shared logic: `supabase/functions/_shared/list.ts` (`recentItems`, `usuals`, `listEntries`,
  `createList`, `changeList`, `addStore`, `renameStore`, `storeLayout`, `setStoreLayout`).
- API: `api/routes.ts`, `api/operations.ts`, `api/handler.ts` (PUT, new error mapping),
  `api/errors.ts` (`too_many_lists`, `too_many_stores`), `api/limits.ts`.
- MCP: `mcp/tools.ts` (seven tools, `Switches`), `mcp/handler.ts` (`readSwitches`, per request,
  fails closed), server version 1.2.0.
- Migration `20261121222637_mcp_lists_stores_switch.sql`: `app_switches.mcp_lists_stores`, off.
- Docs: `docs/API.md`, `docs/MCP.md`, `docs/api/openapi.yaml` (1.2.0, served on the site),
  `docs/ANALYTICS.md`, `docs/PRODUCT_FEATURE_MAP.md`, `docs/DECISIONS.md` ("Job 345"), the feature
  map (`ai-assistants.md`, FEATURES-FOR-WRITERS), the Claude guides (two example asks, DE and EN).
- Journey `.cursor/skills/verify-snacklist/journeys/api-lists-stores.mjs`.

## Rules kept

Same handler, so the same keys, scopes (reads `read`, writes `write`), household isolation, rate
limits, Premium gate (402 with `{integration, unlock: "app"}`) and error shape. POSTs take an
Idempotency-Key. Lists: the app's cap of 50 (`create_list`). Stores: plain names only, strict
bodies, no chain/country/app field; cap 50 for integrations. Another household's list or store in a
path is 404, its name in a body or query 422.

## Legal

The MCP list tools (A8) are behind the switch, as the brief says. Deviation: the MCP store tools
(A9) are behind it too, since privacy §7's MCP paragraph names entries only and stores are no
entries. Proposed §7 text (DE+EN, old -> new) in NEEDS_LEAD "Job 345: Legal text for A8 MCP". No
change to site/content/legal/* or any ARB file in this job.

## How to verify

- `cd supabase/functions && deno test --allow-env --allow-net --allow-read api/ mcp/` (unit).
- With a local stack: `FG_DB_TEST=1 SUPABASE_DB_URL=... deno test ... api/api_integration_test.ts
  mcp/lists_stores_integration_test.ts` (db gate runs them).
- The probe: `~/groceries-ops/jobs/345-api-mcp-suggest-lists-stores/out/run.sh` (local stack only).
- The app: `.cursor/skills/verify-snacklist/journeys/api-lists-stores.mjs` after `helpers/launch.sh`.

## Results

- Probe: 305 of 305 checks as expected, 68 of them new (every new route and tool: happy path,
  read-only key 403, another household's list/store 404 or tool error, the cap, a chain field
  refused, the Premium lock 402, the API switched off 404, the MCP switch off (absent, unknown tool,
  nothing written) and on). MCP smoke: all checks passed in 2025-11-25 and 2026-07-28.
- Unit and integration tests: 284 passed (`api/`, `mcp/` and every `*_integration_test.ts`); two mutations
  (switch read always on, recent without the "open again" rule) each failed their tests.
- The app (release web build, local stack): Rewe's items in the order set through the API, the
  ticked item under „Zuletzt verwendet“, the new list in the switcher (docs/screenshots/345/).

## Open

- The MCP switch waits on Legal (NEEDS_LEAD).
- The API key dialog's „Lesen und schreiben“ sentence (ARB `apiScopeReadWriteBody`) still names
  only items; proposed copy in NEEDS_LEAD "Job 345 review 0" for the lead's copy review.
- An independent review of the diff found no isolation, scope or switch problem; its three small
  findings are fixed or documented (DECISIONS "Job 345" 10).

## Review 0 (FIX), addressed

- Two-household isolation tests for every new route and tool (API: key's user in both households;
  MCP: OAuth with and without `household`). Mutations that drop the household filter from
  `recentItems`, `lists` or `stores` fail them (each 1 to 3 tests).
- Key dialog copy: proposed in NEEDS_LEAD, no ARB change.
- `recentItems` limits before folding; docs on suggestion matching and a category both first and
  hidden; FEATURES-FOR-WRITERS says the API is on; the probe revokes its keys at the end.
