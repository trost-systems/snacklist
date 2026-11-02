# The hummlist.com waitlist (job 82, Spec #10)

hummlist.com shows a landing page with a waitlist form instead of links to the browser app. A
sign-up is double opt-in: the address counts only after its owner presses a button on the
confirmation page. Confirmed sign-ups collect into weekly batches, and Peter invites a batch by
hand with `scripts/waitlist/invite.ts`. Nothing invites anyone automatically.

Privacy rule: no bot or agent reads waitlist rows. Tests use only addresses of the form
`hello+<anything>@hummlist.com`. Nothing logs an address, a token or a request body.

## Off until Peter enables it

| Piece | Off (the default in production) | On |
| --- | --- | --- |
| Site build | `HUMMLIST_WAITLIST` unset in production: the site builds as before job 82 | `HUMMLIST_WAITLIST=on`, or any non-production build (preview, local) |
| Vercel function `/api/waitlist*` | `WAITLIST_UPSTREAM_URL` or `WAITLIST_PROXY_SECRET` unset: 404 | both set |
| Edge function `waitlist` | `WAITLIST_PROXY_SECRET` or `WAITLIST_HMAC_SECRET` unset: 404 | both set, `RESEND_API_KEY` for mail |
| Recipients | `WAITLIST_MAIL_ALLOW` unset: only `hello+…@hummlist.com` are stored and mailed; others get the normal answer and are dropped | `WAITLIST_MAIL_ALLOW=*` |

`HUMMLIST_WAITLIST=off` forces the old site in any build. A production build in waitlist mode
fails while any page or mail template still contains a `⟦…⟧` placeholder (`⟦LAUNCH COPY⟧`,
`⟦LAUNCH COPY FAQ⟧`, `⟦LEGAL W1⟧`, `⟦LEGAL W2⟧`, `⟦LEGAL FOOTER⟧`, `⟦LEGAL privacy.website⟧`) or a
`[PETER: …]`. The edge function refuses to send a template with a `⟦` unless
`WAITLIST_ALLOW_PLACEHOLDERS=1`. That is AC21: production can't go live before the copy and the
legal texts replace the placeholders.

"As before job 82" has one exception: `vercel.json` sends `X-Robots-Tag: noindex` on every path
but `/de` and `/en`, and those two pages say `<meta name="robots" content="noindex">` themselves,
except in a production build in waitlist mode (the PM's override: noindex comes off the landing
pages only). So the old site differs from main's build by that one line on `/de` and `/en`
(`node site/scripts/classic-diff.mjs` proves it), and nothing is indexable until the waitlist goes
live. Guides, legal pages and the confirm and unsubscribe pages keep noindex.

## Request path

```text
browser (hummlist.com, same origin, fetch)
  -> Vercel function site/api/waitlist*  (region fra1; hashes the client IP, never logs)
  -> Supabase edge function waitlist     (x-region: eu-central-1; all logic)
  -> Postgres public.waitlist*           (RLS on, no grants to anon/authenticated)
  -> Resend                              (single sends, no tags, no tracking)
```

The browser never calls `*.supabase.co`. The CSP stays as it is (`connect-src` falls back to
`'self'`; the form posts with `fetch`, so `form-action 'none'` stays).

### Browser to Vercel (`site/api/`)

| Request | Body | Answers |
| --- | --- | --- |
| `POST /api/waitlist` | JSON `{email, platform: "ios"\|"android", locale: "de"\|"en", launch_news: boolean, consent_version, website, elapsed_ms}` | `202 {"status":"ok"}`; `400 {"error":"invalid_email"\|"invalid_platform"\|"invalid_request"}`; `429 {"error":"rate_limited"}`; `503 {"error":"unavailable"}` |
| `POST /api/waitlist/confirm` | JSON `{token}` | `200 {"status":"confirmed"\|"invalid"}` |
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
  `https://hummlist-site-*-peter-trost.vercel.app` and `http://127.0.0.1:<port>` and falls back to
  `https://hummlist.com`.
- `x-region: eu-central-1`, `content-type: application/json`.

It passes the upstream status and JSON body through unchanged; an unreachable upstream is
`503 unavailable`.

### Edge function `waitlist`

- `404` for every request without both secrets set, or without the right
  `x-waitlist-proxy-secret` (timing-safe compare). Unknown paths `404`.
