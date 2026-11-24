# ChatGPT app (plugin) submission

Portal: OpenAI Platform, Plugins, "Upload new or existing plugin" (`https://developers.openai.com/apps-sdk/deploy/submission`,
read 2026-11-22; the flow moves, recheck). Guidelines: `https://developers.openai.com/apps-sdk/app-submission-guidelines`.

## Metadata

| Field | Value | Limit |
| --- | --- | --- |
| `displayName` | `Snacklist` | 30 |
| `shortDescription` | `Shared household shopping list` (29) | 30 |
| `developerName` | the verified name of the OpenAI identity (Peter Trost, individual verification) | 80 |
| `category` | Lifestyle (or Productivity, whichever the portal lists) | |
| `websiteURL` | `https://snacklist.app/en` | https |
| `supportURL` | `https://snacklist.app/en/support` | https |
| `privacyPolicyURL` | `https://snacklist.app/en/privacy` | https |
| `termsOfServiceURL` | **missing: needs the Terms page (README, open point 1)** | https |
| MCP server URL | `https://mcp.snacklist.app` | public https |
| Logo | the app icon, square, PNG, at least 48x48 (use 512x512) | |
| `commerce` | no commerce: the app sells no physical goods and starts no checkout | |
| `publication.countries` | empty (no restriction), unless Peter wants a list; EEA availability unknown | |
| Domain verification | the portal gives a token; serve it as plain text at `https://mcp.snacklist.app/.well-known/openai-apps-challenge` (a file `mcp-proxy/public/.well-known/openai-apps-challenge`, untested that a static file wins over the rewrite; deploy and `curl` it) | |

## Long description (max 4000)

```
Snacklist is the shared shopping list of one household. Connect it and ChatGPT can read your list, add items, tick them off, change them and delete them.

What it does:
- Shows what is on your list, by store or by section, in the order you walk through the store.
- Adds items from plain sentences. "Two cucumbers, Pampers size 3 and toilet paper" becomes three entries with quantity and brand, each sorted into its section and the store where you usually buy it.
- Ticks items off, puts them back, changes them or deletes them.
- Moves an item to another store or section. Snacklist remembers the correction.
- Suggests what your household buys often and shows what was ticked off recently.

Everything you change shows up at once on the phones of everyone in your household.

Who it is for: people who already use Snacklist (iOS, Android or web) and share a list with their household. You need a Snacklist account.

Limits: it only reads and changes the shopping lists of the households you belong to. It cannot order, pay or deliver anything, and it cannot see households you are not a member of. What you add is shared with your household, and ChatGPT (OpenAI) receives what it reads or changes on your list. ChatGPT answers in your language.

You sign in with your Snacklist account and see what ChatGPT may do before you allow it. You can disconnect at any time in the Snacklist app under More, Access.
```

No pricing, plan, trial or discount words (guideline 1.3). The name carries no "MCP" or "Plugin".
It does not suggest that OpenAI made or endorses it.

## Example prompts

1. `Put milk, two cucumbers and toilet paper on my Snacklist.`
2. `What is still on the list for Lidl?`
3. `I bought the milk, tick it off.`
4. `Move the candles to the dm store.`
5. `What do we usually buy that is not on the list yet?`

## Tool annotations (guideline 6.3)

Every tool declares `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint` as
explicit booleans (`toolAnnotations` in `supabase/functions/mcp/tools.ts`, pinned per tool by
`tools_test.ts`). `openWorldHint` is false on all: a tool reaches only the user's own household.
`destructiveHint` is true for deleting or overwriting what the user typed (`remove_items`,
`merge_items`, `update_item`, `rename_list`, `rename_store`, `move_item` and `place_item` (they overwrite an item's store, category or place, job 432), and `set_store_order` and
`set_store_layout`, which replace a store's whole order) and false otherwise. Each operation is
its own tool (guideline 6.2b). `add_items` and `create_list` carry `idempotentHint: false`, the
cautious value: a repeated `create_list` makes another list, and `add_items` creates a new entry
for a different spelling or size, though an item already open is reported under `alreadyOnList`
and not added twice.

Every tool also has a short English `title`, in both `Tool.title` and `annotations.title` (job 421;
Claude's portal flags a tool without the second).

## Plans and purchases (guideline 5.1)

The connector never shows plans or prices, never starts a purchase and never promotes an upgrade. If
a user's account does not include assistant access (a server switch that is off in production
today), a tool answers: "This needs a different Snacklist plan. Info: <link> Nothing was read or
changed.", linking `https://snacklist.app/en/guides/ai-assistants-plan`, a plain information page
with no price and no checkout. Tell the reviewer this in "Review details" so the answer is not read
as a promotion.

## ZIP

`mcp.json` with the server URL and OAuth only: no `clientSecret`, no non-empty headers. No skills in
the first submission. Tool changes need no new ZIP.

```json
{ "mcpServers": { "snacklist": { "url": "https://mcp.snacklist.app" } } }
```

Verify the exact `mcp.json` schema in the portal's current docs on the day; the shape above is the
minimal one from the research and was not validated by a portal.

## Review details

- Reviewer account: `reviewer-account.md`. Credentials go into the portal's secure field, never into
  the ZIP or this repo. It signs in with email and password and no MFA, email or SMS code, magic link or
  private network.
- Test cases: `test-cases.md` (exactly five positive and three negative).
- Demo recording URL: `demo-video.md`.
