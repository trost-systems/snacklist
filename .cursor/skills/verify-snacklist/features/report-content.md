# Report content (DSA notice form on snacklist.app)

snacklist.app/inhalte-melden (EN /en/report) is the public form for reporting illegal content in Snacklist (Art. 16 DSA, job 275). No account, no cookie, nothing from other servers, no captcha. Every page's footer links it („Inhalte melden“ / "Report content"), and so do the Impressum's contact point (#dsa), the help pages and privacy policy §10 (#meldungen / #reports). The page is the intro, the form, then „Regeln für Inhalte und wie wir Meldungen bearbeiten“ (#regeln, EN "Content rules and how we handle reports", #rules). A sent report shows its number (`M-XXXX-XXXX`) on the page; with an e-mail address, a confirmation mail follows from no-reply@snacklist.app. Peter decides each report himself (`docs/MODERATION.md`). The in-app entry (job 281, flag `report-content-entry`, off for everyone) is the sub-feature `rc-app`: it posts to the same function's `/report/app` route with the user's session.

## Sub-features

- `form` „Worum geht es?“ (six choices, required), „Wo ist der Inhalt?“ (required), „Warum ist der Inhalt rechtswidrig?“ (required, 20 to 5,000 characters, counter „0 / 5.000“), „Dein Name“ and „Deine E-Mail-Adresse“ (both „empfohlen“), the good-faith box (required), „Meldung senden“. Every word is Legal's, from the page's front matter (`site/content/legal/inhalte-melden.md`, `report.md`).
- `csam` choosing „Darstellung sexuellen Kindesmissbrauchs“ shows „Bei Darstellungen sexuellen Kindesmissbrauchs kannst du ohne Namen und E-Mail-Adresse melden.“ and folds name and e-mail away behind „Name und E-Mail-Adresse trotzdem angeben“ (fields already typed into stay visible).
- `done` „Danke, deine Meldung ist eingegangen. Nummer: M-…“; the box is scrolled into view and focused.
- `errors` the browser's own messages for missing or too short fields; „Deine Meldung wurde nicht gesendet, weil gerade zu viele Meldungen ankommen. …“ (429, names support@snacklist.app as the e-mail route), „Die Meldung konnte gerade nicht gesendet werden …“ (503), „Keine Verbindung …“ (offline); typed values stay.
- `confirmation-mail` subject „Deine Meldung an Snacklist ist eingegangen (M-…)“, Legal's B.4 text, signed „– Snacklist Support“, reply-to support@snacklist.app. It greets by name only when the name is letters, spaces, apostrophes, hyphens or an abbreviation's dot; otherwise „Hallo,“. Every report with an address gets one (Legal N-241); a failed send is retried twice, then `scripts/moderation/notify.ts --confirmations` finds it (N-244).
- `limits` only from the site's own page (`/api/report` answers 403 to a cross-site or non-JSON post), 5 reports per client network per hour (Vercel function memory), 200 web reports per hour in total as a circuit breaker (database; logs `report: global_cap_hit`), a hidden honeypot field (answered like a success, nothing stored).
- `rc-app` (flag `report-content-entry`) More's feedback row with the subtitle „Auch: Inhalte melden“; „Inhalt melden“ under „An Snacklist Support schreiben“ in „Feedback & Ideen“ (flag `feedback-fb4`), else on top of „Feedback senden“ opened from More (not from a shake). The form is a full page: Legal's intro, the six kinds, „Wo ist der Inhalt?“ through a picker (search, „Woanders“ right under it with N-260's help and a free-text field, then „Einträge“, „Listen“, „Name des Haushalts“), the reason with „n / 5.000“, name and e-mail prefilled from the account (name only from a provider's `full_name`/`name`; the app asks for no name) and, for CSAM, hidden and emptied behind „Namen und E-Mail-Adresse angeben“ (the fields come back empty; leaving CSAM for another kind brings back what they held before, a cleared field stays cleared; a CSAM report leaves no sender row), „Screenshot anhängen (optional)“ only with `feedback-fb2` and a picture of the screen before More, never under CSAM (picking it drops an attached one, Legal N-287) (the annotator opens with „Verdecken“ picked and first, under „Verdecke darauf, was nichts mit der Meldung zu tun hat.“), the good-faith box, „Datenschutzerklärung, Abschnitt 10“. „Meldung senden“ answers „Meldung gesendet“ with the number, „Nummer kopieren“, Legal's thanks, the mail line and „Meldungen stehen nicht unter Deine Notizen …“; „Fertig“ goes back where it started. Stored as `source = 'app'` with `target_kind`/`target_id` and, if attached, a row in `content_report_screenshots`. Limits: 5 per user and 200 app reports per hour.
- `footer` „Inhalte melden“ / "Report content" in the legal footer of every site page.

## How to get to it (user POV)

1. Any snacklist.app page, footer „Inhalte melden“ (EN "Report content"), or the Impressum's „Kontaktstelle nach dem Digital Services Act“.
2. Pick what it is about, say where the content is and why it is illegal, optionally name and e-mail, tick the good-faith box.
3. „Meldung senden“ (EN "Send report"): the number shows on the page.

## Driving it with Playwright

Preconditions: a local Supabase stack with this checkout's migrations and `WAITLIST_PROXY_SECRET` (plus `RESEND_API_KEY`, `RESEND_API_URL` at a stand-in for mail; hz containers can't reach host ports, so run the stand-in as a function inside the stack) in `supabase/functions/.env`; `cd site && npm run build`; `PORT=<prefix>90 WAITLIST_UPSTREAM_URL=http://127.0.0.1:<api port>/functions/v1/waitlist WAITLIST_PROXY_SECRET=<same> node scripts/preview.mjs` (the function derives `/functions/v1/report` from that URL).

