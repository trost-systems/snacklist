# Snacklist API (v1)

A JSON-over-HTTP API for one household's shopping list, next to the MCP server
([`docs/MCP.md`](MCP.md)). It is for people who automate their list: Zapier, n8n, Home Assistant,
iOS Shortcuts, cron jobs, curl. The machine-readable contract is
[`docs/api/openapi.yaml`](api/openapi.yaml) (OpenAPI 3.1); the lint gate validates it and checks
that its paths match the function's route table.

The API and the MCP tools run the same code: `supabase/functions/_shared/list.ts` adds, lists,
ticks, edits and removes items for both, through the same database writes the app and Siri use
(`public.add_list_item`, `public.move_item`, `public.classify_item`, and the app's own updates and
deletes of `public.items`, whose triggers learn and guard against duplicates). A change there
reaches both.

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
- **Scopes**: `read` (every `GET`) and `write` (every `POST`, `PATCH` and `DELETE`). A key has
  `read` or `read` and `write`. A request outside the key's scopes gets `403 insufficient_scope`.
- **Household-bound**: a key acts as the member who created it, in the household it was created
  for, under the same row-level security as the app. It stops working when it is revoked
  (Zugänge → the key's delete button), when its creator leaves that household, or when the
  account is deleted. Ended keys are deleted 30 days later (`purge_access_tokens`, Legal N-4).
- **Other credentials do not work here.** MCP tokens, Siri credentials, OAuth access tokens and
  app sessions get `401 invalid_token`; API keys do not work on the MCP server or Siri.
- **Snacklist Premium**: the API is a Premium integration like the MCP server (Siri and Alexa
  stay free). While the server switch `integration_lock` is on, a key whose holder has no
  Premium (neither their own plan nor a grant of the key's household; another member's plan does
  not count) gets `402 premium_required` with the message "You need Snacklist Premium to use the
  API. Unlock it in the Snacklist app. Nothing was read or changed." and
  `details: {"integration": "api", "unlock": "app"}`: the API is the locked integration, and it
  unlocks in the app. The answer carries no link and no price (store rules). The key keeps working
  once its holder has Premium. While the switch is off (until the paywall release) everyone may use it.

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
| `position` | integer or null | 1-based place among the open items of its list in its store (or among those without a store), in the household's order; null for a ticked item |
| `status` | `open` or `ticked` | Ticked items leave the list |
| `addedAt` | date-time | When it was added |
| `listId` | uuid | The list it is on (`GET /v1/lists`) |

A **category** and a **store**: `{ "id", "name", "sortOrder" }`. A **list**:
`{ "id", "name", "sortOrder", "default" }`. A household has one or more lists (e.g. `Wocheneinkauf`
and `Baumarkt`); an add without `list` goes to the key owner's default list (chosen in the app,
else the first, the lowest `sortOrder`), where Siri and Alexa add too. `default` is `true` on that
list and `false` on the others.

The **household**: `{ "id", "name", "currency", "memberCount" }`. `currency` is the ISO 4217 code
the app shows prices in (e.g. `EUR`). Members' names, email addresses and user ids are never part
of it.

Fields are camelCase, like the items in the MCP tools' results.

**Order mode.** A household sorts its list in one of two ways. With `categories` (the default),
items stand in the aisle order of their categories and, inside a category, in the household's walk
order. With `learned` (switched on in the app; job 352), each store has its own order of items,
learned from the household's shopping trips and set by hand (`POST /v1/items/{id}/place`,
`PUT /v1/stores/{id}/order`); categories still exist and are the starting place of an item the
store has not seen. `position` follows the household's mode. `GET /v1/items?order=walk` shows the
list store by store in that order.

## Endpoints

| Method and path | Scope | Does |
| --- | --- | --- |
| `GET /v1/items` | read | Open items in aisle order; `store`, `category`, `list` filter; paginated |
| `GET /v1/items/{id}` | read | One item, open or ticked |
| `POST /v1/items` | write | Adds 1 to 50 items (batch) |
| `POST /v1/items/{id}/tick` | write | Ticks an item (bought) |
| `POST /v1/items/{id}/untick` | write | Puts a ticked item back on the list |
| `PATCH /v1/items/{id}` | write | Edits an open item: name, quantity, brand, properties, list, category, store |
| `POST /v1/items/{id}/place` | write | Puts an open item right before or after another |
| `DELETE /v1/items/{id}` | write | Removes an item, open or ticked |
| `GET /v1/items/recent` | read | Recently ticked items, the app's „Zuletzt verwendet“ |
| `GET /v1/suggestions` | read | What the household usually buys, ranked like the app's suggestions; `prefix` filter |
| `GET /v1/categories` | read | The household's categories in aisle order |
| `GET /v1/stores` | read | The household's stores |
| `POST /v1/stores` | write | Adds a store by its plain name |
| `PATCH /v1/stores/{id}` | write | Renames a store |
| `GET /v1/stores/{id}/layout` | read | A store's walk order: every category in that store's order |
| `PUT /v1/stores/{id}/layout` | write | Sets a store's walk order and the categories it does not carry |
| `PUT /v1/stores/{id}/order` | write | Sets the order of a store's open items (learned order only) |
| `GET /v1/lists` | read | The household's lists in their order, the default one marked |
| `POST /v1/lists` | write | Makes a list |
| `PATCH /v1/lists/{id}` | write | Renames a list or moves it |
| `GET /v1/household` | read | The key's household: name, currency, how many members |

