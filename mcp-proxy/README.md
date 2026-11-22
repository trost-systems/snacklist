# mcp-proxy

The Vercel project `hummlist-mcp` serves this directory at
`https://mcp.snacklist.app`, the public URL of the Snacklist MCP server, and
at `https://mcp.hummlist.com`, the old address that connected assistants
keep using until R1. It has no build and no secrets. `vercel.json`
rewrites every request to the `mcp` edge function, except a person opening
the URL in a browser, who gets a static page from `public/`. The same project
also serves the public REST API at `https://api.snacklist.app/v1` (see
"api.snacklist.app" below):

| Request on mcp.snacklist.app or mcp.hummlist.com | Goes to (on `https://jdwqrallbpdbshrdhenk.supabase.co` unless a file) |
| --- | --- |
| `/de`, `/en`, `/static/...` | the files in `public/` (`de.html`, `en.html`, CSS, JS, logo, fonts) |
| `/.well-known/oauth-protected-resource` | `/functions/v1/mcp/.well-known/oauth-protected-resource` |
| `/` from a browser, German first in `Accept-Language` | `public/de.html` |
| `/` from a browser, any other language | `public/en.html` |
| `/` | `/functions/v1/mcp` |
| `/<path>` | `/functions/v1/mcp/<path>` |

| Request on api.snacklist.app | Goes to |
| --- | --- |
| `/de`, `/en`, `/static/...` | the files in `public/`, as on every host |
| `/<path>`, `/` included, from any client | `/functions/v1/api/<path>?via=api-snacklist` |

## The page for people

A browser request is one whose `Accept` names `text/html` and that has no
`text/event-stream` in `Accept`, no `Content-Type`, no `Authorization`, no
`Mcp-Session-Id` and no `MCP-Protocol-Version`. Every MCP POST carries a JSON
`Content-Type`, and the GET for the event stream asks for
`text/event-stream`, so MCP clients never get the page. Only `/` serves it;
`/.well-known/...`, `/mcp` and every other path still go to the function.
`scripts/mcp-proxy-routes_test.ts` (lint gate) replays browser and MCP
client requests through these rules.

The page says what the address is for, shows it with a copy button, and
links to snacklist.app and its guides. It names no AI product
(`scripts/brand-names.ts` scans `public/`), loads nothing from another
origin, sets no cookie, has no analytics and is `noindex` (meta tag, and an
`X-Robots-Tag` header on every response of the host). The two HTML files
share their markup and differ only in the strings: change both.
`cleanUrls` serves `de.html` at `/de`; it also redirects `/<x>.html` and
`/index` paths, which no MCP client uses.

Each destination carries a query marker for the host it came from:
`via=mcp-snacklist`, or `via=mcp-hummlist` for the old host (kept until R1). That tells the function to
advertise that host as the resource and
`https://<host>/.well-known/oauth-protected-resource` as its metadata
(`supabase/functions/mcp/handler.ts`). Requests straight to supabase.co keep
getting the supabase.co URLs, so every URL works. The function also accepts
`x-forwarded-host` for those same hosts, which Vercel sends, but Supabase's
gateway replaces that header before it reaches the function, so the marker
is what works (`docs/DECISIONS.md`, Job 26, item 11). The authorization
server stays Supabase Auth on supabase.co.

`x-vercel-enable-rewrite-caching: 0` keeps Vercel from caching any response,
on every host (Vercel caches external rewrites by default for projects created after
2026-04-06).

## api.snacklist.app

The first rewrite sends every path on `api.snacklist.app` to the `api`
function, so `https://api.snacklist.app/v1/items` is
`/functions/v1/api/v1/items` (`docs/API.md`). It comes before the page rules,
so a browser opening `/` gets the API's JSON, never the MCP page. Vercel
serves the filesystem before any rewrite, whatever the host, so `/de`, `/en`
and `/static/...` still answer with the MCP page's files there; the API has
no such paths.