- `getByRole('radio', { name: 'Beleidigung, Bedrohung oder Hetze' }).check()`, `getByLabel(/Wo ist der Inhalt/)`, `getByLabel(/Warum ist der Inhalt/)` (20+ characters), `getByLabel(/Dein Name/)`, `getByLabel(/E-Mail-Adresse/)`, `getByLabel(/in gutem Glauben/).check()`, `getByRole('button', { name: 'Meldung senden' })`.
- Result: `getByText(/Nummer: (M-[0-9A-Z]{4}-[0-9A-Z]{4})\./)`; the row in `public.content_reports` (service connection, your own test rows only); the stand-in's log shows `key=report-confirm/<id>`.
- Wait about a second before measuring where the done box is: the site scrolls smoothly.
- Decision: `select public.content_report_decide('<ref>', 'no_change', '…')`, then `deno run -A scripts/moderation/notify.ts --decision <id>` (dry run).

In the app (`rc-app`): launch with `VH_DEFINES="FLAGS_ON=report-content-entry,feedback-fb4,feedback-fb2"` (hub and screenshot) or `FLAGS_ON=report-content-entry` (sheet), then `cd .cursor/skills/verify-snacklist && node journeys/report-content.mjs <evidence dir> [--fb4] [--screenshot] [--lang en] [--item <name>]`. It prints `REF M-…`; read the row as postgres in the stack's db container (`select … from content_reports where ref = '<ref>'`, the screenshot with `encode(png, 'base64')`). Locally the function has no `RESEND_API_KEY`, so the log says `report: mail_unconfigured`.

## Gotchas

- Flutter web keeps a field's value in the DOM only while it has focus: click the e-mail field, then read `document.activeElement.value` a few frames later.

- Never read real reports, on any copy of production data (N-230). Only rows you made.
- The preview's limiter allows 5 sends per network per hour per process: restart the preview between longer runs. The edge function refuses the 31st web report in an hour.
- `content_reports` and `content_report_decisions` have RLS on and no policy: the anon and authenticated keys get 401/42501.
- Without `WAITLIST_UPSTREAM_URL` ending in `/waitlist` (or without the secret) `/api/report` answers 404.
