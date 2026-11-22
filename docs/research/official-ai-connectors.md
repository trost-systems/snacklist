# Official Snacklist connectors for Claude, ChatGPT and Gemini

Job 405, research only. Written 2026-11-22. Nothing was applied for, submitted, created or sent.
Every vendor page below was read on 2026-11-22 (WebFetch or WebSearch from the Hetzner runner).
Vendor docs move fast; recheck a page the day someone acts on it. Anything I could not read in a
vendor's own text is marked **unknown**; third-party blog posts were used only as pointers.

## Summary

| | Claude | ChatGPT | Gemini |
| --- | --- | --- | --- |
| Official path | Connectors Directory, developer portal, "MCP connector" | Plugins (apps) submission portal, ZIP with `mcp.json`, MCP review | Connected Apps Platform preview (Google Connected Console), apply by form |
| Who may submit | Any paid Claude plan (Pro, Max, Ultra, Team, Enterprise) | Verified individual or business identity in the OpenAI Platform Dashboard | **unknown** (preview, phased) |
| Einzelunternehmen OK | Yes by the docs: no company needed on Pro/Max; the "Company" step asks a company name and contact | Yes by the docs: "individual or business verification" | **unknown** |
| EU users | Not restricted in the docs read | Docs silent; launch post (Oct 2025) excluded EEA, CH, UK; today's status **unknown** | Custom apps: US only, English only, 18+. Platform: markets **unknown** |
| Review | Automatic scan, then listed as "Community" by default; may escalate to "Verified" | Human review, 5 positive and 3 negative test cases, demo video, reviewer account | **unknown** |
| Cost | None stated | None stated | None stated |
| Timeline | "Not fixed" | None stated | **unknown** |
| Our gap | Small | Medium | Cannot start yet |
| Order | 1 | 2 | 3 (apply for the preview now, build nothing) |

Recommendation: **Claude first**, ChatGPT second, Gemini last and only as an application. Details
and numbered questions are at the end (OC-Q1 to OC-Q9).

## What we have today

Facts read from the repo, not from vendors.

- Remote MCP server `mcp.snacklist.app` (Vercel rewrite to the Supabase edge function `mcp`),
  streamable HTTP, protocol versions 2025-11-25 down to 2024-11-05 and the stateless 2026-07-28
  (`docs/MCP.md:1-20`).
- Auth: OAuth 2.1 with PKCE S256, dynamic client registration through Supabase Auth, and Client ID
  Metadata Documents on the 2026-07-28 front (`supabase/functions/mcp/oauth.ts:64-73`,
  `supabase/functions/mcp/cimd.ts:70-72`). Personal access tokens `fgp_...` as a second credential.
  `401` with `WWW-Authenticate: Bearer resource_metadata=...` (`supabase/functions/mcp/handler.ts:255-265`);
  one entry in `authorization_servers` (`handler.ts:126-130`); scopes `openid email` only
  (`handler.ts:73`).
- 22 tools, 5 of them behind the server switch `mcp_lists_stores` (`docs/MCP.md`, "Tools";
  `supabase/functions/mcp/tools.ts:311-815`). Tool titles and descriptions are German.
- Rate limit per user: burst 20, 60 a minute, 1000 a day (`handler.ts:43-45`).
- **Gating today: free.** `app_switches.integration_lock` is off in production
  (`.cursor/skills/verify-snacklist/features/premium.md:44`, `docs/PURCHASES.md:630`). With it on, a
  user without Premium can connect, run OAuth and `tools/list`, but every `tools/call` returns a
  tool result `isError` with `premium_required` (`tools.ts:92-98`, `tools.ts:169-172`; `docs/MCP.md`,
  "Integration lock"). Siri and Alexa stay free either way. The public API is Premium-gated by the
  same switch, per the job brief.
- Operator: Peter Trost as a natural person with a VAT ID (`site/content/legal/imprint.md`). The
  repo does not name a legal form; I did not guess one.
