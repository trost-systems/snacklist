# Job 344: API and MCP item operations (A1, A2, A3, A7, A10, A11, A12)

Peter's pick t1118u from job 331's additions. Job 345 takes A4, A8 and A9.

## What changed for users

An AI assistant connected over MCP, and an integration with a Snacklist API key, can now do
what the app does with an entry, not only add, tick and move it:

| # | API | MCP | Does |
| --- | --- | --- | --- |
| A1 | `PATCH /v1/items/{id}` takes `name`, `quantity`, `brand`, `properties`, `list` (plus `category`, `store` as before) | `update_item` (`toList` moves it to another list) | The app's edit: only the given fields, null or blank clears, a rename onto an open twin on the same list is refused (409 `conflict` / tool error) |
| A2 | `DELETE /v1/items/{id}` (write scope, Idempotency-Key) | `remove_items` | The app's plain delete: the household keeps what it taught the classifier (category, store) |
| A3 | (had untick and get) | `untick_items`, `get_item` | Untick by name takes the most recently ticked row of that name on the list |
| A7 | `GET /v1/lists` entries carry `default` | (had it) | Where an add without `list` lands |
| A10 | | `merge_items` (keep, merge) | The app's "Zusammenführen" (`public.merge_items`): kept keeps its name, quantities add up |
| A11 | `GET /v1/household`: `id`, `name`, `currency`, `memberCount` | | Never member names, emails or user ids |
| A12 | 402 `details: {integration: "api", unlock: "app"}` | Premium refusal `structuredContent` with `integration: "mcp"` | No link, no price |

MCP `serverInfo.version` is 1.1.0 now. The consent screen and the API key dialog say what an
assistant or a key may do: „lesen, hinzufügen, ändern, abhaken und löschen“ (was „lesen,
hinzufügen, abhaken und verschieben“), and the Claude and Alexa guides and the Bring comparison
say the same. The comparison page's "it cannot delete or rename" was about to become false.

## Where

- `supabase/functions/_shared/list.ts`: one `ItemEdit` shape and one write path (`editOpen`) for
  PATCH, `update_item` and `move_item`; `removeItems`, `untickItems`, `getItem`, `mergeItems`,
  `deleteItemById`. `moveItem` and `moveItemById` are gone.
- `supabase/functions/api/{routes,operations,handler}.ts`, `supabase/functions/mcp/tools.ts`,
  `supabase/functions/_shared/telemetry.ts` (`mcpTools`).
- Docs: `docs/API.md`, `docs/MCP.md`, `docs/api/openapi.yaml` (served by the site as
  `/openapi.yaml`), `docs/ANALYTICS.md`, the feature map `ai-assistants.md` and its writers'
  section, `docs/PRODUCT_FEATURE_MAP.md`, DECISIONS "Job 344".
- `app/l10n/app_{de,en}.arb` (`consentListAccess`, `apiScopeReadWriteBody`) and the generated
  l10n; `site/content/guides/{de,en}/{claude,alexa}.md`,
  `site/content/comparisons/de/einkaufsliste-vergleich-bring.md`.
- No migration: every path uses the database writes the app uses.

## Verified

- Live probe (job 331's `probe.ts`, extended): **239 of 239 checks as expected** against this
  branch on the local stack, fg-seeded synthetic households only. New checks per endpoint and
  tool, including another household's item (404 / tool error, row unchanged), a read-only key on
  PATCH and DELETE (403), the 402 and the MCP refusal with their details and without link or
  price, DELETE and PATCH refused under the lock with nothing changed, the household answer
  holding no email, display name or user id, and the delete keeping the category and store
  lesson, and (review 0) `merge_items` refusing two items on different lists with both rows unchanged, and (review 1) `untick_items` by name called twice with two ticked twins leaving one open row. MCP has no scopes, so wrong-scope checks are API-only. The repo's MCP smoke passed in
  both protocol revisions. Log: the job's `out/test-log.md`.
- Deno: unit tests (handler, tools, protocol, telemetry) and the FG_DB_TEST integration tests
  (171 across all `*_integration_test.ts`, new `mcp/item_ops_integration_test.ts`).
- e2e `mcp.spec.ts`: an MCP edit, untick and remove show up live in the running web app.

## Not done, or for the lead

- The PR changes ARB and consent copy, so it is not self-merged (brief rule): NEEDS_LEAD has the
  head and the sha256 of the changed files.
- The consent screen's new words reach users with the next release build of the app and web app;
  the functions deploy with main. Between the two, the old consent text names fewer actions than
  the tools can do. Merging right before a release closes the gap.