The destination carries `via=api-snacklist`. The function drops every `via`
from the query when one of them is that marker, since its query check is
strict and Vercel does not document whether the destination's query comes
before or after the caller's (`supabase/functions/api/handler.ts`, `queryOf`).
The marker also picks the address for the limit on unknown keys: through the
proxy Supabase's gateway sees Vercel, so `X-Real-IP` would put every caller
in one bucket. Marked requests use the first entry of
`x-vercel-forwarded-for`, which Vercel sets to the client and overwrites
when a client sends its own; without it, `X-Real-IP`. Direct requests keep
`X-Real-IP` (the API never reads `X-Forwarded-For`, which hosted Supabase
passes on as the client wrote it). A direct caller adding the marker can
pick its own bucket, which only gets around this limit as many addresses
would; the same tradeoff as MCP's `clientAddress`.

The API answers `Cache-Control: no-store` itself; the header above keeps
Vercel's rewrite cache off on this host too.

The domain is attached to the project once, by hand (`docs/DEPLOY.md`,
"Smoke test"). Until then the host answers `DEPLOYMENT_NOT_FOUND`.

## Check it

```bash
scripts/mcp-smoke.sh https://mcp.snacklist.app
scripts/mcp-smoke.sh https://mcp.hummlist.com
MCP_SMOKE_TOKEN=fgp_… scripts/mcp-smoke.sh https://mcp.snacklist.app   # also initialize + tools/list
MCP_SMOKE_PAGE=1 scripts/mcp-smoke.sh https://mcp.snacklist.app         # also the page, DE and EN
scripts/api-proxy-smoke.sh https://api.snacklist.app/v1
API_SMOKE_KEY=fgp_… scripts/api-proxy-smoke.sh   # also categories?via=smoke, items?limit=abc
```

`npx vercel build` in a copy of this directory, with a hand-written
`.vercel/project.json`, compiles the routes offline without a login. The
compiled routes are in `.vercel/output/config.json`.

## Vercel limits (docs read 2026-10-28)

- **Timeout.** Vercel waits up to 120 s for the first byte from the origin,
  then keeps the response open while data arrives at least every 120 s
  ([limits](https://vercel.com/docs/limits),
  [changelog](https://vercel.com/changelog/cdn-origin-timeout-increased-to-two-minutes)).
  The function answers a POST with a short SSE stream that closes after the
  result, and answers GET with 405, so no stream stays open. A tool call
  slower than 120 s fails with `ROUTER_EXTERNAL_TARGET_ERROR` on this URL;
  the supabase.co URL has only the function's own limit.
- **Body size.** Vercel documents no limit for external rewrites (the 4.5 MB
  limit is for Vercel Functions). MCP requests here are a few KB.
- **Streaming.** Not documented. The responses are short SSE streams, so even
  a buffering proxy delivers them whole.
- **Headers.** Vercel documents the headers it adds: `x-forwarded-host`,
  `x-forwarded-proto`, `x-forwarded-for` and `x-real-ip`
  ([rewrites](https://vercel.com/docs/routing/rewrites)). It does not list
  which client headers it passes on. `scripts/mcp-smoke.sh` proves the ones
  MCP needs: the bad-token check needs `Authorization`, and `tools/list`
  with a token needs `Accept`, `Content-Type` and `MCP-Protocol-Version`.
  The function is stateless, so `Mcp-Session-Id` is never used. It never
  reads the upstream `Host` either.
- **`/.well-known`.** The rewrites page says the path "is reserved and
  cannot be redirected or rewritten". The external rewrite of
  `/.well-known/oauth-protected-resource` works on mcp.snacklist.app and
  mcp.hummlist.com all the same (checked 2026-10-28 on mcp.hummlist.com
  with `scripts/mcp-smoke.sh`, `docs/DECISIONS.md` Job 26, item 13).
- **Cost.** Hobby is free: 1,000,000 CDN requests and 100 GB Fast Data
  Transfer a month ([usage](https://vercel.com/docs/manage-cdn-usage)).
  Hobby is for non-commercial personal use
  ([fair use](https://vercel.com/docs/limits/fair-use-guidelines)).

If the proxy fails, `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp`
still works for every client.
