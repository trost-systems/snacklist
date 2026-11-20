# MCP access (Zugänge)

Mehr → Zugänge shows the MCP server URL, the user's personal access tokens and the AI apps connected over OAuth. A token is shown once when it is created and works as a bearer token at the MCP endpoint (and the Siri endpoint). Revoking a token or disconnecting an app ends its access on its very next request, even though an OAuth access token is valid for an hour.

## Sub-features

- `mcp-consent` is the page an AI app opens to connect (`/oauth/consent?authorization_id=…`, title "Zugriff erlauben?"; an unknown or expired request shows "Verbindung abgelaufen" with "Zurück zur Liste" and no server text, job 57): "Erlauben" approves, "Ablehnen" sends `access_denied` back to the app, and a signed-out user signs in on the way and lands back on it. After the decision (job 62) the page stays up while the app's callback loads: title "Verbunden" with "Fertig, du kannst zu <app> zurückkehren." (key `consent-done`), or "Nicht verbunden" with "Abgelehnt, du kannst zu <app> zurückkehren."; an app approved before gets "Verbunden" with "Fertig, du kannst zu deiner App zurückkehren." without the question.
- `mcp-tools` (six tools: `list_items`, `add_items`, `tick_items`, `move_item`, `list_categories`, `list_stores`). `list_items` returns `counts` `{open, checkedLast24h}` for the whole list, also with a `store` or `category` filter (job 62). `add_items` reads a count at either end of the name as the quantity ("Gurken 3", "2 Gurken"; a trailing one only 1 to 20 after a known name, so "Büroklammern 100" stays the name; job 61).
- `mcp-url` shows the endpoint with a copy button ("Kopiert"): `https://mcp.snacklist.app` in builds for the production project, `<API URL>/functions/v1/mcp` in builds for any other project, such as fg's local stack.
- `mcp-pat-create` creates a named token ("Token erstellen"), shows `fgp_…` once, then lists it after "Fertig" with the title `<name>` and the subtitle `…<last 4> · Erstellt am <date> · Noch nie benutzt` ("Zuletzt benutzt <date>" once it was used).
- `mcp-pat-revoke` revokes a token ("<name> widerrufen", then "Widerrufen"); the next MCP call with it gets 401.
- `mcp-apps` lists each OAuth app the user approved, with the date and the scopes.
- `mcp-disconnect` disconnects an app ("<app> trennen", then "Trennen"); the next MCP call with its unexpired access token gets 401.

- `api-keys` (job 73, behind the PostHog flag `public-api`, off): with the flag on, a section "API" (key `api-section`) under the tokens with the API base URL (`api-url`, `<API URL>/functions/v1/api/v1`), a docs link (`api-docs`) and "API-Schlüssel erstellen" (`api-create`): a name and "Nur lesen" (`api-scope-read`, default) or "Lesen und schreiben" (`api-scope-write`), then the key once. Keys (`api-key-tile`) show "…<last 4> · Nur lesen" or "· Lesen und schreiben"; they are listed, revocable, also with the flag off, and never under the MCP tokens. Force the flag with `--dart-define=FLAGS_ON=public-api` (docs/ANALYTICS.md, "Feature flags"). verify-snacklist's features/ai-assistants.md has the full copy.
- `mcp-locked` (job 50, off by default): with `app_switches.integration_lock` on, `initialize` and `tools/list` work for a user without Snacklist Premium, every `tools/call` answers HTTP 200 with `isError: true` and "Du brauchst Snacklist Premium …" (English by `Accept-Language`); the token stays valid. Then Zugänge (every build since job 328) shows the card `integration-premium` (`integration-buy`, or `integration-soon` / `integration-in-the-apps`) and every token and app as paused (`access-paused`, "Pausiert: braucht Snacklist Premium"); nothing is removed and new tokens can still be created. See features/purchases.md `iap-integration-lock`.
## How to get to it (user POV)

