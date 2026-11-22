# One credential for MCP and the API, and an API URL on snacklist.app (job 388, research)

Peter asked on 2026-11-22: "Can we consolidate keys and tokens, so there is only one thing that
authenticates? Also, can we change the supabase URL to snacklist.app/api? Or api.snacklist.app".
This report answers both. It changes no code and no infrastructure.

## Short answer

- **Auth: AU1.** Let every personal key work on both the MCP server and the API, with the API's
  scopes (`read`, or `read` and `write`). Existing MCP tokens become read-and-write keys and keep
  working; existing API keys keep their scopes. OAuth "Connected apps" and the Siri credential stay
  as they are. One list in More › Zugänge replaces the two. Size: M. It changes ARB strings and
  the privacy text, so it needs a Legal GO. Land it after launch.
- **Domain: AD2.** `https://api.snacklist.app/v1/...` as a Vercel rewrite, the same way
  `mcp.snacklist.app` works today. No cost, the old `supabase.co` URL keeps working. Size: S, plus
  the lead adding the domain in Vercel. The proxy and the small function fix can land any time;
  the app shows the new URL from the first build after launch.
- **Before the freeze (Nov 25):** nothing from this job needs to be in the submitted build. One
  security fix found on the way (below, "Found on the way") is server-only and should land
  before launch.

## What exists today

All three user-made credentials are rows in one table, `public.personal_access_tokens`
(`supabase/migrations/20261022205008_personal_access_tokens.sql`). They differ only by `kind`.

| | MCP access token (`pat`) | API key (`api`) | Siri credential (`siri`) |
| --- | --- | --- | --- |
| Format | `fgp_` + 43 chars | same | same |
| Stored | SHA-256 hash, last 4 chars | same | same |
| Created by | `create_personal_access_token(name, household)` | `create_api_token(name, scopes, household)` | the iPhone app, automatically |
| Who may create | any `authenticated` caller (see "Found on the way") | the app's own session only (`session_required`), only while `app_switches.public_api` is on | the app's session |
| Scopes | none: full read and write | `{read}` or `{read,write}` | none |
| Cap per member | 20 active | 10 active | one per session |
| Household | the one open when created ("Neue Token und API-Schlüssel gelten für „Trost“") | same | the default household |
| Works on | `mcp` (and `voice`) | `api` only | `voice` only |
| Ends | revoked, creator leaves the household, account deleted | same | with its session |
| Expiry | none | none | with its session |
| Purge | 30 days after it ended (`purge_access_tokens`, Legal N-4) | same | same |
| Rate limit | per user: 20 burst, 60/min, 1000/UTC day (`mcp_rate`, job 336) | per key: 20 burst, 60/min; per household 1000/UTC day; 20 unknown keys per address in 10 min (`api/limits.ts`) | Siri's own |
| Premium | `integration_gate(household, 'mcp', user)` | `integration_gate(household, 'api', user)` | free |

Where the kinds are told apart:

- `supabase/functions/_shared/auth.ts`, `authenticate`: an `fgp_` token resolves through
  `public.authenticate_access_token`, which returns `pat` and `siri` rows only. An `api` row is
  "unknown" there.
