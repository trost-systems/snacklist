# Job 82: the hummlist.com waitlist (Spec #10)

PR: https://github.com/trost-systems/family-groceries/pull/210 (open, not merged: see
`docs/NEEDS_LEAD.md` "Job 82"). Design and routes: `docs/WAITLIST.md`.

## What was built

- **Site** (`site/`): a waitlist mode. Landing `/de` and `/en` with the form in the hero (email
  with the Apple ID / Google hint, iPhone or Android, optional unticked launch-news box, consent
  text under the button), an FAQ, and no link to or request for app.hummlist.com. Confirmation
  and unsubscribe pages act only when their button is pressed. `/support` becomes an FAQ page
  with support@hummlist.com. Legal's privacy-policy redlines sit in `::: waitlist` blocks. One
  script (`public/waitlist.js`), CSP unchanged.
- **Off in production**: the mode is on only for `HUMMLIST_WAITLIST=on` or non-production builds.
  `site/scripts/classic-diff.mjs` shows the classic production build equals main's, except a
  noindex meta line on `/de` and `/en` that replaces the header there. A production waitlist
  build fails while any `⟦…⟧` placeholder is left (AC21).
- **Vercel function** `site/api/waitlist*` (fra1): hashes the client IP with a daily key,
  forwards to the edge function with a shared secret and `x-region: eu-central-1`, 404 until
  configured, logs only outcome codes.
- **Edge function** `supabase/functions/waitlist`: validation, honeypot, a 3 s
  time-to-submit check, rate limits, double opt-in with hashed single-use 48 h tokens, the same
  answer and timing for new, known and dropped addresses, welcome mail with one-click unsubscribe,
  HMAC-signed unsubscribe links, Resend single sends without tags. Recipients are limited to
  `hello+…@hummlist.com` until `WAITLIST_MAIL_ALLOW=*`, and mails with placeholders are refused.
- **Database** (migration `20261102213606_waitlist.sql`): `waitlist`, `waitlist_consent_proof`,
  `waitlist_rate`, RLS on with no grants to anon or authenticated, service-only functions, daily
  `purge_waitlist` with Legal's periods (7 days, 3 months after the invite, 30 days after the
  launch mail, 2027-12-31, proof 3 years, counters 2 h).
- **Invites**: `scripts/waitlist/invite.ts`. A dry run prints counts, `--confirm <batch>` sends
  and writes the TestFlight/Play CSVs. Peter runs it, never automatically.
- **app.hummlist.com** gets `X-Robots-Tag: noindex` (it had none; AC15).

## How to verify

- `cd site && npm test` (126 tests, Node 22 and 24); `scripts/gates/site.sh`.
- `supabase test db` (waitlist.test.sql: 108 of 1812); `scripts/gates/functions.sh` (waitlist
  handler and mail tests, invite script tests); the integration test with `FG_DB_TEST=1`.
- Browser checks: `flock /tmp/fg-e2e.lock node site/checks/waitlist.mjs site/dist` (108 checks),
  crawl, contrast, Lighthouse (100 accessibility on /de and /en, mobile and desktop, light and
  dark).
- Full stack, local, driven 2026-11-03: Chromium against the site preview with the Vercel
  handlers, then the served edge function, the local database and a stand-in Resend. 16 checks
  passed: DE sign-up; the same address in other letters from EN gives the identical answer
  `202 {"status":"ok"}` and one row with locale de; one confirmation mail from „Peter von
  Hummlist“, no images, with confirm and delete links; opening the confirm link changes nothing,
  the button confirms, the same link again shows the neutral page; welcome mail with
  List-Unsubscribe and List-Unsubscribe-Post; the unsubscribe button deletes the row and leaves
  one proof record (HMAC only); EN sign-up mails from „Peter from Hummlist“, and RFC 8058
  one-click deletes; an invalid email gets 400 and no row; honeypot and too-fast get 202 and no
  row; the per-client rate limit answers 429; no cookies, no off-origin request, no console
  errors. Anon key: select, insert and RPC on the waitlist tables answer 42501. That run found
  a real bug: the plain-text footer put „:“ right after the unsubscribe URL. Fixed (`<url>`),
  with a test.
- CI: ci-ok green on the PR head (see PR).

## Screenshots

`docs/screenshots/82/`: landing DE/EN at 390 and 1440 px, form errors, success, confirm and
unsubscribe pages before and after, and the full-stack run (`e2e-*`).

## Missing or blocked

- Peter: Resend API key, Supabase secrets, Vercel env vars, then the fra1 proof with a logged-in
  request (NEEDS_PETER "Job 82"). Copy and legal texts await his approval; the markers block
  production until then.
- Lead: merge or wait (Legal's "no copy may be merged"), and the ambiguities in NEEDS_LEAD
  "Job 82".

## Review

An independent review (Sonnet) found one must-fix: rate counters could live about 24 h 24 min,
because the purge ran once a day. `waitlist_rate_hit` now deletes windows older than 2 hours
itself, with a pgTAP case. Should-fix items done: drafts are never mailed once
`WAITLIST_MAIL_ALLOW=*`; the time-to-submit floor is 1.5 s (was 3 s); 10 sign-ups per client per
hour (was 5), and IPv6 clients count as their /64; the doc now says the RFC 8058 URL carries id
and signature in its query. Left as is: the honeypot name `website` (it has `autocomplete=off`
and no report of autofill), and spreadsheet escaping in `ios.csv` (addresses go to TestFlight,
not a spreadsheet).
