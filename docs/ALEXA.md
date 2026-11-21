# Alexa skill "Snacklist" (de-DE, en-*)

A household member says "Alexa, sag snacklist, füg Milch und Eier hinzu", and Milch and Eier land
on the household's Snacklist within seconds, categorized and sorted like items typed in the app.
"Alexa, frag snacklist, was auf der Liste steht" reads the open items aloud. Spec #7, job 31.
On an Echo set to English (en-US, en-GB, en-AU, en-CA, en-IN), "Alexa, ask snacklist to add milk
and eggs" does the same in English (job 69). Certification readiness:
[ALEXA_CERTIFICATION.md](ALEXA_CERTIFICATION.md).

**Status (2026-11-17):** the Snacklist skill passed Amazon certification and has been live worldwide
since 2026-11-16. The beta passages below describe the pre-launch setup and stay as history.

| | |
| --- | --- |
| Skill name, invocation name | `Snacklist`, `snacklist` in all six locales (S4 rename; `skill_package_test.ts` fails on any Hummlist left in the package except the old host `app.hummlist.com` in the account-linking domains) |
| Skill ids | Hummlist `amzn1.ask.skill.fee316d1-e9c1-44a4-a06e-955fbda63a1b` (job 31b), Snacklist `amzn1.ask.skill.ad766331-e979-4a6e-95f1-30198b0a34cb` (job 174, development only). The hosted `ALEXA_SKILL_ID` lists both |
| Endpoint (and skill events) | `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/alexa` (`sslCertificateType: Wildcard`) |
| Function | [`supabase/functions/alexa/`](../supabase/functions/alexa/) |
| Replies | The quoted replies below are the Snacklist wording of the speech PR #353 (deployed 2026-11-10) |
| Skill package | [`alexa/skill-package/`](../alexa/skill-package/) (`skill.json`, `interactionModels/custom/de-DE.json` and the five identical `en-*.json`, icons from `design/app-icon/build.mjs`), [`alexa/ask-resources.json`](../alexa/ask-resources.json) |
| Account linking | [`alexa/account-linking.json`](../alexa/account-linking.json) (no secret), [`scripts/alexa-oauth-client.sh`](../scripts/alexa-oauth-client.sh) |
| Local testing | [`scripts/alexa-test-ca.sh`](../scripts/alexa-test-ca.sh), [`scripts/alexa-say.sh`](../scripts/alexa-say.sh) (`--locale en-US`), [`e2e/tests/alexa.spec.ts`](../e2e/tests/alexa.spec.ts), [`alexa-en.spec.ts`](../e2e/tests/alexa-en.spec.ts) |
| Amazon (ASK CLI signed in) | [`scripts/alexa-deploy-dev.sh`](../scripts/alexa-deploy-dev.sh), [`alexa-validate.sh`](../scripts/alexa-validate.sh), [`alexa-simulate.sh`](../scripts/alexa-simulate.sh) |
| When it fails | [Troubleshooting](#troubleshooting): [`scripts/alexa/diagnose.sh`](../scripts/alexa/diagnose.sh) (what reached Snacklist), [`scripts/alexa/smoke.sh`](../scripts/alexa/smoke.sh) (Amazon calls the endpoint) |
| Decisions | [DECISIONS.md](DECISIONS.md), "Job 31" |
| Manual steps | [NEEDS_PETER.md](NEEDS_PETER.md), "Job 31" |

## How a request flows

```
Echo ──> Alexa (speech to text, intent "AddItemIntent", slot items = "milch und eier")
     ──> POST /functions/v1/alexa  (signed: SignatureCertChainUrl + Signature-256)
         1. verify.ts: cert URL, chain to a pinned Amazon root, SAN echo-api.amazon.com,
            signature over the raw body, timestamp ±150 s, our skill id  ── else 400, nothing read
         2. the linked token (context.System.user.accessToken) ─> _shared/auth.ts authenticate():
            a Supabase OAuth access token whose session still exists; its user's CURRENT
            household from household_members  ── else "Bitte verknüpfe …" + LinkAccount card
         3. voice/parse.ts splits "milch und eier" (the Siri splitter; voice/parse_en.ts for an
            en-* request, alexa/voices.ts picks by request.locale)
         4. 30 items a minute per user (alexa_take_adds)
         5. the target list (job 207, _shared/spoken_list.ts): AddToListIntent's list slot, else
            a list phrase at the end of the items ("… zur geburtstag liste"), else the user's
            default list in that household (public.default_list: chosen in the app, else the first)
         6. voice/items.ts adds through public.add_list_item as the user, under RLS (classifier,
            store memory, duplicates) ─> Realtime ─> every member's app
         7. read-back: "Ich habe Milch und Eier auf die Snacklist gesetzt."
```

Nothing from the request body chooses a household: only the token's user and their membership at
request time do, so after a household switch Alexa adds to the new one. The item's `added_by` is
the linked user, and the other members see it like any partner's add ("Neu").

## What Alexa understands and says

Invocation: "Alexa, sag snacklist, …", "Alexa, frag snacklist, …", "Alexa, öffne snacklist".

| Intent | Examples (de-DE.json has them all) | Answer |
| --- | --- | --- |
| `AddItemIntent` (slot `items`, `AMAZON.SearchQuery`) | füg {items} hinzu · setz {items} auf die Liste · schreib {items} auf · wir brauchen {items} · trag {items} ein | added: "Ich habe Milch und Eier auf die Snacklist gesetzt." · open already, with other spellings of new items (job 32b, added anyway; job 68): "Schon auf der Snacklist: Milch und Möhren." |
| `AddToListIntent` (slots `itemphrase`, custom type `ITEM_PHRASE`, and `list`, custom type `LIST_NAME`; job 207) | füge {itemphrase} zur {list} Liste hinzu · füge {itemphrase} auf die {list} Liste hinzu · füge {itemphrase} zu {list} hinzu · setz/pack/schreib {itemphrase} auf die {list} Liste · en: add {itemphrase} to the {list} list · add {itemphrase} to {list} · add {itemphrase} onto the {list} list | "Ich habe Luftballons auf die Liste Geburtstag gesetzt." · "Schon auf der Liste Geburtstag: Kerzen." The seeded list is "die Einkaufsliste" / "the shopping list". See [Named lists](#named-lists) |
| `ReadListIntent` | was auf der Liste steht · was steht auf der Liste · lies die Liste vor · was brauchen wir | "Auf der Snacklist stehen 3 Sachen: Äpfel, 2 Liter Milch und Eier." in the app's aisle order; at most 10, then "und 5 weitere."; empty: "Die Snacklist ist leer." |
| LaunchRequest | "Alexa, öffne snacklist" | "Was soll auf die Liste?" and waits for the answer (`Dialog.ElicitSlot`, so "Milch" alone works) |
| `AMAZON.HelpIntent` | "Hilfe" | what the skill does, with the two examples; the session stays open |
| `AMAZON.StopIntent`, `CancelIntent`, `NavigateHomeIntent` | "Stopp", "Abbrechen" | "Bis bald." |
| `AMAZON.FallbackIntent`, nothing understood | "äh", "bitte" | once: "Das habe ich nicht verstanden. Was soll auf die Liste?" (re-prompt); the second time: "Das habe ich leider nicht verstanden. Ich habe nichts auf die Snacklist gesetzt." Never a guess. |

Other answers, all German, all ending the session: not linked or link revoked ("Bitte verknüpfe
zuerst dein Snacklist-Konto in der Alexa-App. …" with a LinkAccount card), no household ("Du bist
noch in keinem Haushalt. …"), more than 1000 characters ("Das war zu lang. … Ich habe nichts
hinzugefügt."), more than 30 items (the first 30 are added: "Mehr als dreißig auf einmal gehen
nicht; sag den Rest bitte noch einmal."), the rate limit ("… Warte bitte eine Minute …"), and a
database error ("Entschuldigung, das hat gerade nicht geklappt. Ich habe nichts hinzugefügt. …",
reported to error tracking). Quantities are said in words: "2 l" is "2 Liter", "1 kg" is
"1 Kilo". A phrase heard all in lowercase ("milch ohne laktose") is stored with German capitals
("Milch ohne Laktose").

`SessionEndedRequest`, `System.ExceptionEncountered` and skill events get an empty answer.

### Named lists

Job 207. A household may have several lists; an add goes to the one the user names, else to their
default list in the household (set in the app; none chosen: the first list). The list is never
another household's: the name is matched against the default household's lists only.

- **Why a second intent.** `AMAZON.SearchQuery` must be the only slot in a sample utterance
  (Amazon, "Tips for Using Built-in Slots"; the model build refuses "a phrase slot and another
  intent slot"). So `{list}` cannot join `AddItemIntent`'s `{items}`; `AddToListIntent` has both
  slots in custom types. The phrase slot is `{itemphrase}`: Amazon also refuses one slot name
  with two types, and `{items}` is already `AMAZON.SearchQuery` on `AddItemIntent`.
  `ITEM_PHRASE` and `LIST_NAME` carry sample values (groceries and party
  things; Alltag, Geburtstag, Baumarkt, Party, Wocheneinkauf, …; en: Birthday, Party, Hardware
  store, Weekly shop, …); custom slots also take values outside the list. Its dialog model
  elicits `itemphrase` with the launch prompt, so "füge zur Geburtstag Liste hinzu" asks "Was soll auf
  die Liste?" and keeps the list slot.
- **Alexa may swallow the list into the items.** `AddItemIntent` stays as it was, so "füge
  luftballons zur geburtstag liste hinzu" can arrive there with items "luftballons zur geburtstag
  liste". The server takes a list phrase off the end of the items, the way it does for Siri's
  text (docs/SIRI_SHORTCUT.md, "Target list"): „zur X Liste“, „auf die X Liste“, „to the X list“
  always; bare „zu X“, „to X“ only when X is a list's name exactly. The list slot wins over a
  phrase. A sample's own words („füg {items} zur einkaufsliste hinzu“) never reach the function,
  so with several lists every read-back names the list used („Ich habe Milch auf die Liste Alltag
  gesetzt.“); with one list it says „auf die Snacklist“ as before. Alexa
  sends no raw utterance in an IntentRequest (only the slot values), so the slots are all there is
  to parse.
- **Matching.** Case-insensitive, umlauts folded, a trailing „Liste“/„list“ stripped („Geburtstag
  Liste“ finds „Geburtstag“), exact before fuzzy (Levenshtein ratio at least 0.75, one edit per
  four letters). A list whose name is the spoken word exactly comes first (a list called
  „Einkaufsliste“); otherwise „Liste“, „Einkaufsliste“, „shopping list“ and the app's names name no
  list.
- **Unknown or ambiguous: no question** (docs/DECISIONS.md, job 207). The items go to the default
  list and Alexa says so before the read-back: "Eine Liste „Party“ habe ich nicht gefunden. Ich
  habe Luftballons auf die Liste Alltag gesetzt." or "„Party“ passt zu mehreren Listen. …" (en:
  "I couldn't find a list called Party. I put balloons on the Alltag list."). A clarification
  prompt is easy to drop on Alexa, and the user must not think the items went to Party.
- **Q79 on a named list.** The `Dialog.ConfirmIntent` names the intent the request came with
  (AddToListIntent keeps its list slot) and the session attribute `list` holds the list id; the
  yes or no reads it back, so the answer lands on the same list.
- Dynamic entities (`Dialog.UpdateDynamicEntities` with the household's list names) are not used:
  the server-side match covers what a static `LIST_NAME` misses.

**Integration lock: Alexa stays free (job 72).** The skill is not part of Snacklist Premium
(Peter Q39, Legal Review N-27). The alexa function never asks the integration lock, and
`integration_gate` answers `alexa` open even with `integration_lock` on (for a function deployed
before job 72). Its Zugänge tile never shows as paused. Siri and MCP: docs/PURCHASES.md,
"Integration lock".

## Account linking

Alexa links accounts with the OAuth 2.0 authorization code grant. **Supabase Auth's OAuth 2.1
server (the one the MCP server uses) does it directly; no shim.** Checked against its source
(`supabase/auth`, `internal/api/oauthserver`) and end to end on the CI stack:

- It accepts **confidential clients** (`token_endpoint_auth_method` `client_secret_basic` or
  `client_secret_post`), also through dynamic client registration, and checks the secret at the
  token endpoint.
- It **requires PKCE** (`code_challenge` with S256 or plain) on every authorization. Alexa sends
  PKCE when the skill turns it on (`pkceConfiguration: {status: ENABLED, codeChallengeMethod:
  S256}` in the account-linking request, "PKCE" in the console), so it must be on.
- Redirect URIs match exactly; the client is registered with all three Alexa URLs
  (`https://pitangui.amazon.com/api/skill/link/<vendor id>`, `https://layla.amazon.com/…` for
  Europe incl. de-DE, `https://alexa.amazon.co.jp/…`).
- The token answer has `expires_in` (1 h) and a `refresh_token`; Alexa refreshes with HTTP Basic.
  A refresh keeps the session, so the function's session check keeps passing.
- No scopes are configured; Supabase applies its default.

The user sees the app's consent page (`/oauth/consent`, the one MCP clients get) with
"Amazon Alexa", signs in there if needed and taps "Erlauben". The link then shows under
Mehr → Zugänge as "Amazon Alexa".

| Alexa console, Account Linking | Value |
| --- | --- |
| Authorization grant type | Auth Code Grant |
| Your Web Authorization URI | `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/oauth/authorize` |
| Access Token URI | `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/oauth/token` |
| Your Client ID / Secret | from `scripts/alexa-oauth-client.sh <vendor id>` (the secret is shown once) |
| Your Authentication Scheme | HTTP Basic (Recommended) |
| Scope | none |
| Domain List | `app.snacklist.app`, `app.hummlist.com`, `jdwqrallbpdbshrdhenk.supabase.co` (keep the old host until S5: the consent page moves with the Supabase Site URL) |
| PKCE | on, S256 |
| Allow users to enable skill without account linking | off |

### Unlinking and revocation

A revoked or expired token is treated as unlinked: the LinkAccount card, nothing added. The
token is refused as soon as its Supabase session is gone (`authenticate` checks the session on
every request, not only the JWT's expiry). That happens when:

- the user taps "Amazon Alexa trennen" under Mehr → Zugänge (revokes the grant, deletes its
  sessions and refresh tokens);
- the user **disables the skill** in the Alexa app: Alexa sends `AlexaSkillEvent.SkillDisabled`
  (subscribed in `skill.json`). It carries only Alexa's user id, so the function keeps a map of
  which Snacklist session each Alexa account holds (`alexa_links`, the Alexa id SHA-256 hashed,
  written on every request) and deletes those sessions (`alexa_revoke`);
- the user **links again** (`AlexaSkillEvent.SkillAccountLinked`): the sessions that Alexa
  account held before are revoked, the new one stays;
- the account is deleted (the sessions go with the user) or the user signs out everywhere.

"Unlink" in the Alexa app without disabling the skill sends no event: Alexa deletes the access
and refresh token it held, so the next request comes without a token and gets the link prompt.
The grant stays listed under Zugänge until it is removed there, the skill is linked again or
disabled, or it goes unused for 12 months; nobody holds a token for it (Alexa had the only copy).

### What is kept, and for how long

Legal Review N-24 and N-28 (privacy §7), migration `20261102093000_alexa_cleanup.sql`:

| Data | Deleted |
| --- | --- |
| `alexa_links` row (Alexa id hash, session, `last_seen`) | with its session, right away (trigger on `auth.sessions`): Zugänge "trennen", SkillDisabled, linking again, signing out everywhere, account deletion |
| `alexa_rate` counter | with the user's last link, right away; otherwise by the daily job once its minute has passed |
| The grant (`auth.oauth_consents`, the Zugänge entry) | SkillDisabled: right away, once the user holds no other Alexa session. "trennen": GoTrue only marks it revoked; the daily job deletes it |
| An Alexa session and its link unused for 12 months | by the daily job, then its grant with it |

The daily job is `public.purge_alexa()` (pg_cron `purge-alexa`, 03:29 UTC). It also deletes
links whose session is gone and Alexa grants with no session left (a day's grace while a link
is in progress). "Unused" means no request moved `last_seen` and Alexa did not refresh the
token. The Alexa client is the one whose redirect URIs are Amazon's account linking URLs
(`public.alexa_client_ids()`), not the one named "Amazon Alexa".

## Request verification

Amazon requires it of every skill hosted outside Lambda; `verify.ts`, unit-tested rule by rule in
`verify_test.ts`:

1. `SignatureCertChainUrl`: `https`, host `s3.amazonaws.com` (any case), path starting with
   `/echo.api/` (case-sensitive, after normalizing `..`), port 443 if given, no user info.
2. The chain behind it (fetched once per worker and path, without the URL's query string, 3 s
   timeout, at most 64 KiB, at most 16 fetched chains kept): the first
   certificate valid now and with the SAN `echo-api.amazon.com`; each certificate signed by the
   next one (a CA, valid now) until one is signed by a pinned root: Amazon Root CA 1-4 and
   Starfield Services Root CA - G2 ([`anchors.ts`](../supabase/functions/alexa/anchors.ts)). A test
   checks Amazon's real `echo-api-cert-12` chain against them. **If Amazon moves to another root,
   add it there.**
3. `Signature-256`: RSA PKCS#1 v1.5 with SHA-256 over the raw body bytes.
4. `request.timestamp` at most 150 s from now; one hour for `AlexaSkillEvent.*` (they are delivered
   later and retried, as the ASK SDK allows).
5. The application id (`context.System.application.applicationId`, else the session's) is one of
   `ALEXA_SKILL_ID`. Without it every request is refused.

Any failure answers 400 `{"error": "<reason>"}` before the database is touched.

## Configuration

| Variable | Where | What |
| --- | --- | --- |
| `ALEXA_SKILL_ID` | Supabase secrets (hosted), `supabase/functions/.env` (local) | the skill id(s), comma-separated, `amzn1.ask.skill.…`. Not secret, but configuration, so not in code |
| `ALEXA_TEST_ROOT_PEM`, `ALEXA_TEST_CHAIN_PEM` | local `supabase/functions/.env` only | the test CA (base64 PEM). Honoured only when the function runs in a local stack (`SUPABASE_URL` is `http://kong:8000`); in a hosted project they are ignored |
| `POSTHOG_PROJECT_API_KEY`, `POSTHOG_HOST` | as for every function (job 19) | error tracking and the `item_added` event |

The account-linking client secret lives only in the Alexa console (Amazon keeps it); Supabase
keeps its hash. It is never in the repo, the function's environment or a log.

## Analytics and privacy

- An add over Alexa is counted as `item_added` with `source: alexa`, `actor_role` and
  `household_size`, once per item that was not on the list yet, **only if the user's newest
  answer to the analytics question in the app was yes** (docs/ANALYTICS.md). The app records each
  install's answer on the server (`record_analytics_consent`) when the user answers, switches it
  under More, or signs in; the event goes out under that install id. No item names, utterances,
  Alexa ids or tokens in any event or log; the server catalog allows nothing else.
- Errors reach PostHog error tracking (project 319492) through `withTelemetry` and
  `telemetry.exception`, tagged `function_name: alexa`, scrubbed (no names, no tokens).
- Amazon processes the voice audio and the transcript. The privacy policy must name the skill
  before certification (NEEDS_PETER, Job 31).
- "Meine Daten exportieren" lists the stored analytics answers and the Alexa links (last use).

## Request log

The function writes exactly one line per request to its log (`requestLine` in
`supabase/functions/alexa/handler.ts`), so a missing line means the request never reached
Snacklist:

```
alexa: <request type> <intent name|-> <locale|-> linked=<true|false> -> <reply kind> [reason] rid=<id end> slot=<words|-> confirm=<status|-> ended=<reason|-> error=<type|-> ms=<n>
alexa: IntentRequest AddItemIntent de-DE linked=true -> added rid=3f2a9c1d0b7e slot=3 confirm=NONE ended=- error=- ms=812
alexa: AlexaSkillEvent.SkillAccountLinked - - linked=true -> empty rid=8d0e11aa42c1 slot=- confirm=- ended=- error=- ms=640
alexa: IntentRequest ReadListIntent de-DE linked=true -> link invalid_token:session_ended rid=c1d0b7e3f2a9 slot=- confirm=NONE ended=- error=- ms=31
alexa: SessionEndedRequest - de-DE linked=true -> empty rid=0b7e3f2a9c1d slot=- confirm=- ended=ERROR error=INVALID_RESPONSE ms=3
alexa: - - - linked=false -> refused bad_signature rid=- slot=- confirm=- ended=- error=- ms=41
```

Job 170 added the fields after the reply kind, for following a device test live
(`scripts/voice/tail.sh`, `docs/voice/TEST-SESSION-2026-11-08.md`):

- `rid`: the last 12 characters of Alexa's request id, to match the console's device log.
- `slot`: how many words Alexa heard for the items (`-` when the intent has no items slot). The
  words themselves never.
- `confirm`: the intent's confirmation status (`NONE`, `CONFIRMED`, `DENIED`), the Q79 yes or no.
- `ended` and `error`: a `SessionEndedRequest`'s reason and Alexa's error type. `ended=ERROR
  error=INVALID_RESPONSE` is Alexa refusing the previous answer ("Problem mit der Antwort des
  Skills"); `ENDPOINT_TIMEOUT` is an answer later than 8 s.
- `ms`: how long the function took, verification included.

- `linked` says whether Alexa sent an access token (for `SkillAccountLinked`, the one in the event
  body). `linked=true -> link <reason>` means Snacklist rejected the token, and the reason says
  why (job 170b): `invalid_token:<check>` with the check it failed (`InvalidTokenDetail` in
  `supabase/functions/_shared/auth.ts`). A `SkillAccountLinked` event whose new token is rejected
  logs the same reason after `empty`. The reasons and their next step are in
  [Troubleshooting](#troubleshooting); `diagnose.sh` prints the step under the requests.
- Reply kinds: `link` (link card), `no-household`, `launch`, `added`, `ask` (the yes/no question about a branded open item, Q79), `read`, `help`, `goodbye`,
  `reprompt` (the one second try), `not-understood`, `too-long`, `rate-limited`, `empty` (session end, `System.ExceptionEncountered` and the skill
  events, which want no speech), `error` (the apology or a 500; the exception is in PostHog error
  tracking) and `refused` (verification failed, with its reason, or not a POST; nothing from the
  body is trusted, so type, intent and locale are `-`).
- Never in the line: tokens, Alexa, user, household or session ids, item names, utterances,
  Alexa's error message, IP addresses. Each field is cut to one word of `[A-Za-z0-9_.:-]`. `handler_test.ts` ("job 74")
  feeds tokens, ids and item names through every kind and checks none appears.

Read it in the dashboard (Edge Functions → alexa → Logs) or through the Management API, about the
last 24 hours per query (`SUPABASE_ACCESS_TOKEN` from the ops env):

```bash
curl -sS -G "https://api.supabase.com/v1/projects/jdwqrallbpdbshrdhenk/analytics/endpoints/logs" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  --data-urlencode "sql=select timestamp, event_message from logs where source = 'function_logs' and event_message like 'alexa: %' order by timestamp desc limit 50" \
  --data-urlencode "iso_timestamp_start=$(date -u -d '-23 hours' +%FT%TZ)" \
  --data-urlencode "iso_timestamp_end=$(date -u +%FT%TZ)"
```

`source = 'function_edge_logs'` has the same requests with status and response size, if a line
is missing.

## Troubleshooting

Start with one question: did the request reach Snacklist? Every request the function receives
writes one [request line](#request-log). So a request with no line was stopped at Amazon, and
nothing in this repo can fix it.

```bash
scripts/alexa/diagnose.sh --last 2h
scripts/alexa/diagnose.sh --from '2026-11-03 07:00' --to '2026-11-03 12:00'   # Europe/Berlin, at most 24 h
```

It reads the production logs and the database without writing anything (`SUPABASE_ACCESS_TOKEN`
from the ops env). It prints three sections. **Requests** has one row per call to the `alexa`
function, with status, duration and the request line. A call that crashed before it could log
shows as a row without a line. **Account linking** has the Amazon Alexa client's OAuth steps:
authorize, the consent page, consent, and the token exchanges and refreshes, each with its status
and error code. **alexa_links now** has the links, live sessions, live refresh tokens and the
last use. It prints no tokens, e-mail addresses, names or IP addresses. Ids appear only as an
8-character hash, so rows of the same flow can be matched.

To check the path from Amazon to the function without an Echo, run
`ALEXA_SKILL_ID=… scripts/alexa/smoke.sh` where the ASK CLI is signed in (the box). Amazon
signs a de-DE LaunchRequest and sends it to the endpoint. Unlinked, it must come back with the
LinkAccount card. Linked (`ALEXA_SMOKE_TOKEN`, an access token of a test account), it must come
back with the launch prompt. `--dry-run` prints the requests without calling Amazon. If the
smoke test passes but the Echo still fails, the endpoint and its verification work, and the
fault is in how Amazon routes that device's requests.

| What Alexa says or shows | Reached Snacklist? (diagnose.sh) | Likely cause | Fix |
| --- | --- | --- | --- |
| Nothing, „Ich weiß nicht“, „Das weiß ich leider nicht“, or Alexa's own shopping list opens | No row at that time | Alexa did not route to the skill. Either she misheard „Snacklist“, or the Echo's account has no enabled skill (see the beta rules below) | Alexa app → Mehr → Aktivität → Sprachverlauf shows what she heard. Say „Alexa, öffne snacklist“, clearly in one word. Then check the beta rules |
| „Du hast 26 Artikel auf deiner Einkaufsliste“ (any „… Artikel auf deiner Einkaufsliste“) | No `ReadListIntent` row | Alexa's own shopping list answered, not Snacklist. The skill always says „Auf der Snacklist stehen N Sachen: …“ and counts only open items of the linked household (`_shared/read_open_only_integration_test.ts`). On 2026-11-08 Peter heard this at about 14:35 with 3 open items; the last request that reached the skill was an add at 14:33 (job 172) | Say „Alexa, frag snacklist, was auf der Liste steht“, clearly in one word, or „Alexa, öffne snacklist“ and then „Was steht auf der Liste?“. Alexa app → Mehr → Aktivität → Sprachverlauf shows what she heard; Alexa app → Listen → Einkaufsliste holds the items she counted |
| „Beim Verbinden mit dem angeforderten Skill ist ein Problem aufgetreten“ or „Bei der Antwort des angeforderten Skills ist ein Problem aufgetreten“ | No row | Amazon did not call the endpoint for this account or device. On 2026-11-02 and 2026-11-03 this was the case for every spoken request: linking worked, and no LaunchRequest ever arrived | Check the beta rules, then run smoke.sh. If smoke.sh passes, the endpoint is fine and the problem is on Amazon's side: the account, the device, Alexa+, or the marketplace |
| the same | `-> refused <reason>` | The function refused the request. `wrong_skill` means the function's `ALEXA_SKILL_ID` secret is not this skill's id. `stale_timestamp` means a clock more than 150 s off. `cert_*` or `bad_signature` means the request was not signed by Amazon | `wrong_skill`: set the secret ([Deploy](#deploy), step 5). Otherwise check that the console's endpoint is the URL in the table at the top |
| the same | `-> error`, a 5xx, or a row with no line | Our bug, or the function did not answer in time. Alexa gives up after about 8 s | The exception is in PostHog error tracking. The row's duration shows a timeout |
| „Es ist ein unerwartetes Kommunikationsproblem aufgetreten“ | No row | Amazon's own failure before the skill was chosen. One possible cause is Alexa+ (Early Access) handling a beta skill; that is a guess, Amazon does not document it | Try once more, try the Alexa app on the phone, and check whether the Echo is on Alexa+. If it repeats with no row, it is Amazon's problem; note the time and the device |
| the same | A row | Read its kind as above | |
| „Bitte verknüpfe zuerst dein Snacklist-Konto …“ and a LinkAccount card in the Alexa app | `linked=false -> link` | Alexa sent no token. The Amazon account the Echo uses has the skill enabled but not linked. Often this is a different account from the one that linked | Link in the Alexa app of the Echo's account: Skills → Snacklist → Konto verknüpfen |
| the same | `linked=true -> link invalid_token:session_ended` | The link's session is gone: the link was removed under Zugänge, the account was signed out everywhere or deleted, or a reused refresh token revoked it | Link again. Still `session_ended` right after a fresh link: check the Access Token URI as for `issuer` |
| the same | `linked=true -> link invalid_token:expired` | Alexa sent an access token past its expiry: its refresh failed. diagnose.sh shows a `token refresh_token` row with an error, often `refresh_token_already_used` (DECISIONS „Job 91“) | Link again |
| the same | `linked=true -> link invalid_token:not_oauth` or `:unknown_key` | A valid Snacklist app session, API key or Siri credential, not an OAuth token from account linking | Console › Account Linking: the Client ID must be the „Amazon Alexa“ OAuth client (`scripts/voice/health.sh` prints its id), the URIs as in [Account linking](#account-linking). Then link again |
| the same | `linked=true -> link invalid_token:issuer`, `:audience`, `:signature`, `:claims` or `:malformed` | The token is not a user token from this project's auth server: the Access Token URI points at another host or project, or the signing keys were rotated (`signature`) | Check the Authorization and Access Token URIs against [Account linking](#account-linking), then link again |
| the same | `linked=true -> link invalid_token:unverified` | Snacklist could not check the token: its key set did not load | Try again. If it repeats, look for an auth outage in the function logs. Linking again does not help |
| the same | `-> empty invalid_token:<check>` on `SkillAccountLinked` | Linking finished in the Alexa app, but Snacklist rejects the new token. Requests after it log `-> link` with the same reason | The row for that reason above |
| Skill not found: no Snacklist in the Alexa app's skill search, or „Ich konnte den Skill nicht finden“ | No row | The skill is not live. Only beta testers can see it, through their invitation link, on amazon.de | Open the invitation link while signed in to the invited Amazon account (beta rules) |
| The Alexa app reports that linking failed | No new link in alexa_links | Check the Account linking section. A 403 `bad_jwt` on `authorization` means the Snacklist sign-in in the browser had expired, and the consent page asks to sign in again. A `token` row that is not 200 means a problem with the client secret or PKCE | Try linking again and sign in on the consent page. A token error: [Account linking](#account-linking) |

**Beta rules.** All four must hold for the Echo that is being tested:

1. The beta invitation goes to the e-mail address of the Amazon account **the Echo is registered
   to**: Alexa app → Geräte → the Echo → „Registriert für“. Another household member's account
   does not count, and neither does the voice profile of the person speaking.
2. The skill is enabled **and** linked on that same account, from the invitation link.
3. The device language is **Deutsch (Deutschland)**: Alexa app → Geräte → the Echo → Sprache.
4. The account is on the **amazon.de** marketplace (Alexa app → Einstellungen → Info: host
   `alexa.amazon.de`). The skill's de-DE locale is only offered there.

In the developer console, Test tab, stage „Entwicklung“, typing „öffne snacklist“ in Deutsch
(Deutschland) should log a LaunchRequest in diagnose.sh. The SMAPI simulator (`simulate-skill`,
`scripts/alexa-simulate.sh`) has answered „did not resolve to any intent“ for every utterance
since October, and nothing ever reached the function. Treat that as a SMAPI artefact, not as
evidence ([ALEXA_CERTIFICATION.md](ALEXA_CERTIFICATION.md), Results). smoke.sh is the check to
trust.

## Invocation name and Alexa's own lists

**Languages.** `alexa/voices.ts` picks the language per request from `request.locale`: de-DE
(and a request without a locale) is German (`speech.ts`, `voice/parse.ts`, German capitals for
names heard in lowercase); every en-* locale is English (`speech_en.ts`, `voice/parse_en.ts`,
names stored as heard, like Siri in English). The five English models are one model
(`skill_package_test.ts` keeps them identical). English one-shots: "Alexa, ask snacklist to add
milk", "Alexa, tell snacklist we need milk", "Alexa, ask snacklist what's on the list"; "Alexa, add
milk to Snacklist" goes to Alexa's own lists, as in German.

The invocation name is `snacklist` in every locale (S4 of the Hummlist → Snacklist rename,
2026-11-10). Hummlist used the split form `humm list` (Q75 IN1, Peter, 2026-11-05), because German
Alexa did not select the one-word „hummlist“; the one-word „snacklist“ already runs as the
development invocation of the Snacklist skill (`ad766331…`) in all six locales. If a German Echo
mishears it (or hears only „Liste“ and opens her own shopping list), „Alexa, öffne snacklist“
first, then the items, is the fallback. Certification later needs brand proof for a one-word
invocation (plan §6); the skill stays unpublished until then.

Alexa's built-in lists take any sentence without the invocation pattern: „Alexa, setz Milch auf
die Hummlist“ ended at „Ich konnte keine Liste finden unter Hummlist“ (heard before S4; the same
holds for Snacklist). Only „Alexa, sag/frag
snacklist, …“ and „Alexa, öffne snacklist“ reach the skill. The guide lists those phrasings, and
`site/test/content.test.mjs` checks that each „Alexa, sag/frag <Name>, …“ in the guides matches
a sample utterance of the de-DE model; `skill_package_test.ts` keeps the common one-shot forms
(„ich brauche Milch“, „füge Milch hinzu“, „setz Milch drauf“) in the model.

## Deploy

Deployed by job 31b (2026-10-30) to Peter's Amazon Developer account: skill
`amzn1.ask.skill.fee316d1-e9c1-44a4-a06e-955fbda63a1b` (development stage, de-DE), account linking
with the Supabase client "Amazon Alexa", development testing on, a beta test created (pre-launch)
with no testers. Status and smoke results: [done/31b-alexa-deploy.md](done/31b-alexa-deploy.md).
The steps below are how it was done and how to redo it.

Job 174 (2026-11-10) added a second skill, "Snacklist", with the id
`amzn1.ask.skill.ad766331-e979-4a6e-95f1-30198b0a34cb`. It is in the development stage only, with
the invocation „snacklist“ in all six locales, the same endpoint and the same account linking. Its
beta test ran with Lea and Max until the public launch. The hosted `ALEXA_SKILL_ID` is
`amzn1.ask.skill.fee316d1-e9c1-44a4-a06e-955fbda63a1b,amzn1.ask.skill.ad766331-e979-4a6e-95f1-30198b0a34cb`,
so the function takes requests from both skills. The scripts take one id in `ALEXA_SKILL_ID`; pass
the skill you mean. Since S4, `alexa/skill-package/` holds Snacklist's name, invocation and
snacklist.app privacy URLs: deploy it to the Snacklist skill only. Deploying it to the Hummlist
skill would rename that one to Snacklist too.

1. **ASK CLI.** `npm install -g ask-cli` (v2), then `ask configure` and sign in with the
   developer account (opens a browser; `ask configure --no-browser` on a server). The vendor
   id: `ask smapi list-vendors`.
2. **Create the skill** from the package: `cd alexa && ask deploy --target skill-metadata`.
   It creates the skill "Snacklist" (development stage), uploads `skill.json`, the de-DE model and
   the icons, and builds the model. The skill id lands in `alexa/.ask/ask-states.json`
   (gitignored). Check: `ask smapi get-skill-status -s <skill id>` shows the de-DE model
   `SUCCEEDED`.
3. **OAuth client.** `scripts/alexa-oauth-client.sh <vendor id>`. It prints the client id and the
   secret once.
4. **Account linking.** Without writing the secret to a file in the repo:

   ```bash
   jq --arg id "<client id>" --arg secret "<client secret>" \
     '.accountLinkingRequest.clientId = $id | .accountLinkingRequest.clientSecret = $secret' \
     alexa/account-linking.json > /tmp/alexa-linking.json
   ask smapi update-account-linking-info -s <skill id> --account-linking-request file:/tmp/alexa-linking.json
   rm /tmp/alexa-linking.json
   ask smapi get-account-linking-info -s <skill id>   # PKCE on, S256; no secret shown
   ```

   If the CLI refuses `pkceConfiguration`, set it in the console (Build → Account Linking →
   "PKCE" on, S256) and remove it from the file.
5. **Skill id for the function.** The lead (Supabase access token): `supabase secrets set
   ALEXA_SKILL_ID=<skill id> --project-ref jdwqrallbpdbshrdhenk`. The function itself is deployed
   by `supabase-deploy.yml` with every merge; `scripts/smoke-remote.sh` checks that an unsigned
   request gets 400.
6. **Try it** in the console's Test tab (Development) or on an Echo signed in as the developer
   account, after linking in the Alexa app (Skills → Snacklist → Konto verknüpfen). The beta
   checklist below is the full run.

Changes to the model, manifest or icons later: commit them, then run
`ALEXA_SKILL_ID=<skill id> scripts/alexa-deploy-dev.sh` where the ASK CLI is signed in (the box,
job 69). Job 207's `AddToListIntent` and its slot types go out the same way, to the development
stage only (no publishing, no certification):
`ALEXA_SKILL_ID=amzn1.ask.skill.ad766331-e979-4a6e-95f1-30198b0a34cb scripts/alexa-deploy-dev.sh`.
The function answers both intents before the model has them; until the deploy, a list name
spoken inside `AddItemIntent`'s items is parsed on the server. It writes the state file below, runs `ask deploy --target skill-metadata` (development
stage only), restores `alexa/`, waits for the de-DE model build and checks over SMAPI that the
development stage serves the name „Snacklist“, the invocation name `snacklist` and both icons. By
hand: `ask deploy --target skill-metadata` from `alexa/`. In a checkout without `alexa/.ask/ask-states.json`, write it first, or ask deploy
creates a second skill:

```bash
mkdir -p alexa/.ask && jq -n --arg id "$ALEXA_SKILL_ID" \
  '{askcliStatesVersion: "2020-03-31", profiles: {default: {skillId: $id}}}' > alexa/.ask/ask-states.json
```

ask deploy rewrites `skill.json` and `ask-resources.json` in its own JSON style; discard that
(`git checkout -- alexa/`). It also keeps only what is inside `manifest`, which is why
`manifestVersion` sits there (`skill_package_test.ts` checks it).

**Smoke test without a device.** `scripts/alexa/smoke.sh` ([Troubleshooting](#troubleshooting))
wraps `ask smapi invoke-skill-end-point -s <skill id> --endpoint-region Default
--skill-request-body file:<request.json>`, which makes Amazon sign a request and send it to the
function: an unlinked LaunchRequest or AddItemIntent answers "Bitte verknüpfe
zuerst dein Snacklist-Konto …" with a LinkAccount card, and the function logs
`alexa: LaunchRequest - de-DE linked=false -> link` ([Request log](#request-log)). A refused one
logs `alexa: - - - linked=false -> refused <reason>` and answers 400.

## Beta and certification (pre-launch history; the skill is live since 2026-11-16)

Both need Peter's yes first ([NEEDS_PETER.md](NEEDS_PETER.md), Job 31). Neither needs the other:
beta testing runs without certification.

**Beta (up to 500 testers, no certification).** Console → Distribution → Availability → Beta
Test: add the testers' e-mail addresses (their Amazon accounts), start the beta; Amazon mails each
an invitation link. Peter, Lea, Max and Barbie first.

**Beta checklist (on a real Echo or the Alexa app, each tester):**

1. Alexa app → Skills → "Snacklist" (from the beta link) → aktivieren → Konto verknüpfen: the
   Snacklist consent page shows "Amazon Alexa"; sign in, "Erlauben"; the Alexa app says the
   account is linked. In Snacklist, Mehr → Zugänge lists "Amazon Alexa".
2. "Alexa, sag snacklist, füg Milch hinzu": Alexa says "Ich habe Milch auf die Snacklist gesetzt.";
   Milch appears on another member's phone within 5 seconds, in Kühlregal (AC1, AC3).
3. "Alexa, sag snacklist, füg Milch und Eier hinzu": "Ich habe Eier … Schon auf der Snacklist:
   Milch." Then with two new things ("Brot und Äpfel"): "Ich habe Brot und Äpfel auf die Snacklist
   gesetzt." (AC2).
4. "Alexa, sag snacklist, füg zwei Liter Hafermilch hinzu": the app shows "Hafermilch" with 2 l.
5. "Alexa, öffne snacklist", then mumble something: "Das habe ich nicht verstanden. Was soll auf
   die Liste?"; mumble again: "… Ich habe nichts auf die Snacklist gesetzt."; nothing added (AC4).
6. "Alexa, frag snacklist, was auf der Liste steht": the open items, at most 10 (AC6 of the spec's
   read-back).
7. Disable the skill in the Alexa app, enable it again without linking: "Alexa, sag snacklist, füg
   Brot hinzu" asks to link the account; nothing added; Zugänge no longer lists "Amazon Alexa"
   (AC8).
8. Link again, then Mehr → Zugänge → "Amazon Alexa trennen": the next request asks to link (AC8).

**Certification**: [ALEXA_CERTIFICATION.md](ALEXA_CERTIFICATION.md) has what is ready, what
Amazon's validation said and what is left (the test account, the submit). The privacy policy URLs
are in `skill.json` (`/datenschutz`, `/en/privacy`); no terms URL until the terms pages are live.
The testing instructions are in `skill.json` too, without credentials (the test account goes
into the console field only).
The spoken invocation is `snacklist` (S4). The display name "Snacklist" is the product's brand
(the app's name in the stores).

**Testing instructions**: `publishingInformation.testingInstructions` in `skill.json`, German and
English, checked by `skill_package_test.ts` (no credentials).

## Testing

- `deno test` in `supabase/functions` (the functions gate): `alexa/verify_test.ts` (each
  verification rule, Amazon's real chain), `handler_list_test.ts` (job 207: named lists, unknown
  and ambiguous names, Q79 on a named list), `handler_test.ts` (intents, read-back, re-prompt,
  unlinked and revoked, two households and a switch, errors, rate limit, long input, analytics
  and error-tracking payloads), `skill_package_test.ts` (AC11 and the package's structure),
  `config_test.ts` (the test CA only in a local stack). English: the `English …` tests at the end
  of `handler_test.ts`, and every locale's model in `skill_package_test.ts`.
- `alexa/store_integration_test.ts` against the stack's database (the db gate): the production
  wiring adds and reads like the app, keeps households apart, limits, links and revokes.
- `supabase/tests/alexa.test.sql` (pgTAP): no client reaches the tables or functions; the
  consent RPC; the rate limit; links and revocation; the export; what is kept and the daily job.
- `e2e/tests/alexa.spec.ts` (the e2e gate, CI): account linking with a confidential client, PKCE
  and the layla redirect through the app's consent page, a refresh, signed requests adding
  "Milch" visible on another member's screen within 5 s, categories as typed, re-prompt,
  revocation in Zugänge and by SkillDisabled (the link, the counter and, for SkillDisabled, the
  Zugänge entry gone right away), two households and a switch, forged, stale and
  foreign-skill requests refused. `e2e/tests/alexa-en.spec.ts`: the same linking, then an en-US
  add, duplicate and read in English. It writes a redacted transcript of the linking
  (`alexa-account-linking-transcript.txt` in the screenshots artifact).
- By hand on a local stack: `scripts/alexa-test-ca.sh` runs with every `supabase_up`
  (scripts/lib.sh); restart the stack once if it was running before. Then
  `scripts/alexa-say.sh --launch`, `scripts/alexa-say.sh --token <access token> "Milch und Eier"`,
  `--read`, `--unsigned`, `--stale`, `--disable`. `--list Geburtstag "Luftballons"` sends
  `AddToListIntent` with both slots (job 207); a Q79 answer is
  `--confirm CONFIRMED --attributes '{"list":"<list id>"}'` with the question's items. An access token comes from the linking flow
  above (the e2e helpers), or any OAuth client's token for the user.