- Sign-up: validates (email trimmed, at most 254 characters, `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`, no
  control characters; platform; locale; `consent_version` must be the current version of that
  locale), then counts the request against the rate limits, then answers `202 ok`. A filled
  honeypot, `elapsed_ms` under 1500 or missing, or a recipient outside `WAITLIST_MAIL_ALLOW` also
  answers `202 ok` and stores nothing. Everything after the answer (the database write, the mail)
  runs in `EdgeRuntime.waitUntil`, so a new address, a known one and a dropped one answer with the
  same body and the same timing (AC6).
- Rate limits (`public.waitlist_rate_hit`): 10 sign-ups per client key per hour, 300 in total per
  hour. Counters hold only the hashed key and a window start, and the purge removes them after
  two hours.
- Confirm and unsubscribe answer only after the work: they reveal nothing about other addresses.
- A sign-up without `x-waitlist-client` is `400 invalid_request`. The counter stores the SHA-256
  of that header, never the header. Every `404` body is `{"error":"not_found"}`; a database
  failure before the answer is `503 unavailable` on every route.
- An unsubscribe with a valid signature answers `deleted` also when the row is already gone, so a
  second press of the same link shows the same page.
- On the local stack (`SUPABASE_URL` is `http://kong:8000`) the answer waits for the deferred
  work: its `oneshot` workers (DECISIONS 3.11) end with the response and drop `waitUntil` work.
- Logs are fixed outcome codes (`waitlist: signup_stored`, `mail_refused_placeholder`,
  `signup_failed 23505`), never an address, token, body, header or Postgres message.

## Data

`public.waitlist`, one row per address (unique on `lower(email)`):

| Column | |
| --- | --- |
| `id` | uuid |
| `email` | as typed, trimmed |
| `email_hmac` | HMAC-SHA256 of `lower(email)` with `WAITLIST_HMAC_SECRET`, hex; copied into the proof record |
| `platform` | `ios` or `android` |
| `locale` | `de` or `en`, from the page |
| `launch_news` | the optional checkbox, default false |
| `consent_text_version` | `waitlist-de-v1` or `waitlist-en-v1`, the text shown under the button |
| `created_at` | |
| `confirm_token_hash` | SHA-256 hex of the confirm token; null once confirmed |
| `confirm_expires_at` | 48 h after the confirmation mail |
| `confirmed_at` | |
| `invite_sent_at`, `launch_mail_sent_at`, `last_mail_at` | |

No IP, no user agent, no `unsubscribed_at`: unsubscribing deletes the row (Legal handoff §3).

`public.waitlist_consent_proof`: `email_hmac`, `consent_text_version`, `locale`, `launch_news`,
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
  locale, launch news and consent version, rotate the token and send the confirmation mail again;
  otherwise nothing.
- **Sign-up, known confirmed address:** nothing.
- **Confirm (POST with the token):** sets `confirmed_at` and clears the token if the token is
  known and not expired, then sends the welcome mail. A used, unknown or expired token answers
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
`*_waitlist.sql`) are `waitlist_signup`, `waitlist_confirm`, `waitlist_mailed`,
`waitlist_unsubscribe`, `waitlist_rate_hit`, `waitlist_batch_counts`, `waitlist_batch_rows` and
`purge_waitlist`; each takes the time as a parameter, so `supabase/tests/waitlist.test.sql` tests
every period to the minute.

## Mails

From `"Peter von Hummlist" <hello@hummlist.com>` (English: `"Peter from Hummlist"`), Reply-To
`hello@hummlist.com`, HTML and plain text, no images, no tracking, no tags or metadata. Resend's
open and click tracking stay off in the domain settings.

| Mail | When | Footer | List-Unsubscribe |
| --- | --- | --- | --- |
| Confirmation | sign-up | (a) with „Eintrag sofort löschen“ | no |
| Welcome | after confirming | (b) | yes, one-click |
| Beta invite | `scripts/waitlist/invite.ts --confirm` | (b) | yes, one-click |

The texts come from the Legal handoff (confirmation mail, footers) and Hummlist Launch (welcome,
invite) and stay behind their `⟦…⟧` markers until Peter approves them.

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
refuses an invite with `⟦…⟧` markers unless `--allow-placeholders`, which works only while
`WAITLIST_MAIL_ALLOW` is unset.
