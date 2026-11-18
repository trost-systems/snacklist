# The snacklist.app waitlist (job 82, Spec #10)

snacklist.app (hummlist.com redirects there) keeps its landing page; only its calls to action
change by stage, and none links the browser app. In the `waitlist` stage they lead to a sign-up form. A sign-up is double opt-in: the
address counts only after its owner agrees on the confirmation page and presses the button there
(Legal N-73: only the person's own click is consent, whoever filled in the form). Confirmed sign-ups collect into weekly batches, and Peter invites a batch by
hand with `scripts/waitlist/invite.ts`. Nothing invites anyone automatically.

Privacy rule: no bot or agent reads waitlist rows. Tests use only addresses of the form
`hello+<anything>@hummlist.com`, `test@snacklist.app` or `test+<anything>@snacklist.app`. Nothing
logs an address, a token or a request body.

## Stages and switches

`site/config/stage.ts` holds the stage in one line (`export const stage: Stage = 'waitlist';`).
Changing it is a one-line PR; it decides the calls to action (site/README.md, "Stages and the
waitlist"):

| Stage | Calls to action | Closing block |
| --- | --- | --- |
| `waitlist` (now) | „Auf die Warteliste“ / "Join the waitlist" | the sign-up form |
| `beta` (built, off) | „Zur Beta anmelden“ / "Join the beta" | the sign-up form |
| `launch` (built, off) | „App laden“ / "Get the app"; store badges in the hero | badges and a QR code for snacklist.app/get |

`/get` (`site/api/get.mjs`) sends an iPhone or iPad to the App Store and Android to Google Play once
`site/config/stores.mjs` has their URLs, and everything else to the landing page.

The site goes live with the merge of the PR into `main`; every other piece stays off until its
secrets are set:

| Piece | Off | On |
| --- | --- | --- |
| Vercel function `/api/waitlist*` | `WAITLIST_UPSTREAM_URL` or `WAITLIST_PROXY_SECRET` unset: 404 | both set |
| Edge function `waitlist` | `WAITLIST_PROXY_SECRET` or `WAITLIST_HMAC_SECRET` unset: 404 | both set, `RESEND_API_KEY` for mail |
| Recipients | `WAITLIST_MAIL_ALLOW` unset: only `hello+…@hummlist.com`, `test@snacklist.app` and `test+…@snacklist.app` are stored and mailed; others get the normal answer and are dropped | `WAITLIST_MAIL_ALLOW=*` |

No build may contain a `⟦…⟧` placeholder: every build fails on one (preview and local too), so the
CI `site` gate catches it. The edge function still refuses to send a mail with a `⟦` unless
`WAITLIST_ALLOW_PLACEHOLDERS=1`, which only works while just test addresses are mailed.

Every response carries `X-Robots-Tag: noindex` until the launch PR removes the header (job 93's
launch guard fails a `launch` build while it is there). The confirm and unsubscribe pages say
noindex in the page and keep it.

## Request path

```text
browser (snacklist.app, same origin, fetch)
  -> Vercel function site/api/waitlist*  (region fra1; hashes the client IP, never logs)
  -> Supabase edge function waitlist     (x-region: eu-central-1; all logic)
  -> Postgres public.waitlist*           (RLS on, no grants to anon/authenticated)
  -> Resend                              (single sends, no tags, no tracking)
```

The browser never calls `*.supabase.co`. The CSP's only change is `form-action 'self'` (was
`'none'`): the form posts with `fetch` (`connect-src` falls back to `'self'`), and without the
script it posts its body to `/api/waitlist` (`method="post"`), so an address never ends up in a URL.

### Browser to Vercel (`site/api/`)

| Request | Body | Answers |
| --- | --- | --- |
| `POST /api/waitlist` | JSON `{email, platform: "ios"\|"android", locale: "de"\|"en", consent_version, website, elapsed_ms}`; a `launch_news` is ignored | `202 {"status":"ok"}` for every sign-up, new, known, dropped or rate-limited; `400 {"error":"invalid_email"\|"invalid_platform"\|"invalid_request"}`; `503 {"error":"unavailable"}` |
| `POST /api/waitlist/confirm` | JSON `{token, confirm_version, launch_news}` | `200 {"status":"confirmed"\|"invalid"}`; `400 invalid_request` for an unknown `confirm_version` |
| `POST /api/waitlist/unsubscribe` | JSON `{id, sig}` | `200 {"status":"deleted"\|"invalid"}` |
| `POST /api/waitlist/unsubscribe?id=…&s=…` | `List-Unsubscribe=One-Click` (RFC 8058, form-encoded) | same |
| `GET /api/waitlist/unsubscribe?id=…&s=…&l=de` | | `303` to the unsubscribe page with the values in the fragment; never deletes |

`website` is the honeypot (hidden, must be empty) and `elapsed_ms` the milliseconds between page
load and submit, set by `public/waitlist.js`. Every answer is `application/json` with
`cache-control: no-store`. Bodies above 2 KB answer `400 invalid_request`.

The Vercel function forwards to `${WAITLIST_UPSTREAM_URL}/{signup|confirm|unsubscribe}` (the
upstream is `https://<ref>.supabase.co/functions/v1/waitlist`) with:

- `x-waitlist-proxy-secret: $WAITLIST_PROXY_SECRET`
- `x-waitlist-client`: hex HMAC-SHA256 of `<UTC date>|<client IP>` keyed with the proxy secret.
  The client IP comes from Vercel's `x-real-ip` (first `x-forwarded-for` entry as a fallback). The
  raw IP never leaves the function, and the key changes every day.
- `x-waitlist-origin`: the site origin the request came to (`https://` + `host`), for the links in
  the mails. The edge function accepts only `https://hummlist.com`,
  `https://snacklist.app` (job 174), `https://hummlist-site-*-peter-trost.vercel.app` and
  `http://127.0.0.1:<port>` and falls back to `https://snacklist.app`. `https://hummlist.com` stays on the
  list while hummlist.com still serves `/api/*` (the one-click unsubscribe links in mails sent before the rename).
- `x-region: eu-central-1`, `content-type: application/json`.

It passes the upstream status and JSON body through unchanged; an unreachable upstream is
`503 unavailable`.

### Edge function `waitlist`

- `404` for every request without both secrets set, or without the right
  `x-waitlist-proxy-secret` (timing-safe compare). Unknown paths `404`.
- Sign-up: validates (email trimmed, at most 254 characters, `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`, no
  control characters; platform; locale; `consent_version` must be the current form text of that
  locale, `CONSENT_VERSIONS` in `consent.ts`), then counts the request against the rate limits,
  then answers `202 ok`. A filled honeypot, `elapsed_ms` under 1500 or missing, a recipient outside
  `WAITLIST_MAIL_ALLOW` or a request over a rate limit also answers `202 ok` and stores nothing.
  `launch_news` is ignored (Legal N-74: an assistant filling in the form must not tick it). Everything after the answer (the database write, the mail)
  runs in `EdgeRuntime.waitUntil`, so a new address, a known one and a dropped one answer with the
  same body and the same timing (AC6).
- Rate limits (`public.waitlist_rate_hit`): 10 sign-ups per client key per hour, 300 in total per
  hour. Counters hold only the hashed key and a window start, and the purge removes them after
  two hours.
- Confirm takes the token, `confirm_version` (one of `CONFIRM_VERSIONS`, the text the
  confirmation page shows) and `launch_news` (the box on that page, unticked by default) and stores
  both with the confirmation. Confirm and unsubscribe answer only after the work: they reveal
  nothing about other addresses.
- A sign-up without `x-waitlist-client` is `400 invalid_request`. The counter stores the SHA-256
  of that header, never the header. Every `404` body is `{"error":"not_found"}`; a database
  failure before the answer is `503 unavailable` on every route.
- An unsubscribe with a valid signature answers `deleted` also when the row is already gone, so a
  second press of the same link shows the same page.
- On the local stack (`SUPABASE_URL` is `http://kong:8000`) the answer waits for the deferred
  work: its `oneshot` workers (DECISIONS 3.11) end with the response and drop `waitUntil` work.
- Logs are fixed outcome codes (`waitlist: signup_stored`, `signup_rate_limited`,
  `confirm_invalid_request`, `signup_failed 23505`), never an address, token, body, header, IP,
  user agent or Postgres message. Nothing records who or what submitted the form (Legal Q5).

## Data

`public.waitlist`, one row per address (unique on `lower(email)`):

| Column | |
| --- | --- |
| `id` | uuid |
| `email` | as typed, trimmed |
| `email_hmac` | HMAC-SHA256 of `lower(email)` with `WAITLIST_HMAC_SECRET`, hex; copied into the proof record |
| `platform` | `ios` or `android` |
| `locale` | `de` or `en`, from the page |
| `launch_news` | the box on the confirmation page, set only at the confirm press; false before |
| `consent_text_version` | the form text the sign-up answered (`waitlist-de-v2`, `waitlist-en-v2`); not the consent |
| `confirm_text_version` | the consent text shown on the confirmation page when the button was pressed (`waitlist-confirm-de-v1`, `waitlist-confirm-en-v1`), migration `*_waitlist_confirm_consent.sql` |
| `created_at` | |
| `confirm_token_hash` | SHA-256 hex of the confirm token; null once confirmed |
| `confirm_expires_at` | 48 h after the confirmation mail |
| `confirmed_at` | |
| `invite_sent_at`, `launch_mail_sent_at`, `last_mail_at` | |

No IP, no user agent, no `unsubscribed_at`: unsubscribing deletes the row (Legal handoff §3).

`public.waitlist_consent_proof`: `email_hmac`, `consent_text_version`, `confirm_text_version`, `locale`, `launch_news`,
`created_at`, `confirmed_at`, `last_mail_at`, `ended_at`, `end_reason`
(`unsubscribed`, `deletion_request`, `purpose_done`). Written when a confirmed row ends; never
used for sending.

`public.waitlist_rate`: `key_hash`, `window_start`, `hits`.

All three: RLS on, no policies, every privilege revoked from `anon` and `authenticated`. The
database functions are `security definer`, executable only by the service connection
(`postgres`/`service_role`).

### Lifecycle

- **Sign-up, new address:** insert with a fresh token and send the confirmation mail.
- **Sign-up, known unconfirmed address:** if the last mail is 24 h old or older, update platform,
  locale and form text version, rotate the token and send the confirmation mail again; otherwise
  nothing. Launch news stays false.
- **Sign-up, known confirmed address:** nothing.
- **Confirm (POST with the token, the confirm text version and the box):** sets `confirmed_at`,
  `confirm_text_version` and `launch_news` and clears the token if the token is known and not
  expired, then sends the welcome mail. A used, unknown or expired token answers
  `invalid` (the neutral page).
- **Unsubscribe (POST with id and signature):** deletes the row at once; a confirmed row first
  writes its proof record (`unsubscribed`). The signature is the HMAC of `unsubscribe:<id>` with
  `WAITLIST_HMAC_SECRET`, so links in old mails keep working.

### Purge (`public.purge_waitlist(now)`, pg_cron daily)

- unconfirmed rows older than 7 days: deleted, no proof record;
- confirmed, without launch news, 3 months after `invite_sent_at`: proof (`purpose_done`), deleted;
- confirmed, with launch news, 30 days after `launch_mail_sent_at`: proof, deleted;
- every row on or after 2027-12-31: proof if confirmed, deleted;
- proof records 3 years after the later of `last_mail_at` and `ended_at`: deleted;
- rate counters older than 2 hours: deleted.

"2027-12-31" is midnight in Europe/Berlin. The database functions (migration
`*_waitlist.sql`, `*_waitlist_confirm_consent.sql`) are `waitlist_signup`, `waitlist_confirm`
(the 4-argument one; the 2-argument one of the first migration is superseded), `waitlist_mailed`,
`waitlist_unsubscribe`, `waitlist_rate_hit`, `waitlist_batch_counts`, `waitlist_batch_rows` and
`purge_waitlist`; each takes the time as a parameter, so `supabase/tests/waitlist.test.sql` tests
every period to the minute.

## Mails

From `"Peter · Snacklist" <hello@snacklist.app>` (same display name in German and English; the middle dot is U+00B7), Reply-To
`hello@snacklist.app`, HTML and plain text, no images, no tracking, no tags or metadata. Resend's
open and click tracking stay off in the domain settings.

| Mail | When | Footer | List-Unsubscribe |
| --- | --- | --- | --- |
| Confirmation (Legal M-1/M-2, `doi-mail-*-v2`) | sign-up | (a) with „Eintrag sofort löschen“ | no |
| Welcome | after confirming | (b) | yes, one-click |
| Beta invite | `scripts/waitlist/invite.ts --confirm` | (b) | yes, one-click |

The confirmation mail is Legal's M-1/M-2 of 2026-11-04 word for word: it says an assistant may
have entered the address and has no launch sentence. The footers are Legal's of 2026-11-02. The
welcome and invite mails are drafts for Snacklist PM. All of it waits for Peter's approval; the PR
is not merged before.

Links: confirm `<origin>/de/warteliste/bestaetigen#t=<token>` (`/en/waitlist/confirm`),
unsubscribe `<origin>/de/warteliste/abmelden#id=<id>&s=<sig>` (`/en/waitlist/unsubscribe`). The
values sit in the fragment, so they reach no server log (only the List-Unsubscribe URL of later
mails carries id and signature in its query, as RFC 8058 needs; no address), and opening a link changes nothing: the
page sends them only when its button is pressed (mail scanners can't confirm or unsubscribe).

## Invites (manual)

`deno run -A scripts/waitlist/invite.ts --batch 2026-W47` prints, for that ISO week of
`confirmed_at` (Europe/Berlin), only counts: confirmed, already invited, to invite, per platform
and locale. `--confirm 2026-W47` (the batch id again) sends the invite mail to each uninvited
row, sets `invite_sent_at` and `last_mail_at`, and with `--export-dir <dir>` writes `ios.csv` and
`android.csv` for TestFlight and Google Play. The full call is
`--batch 2026-W47 --confirm 2026-W47`. `ios.csv` has TestFlight's three columns with empty names
(`,,<email>`), `android.csv` one address a line. It prints counts only. Peter runs it on his own
machine with `SUPABASE_DB_URL`, `RESEND_API_KEY` and `WAITLIST_HMAC_SECRET`; no agent runs
`--confirm`. Each invite's Resend idempotency key is `invite/<batch>/<id>`, and the row is marked
after its send, so a rerun after a crash sends no second invite within Resend's 24 h window. It
refuses an invite with a `⟦…⟧` marker unless `--allow-placeholders`, which works only while
`WAITLIST_MAIL_ALLOW` is unset.

## For assistants

While the stage is `waitlist`, `llms.txt` carries Legal's L-1 text (`site/content/llms-waitlist.md`):
start a sign-up only when asked, expect a pending 202, never open or press confirmation links. No
page, `llms.txt` or API description promises a sign-up without the confirmation, and
`/api/waitlist` stays undocumented (Legal A-1 is the text if it ever is).
