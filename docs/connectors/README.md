# Directory submission pack: Claude and ChatGPT (job 415)

Everything someone needs to paste into the two directories' forms. Nothing here was submitted.
Source research: `docs/research/official-ai-connectors.md` (job 405, PR #645, on branch `job/405-research-ai-connectors` until it merges). Account steps and the
exact click path are in `docs/done/415.md`, section "FOR OPS".

| File | For |
| --- | --- |
| `claude-listing.md` | Claude connector directory: every portal field, English and German |
| `chatgpt-app.md` | ChatGPT plugin submission: metadata, `mcp.json` shape, review details |
| `test-cases.md` | The 5 positive and 3 negative review cases (OpenAI requires them; useful for Claude's "Test & launch") |
| `demo-video.md` | Shot list for the demo recording |
| `reviewer-account.md` | The synthetic reviewer account: what Ops creates, the seed script, the sign-in check |

## Rules the texts follow

- No listing text mentions Premium, plans, prices, free trials or discounts (OpenAI guidelines 1.3 and
  5.1). The one place a plan comes up is the tool's neutral "needs a different Snacklist plan" answer
  with a link to an information page (`supabase/functions/mcp/tools.ts`, `docs/MCP.md`), and it only
  shows while the server switch `integration_lock` is on. It is off in production today.
- No name ends in "MCP" or "Plugin". No claim of an official partnership; Claude's "Community" label
  and ChatGPT's listing are not endorsements.
- English first. The tools' own titles and descriptions are German (decision OC-Q7 left open in the
  research; see "Open points" below).

## URLs

| What | URL |
| --- | --- |
| Server (remote MCP, streamable HTTP, root path, not `/mcp`) | `https://mcp.snacklist.app` |
| Website | `https://snacklist.app/en` |
| Documentation (Claude guide) | `https://snacklist.app/en/guides/claude` |
| Privacy policy (EN / DE) | `https://snacklist.app/en/privacy` / `https://snacklist.app/datenschutz` |
| Support | `https://snacklist.app/en/support` (DE `https://snacklist.app/support`) |
| Terms of service | **none exists yet**, see "Open points" |
| Plan information page (the locked answer links it) | `https://snacklist.app/en/guides/ai-assistants-plan` (DE `https://snacklist.app/de/anleitungen/ki-assistenten-tarif`) |
| Imprint | `https://snacklist.app/en/imprint` |

## OAuth details for reviewers

- Standard: OAuth 2.1 with PKCE (S256). The server answers an unauthenticated request with
  `401` and `WWW-Authenticate: Bearer resource_metadata="https://mcp.snacklist.app/.well-known/oauth-protected-resource"`.
- Authorization server: Supabase Auth (project `jdwqrallbpdbshrdhenk`), one entry in
  `authorization_servers`. Its metadata is served at
  `https://mcp.snacklist.app/.well-known/oauth-authorization-server`.
- Client registration: dynamic client registration (RFC 7591), and Client ID Metadata Documents
  for clients on the 2026-07-28 protocol. No client id or secret to hand out; reviewers' clients
  register themselves. Public clients only (`token_endpoint_auth_method: none`).
- Redirect URIs accepted: whatever the registering client sends (`https://claude.ai/api/mcp/auth_callback`,
  `https://chatgpt.com/connector/oauth/<callback_id>`, loopback URIs for CLI clients).
- Scopes: `openid email`. The consent page lists what the client may do: read, add, change, tick
  off and remove items on the shopping list.
- Tokens: ES256 JWT access tokens, one hour; refresh tokens through Supabase Auth.
- Consent page: `https://app.snacklist.app/oauth/consent`, German, button "Erlauben" / "Ablehnen".
- Sign-in on the way there: email and password, nothing else (`reviewer-account.md`, "Sign-in check").
- Rate limit per user: burst 20, 60 a minute, 1000 a day. Anthropic's calls come from
  `160.79.104.0/21` (Anthropic's auth page as read in job 405; recheck on the day).
- Data handling: tool arguments only. No conversation data is collected or stored. `mcp_tool_call`
  telemetry is switched off (Legal N-147).

## Open points (decisions for Peter or Legal; also in NEEDS_LEAD)

1. **Terms of service.** ChatGPT requires a `termsOfServiceURL`. The site has none. Legal writes it.
2. **Directory-facing text on privacy.** Privacy section 7 names assistants as "AI assistants you
   connect yourself". A listing makes it a promoted feature; Legal decides if a sentence is needed.
3. **Brand names.** The listings below name Claude and ChatGPT only where the vendor's form needs it.
   The site's `brand-names` lint is not touched; these files live in `docs/`.
4. **Tool language.** Titles and descriptions stay German. Reviewers read English; the test cases give
   the German names the tools show. A later job can add English titles by `Accept-Language`.
5. **ChatGPT in the EU.** Whether the directory reaches German users is unknown (research OC-Q4).
   Do not promise the listing in store or site copy until known.
