# Job 275: DSA notice-and-action, web part (N-219)

Branch `job/275-dsa-notice-web`, PR: see the BOARD line (not merged: the merge waits for PM's check
and Legal's hash GO). Live without a flag once merged (N-239).

## What was built

- **Report pages** `/inhalte-melden` and `/en/report` on snacklist.app, in the site's style: Legal's
  intro (B.4), the form, then the content rules (B.5, `#regeln` / `#rules`). Fields per N-228:
  kind (six choices), where (required), why (required, 20 to 5,000 characters, with a counter),
  name and e-mail (recommended), the good-faith box (required). CSAM folds name and e-mail away
  with Legal's note. No account, cookie, captcha or third-party request; a honeypot field.
  Every form string is in the page's front matter (`site/content/legal/inhalte-melden.md`,
  `report.md`); `site/report.mjs` renders it, `site/public/report.js` (module) sends it.
- **Confirmation (N-229).** The number (`M-XXXX-XXXX`) on screen at once; Legal's B.4 mail via
  Resend from `no-reply@snacklist.app`, reply-to support@, when an address was given.
- **Path.** `/api/report` (Vercel function, fra1, `site/api/_report.mjs`): 5 per client network
  per hour in memory, forwards with the site's existing proxy secret to the edge function
  `report` (`supabase/functions/report/`), which validates, stores and mails. No new secret.
- **Storage (N-227, N-230).** `public.content_reports` and `public.content_report_decisions`
  (migration `20261117192753_content_reports.sql`): RLS on, no policy, service connection only,
  no household or feedback link; 200 web reports per hour overall as a circuit breaker, a confirmation for
  every report with an address (retried, then `notify.ts --confirmations`). Decisions logged with `content_report_decide`; `scripts/moderation/notify.ts` sends Legal's
  B.6a decision mail. Retention: 12 months after the latest decision, daily pg_cron
  `purge-content-reports`, held while `retain_until` is set.
- **Texts.** Impressum/Imprint contact point (B.3), privacy §10 "Meldungen rechtswidriger Inhalte"
  (B.8), help pages (B.9), all verbatim; footer link „Inhalte melden“ / "Report content" on every
  page. `docs/MODERATION.md`: the daily routine, decision and statement-of-reasons templates
  (B.6a/B.6b), the Art. 18 runbook (B.7), retention.
- Docs: DECISIONS „Job 275“, NEEDS_PETER „Job 275“ (a test report, the daily look; BKA phone-first, registration only once a case arises),
  PRIVACY_DATA_MAP, feature map `report-content.md` + FEATURES-FOR-WRITERS.

## How it was verified

- Full chain on a local stack (port block 577): Playwright at 390 px on both pages → preview
  server `/api/report` → edge function → Postgres → confirmation mail captured by a stand-in
  Resend (`docs/screenshots/275-dsa-notice-web/chain-proof.txt`): numbers shown, rows stored
  trimmed, mails with Legal's text, no cookie, no off-origin request; the anon key gets 401 on
  the table. A decision logged in SQL and rendered by `notify.ts`.
- Screenshots of every state, DE/EN, desktop and phone: `docs/screenshots/275-dsa-notice-web/`.
- Tests: pgTAP `content_reports.test.sql` (69) and the full pgTAP suite (3180, pass); edge
  function unit tests and the DB integration test; `notify.ts` tests; site `npm test` 238/238 on
  Node 22; production site build; `scripts/gates/functions.sh` and `scripts/lint.sh` green;
  axe/CSP crawl and contrast on both pages with no findings.

## Open

- Merge waits for PM's check and Legal's hash GO (NEEDS_LEAD „Job 275“, with the hashes and the
  spots where Legal's text runs ahead of the app).
- Peter: send one test report after the deploy. No BKA registration in advance (N-235 accepted):
  the runbook reports by phone first and registers once a case arises.
- The in-app „Inhalt melden“ entry is its own job (prototype round, flag).