### GET /v1/items

Query: `store` and `category` (an id or a name; names match like the MCP tools: any case,
umlauts optional, a unique part is enough), `list` (an id or the exact name, any case; without
it, every list's items), `limit` (1 to 100, default 50), `cursor`, `order` (`aisle`, the
default, or `walk`). With `store`, the list shows that store's items plus the ones without a store.

- `aisle` (v1's default, in every household): categories in aisle order (with `store`, that
  store's aisle order); inside a category, the household's walk order.
- `walk`: store by store in the stores' order (`GET /v1/stores`), then the items without a
  store; inside each, by `position`. This is the order the app shows in a household with the
  learned order. In v2 it becomes the default.

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
A cursor is opaque, belongs to the filter and the `order` it came with (another filter or order:
`400 invalid_cursor`) and is a place in the list, not a page number: items added or ticked
meanwhile do not shift the next page. A `walk` cursor also belongs to the household's order mode:
if the household switches between `categories` and `learned` while you page, the next request is
`400 invalid_cursor`; start again without a cursor.

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
            "similarOnList": [ { "itemId": "…", "onList": [ …items ], "total": 1 } ] } }
```

`201` when something was added, else `200`. An item already on that list is not added twice and
comes back under `alreadyOnList`. A spelling variant or synonym of an open item ("Karotten" next to
"Möhren") is added and reported under `similarOnList`: `itemId` is the new item, `onList` the
similar open items, at most three (the oldest first), and `total` how many there are. Nothing is
merged (the MCP tool `merge_items` does that on the user's word; the API has no merge yet).
Items are added in order in one transaction: an unknown `store`, `category` or `list` anywhere fails
the whole batch with `422` and adds nothing. So does a batch whose adds take longer than 5 seconds
together (`503 timeout`). Each add looks through the list's open items, so on a list with many
hundreds of them send fewer items per request.

### POST /v1/items/{id}/tick, POST /v1/items/{id}/untick

No body. Returns `{ "data": item }`. Ticking a ticked item, or unticking an open one, changes
nothing and returns the item: both are safe to repeat. Ticks through the API are marked as an
agent's: they never make a shopping trip and never teach the learned order, which only ticks in the
app do.

### PATCH /v1/items/{id}

```json
{ "name": "Hafermilch", "quantity": "2", "brand": null, "category": "Kühlregal", "store": null }
```

Edits an open item like the app's edit sheet. Every field is optional, but at least one must be
there (else `400 validation_failed`, "Give at least one field to change"):

| Field | Value | Does |
| --- | --- | --- |
| `name` | 1 to 120 characters | Renames the item; taken as it is, not split like an add |
| `quantity` | up to 40 characters, or null | Menge; null or blank clears it |
| `brand` | up to 60 characters, or null | Marke; null or blank clears it |
| `properties` | up to 120 characters, or null | Eigenschaften; null or blank clears them |
| `list` | id or exact name | Moves the item to that list; it keeps its category and store |
| `category` | id or name | Moves the item to that category |
| `store` | id, name, or null | Moves the item to that store; null removes the store |

A new category or store puts the item at the end of its new group, and the household remembers
both for the next time the item is added (like a move in the app). In a household with the learned
order, an item that changes its store takes its place in the new store's order instead (the place
that store has learned for it, else where its category starts); a new category alone keeps its
place. Answers `200` with the item as
it is now. Only open items: a ticked one is `404 item_not_found`. A rename that would make the item
the twin of another open item on its list (the same name, brand and properties) is
`409 conflict`, "An open item with this name, brand and details is already on the list.", and
changes nothing.

### DELETE /v1/items/{id}

No body. Removes the item, open or ticked, and answers `200` with the item as it was. An unknown
id, or one of another household, is `404 item_not_found`. Send an `Idempotency-Key` to retry
safely: a retry with the same key gets the same `200` instead of a `404`.

A removed item is gone, like a delete in the app. What the household taught Snacklist about it
stays: the next add of the same item gets the category and store it was moved to.

### GET /v1/items/recent

Query: `list` (an id or the exact name, any case; without it, every list at once) and `limit` (1 to
50, default 20, what the app shows). The app's „Zuletzt verwendet“: ticked items, newest first,
one per thing (its newest purchase; spelling variants that share a key count as one thing) among the newest 200 ticked rows, and
none for a thing that is open on the list again. Each is an item with `status` `ticked` and
`tickedAt`, when it was ticked; its id works with `POST /v1/items/{id}/untick`.

```json
{ "data": [{ "id": "…", "name": "Milch", …, "status": "ticked", "tickedAt": "2026-11-21T17:40:12.5+00:00" }],
  "nextCursor": null }
