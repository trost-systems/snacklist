# Snacklist API (v1)

A JSON-over-HTTP API for one household's shopping list, next to the MCP server
([`docs/MCP.md`](MCP.md)). It is for people who automate their list: Zapier, n8n, Home Assistant,
iOS Shortcuts, cron jobs, curl. The machine-readable contract is
[`docs/api/openapi.yaml`](api/openapi.yaml) (OpenAPI 3.1); the lint gate validates it and checks
that its paths match the function's route table.

The API and the MCP tools run the same code: `supabase/functions/_shared/list.ts` adds, lists,
ticks and moves items for both, through the same database functions the app and Siri use
(`public.add_list_item`, `public.move_item`, `public.classify_item`). A change there reaches both.

- Function: `supabase/functions/api/` (`index.ts`, `handler.ts`, `routes.ts`, `limits.ts`).
- Database: `supabase/migrations/20261102130000_public_api.sql` (API keys, rate counters,
  idempotency records, the integration lock for `api`), tests in `supabase/tests/api.test.sql`.
- Server switch: `public.app_switches.public_api`, off after the migrations
  (`supabase/migrations/20261102200000_public_api_switch.sql`, tests in
  `supabase/tests/public_api_switch.test.sql`). See [Switched off](#switched-off).
- App: More → Zugänge → "API", shown only while the PostHog flag `public-api` is on.

## Switched off

The API runs only on a server where `app_switches.public_api` is on. The migrations add it off,
so a new database, the local stack and production start without the API. While it is off:

- every request answers `404 not_found`, the same answer as an unknown path, without rate
  headers. Nothing is read, counted or written, and no key is marked as used;
- the app cannot create API keys: `create_api_token` raises `api_disabled` (SQLSTATE `42501`) and
  the app shows "Die API ist noch nicht freigeschaltet.";
- members can still list and revoke the keys they have. MCP, Siri and Alexa do not read the
  switch.

To turn the API on in production (project `jdwqrallbpdbshrdhenk`), run this as the service role,
in the dashboard's SQL editor or through the Management API:

```sql
update public.app_switches set enabled = true where key = 'public_api';
```

Then turn on the PostHog flag `public-api`, which shows the API section in the app. Setting
`enabled = false` switches the API off again. Keys made in between stay and work again when it is
back on.

## Base URL

```
https://<project-ref>.supabase.co/functions/v1/api/v1
```

Production: `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/api/v1`. A short public
domain (for example `api.snacklist.app`, a rewrite like `mcp-proxy/`) needs Peter's OK and is not
set up (NEEDS_LEAD "Job 73").

## Authentication

Every request carries an API key:

```
Authorization: Bearer fgp_…
```

- **API keys** are personal access tokens of kind `api`. Create one in the app under More →
  Zugänge → API ("API-Schlüssel erstellen"), only from the app's own sign-in: an OAuth-connected
  app or another key cannot create one. The app shows the key once; the database keeps only its
  SHA-256 hash and its last four characters.
- **Scopes**: `read` (every `GET`) and `write` (every `POST` and `PATCH`). A key has `read` or
  `read` and `write`. A request outside the key's scopes gets `403 insufficient_scope`.
- **Household-bound**: a key acts as the member who created it, in the household it was created
  for, under the same row-level security as the app. It stops working when it is revoked
  (Zugänge → the key's delete button), when its creator leaves that household, or when the
  account is deleted. Ended keys are deleted 30 days later (`purge_access_tokens`, Legal N-4).
- **Other credentials do not work here.** MCP tokens, Siri credentials, OAuth access tokens and
  app sessions get `401 invalid_token`; API keys do not work on the MCP server or Siri.
- **Snacklist Premium**: the API is a Premium integration like the MCP server (Siri and Alexa
  stay free). While the server switch `integration_lock` is on, a household without Premium gets
  `402 premium_required`; nothing is read or changed, the key keeps working once the household
  unlocks. While the switch is off (until the paywall release) every household may use it.

OAuth access for third-party apps is not part of v1 (see "Later").

## Resources

An **item** (an entry on the list):

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | uuid | Stable id |
| `name` | string | What to buy, e.g. `Windeln` |
| `brand` | string or null | Marke, e.g. `Pampers` |
| `properties` | string or null | Eigenschaften, comma-separated, e.g. `Größe 3, Big Pack` |
| `quantity` | string or null | Menge, e.g. `2` or `500 g` |
| `category` | string | Category name (aisle), e.g. `Drogerie` |
| `categoryId` | uuid | |
| `store` | string or null | Store name, e.g. `dm`; null: buyable anywhere |
| `storeId` | uuid or null | |
| `status` | `open` or `ticked` | Ticked items leave the list |
| `addedAt` | date-time | When it was added |
| `listId` | uuid | The list it is on (`GET /v1/lists`) |

A **category**, a **store** and a **list**: `{ "id", "name", "sortOrder" }`. A household has one
or more lists (e.g. `Wocheneinkauf` and `Baumarkt`); an add without `list` goes to the key owner's
default list (chosen in the app, else the first, the lowest `sortOrder`), where Siri and Alexa add
too.

Fields are camelCase, like the MCP tools' results.

## Endpoints

| Method and path | Scope | Does |
| --- | --- | --- |
| `GET /v1/items` | read | Open items in aisle order; `store`, `category`, `list` filter; paginated |
| `GET /v1/items/{id}` | read | One item, open or ticked |
| `POST /v1/items` | write | Adds 1 to 50 items (batch) |
| `POST /v1/items/{id}/tick` | write | Ticks an item (bought) |
| `POST /v1/items/{id}/untick` | write | Puts a ticked item back on the list |
| `PATCH /v1/items/{id}` | write | Moves an open item to another category and/or store |
| `GET /v1/categories` | read | The household's categories in aisle order |
| `GET /v1/stores` | read | The household's stores |
| `GET /v1/lists` | read | The household's lists in their order |

### GET /v1/items

Query: `store` and `category` (an id or a name; names match like the MCP tools: any case,
umlauts optional, a unique part is enough), `list` (an id or the exact name, any case; without
it, every list's items), `limit` (1 to 100, default 50), `cursor`. With
`store`, the list shows that store's items plus the ones without a store, in that store's aisle
order; inside a category, the household's walk order.

```json
{
  "data": [{ "id": "…", "name": "Milch", "brand": null, "properties": "1,5 %", "quantity": "2",
             "category": "Kühlregal", "categoryId": "…", "store": null, "storeId": null,
             "status": "open", "addedAt": "2026-11-02T08:00:00.123456+00:00", "listId": "…" }],
  "counts": { "open": 12, "checkedLast24h": 3 },
  "nextCursor": "eyJ2IjoxLC…"
}
```

`counts` is always the whole list's (with `list`, that list's; without, every list's), whatever
the store or category filter. `nextCursor` is null on the last page.
A cursor is opaque, belongs to the filter it came with (another filter: `400 invalid_cursor`) and
is a position, not a page number: items added or ticked meanwhile do not shift the next page.

### POST /v1/items

```json
{ "items": [ { "name": "Windeln Pampers Größe 3" }, { "name": "Gurken", "quantity": "2",
               "store": "Lidl" } ], "list": "Wocheneinkauf" }
```

`list` (optional, an id or the exact name, any case): the list the items go to; without it, the
key owner's default list in the household (chosen in the app, else the first list; job 207).

Per item: `name` (1 to 120 characters, required), `quantity` (up to 40), `brand` (up to 60),
`properties` (up to 120), `category` and `store` (an id or a name, up to 60). The name is split
like everywhere in Snacklist ("2 Gurken" is name `Gurken`, quantity `2`); a given `quantity`,
`brand` or `properties` replaces the parsed one. A given `category` is learned like a correction in
the app. Without `store`, the item gets the store it was last bought in, an own brand's store
(Balea → dm) or dm for drugstore items.

```json
{ "data": { "added": [ …items ], "alreadyOnList": [ …items ],
            "similarOnList": [ { "itemId": "…", "onList": [ …items ] } ] } }
```

`201` when something was added, else `200`. An item already on that list is not added twice and
comes back under `alreadyOnList`. A spelling variant or synonym of an open item ("Karotten" next to
"Möhren") is added and reported under `similarOnList` (`itemId`: the new item). Nothing is merged.
Items are added in order in one transaction: an unknown `store`, `category` or `list` anywhere fails
the whole batch with `422` and adds nothing.

### POST /v1/items/{id}/tick, POST /v1/items/{id}/untick

No body. Returns `{ "data": item }`. Ticking a ticked item, or unticking an open one, changes
nothing and returns the item: both are safe to repeat.

### PATCH /v1/items/{id}

```json
{ "category": "Kühlregal", "store": null }
```

At least one of `category` (id or name) and `store` (id, name, or null to remove the store). The
item goes to the end of its new group; the household remembers both for the next time the item is
added (like a move in the app). Only open items: a ticked one is `404 item_not_found`.

### GET /v1/categories, GET /v1/stores, GET /v1/lists

`{ "data": [ { "id", "name", "sortOrder" } ], "nextCursor": null }`. These lists are short and
always come whole; `nextCursor` is there so every list has the same shape.

## Idempotency

Every `POST` takes an `Idempotency-Key` header (1 to 255 printable ASCII characters, for example
a UUID). The first successful response for a key is stored for 24 hours, per API key, and a retry
with the same key and the same request gets the stored response again (with
`Idempotent-Replayed: true`) instead of adding the items twice. The same key with a different
method, path or body gets `422 idempotency_key_reused`. Two requests with one key at the same time
are serialised: the second waits for the first and gets its response. An error response stores
nothing (the request changed nothing), so a retry with the same key runs again.

## Errors

Every error has the same body:

```json
{ "error": { "code": "store_not_found", "message": "Store \"Rewe\" not found.",
             "details": { "candidates": ["dm", "Lidl"] } } }
```

`code` is the contract; `message` is English text for a developer and may change. `details` is
optional.

| Status | `code` | When |
| --- | --- | --- |
| 400 | `invalid_json` | The body is not JSON |
| 400 | `validation_failed` | A field is missing, too long, of the wrong type, or unknown (`details.issues`) |
| 400 | `invalid_cursor` | The cursor is broken or belongs to another filter |
| 400 | `invalid_id` | The `{id}` in the path is not a UUID |
| 400 | `invalid_idempotency_key` | The key is empty, too long or not printable ASCII |
| 401 | `missing_token` | No `Authorization: Bearer` header |
| 401 | `invalid_token` | Unknown, revoked or not an API key |
| 402 | `premium_required` | The household needs Snacklist Premium for the API (integration lock on) |
| 403 | `insufficient_scope` | The key lacks the scope (`details.required`) |
| 404 | `not_found` | No such endpoint |
| 404 | `item_not_found` | No such item in this household (or not open, for `PATCH`) |
| 405 | `method_not_allowed` | The path exists, the method does not (`Allow` header) |
| 409 | `conflict` | The change clashes with the list's current state (for example the item is already open twice) |
| 413 | `payload_too_large` | The body is over 64 KiB |
| 415 | `unsupported_media_type` | A body that is not `application/json` |
| 422 | `store_not_found`, `category_not_found`, `list_not_found` | A named store, category or list does not exist (`details.candidates`) |
| 422 | `ambiguous_store`, `ambiguous_category`, `ambiguous_list` | A name matches several (`details.candidates`) |
| 422 | `idempotency_key_reused` | The key came with a different request |
| 429 | `rate_limited` | Over a rate limit (`Retry-After`) |
| 429 | `auth_throttled` | Too many unknown keys from this address (`Retry-After`); valid keys still work |
| 500 | `internal_error` | Our fault; retry later (`X-Request-Id` helps us find it) |
| 503 | `unavailable` | The database or the Premium check is not answering; retry later (`Retry-After`) |

## Limits

Config constants in `supabase/functions/api/limits.ts`; the database functions take them as
arguments, so that file is the one place to change them.

| Limit | Value | Counted |
| --- | --- | --- |
| Per API key | 20 requests burst, refilled at 60 a minute (one a second) | Token bucket, every authenticated request |
| Per household | 1000 requests a day (UTC) | All the household's keys together |
| Unknown keys per address | 20 per 10 minutes | Every key we have never issued; then `429 auth_throttled` for unknown keys from that address. A missing key, a revoked or otherwise ended key and a valid key never count and are never blocked, so an integration still polling with a revoked key does not block others behind the same address |
| Batch | 50 items per `POST /v1/items` | |
| Body | 64 KiB | `413` |
| Page size | 1 to 100, default 50 | |
| Idempotency keys | kept 24 hours | |
| API keys | 10 active per member | `create_api_token` refuses an 11th (`too_many_tokens`); with the API switched off it refuses all (`api_disabled`) |

Every response says where the caller stands:

- `X-RateLimit-Limit`: the size of the limit closest to running out: the key's bucket (20) or the
  household's day (1000). For an unauthenticated response, the failed-authentication budget (20).
- `X-RateLimit-Remaining`: requests left in it after this one.
- `X-RateLimit-Reset`: seconds until it is full again (the bucket refilled, the next UTC day, the
  failure window over).
- `Retry-After` (on `429` and `503`): seconds until the next request can succeed.

A refused request (`429`) does not count against the limits. Every other authenticated request
does, errors included: a `400`, `403` or `404` uses up a request like a `200`. `X-Request-Id` (a UUID) comes with every response;
the rate headers are missing only on a `503` from a database that could not count the request
and while the API is [switched off](#switched-off).

## Versioning

The version is in the path. Within v1, changes are additive only: new endpoints, new response
fields, new error codes, new optional request fields. Clients should ignore unknown response
fields. Requests are strict (unknown fields are a `400`), so a new optional request field never
changes what an old request means. A breaking change gets `/v2`, and v1 keeps running alongside
it with a deprecation notice in this document and in a `Deprecation` header.

## Privacy and logs

- Per API key the database stores: the creator, the household, a name the user chose, the SHA-256
  hash, the last four characters, the scopes, when it was created, last used and revoked.
- Rate counters: per key a fill level and a timestamp, per household a request count per UTC day,
  per address that sent unknown keys (SHA-256 of the address the gateway saw, `X-Real-IP`, never
  the address itself) a failure count; rows of ended windows go as new failures come. A daily job
  (`purge_api_rate`, pg_cron 03:41 UTC) deletes household days older than yesterday, failure rows
  and buckets older than a day, and idempotency records older than 24 hours.
- Idempotency records hold the stored response for 24 hours, which contains item names; they are
  deleted with the key, the household or the account (cascade) and by the daily job.
- The function logs one line per request: request id, method, route template (`/v1/items/{id}`,
  never the id or a query value), status, duration, the key's id. Never a body, a name, a header
  value or an address. Errors go to the functions' error tracking with the template words only
  (`_shared/telemetry.ts`).

## Examples

```sh
API=https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/api/v1
KEY=fgp_…   # from the app, Zugänge → API

curl -s "$API/items?store=dm" -H "Authorization: Bearer $KEY"

curl -s "$API/items" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" -d '{"items":[{"name":"2 Gurken"},{"name":"Milch"}]}'

curl -s -X POST "$API/items/<id>/tick" -H "Authorization: Bearer $KEY"
```

## Later (not in v1)

- **OAuth for third-party apps**: Supabase's OAuth server already serves the MCP connectors;
  an integration like Zapier's would register as a client and get `read`/`write` scopes there.
- **Webhooks** (outgoing events such as "item added"), so automations need not poll.
- **A public domain** such as `api.snacklist.app` (Vercel rewrite like `mcp-proxy/`).
- **Editing names and quantities** (`PATCH` of `name`, `quantity`, `brand`, `properties`).