- Tap "Mehr" in the tab bar, then "Zugänge".
- An app appears under "Verbundene Apps" after the user approves it on the consent page. Supabase Auth sends the browser there, so only the web build shows it. On the Linux surface nothing opens that route, so the journey grants the app over HTTP as a precondition.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`; peter signed in on the list. One client is enough.
- For `mcp-apps` and `mcp-disconnect`: an approved OAuth client. `journeys/mcp-disconnect.sh` registers one dynamically and approves it as peter over HTTP: authorize, GET the authorization, POST the consent, then exchange the code with PKCE.

- **Consent page.** Not drivable with fg. Run `scripts/gates/e2e.sh --workers=1 tests/mcp.spec.ts tests/mcp-consent-wait.spec.ts`: the second shows "Fertig, du kannst zu Claude (E2E) zurückkehren." and "Verbunden" after "Erlauben"; the first approves on the page ("Erlauben"), denies ("denying consent sends access_denied back to the client") and signs in on the way ("a signed-out user signs in on the way to the consent page and lands back on it").
- **Open.** Run `fg tap --key tab-more` (once more if More reopened a subpage, see `features/README.md`), `fg marionette -- scroll-to --key more-access`, `fg tap --key more-access`, as `journeys/mcp-disconnect.sh` does. `fg wait --text "Verbundene Apps"` succeeds on `access-screen` (route `/more/access`; export and deletion are on the separate Konto page, `features/account.md`).
- **URL.** `fg wait --text "$(fg env | jq -r .apiUrl)/functions/v1/mcp"` succeeds. `fg tap --tooltip Kopieren` and `fg wait --text Kopiert` succeed.
- **Disconnect.** Run `fg tap --tooltip "<app> trennen"`, `fg wait --text "<app> trennen?"`, `fg tap --text Trennen` and `fg wait --text "<app>" --gone`. A `tools/list` POST to the MCP URL with the app's access token now returns 401. `fg db query "select count(*) from auth.sessions where oauth_client_id = '<client id>'"` returns 0.
- **Create a token.** Use a unique name, such as `N="Siri $(date +%s)"`. Run `fg tap --text "Token erstellen"`, `fg wait --label Name`, `fg type --label Name --input "$N"`, `fg tap --text Erstellen`. `fg wait --contains fgp_` returns the token. It reaches MCP (200). Then run `fg tap --text Fertig`; `fg find --contains "Noch nie benutzt"` shows its row.
- **Tools.** With that token as `$T`, POST to the MCP URL as `journeys/mcp-disconnect.sh` does (`curl -X POST "$(fg env | jq -r .apiUrl)/functions/v1/mcp" -H "authorization: Bearer $T" -H 'content-type: application/json' -H 'accept: application/json, text/event-stream'`) with `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"add_items","arguments":{"items":[{"name":"Gurken 3"}]}}}`: the result text names Gurken with quantity "3", and `fg wait --text "3× Gurken"` succeeds on peter's app without a tap. Then `"name":"list_items","arguments":{"store":"dm"}`: `counts.open` equals `fg db query "select count(*) from items where status = 'active'" --as peter`.
- **Revoke a token.** Run `fg tap --tooltip "$N widerrufen"`, `fg wait --text "Token widerrufen?"`, `fg tap --text Widerrufen`, `fg wait --tooltip "$N widerrufen" --gone`. The token now gets 401 from MCP. `fg db query "select revoked_at from personal_access_tokens where name = '$N'"` is not null.
- **Proof.** Run `journeys/mcp-disconnect.sh`. It prints `PASS` with both status codes and the minutes the OAuth token had left, and saves `mcp-01-connected`, `mcp-02-disconnected` and `mcp-03-token-revoked` plus a recording.

## Gotchas

- Wait for each dialog's title before tapping. Taps sent during the open animation fail with `not_found`.
- Button labels inside dialogs ("Trennen", "Widerrufen", "Erstellen") are not listed by `fg find`. `fg tap --text` still finds them.
- The created token appears in `fg wait --contains fgp_` output. Keep that output out of committed logs.
- GoTrue only approves an authorization after the user has read it (GET `/auth/v1/oauth/authorizations/<id>`). A consent POST without it returns `oauth_authorization_not_found`.
- Grants and tokens pile up across runs (`fg up` keeps data). Use unique app and token names, as the journey does, or `fg up --fresh`; a second "Siri" token makes the tooltip "Siri widerrufen" ambiguous.
- The list of tokens and apps loads when the screen opens. Leave and reopen Zugänge to see a grant made over HTTP or a "Zuletzt benutzt" date.