```

### GET /v1/suggestions

Query: `prefix` (up to 60 characters; without it, every usual) and `limit` (1 to 50, default 10).
What the household usually buys, ranked like the suggestions in the app's add sheet
(`public.suggest_items`, the same function): bought often and lately first, a tick undone within 10
minutes and an item added and deleted without a purchase not counted. Things open on any list are
left out. With `prefix`, names starting with it come first, then names with a word starting with
it („br“ finds „Brot“, then „Bio-Brot“). The order is the app's; the add sheet matches more on the device
(names that contain the text, and typos), the API only these two.

```json
{ "data": [{ "name": "Milch", "quantity": "2", "uses": 14, "lastUsed": "2026-11-19T23:00:00+00:00",
             "due": true }], "nextCursor": null }
```

`uses` counts the days in the last year on which it was added or bought; `lastUsed` is the last of
them, as the start of that day in Berlin (job 352: never the time of a member's tick); `due` is
`true` when its usual interval since the last purchase is up (bought at least twice).
The prefix is a query value, so it is in the gateway's access log like a filter (see
[Privacy and logs](#privacy-and-logs)).

### POST /v1/lists, PATCH /v1/lists/{id}

```json
{ "name": "Baumarkt" }
```

`POST` makes a list after the others, like the app, and answers `201` with it. A name has 1 to 60
characters (spaces in a row become one); names need not be unique. A household has at most 50
lists, the app's limit: the 51st is `409 too_many_lists` (`details.limit`). Send an
`Idempotency-Key` to retry without making a second list.

`PATCH` takes `name` and/or `position` (0 is first; past the end is last; the lists are numbered 0,
1, 2... again) and answers `200` with the list. A member who never picked a default list in the
app has the first list as default, so moving another list first changes where their adds without
`list` go, as it does in the app. Another household's list, or none, is `404 list_not_found`.
Deleting a list (with its items) stays in the app.

### POST /v1/stores, PATCH /v1/stores/{id}

```json
{ "name": "Rewe" }
```

A store is its plain name (1 to 40 characters) and nothing else: no chain, country, store app or
logo. `POST` adds it like the app (dm, Lidl, Edeka and a Baumarkt get their aisle layout) and
answers `201`; a name the household already has (any case, umlauts folded: „rewe“, „REWE“) answers
that store with `200` and adds nothing. A household has at most 50 stores this way (the 51st is
`409 too_many_stores`; a known name still answers `200`). `PATCH` renames it; a name another store
has is `409 conflict` and changes nothing. Another household's store, or none, is
`404 store_not_found`. Deleting a store stays in the app.

### GET /v1/stores/{id}/layout, PUT /v1/stores/{id}/layout

A store's walk order: every category of the household in the order you meet them in that store,
the order `GET /v1/items?store=` shows. `hidden` marks the categories the store does not carry.

```json
{ "data": [{ "id": "…", "name": "Getränke", "sortOrder": 10, "hidden": false }, …], "nextCursor": null }
```

`PUT` sets it like the store screen in the app:

```json
{ "categories": ["Getränke", "Kühlregal"], "hidden": ["Drogerie"] }
```

`categories` (ids or names) come first, in that order; the others follow in their current order.
`hidden`, when given, is every category the store does not carry; without it they stay as they
are. At least one of the two. A category in both comes first and is hidden. A category named twice (by name and by id, say) is
`400 validation_failed`, an unknown one `422 category_not_found`. Answers the whole new order.
In a household with the learned order the walk order is only the default order for new items:
the open items' order in the store is what the household learned and what
`POST /v1/items/{id}/place` and `PUT /v1/stores/{id}/order` set.

### POST /v1/items/{id}/place

```json
{ "after": "…id of Mehl…" }
```

Exactly one of `before` and `after`: the id of another open item of the household (the anchor).
Returns `{ "data": item }` with its new `position`.

- Learned order: the item's place in its store is set by hand and kept until three trips in a
  row disagree with it. The anchor must be in the same store (or both without a store), else
  `422 anchor_in_other_store`; to change the store, `PATCH` first.
- Categories order: the item takes the anchor's store and category, like dragging it in the app.

Placing next to the same anchor again changes nothing. An anchor that is not an open item of the
household is `422 anchor_not_found`; the item itself, `404 item_not_found`. Both also hold for a
tick or delete that lands while the request runs, except that an anchor deleted then is
`404 item_not_found`.

### PUT /v1/stores/{id}/order

```json
{ "items": ["…id of Brot…", "…id of Mehl…", "…id of Eier…"] }
```

1 to 200 item ids, each once, every one an open item of that store (else
`422 items_not_in_store`, `details.items` lists them). They come first in this order, as places set
by hand; the store's other open items keep their order after them. Returns
`{ "data": [ …items ] }`: the store's open items in their new order. Only in a household with the
learned order: a `categories` household is `409 order_mode` (its order is its categories' aisle
order; place single items with `POST /v1/items/{id}/place`). Sending the same order again
changes nothing, so the request takes no `Idempotency-Key`. An unknown store is
`404 store_not_found`.

### GET /v1/categories, GET /v1/stores, GET /v1/lists

`{ "data": [ { "id", "name", "sortOrder" } ], "nextCursor": null }`; each list also carries
`"default"`, `true` for the key owner's default list. These lists are short and always come whole;
`nextCursor` is there so every list has the same shape.

### GET /v1/household

```json
{ "data": { "id": "…", "name": "Familie Brandt", "currency": "EUR", "memberCount": 3 } }
```

The household the key works in. It names no member: no names, email addresses or user ids.

## Idempotency

Every `POST` and `DELETE` takes an `Idempotency-Key` header (1 to 255 printable ASCII characters,
for example a UUID); `GET`, `PATCH` and `PUT` take none (a repeated `PATCH` or `PUT` sets the same
state again). The first successful response for a key is stored
for 24 hours, per API key, and a retry with the same key and the same request gets the stored
response again (with `Idempotent-Replayed: true`) instead of adding the items twice. The same key
with a different method, path or body gets `422 idempotency_key_reused`. Two requests with one key at the same time
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
| 400 | `invalid_cursor` | The cursor is broken, belongs to another filter or `order`, or the household changed its order mode while paging |
| 400 | `invalid_id` | The `{id}` in the path is not a UUID |
| 400 | `invalid_idempotency_key` | The key is empty, too long or not printable ASCII |
| 401 | `missing_token` | No `Authorization: Bearer` header |
| 401 | `invalid_token` | Unknown, revoked or not an API key |
| 402 | `premium_required` | The key's holder needs Snacklist Premium for the API (integration lock on); `details: {integration: "api", unlock: "app"}` |
| 403 | `insufficient_scope` | The key lacks the scope (`details.required`) |
| 404 | `not_found` | No such endpoint |
| 404 | `item_not_found` | No such item in this household (or not open, for `PATCH` and `place`) |
| 404 | `list_not_found`, `store_not_found` | The list or store in the path is not one of this household's |
| 405 | `method_not_allowed` | The path exists, the method does not (`Allow` header) |
| 409 | `order_mode` | A store order in a household that sorts by categories |
| 409 | `conflict` | A concurrent change got in the way (for example the `Idempotency-Key` was released at that moment, or a category was added while a layout was set); nothing was changed, retry. For `PATCH` on an item: the new name would duplicate an open item on the list; on a store: another store has the name. Nothing was changed, and a retry gets the same answer |
| 409 | `too_many_lists`, `too_many_stores` | The household has 50 lists or stores (`details.limit`); nothing was changed |
| 413 | `payload_too_large` | The body is over 64 KiB |
| 415 | `unsupported_media_type` | A body that is not `application/json` |
| 422 | `store_not_found`, `category_not_found`, `list_not_found` | A named store, category or list does not exist (`details.candidates`) |
| 422 | `ambiguous_store`, `ambiguous_category`, `ambiguous_list` | A name matches several (`details.candidates`) |
| 422 | `anchor_not_found` | The `before` or `after` item is not an open item of this household |
| 422 | `anchor_in_other_store` | Learned order: the `before` or `after` item is in another store |
| 422 | `items_not_in_store` | Items of a store order that are not open items of that store (`details.items`) |
| 422 | `idempotency_key_reused` | The key came with a different request |
| 429 | `rate_limited` | Over a rate limit (`Retry-After`) |
| 429 | `auth_throttled` | Too many unknown keys from this address (`Retry-After`); valid keys still work |
| 500 | `internal_error` | Our fault; retry later (`X-Request-Id` helps us find it) |
| 503 | `timeout` | The request took too long and was stopped; nothing was changed. For `POST /v1/items`, send fewer items at once; send one request at a time |
| 503 | `unavailable` | The database or the Premium check is not answering, or the household or the key is being changed at this moment (a member leaves, a role changes, an account is deleted); nothing was changed, retry later (`Retry-After`) |

## Limits

Config constants in `supabase/functions/api/limits.ts`; the database functions take them as
arguments, so that file is the one place to change them.

| Limit | Value | Counted |
| --- | --- | --- |
| Per API key | 20 requests burst, refilled at 60 a minute (one a second) | Token bucket, every authenticated request |
| Per household | 1000 requests a day (UTC) | All the household's keys together |
| Unknown keys per address | 20 per 10 minutes | Every key we have never issued; then `429 auth_throttled` for unknown keys from that address. A missing key, a revoked or otherwise ended key and a valid key never count and are never blocked, so an integration still polling with a revoked key does not block others behind the same address |
| Batch | 50 items per `POST /v1/items` | |
| Store order | 200 items per `PUT /v1/stores/{id}/order` | |
| Similar items | 3 per added item in `similarOnList` | `total` counts them all |
| Time | 5 seconds for the adds of one `POST /v1/items`, 8 seconds for any one database statement | `503 timeout`, nothing changed |
| At once | One request per member: requests with one member's keys wait for each other | One that waited 5 seconds gets `503 timeout` |
| Body | 64 KiB | `413` |
| Page size | 1 to 100, default 50 | |
| Recent, suggestions | 1 to 50; default 20 recent items, 10 suggestions | |
| Lists, stores | 50 each per household | `409 too_many_lists`, `too_many_stores` |
| Idempotency keys | kept 24 hours | |
| API keys | 10 active per member | `create_api_token` refuses an 11th (`too_many_tokens`); with the API switched off it refuses all (`api_disabled`) |

Every response says where the caller stands:

- `X-RateLimit-Limit`: the size of the limit closest to running out: the key's bucket (20) or the
  household's day (1000). For an unauthenticated response, the failed-authentication budget (20).
- `X-RateLimit-Remaining`: requests left in it after this one.
- `X-RateLimit-Reset`: seconds until it is full again (the bucket refilled, the next UTC day, the
  failure window over).
- `Retry-After` (on `429` and `503 unavailable`): seconds until the next request can succeed.

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

One deliberate exception, for privacy: since job 352, `lastUsed` in `/v1/suggestions` (and MCP's
suggestions) is cut to the day (midnight, Berlin) instead of the exact time. Members can no longer
read each other's tick times, and an exact `lastUsed` would give them back to the microsecond. The
field keeps its name and type; only its precision changed.

## Privacy and logs

- Per API key the database stores: the creator, the household, a name the user chose, the SHA-256
  hash, the last four characters, the scopes, when it was created, last used and revoked.
- Rate counters: per key a fill level and a timestamp, per household a request count per UTC day,
  per address that sent unknown keys (SHA-256 of the address the gateway saw, `X-Real-IP`, salted
  in the database, never the address itself) a failure count; rows of ended windows go as new failures come. A daily job
  (`purge_api_rate`, pg_cron 03:41 UTC) deletes household days older than yesterday, failure rows
  and buckets older than a day, and idempotency records older than 24 hours.
- Idempotency records hold the stored response for 24 hours, which contains item names; they are
  deleted with the key, the household or the account (cascade) and by the daily job.
- The function logs one line per request: request id, method, route template (`/v1/items/{id}`,
  never the id or a query value), status, duration, the key's id. Never a body, a name, a header
  value or an address. Errors go to the functions' error tracking with the template words only
  (`_shared/telemetry.ts`).
- Every answer carries `Cache-Control: no-store` (no shared cache keeps a list) and
  `X-Content-Type-Options: nosniff`.
- The gateway in front of the function keeps its own access log: each request's URL with its query
  string, so a `store`, `category` or `list` filter, a cursor (which carries the filter) and a
  suggestions `prefix` (the start of an item name) appear there.
  Send the key in the `Authorization` header only; in a URL it is refused and would stay in that
  log.

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
- **Merging items**, which the MCP tool `merge_items` does for assistants.
- **Deleting a list or a store**: it takes its items or its place on items with it, so it stays a
  decision in the app.