- Jobs 397 (unified keys) and 398 (`api.snacklist.app`) are in progress per the brief. I did not read
  them; neither changes the MCP URL or OAuth in anything I found.

## 1. Anthropic Claude

### Listing path

- Remote MCP servers go through the developer portal at `https://claude.ai/directory/manage`:
  Submit new, then "MCP connector"
  ([Submit a connector](https://claude.com/docs/connectors/building/submission.md), read 2026-11-22).
  The portal is "always open for new submissions".
- Local servers and MCPB desktop extensions are no longer accepted. Not relevant to us.
- A plugin bundle is a separate submission. Anthropic says to submit the remote server as a
  connector first, then optionally a plugin whose skills teach Claude to use it
  ([Publish to the directory](https://claude.com/docs/directory/publish.md), read 2026-11-22).
  Skills could carry the shopping-list etiquette we now put in `INSTRUCTIONS` (`tools.ts:39`).
  Optional, later.

### Eligibility

- "Pro, Max, Ultra, Team, or Enterprise. Free accounts can't submit." On Pro, Max and Ultra you
  submit from your own account with no role check; on Team and Enterprise an Owner submits
  ([Publish](https://claude.com/docs/directory/publish.md)). "The listing belongs to the
  organization you submit from."
- No company is required. The portal's Company step asks for a company name, website and a primary
  contact (submission page, step 5). What a sole proprietor enters there is **unknown**; Peter's
  name and site are the natural answer.
- EU: no restriction in the connector docs. The policy says software must comply with "the countries
  and regions Anthropic currently supports"
  ([Directory Policy](https://support.claude.com/en/articles/13145358-anthropic-software-directory-policy), §1A).
- Costs: none stated. A paid Claude plan is needed (Peter's own; price not looked up).

### Review

- Every submission is scanned automatically and "by default" listed as a **Community** connector,
  with no action from us. Anthropic "may escalate" a listing flagged as highly useful to **Verified**
  review: a human tests each tool; slower; no separate application
  ([Connector verification](https://claude.com/docs/connectors/verification.md)).
- Timeline: "Review time isn't fixed" (publish page). No number. **Unknown.**
- Portal fields (submission page): server URL; tools synced from the server (those missing a title
  or annotation are flagged); name up to 100 characters, one-liner up to 200, description up to
  2,000, 1 to 5 categories, documentation URL, privacy policy URL, support contact, icon, a URL slug
  that is permanent; use cases and what users need first ("accounts, plans, or other setup"); company;
  authentication; data handling; a "Test & launch" confirmation that every tool was run;
  seven compliance acknowledgments (guidelines, first-party API use, financial transactions, AI media
  generation, prompt injection, conversation data collection, public documentation).
- Test account: Community needs none. For Verified review a reviewer emails and asks; the account
  must be a sandbox with sample data, and credentials never go in the portal
  ([Test your connector](https://claude.com/docs/connectors/building/testing.md)).
- Hard rejection reasons from the pre-submission checklist
  ([review criteria](https://claude.com/docs/connectors/building/review-criteria.md)): a tool with
  both read and write modes; missing `title` or `readOnlyHint`/`destructiveHint`; tool name over 64
  characters; descriptions that tell Claude how to behave or call other tools; generic errors;
  oversized responses; collecting conversation data; unreachable server.
- Paywalls: **the directory policy has no rule on subscriptions or paywalls** (policy read; §4 covers
  autonomous financial transactions and ads only). Free tier is not required.
- Anthropic's calls come from `160.79.104.0/21` ([auth page](https://claude.com/docs/connectors/building/authentication.md)).

### Technical gaps (our server against Claude's rules)

Claude's auth page lists where its client is stricter than the MCP spec. Against each:

| Requirement | Us | Verdict |
| --- | --- | --- |
| `401` with `resource_metadata`, not `200` | `handler.ts:255-265` | OK |
| `resource` equals the URL as the user typed it | host marker per rewrite, `docs/MCP.md` "Public URL" | OK on `mcp.snacklist.app` |
| First `authorization_servers` entry used | one entry, `handler.ts:126-130` | OK |
| S256 PKCE advertised | `oauth.ts:71` | OK |
| DCR or CIMD; CIMD only if metadata has `client_id_metadata_document_supported` and `none` in `token_endpoint_auth_methods_supported` | CIMD flag set at `oauth.ts:72`; `none` comes from Supabase's metadata spread (`oauth.ts:65`), **not verified**; DCR is the fallback and works | Verify, low risk |
| Redirect `https://claude.ai/api/mcp/auth_callback`; Claude Code loopback on any port | DCR/CIMD accept what the client sends; the Claude path is documented as working (`docs/MCP.md`, "Claude") | OK, but "not tested from this box" there; Peter's own connector run is the proof |
| `offline_access` appended when advertised, for a refresh token | `SCOPES` is `openid email` (`handler.ts:73`); access tokens live 1 hour (`docs/MCP.md`) | **Gap to check**: does a Claude session survive the first hour? Codex got a refresh token with `offline_access`; Claude's behaviour unobserved |
| `/token` accepts form-urlencoded; `invalid_grant` on a dead refresh token; rotate for public clients | Supabase Auth's token endpoint | Likely OK, **unverified** |
| 10 s for discovery, registration, token; 30 s refresh | cold start up to about 2 s (`docs/MCP.md`, ~10 s wait section) | OK |
| Every tool has `title` and `readOnlyHint` or `destructiveHint` | `add_items` has **no annotations** (`tools.ts:365-408`). Titles exist on all 22 | **Gap**: portal flags it |
| `destructiveHint` meaning: "true for tools that modify or delete data. Destructive tools always prompt" | We set `destructiveHint: false` on additive writes (`tools.ts:409-760`) and `true` on `remove_items` and `merge_items` | Decision: Claude treats `true` as "always prompts". Keep our honest values; expect Claude to read missing/false as auto-permission. See OC-Q6 |
| `move_item` has `idempotentHint` only (`tools.ts:448-463`), so `destructiveHint` defaults to true per the MCP spec | | **Gap**: set `destructiveHint: false` |
| Tool descriptions must not instruct behaviour | `add_items` says "sag dem Nutzer dann..." and names `merge_items` (`tools.ts:367-390`) | Low risk, reword to be safe |
| Responses "reasonably sized" | `list_items` returns the whole open list; 50 items per write | Probably fine; no numeric limit in the docs. **Unknown** |
| Documentation URL, privacy URL, support contact, icon | docs `docs/MCP.md` is a GitHub link (`handler.ts:131`); `/de/anleitungen/claude` exists on the site; privacy §7 covers assistants (`site/content/legal/privacy.md:105`); support page exists | Need an English public docs page; a stable icon file |
| Tool language | German titles and descriptions, German tool errors | Not a stated rule. Worth deciding OC-Q7 |

### Effort

About **1 job** (S): annotation fixes plus a tools test row, an English docs page on the site, listing
text and icon, a reviewer sandbox account (email and password, Premium granted if the lock is on),
and a runbook for Peter. Peter then needs about an hour in the portal. Community listing may follow
the same day; Verified is not in our hands.

## 2. OpenAI ChatGPT

### Listing path

- Apps are now submitted **as part of a plugin** in the plugin submission portal: Plugins, "Upload new
  or existing plugin", choose a verified developer identity, upload a ZIP, connect the MCP server,
  fill "Review details", submit, then publish after approval
  ([Submit plugins](https://developers.openai.com/apps-sdk/deploy/submission), read 2026-11-22).
  Older third-party guides describe a "+ New App" dashboard flow; do not follow them.
- Submissions opened 2025-12-17 ([OpenAI announcement](https://openai.com/index/developers-can-now-submit-apps-to-chatgpt/),
  via search result; not re-read in full).
- The GPT Store (custom GPTs with Actions) is not covered by the Apps SDK docs. Whether it is still
  relevant is **unknown**; I did not research it. A GPT would use the OpenAPI at `docs/api/openapi.yaml`
  and the public API, which is Premium-gated. Recommendation: skip.
- Users can also add any MCP server themselves as a custom plugin, but only on Business and
  Enterprise/Edu for full read/write; Pro gets read/fetch only; "custom MCP servers can't be
  connected on mobile"
  ([Help: custom MCP servers](https://help.openai.com/en/articles/12584461), read 2026-11-22). This is
  what `docs/MCP.md` already says. A directory listing is the only way to reach Free and Plus users.

### Eligibility

- "Submissions must come from verified individuals or organizations" via the OpenAI Platform
  Dashboard; the doc names "individual or business verification"
  ([Plugin guidelines](https://developers.openai.com/apps-sdk/app-submission-guidelines), §2.1).
  Einzelunternehmen: **an individual identity is explicitly allowed**; what it shows publicly is the
  verified name (`developerName`, up to 80 characters).
- Organization Owners submit; others need "Apps Management Write". An OpenAI organization is needed;
  creating one is a Peter step and was not done here.
- Regions: the submission doc has a `publication.countries` allowlist, empty array means no
  restriction. **EU, EEA, Switzerland and UK availability of the directory is unknown**: the October
  2025 launch post said apps were available "outside of the European Economic Area, Switzerland, and
  the United Kingdom" at first ([Introducing apps](https://openai.com/index/introducing-apps-in-chatgpt/),
  via search result); the current help page says availability "depends on the app, your ChatGPT plan,
  region, workspace, role" and names no EU rule
  ([Apps in ChatGPT](https://help.openai.com/en/articles/11487775-apps-in-chatgpt)). Our users are
  German. **This could make the listing worthless for the launch audience.** OC-Q4.
- Age: plugins must suit "users aged 13-17" and not target under 13 (guidelines §3.2). Snacklist is
  16+ (CLAUDE.md legal dispositions). A 13 to 15 year old can open ChatGPT, but cannot create an
  account in our app, so cannot finish OAuth. Fine, but ask Legal (OC-Q3).
- Cost: none stated. Timeline: none stated. **Unknown.**

### Review

- Required fields: `displayName` up to 30 characters, `shortDescription` up to 30, `longDescription`
  up to 4000, `developerName`, `category`, example prompts; `websiteURL`, `supportURL`,
  `privacyPolicyURL`, `termsOfServiceURL` all required for an MCP app, HTTPS; a square logo of at
  least 48x48 in PNG, JPEG, WebP or SVG; a `demo_recording_url`; "exactly five positive and three
  negative cases"; a reviewer account in a secure form (not in the ZIP) that works "without MFA,
  email or SMS codes, magic links, or private-network access"; `commerce` declaration
  (submission page).
- Domain verification: plain-text token at `https://<host>/.well-known/openai-apps-challenge`.
- Only one review per plugin at a time; appeal by replying to the rejection email.
- A **ZIP** with `mcp.json` (no `clientSecret`, no non-empty headers). Skills optional. Hosted
  tool changes do not need a new ZIP.
- Rules that bite us:
  - §1.3: names must not append "MCP" or "Plugin"; descriptions must not mention "pricing,
    subscriptions, free trials, discounts, or promotions". The listing may not say "Premium".
  - §1.4: a reviewer needs a "fully featured demo account with sample data". If `integration_lock` is
    on, that account needs a Premium grant, or review sees only `premium_required`.
  - §5.1: only physical-goods commerce; "Plugins must not display subscription plans, start new
    subscriptions, or promote upgrades"; existing subscribers may use what their plan includes; a
    plugin "may explain" that a feature needs another plan and link to an informational page, but no
    checkout. Our locked answer says "Schalte es in der Snacklist-App frei" with no link and no price
    (`tools.ts:92-98`, `docs/MCP.md` "Integration lock"). That reads compatible, but a reviewer might
    call "Unlock it" a promotion. Keep the text neutral. Also §5.1: "Plugin quality must match your
    external app", so the free-versus-Premium split must be explainable.
  - §1.2: "Tools should be safe to retry, or explicitly state when retries cause repeated effects."
    `create_list` and `add_items` create on every call (`tools.ts:716`, `tools.ts:365`); the
    descriptions already report duplicates (`alreadyOnList`), `create_list` does not.
  - §6.2b: each operation its own tool. We comply.
  - §6.4 and §4.2b: no credentials or restricted data in tool IO. Items are free text; Legal may want
    a line (OC-Q3).

### Technical gaps

| Requirement | Us | Verdict |
| --- | --- | --- |
| Explicit `readOnlyHint`, `destructiveHint` and `openWorldHint` as `true`/`false` on every tool (guidelines §6.3) | `openWorldHint` is **set on no tool** (`tools.ts:311-815`); `add_items` has no annotations (`tools.ts:365-408`); read-only tools omit `destructiveHint`; additive writes omit `readOnlyHint` | **Gap, 22 tools.** Our list is a bounded private catalogue, so `openWorldHint: false` everywhere. Defaults in the MCP spec are `openWorldHint: true` and `destructiveHint: true`, which would show every write as destructive and open-world |
| `destructiveHint` "false only for additive writes without destructive or irreversible effects. Reversibility alone doesn't justify false" | `tick_items`, `update_item`, `rename_*`, `place_item`, `set_store_layout` are `false`. `update_item` overwrites name, quantity, brand, store (`tools.ts:531-560`), `set_store_order` and `set_store_layout` overwrite an order, `rename_list` overwrites a name | **Judgment call.** OpenAI's wording would make overwrites `true`. Needs a decision; see OC-Q6 |
| OAuth 2.1, PKCE S256, PRM, `iss` in the authorization response (RFC 9207) for the stable redirect | S256 and PRM yes. `iss` handling of Supabase Auth: **unknown**. Without it ChatGPT uses a callback-specific redirect `https://chatgpt.com/connector/oauth/{callback_id}`; DCR handles that | Verify with Inspector and Developer Mode |
| CIMD preferred, DCR works; `none` or `private_key_jwt` | CIMD accepts `none` only (`cimd.ts:70-72`); `private_key_jwt` rejected. ChatGPT's CIMD lists both, and says servers "should accept any method in the intersection" | OK, `none` is in the intersection |
| Scopes: `openid`, `email`, `profile` requested if advertised | we advertise `openid email` | OK |
| Per-tool `securitySchemes`; linking UI needs `_meta["mcp/www_authenticate"]` on an error result | none in the code (grep of `mcp/*.ts`, no hits outside tests) | **Unknown whether needed**: our server answers HTTP 401 before MCP. A plain custom-plugin test shows it; do that first |
| Public HTTPS, streamable HTTP at `/mcp` | root path of `mcp.snacklist.app`, not `/mcp` (`docs/MCP.md`) | Probably OK, the form takes any URL; check |
| Challenge file `/.well-known/openai-apps-challenge` on our host | `mcp-proxy/vercel.json` rewrites only `/.well-known/oauth-protected-resource`; `mcp-proxy/public/` is static. A file under `public/.well-known/` should be served before rewrites, **not tested** | Small change in `mcp-proxy/public/`; the token comes from the portal, so it is a post-submission edit |
| mTLS client certificate or egress IPs (optional hardening) | none | Optional; skip |
| Rate limit 20 burst / 60 per minute (`handler.ts:43-45`) | **Unknown** what ChatGPT's call rate looks like; review traffic is small | Watch; no stated requirement |
| UI widget (Apps SDK component) | none. UI is **optional**: the guidelines treat UI as "follow the UI guidelines" only when present | Not a gap. A list widget would be a separate, later job |
| Tool descriptions and listing in English | German today | OC-Q7 |
| 5 positive and 3 negative review cases, demo video | none | Written by a job; the video is filmed with the verify-snacklist or howto-clips skills against a seeded household. Peter or a job records it |

### Effort

**1.5 to 2 jobs.** One for the server and proxy changes (annotations on all 22 tools, any wording
the first review round names, challenge file) plus the ZIP and its CI check; a half to one job for
the review materials (cases, demo video, reviewer account, privacy and terms URLs in English). Peter
adds the OpenAI organization and identity verification, which are outside our control and can take
days (**unknown**).

## 3. Google Gemini

### What exists

1. **Custom apps in the Gemini app** (personal use). The user pastes an MCP server URL under Settings,
   Connected Apps, Custom apps on gemini.google.com
   ([Gemini Apps Help](https://support.google.com/gemini/answer/17209137), read 2026-11-22). Rules from
   that page: "18 or over and in the US"; personal Google account only, no work or school accounts;
   History on; **English only**; the server "must follow the standard MCP specifications"; a server
   without DCR can take credentials under "Advanced features"; "Gemini requires manual confirmation
   for any write actions"; Google "does not control, monitor, or secure" third-party servers; apps
   "may request more data than needed, and Gemini may share chat content". No listing, no review.
   For our German users this route is closed (US and English only), so it does not serve the launch
   audience.
2. **Connected Apps Platform**, a developer preview announced 2026-10-28: cloud-hosted MCP server or
   Android AppFunctions, then "register, test, and submit" in the Google Connected Console; developers
   choose Search, the Gemini app or both; verified logos and authenticated accounts
   ([Google blog](https://blog.google/innovation-and-ai/technology/developers-tools/connected-apps-one-place/),
   [developer page](https://developers.google.com/connected-apps), both read 2026-11-22). Access is
   "in phases": "We will add more developers, markets, and Google products over the coming months."
   Apply through a form linked from the developer page. OAuth 2.1 is the named auth; transport,
   annotations, review criteria and timeline are not on the pages I could read. A search result (not
   a Google page) says the preview is for US developers on a waitlist; **unverified**.
3. Gemini Enterprise supports custom MCP servers in Business edition, added by admins
   ([search result only](https://cloud.google.com/blog/products/ai-machine-learning/gemini-enterprise-agent-platform-remote-mcp-server)).
   Not for our consumers.
4. The old "Gemini extensions" are not what Google offers for third parties now; I found nothing
   current. **Unknown.**

### Eligibility, review, cost

Company or individual: **unknown**. EU: **unknown**, the only hard statements are the US and English
limits on route 1. Review: exists, content **unknown**. Cost: none stated. Timeline: **unknown**.

### Gaps

Cannot be listed without reading the console guide, which needs preview access. From what is known:
OAuth 2.1 with PKCE (have it), streamable HTTP (have it), "standard MCP" (have it), English tool
text (OC-Q7). The Gemini client's own OAuth behaviour (DCR or CIMD, redirect URI) is **unknown**.

### Effort

Now: **0.1 job**, an application text for Peter to paste and a calendar note to recheck. Later,
once access exists: probably about 0.5 job on top of the Claude and ChatGPT changes, **a guess**.

## 4. Legal and privacy items for Legal Review

1. **Data flow.** A connected assistant reads and changes list items and sees household names and
   member counts (privacy §7, `site/content/legal/privacy.md:107`). Vendors are named there only as
   "AI assistants you connect yourself" and independent controllers (`privacy.md:189`). A directory
   listing makes the connection a product feature we promote, so Legal should decide whether those
   sentences still hold or need a "listed in vendor X's directory" line. No DPA with Anthropic, OpenAI
   or Google exists in `docs/legal/dpas/` (only Vercel and RevenueCat); under the independent
   controller reading none is needed, but that is Legal's call.
2. **Vendor directory terms are contracts.** Anthropic: Software Directory Terms and Policy,
   plus promises to "respond to security issues promptly" and "notify Anthropic of material changes to
   data practices" (policy §3H). OpenAI: usage policies and the verified-identity attestations.
   Google: **unknown**. Someone with authority (Peter as the natural-person operator) accepts them.
3. **Brand rule conflict.** The standing disposition says "No marketing strings naming Claude" and the
   lint `brand-names` fails ChatGPT, OpenAI, Claude and Anthropic in `site/content`, `site/public`,
   `mcp-proxy/public` and ARB values outside an allow list (CLAUDE.md, lint table; Legal N-80..N-86).
   A directory listing names the vendor by necessity, and the vendor's own rules also constrain us:
   OpenAI "don't imply OpenAI made or endorses the plugin"; Anthropic shows a Community label. Legal
   needs to say which listing and docs strings are allowed and whether logos may be used (OC-Q3).
4. **Listing claims.** OpenAI forbids pricing, subscription and promotion words in descriptions;
   Anthropic asks the portal for "what users need before they can connect, such as accounts, plans".
   Whether MCP access is free or Premium at listing time changes what we may say (OC-Q1). Never claim
   "official" Anthropic or OpenAI partnership; a Community label is not an endorsement.
5. **Data minimisation claims.** Both vendors ask for "only necessary" data and no conversation
   data. Our server receives tool arguments only; `mcp_tool_call` telemetry exists
   (`supabase/functions/mcp/telemetry.ts`) and I did not audit its fields. Before a privacy URL is
   submitted, someone should confirm it logs no item text (`docs/ANALYTICS.md` rule: never list text).
6. **Age.** OpenAI expects 13 to 17 to be possible; Snacklist is 16+. Confirm the consent page is
   enough as the age gate for the connector path.
7. **EU availability.** If ChatGPT's directory is not available to German users, the privacy and
   store copy must not promise it.
8. **Sensitive data.** Free-text item names can hold health or religion hints ("Insulin", "halal").
   OpenAI §4.2c asks for explicit disclosure when sensitive data is "strictly necessary"; probably
   not applicable, but one Legal sentence closes it.
9. **Premium and review.** Whether a reviewer account gets a Premium grant is a product call
   (`docs/PURCHASES.md` grants), and the locked tool answer must not read as an upgrade pitch for
   OpenAI (§5.1).
10. **Support channel.** Both vendors require a named support contact (Anthropic policy §3B, OpenAI
    §2.2). `site/content/legal/support.md` exists; confirm it is the address to publish.

## 5. Recommended order and effort

Job-size unit: one agent job ending in one merged PR, roughly the size of jobs 345 or 365.

| Step | Vendor | What | Size | Needs from Peter |
| --- | --- | --- | --- | --- |
| 1 | Claude | Annotations on all tools, English docs page, listing text and icon, reviewer sandbox, runbook; Peter submits the Community listing | 1 job | Portal session, about 1 hour; accept Directory Terms |
| 2 | ChatGPT | Same server fixes (shared with step 1), ZIP package, challenge file, 5+3 cases, demo video, English privacy and terms URLs | 1.5 to 2 jobs | OpenAI organization, identity verification, Plugins portal session |
| 3 | Gemini | Application text now; build only after preview access | 0.1 now, about 0.5 later (guess) | Apply form (needs Google account) |

Why this order:

- Claude has the lowest bar (no human review needed for a Community listing, no stated cost, no
  company, EU not restricted) and our server was already built against Claude's OAuth flow. The work
  is mostly the annotation fix we need for every vendor anyway.
- ChatGPT's work is larger, its EU availability is the biggest unknown and decides whether it is worth
  doing before the first German users ask; the review is human and the rules about subscriptions
  interact with our Premium plan. Do the shared server fixes in step 1 so step 2 starts with the
  annotations already right.
- Gemini's consumer route is US and English only; the platform route is a gated preview. Apply early
  because it costs a form; expect nothing soon.

Before versus after the Nov 25 freeze (default stated in the brief: after, nothing in the launch build):

- **Before, allowed, no build change:** this document; Peter creates or confirms accounts and starts
  identity verification; Peter applies for Google's preview; Legal Review of section 4.
- **After the freeze:** every code change. The MCP function is not in the app binaries, but it deploys
  from `main` through `supabase-deploy.yml` and the launch build shares that pipeline, so the default
  stands (OC-Q2). The annotation fix changes what clients show for 22 tools, so it should land with
  a `tools_test.ts` row (`tools_test.ts` already asserts annotations per `docs/MCP.md`, "Tests").
- **Do not do before Legal:** any listing text naming a vendor, any submission.

## 6. Open questions for Lead

Defaults apply unless Lead says otherwise.

- **OC-Q1.** Is MCP access free or Premium when we list? Default: **free for now**; production has
  `integration_lock` off and neither vendor requires a free tier, but OpenAI forbids upgrade promotion
  and wants a fully featured demo account. If the lock goes on later, the reviewer account gets a Premium
  grant and the locked answer keeps its neutral wording.
- **OC-Q2.** May the server and proxy changes land before Nov 25? Default: **no**, after the freeze.
- **OC-Q3.** Which Legal items need a yes before any listing (section 4: brand rule exception,
  vendor terms, age, sensitive data, support contact)? Default: Legal reviews section 4 first; no
  submission before the written yes.
- **OC-Q4.** Is ChatGPT worth doing if the directory is not open to German users? Default: **ask
  OpenAI's current help or a Developer Mode test on Peter's account before starting step 2**; if
  EEA is excluded, defer step 2.
- **OC-Q5.** Who submits and under what name? Default: **Peter Trost as the natural-person operator**
  (matches the imprint), not a made-up company.
- **OC-Q6.** Annotation policy for overwrites (`update_item`, `rename_*`, `set_store_order`,
  `set_store_layout`). Default: **follow OpenAI's reading** (overwrites count as destructive, only
  additive writes `false`) for ChatGPT, keep `idempotentHint: true`; the cost is more confirmation
  prompts in Claude for edits. Alternative: keep today's honest-additive values and defend them in
  review.
- **OC-Q7.** English tool text? Default: **keep German titles and descriptions**, add an English
  listing and docs page; revisit if a reviewer asks. The server already negotiates `Accept-Language`
  for the Premium message (`tools.ts:92-98`), so localised descriptions are possible later.
- **OC-Q8.** Should the GPT Store be researched? Default: **no**; the Apps SDK path replaces it and a
  GPT would sit on the Premium-gated public API.
- **OC-Q9.** Ship a Claude plugin bundle with skills after the connector? Default: **later, only
  if the Community listing gets traction**.

## Sources

All read 2026-11-22 unless noted.

- Claude: [Submit a connector](https://claude.com/docs/connectors/building/submission.md),
  [review criteria](https://claude.com/docs/connectors/building/review-criteria.md),
  [Authentication](https://claude.com/docs/connectors/building/authentication.md),
  [Testing](https://claude.com/docs/connectors/building/testing.md),
  [Publish](https://claude.com/docs/directory/publish.md),
  [Verification](https://claude.com/docs/connectors/verification.md),
  [Directory Policy](https://support.claude.com/en/articles/13145358-anthropic-software-directory-policy).
  Not read: the Directory Terms page and Claude's tool-response size limit (none found).
- OpenAI: [Submit plugins](https://developers.openai.com/apps-sdk/deploy/submission),
  [Plugin guidelines](https://developers.openai.com/apps-sdk/app-submission-guidelines),
  [Auth](https://developers.openai.com/apps-sdk/build/auth),
  [Connect to ChatGPT](https://developers.openai.com/apps-sdk/deploy/connect-chatgpt),
  [Help: custom MCP servers](https://help.openai.com/en/articles/12584461),
  [Help: Apps in ChatGPT](https://help.openai.com/en/articles/11487775-apps-in-chatgpt).
  Search results only: the Oct 2025 launch post and the 2025-12-17 submissions post.
- Google: [Gemini Apps Help, custom apps](https://support.google.com/gemini/answer/17209137),
  [Connected Apps blog, 2026-10-28](https://blog.google/innovation-and-ai/technology/developers-tools/connected-apps-one-place/),
  [developer page](https://developers.google.com/connected-apps). The MCP developer guide, OAuth guide
  and Policy page linked from it were not read.