- `public.api_begin` (`20261115100000_key_checks_without_waiting.sql`) looks up
  `kind = 'api'` only, so an MCP token gets `401 invalid_token` on the API (`docs/API.md`, "Other
  credentials do not work here").
- The app reads `kind` and `scopes` (`app/lib/settings/access_repository.dart`) and shows two
  sections in `access_screen.dart`: "Zugriffstoken" and, behind the PostHog flag `public-api`,
  "API".

So the two credentials are already the same thing with a label. Unifying them is mostly removing
two `kind` filters and adding scopes to MCP, not a new token system. **Tokens never expire**, so
"keep working until they expire" means "keep working until revoked": there is no natural end to
wait for, and any plan has to keep old tokens valid or break integrations.

The Premium check is the same for both (`integration_gate` with the caller's own Premium, or a
grant of the key's household), so unifying does not change who pays for what.

## Auth options

### AU1. One key, both doors, with scopes (recommended)

Every personal key works on both MCP and the API. Scopes apply on both.

- **Database (one migration):** backfill `scopes = '{read,write}'` on every `pat` row (a data
  update, no column change, so squawk is fine); let `authenticate_access_token` return `api` rows
  and `api_begin` accept `pat` rows; give `create_personal_access_token` the
  `session_required` check and make it create a read-and-write key, so old app builds that still
  call it keep working; one cap (20 active per member, the higher of today's two). The `kind`
  column stays for history; new keys are `api`.
- **MCP function:** a read-only key may call the read tools (`list_items`, `get_item`,
  `list_recent`, `suggest_items`, `list_categories` and the like) and gets a tool error naming the missing `write` scope on the
  others. That needs one table of tool → scope in `mcp/tools.ts`. Rate limits stay per surface:
  a key used on both counts in the MCP bucket and the API bucket separately. That matches the
  privacy text as written.
- **API function:** no change beyond `api_begin`.
- **The `public_api` switch:** creating a key no longer depends on it (MCP keys never did). The
  switch keeps gating API requests.
- **App:** one section "Zugriffsschlüssel" (name open) in More › Zugänge: create with a name and
  the read / read-and-write choice the API sheet has today, one list, one revoke. It shows both
  URLs (MCP and API) next to the list. "Verbundene Apps" (OAuth) and "Siri (dieses iPhone)" stay
  separate: they are sign-ins, not keys. The `public-api` flag then only hides the API URL and
  docs link.
- **Docs:** `docs/API.md` (Authentication, Limits), `docs/MCP.md` (tokens, scopes), OpenAPI
  `securitySchemes` description, the feature files `ai-assistants.md` and
  `FEATURES-FOR-WRITERS.md`, the guides `site/content/guides/{de,en}/claude.md`.
- **Strings:** about 15 ARB keys change or go (`accessTokens`, `accessTokensHint`,
  `accessTokensHintWithApi`, `accessKeysHousehold*`, `apiHeader`, `apiBody`, `apiKey*`), DE and EN.
- **Privacy text: changes, so Legal GO.** Section 7 says "Ein Zugriffstoken gilt nur für den
  Haushalt ..." and the API section describes API keys separately with their scopes. After AU1 an
  existing MCP token can also reach the API. The data stored per key is unchanged, but what a
  token can do is wider, and the two paragraphs merge. Legal should see the new wording.
- **Risk:** an MCP token someone pasted into an AI assistant can now call the REST API too. It
  could already do the same things through MCP tools (both use `_shared/list.ts`), so the reach
  is the same; the door is new.
- **Size:** M. Migration and pgTAP about 0.5 day, MCP scopes 0.5 day, app section rewrite and
  tests 1 to 1.5 days, docs and strings 0.5 day. About 3 days of one job, plus a Legal round.

### AU2. AU1, and convert old MCP tokens to API keys in the data

As AU1, but the migration also sets `kind = 'api'` on every `pat` row, so one kind remains. Same
user result. It touches every row and the `kind` check, and old app builds that read `kind` to
pick a section would show converted MCP tokens under "API" until they update. Runner-up: tidier
data, more risk for no user gain. Size: M, slightly more than AU1.

### AU3. Only the UI merges

The app shows MCP tokens and API keys in one list, each marked with where it works; the server
stays as is. Small (S, about 1 day), no Legal change in substance, but Peter still has two things
that authenticate, which is what he asked to end. Only worth it if AU1 waits long.

### AU4. OAuth everywhere, no static keys

Retire personal keys; the API takes OAuth tokens like MCP's connected apps. Home Assistant,
n8n, cron jobs and curl need a static key, and Supabase's OAuth server gives short access tokens
with a refresh flow those tools handle badly. Large (L), breaks every existing token. Not
recommended.

## Domain options

Measured from the Hetzner box on 2026-11-22 (two rounds of 12 POSTs each, time to first byte
with a fresh TLS connection): `mcp.snacklist.app` (Vercel rewrite) had medians of 198 ms and
107 ms, `…supabase.co/functions/v1/mcp` 131 ms and 124 ms. The difference is within the noise of
this sample; expect at most a few tens of milliseconds for the extra hop. Vercel served from
`arn1` (Stockholm) for this box.

What the domains do today (`dig`, `curl`, 2026-11-22):

- `mcp.snacklist.app` and `mcp.hummlist.com`: Vercel project `hummlist-mcp` (`mcp-proxy/`),
  rewriting to the `mcp` function; a browser gets a static page. Both answer an MCP POST with the
  function's `401` (Supabase headers `sb-gateway-version`, `cf-ray` come through).
- `snacklist.app` uses Vercel DNS with a wildcard: `api.snacklist.app` already resolves to Vercel
  and answers `404 DEPLOYMENT_NOT_FOUND`. No project owns it yet.
- `snacklist.app/api/v1/items` answers 404 from the site project. The site already uses `/api/`
  for its own functions (`site/api/`: `get`, `report`, `waitlist`).
- The production API itself is on (`…/functions/v1/api/v1/items` answers `401`, not the
  switched-off `404`).

### AD1. `snacklist.app/api/v1/*` as a rewrite in the site project

One rewrite in `site/vercel.json` to `…supabase.co/functions/v1/api/v1/:path*`.

- **Pros:** no new hostname, no lead DNS step.
- **Cons:** `/api/` is the site's own function namespace (`/api/get`, `/api/report`,
  `/api/waitlist`): only `/api/v1/*` could be the API, and one wrong rule sends waitlist posts to
  Supabase. The site's headers (CSP, the `/(.*)` rules) apply to API answers unless excluded.
  Site production deploys wait for `supabase-deploy` and the release gating, so a fix to the
  proxy rides the site's release path. API traffic mixes into the marketing site's Vercel usage.
- Same as AD2 for latency, streaming, CORS and the client address (below).
- **Size:** S. Runner-up if Peter prefers the path over a subdomain.

### AD2. `api.snacklist.app` as a Vercel rewrite (recommended)

Add host rules to the existing `hummlist-mcp` project (`mcp-proxy/vercel.json`): requests with
host `api.snacklist.app` go to `…/functions/v1/api/:path*`, so the base URL becomes
`https://api.snacklist.app/v1`. The lead adds the domain to that project (the wildcard DNS
already points at Vercel). A separate small project is equally possible; one project keeps one
place for "public hosts in front of Supabase functions".

- **Cost:** none beyond today's Vercel plan; the MCP host already runs this way.
- **Latency:** one more hop, see the measurement above.
- **Streaming:** the API answers plain JSON, no streams. MCP stays on `mcp.snacklist.app`.
- **Headers and auth:** Vercel passes `Authorization`, `Idempotency-Key` and the body through
  unchanged (the MCP proxy relies on the same). The function's path parser
  (`api/handler.ts`, `routePath`) already strips `/functions/v1`, so it needs no change.
- **Caching:** the rule set must keep `x-vercel-enable-rewrite-caching: 0` for the host, as the
  MCP host does. Without it Vercel may cache a `GET /v1/items` answer for another caller.
- **CORS:** the function sets `access-control-allow-origin: *` itself; it passes through.
- **Rate limits: one fix needed.** The API's "unknown keys per address" guard hashes
  `X-Real-IP` (`api/handler.ts`, `ipHash`). Behind Vercel that is Vercel's address, so all
  proxied callers share one bucket. The MCP function solved this with `clientAddress`
  (`mcp/handler.ts`): a `via=` marker on the rewrite, then `x-vercel-forwarded-for`. The API
  needs the same, about 20 lines and a test. Valid keys are never blocked by that guard, so the
  failure without the fix is weak protection, not an outage.
- **Timeouts:** Vercel waits 120 s for the first byte (`mcp-proxy/README.md`); every API call is
  far below that.
- **Old URL:** `…supabase.co/functions/v1/api/v1` keeps working forever; nothing on Supabase
  changes. Old app builds keep showing it.
- **App:** `Environment.apiUrl` (`app/lib/core/environment.dart`) gets the same
  production-or-local switch as `mcpUrl`. That needs a new app build.
- **Docs:** `docs/API.md` Base URL, OpenAPI `servers`, the feature files, `docs/DEPLOY.md`
  smoke, `mcp-proxy/README.md`, and a route test in `scripts/mcp-proxy-routes_test.ts`.
- **Privacy text:** names no Supabase URL. Its provider list says "Vercel Inc. (Hosting von
  snacklist.app, app.snacklist.app, mcp.snacklist.app; Domain und DNS)". Add
  `api.snacklist.app` there, and Vercel now also sees API callers' IP addresses (it already does
  for MCP). A small Legal edit; it can ride AU1's Legal round.
- **Size:** S. Rewrite rules and route tests 2 hours, API `clientAddress` fix 2 hours, app URL
  and docs 2 hours, plus the lead's domain step.

### AD3. Supabase custom domain add-on

Supabase serves the whole project (Auth, REST, functions) on a domain such as
`api.snacklist.app` ([docs](https://supabase.com/docs/guides/platform/custom-domains)).

- **Cost:** $10 a month for the add-on
  ([usage page](https://supabase.com/docs/guides/platform/manage-your-usage/custom-domains)),
  and it needs a paid plan (Pro, $25 a month). The project is on the free tier and the standing
  rules forbid upgrading. Out for now.
- **Path:** still `https://api.snacklist.app/functions/v1/api/v1/...`. It does not give the short
  `/v1` URL Peter asked for.
- **Auth:** OAuth flows then advertise the custom domain as the callback URL, so Google and Apple
  sign-in consoles need the new callback added before activation. The MCP authorization server
  must stay the project's Auth issuer. One custom domain per project. The `supabase.co` domain
  keeps working.
- **Latency:** one hop less than AD1 and AD2. Not worth $35 a month here.

### AD4. Cloudflare

A Cloudflare Worker or proxied DNS record in front of the function.

- `snacklist.app` uses Vercel DNS (`ns1.vercel-dns.com`). A Worker on a route of this zone needs
  the zone on Cloudflare, which moves DNS for the site, the web app, MCP and mail. Too much to
  move before launch for one hostname.
- Free tier would cover the traffic; Supabase already sits behind Cloudflare, so latency is
  similar to AD2.
- It adds a second provider to the privacy text's list (Cloudflare as processor), so a larger
  Legal change than AD2.
- **Size:** M, mostly DNS migration risk. Not recommended.

### What happens to the MCP URL

Nothing in AD2: `mcp.snacklist.app` stays the MCP URL, `mcp.hummlist.com` stays until R1. With
AU1 one key then works on `https://mcp.snacklist.app` and `https://api.snacklist.app/v1`. Serving
MCP also at `api.snacklist.app/mcp` is possible later, but it would need a third `via=` marker
and OAuth metadata for that host, for no user gain now.

## Timing

Today is Sunday 2026-11-22. Submission freeze is Wednesday 2026-11-25, public launch Monday
2026-12-01.

| Part | Size | Before the freeze | Notes |
| --- | --- | --- | --- |
| Found on the way: session check in `create_personal_access_token` | XS | Yes, server-only | One migration and a pgTAP case. No app or Legal change |
| AD2 proxy rules + API `clientAddress` fix | S | Can land any time; server and Vercel only | Lead adds the domain. Not visible in the app until the next point |
| AD2 app shows `api.snacklist.app` | XS | No: needs a new build; ship after launch | Old builds keep showing the working supabase.co URL |
| AD2 privacy line (Vercel hosts) | XS | With the Legal round | Before docs advertise the new URL |
| AU1 server (scopes on MCP, both doors) | S-M | No | Changes what existing tokens can do; needs the Legal GO first |
| AU1 app section and strings | M | No | Store builds after launch. A server switch could stage it, but the privacy text must match first |

So: before the freeze, land only the session-check fix. After launch, AD2 first (small, no
behaviour change), then AU1 with its Legal round. Neither needs a PostHog flag beyond the
existing `public-api`; AU1's server side can sit behind a new `app_switches` row
(`unified_keys`) so the deploy and the switch-on are separate steps.

## Found on the way

`create_personal_access_token(text, uuid)` is granted to `authenticated` and has no
`session_required` check (`20261108125048_households_multi.sql`, lines 559 to 591), while
`create_api_token` refuses tokens with a `client_id`. Inferred from the code, not run: an OAuth
access token that an MCP client holds is an `authenticated` JWT, so the client could call
`/rest/v1/rpc/create_personal_access_token` directly and mint a token that never expires and
survives "Verbindung trennen" in Zugänge. The fix is the same check `create_api_token` has. A
pgTAP case with a JWT carrying `client_id` would prove it either way. This should be its own
small job before launch.

## Recommendation

- **AU1** (one key for both, API scopes on MCP, old tokens become read-and-write keys).
  Runner-up **AU2** (same, plus converting the `kind` in the data).
- **AD2** (`api.snacklist.app` as a Vercel rewrite in `hummlist-mcp`). Runner-up **AD1**
  (`snacklist.app/api/v1` in the site project).

## Open questions, with the default used if nobody answers

1. **Name in the app** for the one credential: default "Zugriffsschlüssel" / "Access key".
2. **Host or path:** default `api.snacklist.app/v1` (AD2); `snacklist.app/api/v1` (AD1) if Peter
   prefers one hostname.
3. **What existing MCP tokens become:** default read-and-write keys (what they can do today).
4. **Cap per member:** default 20 active keys (today: 20 MCP, 10 API).
5. **Shared or separate rate limits** for one key used on both: default separate (as now, as the
   privacy text reads).
6. **Show the API URL to users without the `public-api` flag:** default no, until Peter opens the
   API to everyone.
7. **MCP on `api.snacklist.app/mcp` too:** default no.
