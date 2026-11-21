# Reports of illegal content (DSA notice and action)

Internal runbook. Snacklist stores what users type for their household, so it is a hosting service
under the Digital Services Act (Art. 3(g)(iii)) and must take reports of illegal content (Art. 16).
Legal Review's Addendum B (N-226 to N-240, 16 Nov 2026) sets the rules; job 275 built the web part.
The public side is the form at [snacklist.app/inhalte-melden](https://snacklist.app/inhalte-melden)
and [snacklist.app/en/report](https://snacklist.app/en/report), linked from every page's footer, the
Impressum (contact point under Art. 11/12 DSA) and the help pages. Job 281 adds the in-app entry
behind the flag `report-content-entry` (N-226: a separate first-level choice, not a feedback
category); its reports land in the same table ("Reports from the app" below).

**Only Peter reads and decides reports.** No agent, bot, LLM or script reads, sorts or summarises
a report, on any copy of the production database (N-230, and Peter's rule that bots don't read user
content). Agents work on local stacks with made-up reports only.

## The path of a report

| Step | Where | What |
| --- | --- | --- |
| Form | `/inhalte-melden`, `/en/report` (`site/content/legal/inhalte-melden.md`, `report.md`, `site/public/report.js`) | No account, no cookie, no third-party script, no captcha. A honeypot field. Posts JSON to the same origin. |
| Vercel function `/api/report` | `site/api/report.mjs`, region fra1 | Only from the site's own page (`Sec-Fetch-Site: same-origin`, JSON). At most 5 reports per client network per hour, counted in the function's memory only; the IP is never stored, logged or forwarded. Forwards to the edge function with the site's proxy secret. |
| Edge function `report` | `supabase/functions/report/`, eu-central-1 | Checks the fields (reason 20 to 5,000 characters), drops honeypot hits with a made-up number, stores the report, sends the confirmation. Logs fixed outcome codes only. |
| `public.content_reports` | Supabase Postgres, Frankfurt | The report: number (`M-XXXX-XXXX`), time, language, kind, where, why, the good-faith box, name and e-mail if given. |
| `public.content_report_decisions` | same | Every decision: time, outcome, ground, when the notifier was told. |
| Resend | domain snacklist.app, sent from Ireland | The confirmation (Art. 16(4)) and the decision (Art. 16(5)), from `no-reply@snacklist.app`, reply-to `support@snacklist.app`. |

The two tables have row level security on and no policy: no app user, household or anon key can
read or write them. Only the service connection (the edge function, Peter in the dashboard, the
notify script) reaches them. Reports are not feedback: no FB4 status, no reply, no +1, not in the
feedback purge, not in any household's data or export.

Limits that never decide on content (so no Art. 16(6) disclosure is needed): the honeypot, 5 per client network per hour at Vercel, and 200 web reports per hour in total as a circuit breaker (more are refused with the message that names support@snacklist.app, and the function logs "report: global_cap_hit"). Every stored report with an e-mail address gets the confirmation (Art. 16(4); Legal N-241: no per-address mail cap). A report e-mailed to support@snacklist.app is a valid notice too: confirm it by hand without undue delay and file it as a report (N-246).

## Reports from the app

The app posts to the same edge function's route `/functions/v1/report/app`, pinned to Frankfurt
(`?forceFunctionRegion=eu-central-1`, Legal N-285), with the user's own
session token (no proxy secret, no Vercel step; API keys, MCP and Siri tokens are refused). It
checks the same fields, stores through `content_report_submit_app` and sends the same B.4
confirmation through the same code as a web report. An app report differs in four columns and two
tables:

- `source` is `app`.
- `target_kind` and `target_id` say what the reporter picked: `household`, `list` or `item` with
  that row's id, or `elsewhere` without an id (then `location` holds the reporter's own words).
  For a picked target `location` is the app's English summary for you, such as
  `item "Hafermilch" in list "Wocheneinkauf", household "Familie Brandt"`. The id is no foreign
  key: the content may be gone when you look. Find it with
  `select * from public.households where id = '<target_id>'`, or `public.lists`, `public.items`
  (both carry `household_id`).
- `public.content_report_screenshots` holds the screenshot the reporter attached, if any: a PNG
  of their screen before More, with what has nothing to do with the report covered by them. It
  shows in the Table Editor as bytes only. Save it as a file on your own machine (never an agent), with
  `SUPABASE_DB_URL` set:

  ```sh
  psql "$SUPABASE_DB_URL" -At -c "select encode(s.png, 'base64')
    from public.content_report_screenshots s join public.content_reports r on r.id = s.report_id
    where r.ref = 'M-XXXX-XXXX'" | base64 -d > M-XXXX-XXXX.png
  ```

  It goes with its report: the 12-month purge deletes it by cascade. The purge does not reach your saved file: delete it as soon as the case is closed, unless the Art. 18 runbook needs it for the BKA. Never save the screenshot of a csam report (N-287).
- `public.content_report_app_senders` keeps the sender's user id and time, for the limit only. Rows
  go after an hour (at the next app report, and every hour at :20 by
  `prune_content_report_app_senders`, so none is older than two hours). A report itself never names its sender's account; ask by
  e-mail if you need more.

App limits, on content never (Legal N-241, N-242): 5 app reports per user per hour, and 200 app
reports per hour in total as a circuit breaker, counted apart from the web's. A refused report gets
429; the function logs `report: user_cap_hit` or `report: global_cap_hit` next to `report 429`.
Every stored app report with an e-mail address gets the confirmation: the app route has no
per-address mail cap.

`notify.ts --confirmations` (N-244: reports with an address and no `confirmation_sent_at`) covers
app reports too: they use the same columns and the same `report-confirm/<id>` idempotency key, and
it does not filter on `source`.

## Daily routine

1. Check for reports with an e-mail address but no confirmation_sent_at (a failed Resend send) and send the confirmation now (Art. 16(4); Legal N-244).
   `deno run -A scripts/moderation/notify.ts --confirmations` lists them; add `--send` to send
   them (the function already retries a failed send twice before it gives up).
2. Supabase dashboard › Table Editor › `content_reports`, sorted by `created_at`. Open reports have
   no `closed_at`.
3. Kinds `danger` (threat to life or safety) and `csam` (child sexual abuse material) the same day;
   everything else within 7 days (B.5, the page promises it).
4. A `danger` report, or any report that suggests a crime threatening someone's life or safety: the
   Art. 18 runbook below first.
5. Find the content (household and list names, the item text, the invite code), decide, act in the
   database (remove, hide, suspend), then log the decision and tell the notifier (below). If the
   content's author is an app user, send them the statement of reasons (B.6b) too.
6. Unclear case: the safe default is to defer. Leave the content, ask the notifier for details by
   replying from support@snacklist.app, and don't guess at criminal law.

## Log a decision and tell the notifier

In the SQL editor (the outcome is one of `removed`, `made_invisible`, `account_suspended`,
`no_change`; the ground is the "Grund"/"Reason" sentence the notifier reads):

```sql
select public.content_report_decide('M-XXXX-XXXX', 'no_change',
  'Wir konnten den Inhalt anhand deiner Angaben nicht finden.');
-- returns the decision id
```

This logs the decision and closes the case (`closed_at`). A second look after a reply is a new
decision on the same number; the latest one counts for the retention.

Then, on your own machine (never an agent), with `SUPABASE_DB_URL` and `RESEND_API_KEY` set:

```sh
deno run -A scripts/moderation/notify.ts --decision <id>          # shows the mail, sends nothing
deno run -A scripts/moderation/notify.ts --decision <id> --send   # sends it and records notified_at
```

It renders Legal's B.6a text in the report's language. A report without an e-mail address gets no
mail; the decision is logged all the same.

### B.6a Decision to the notifier (16(5))

Subject DE „Unsere Entscheidung zu deiner Meldung ({ref})“ / EN "Our decision on your report ({ref})".

> DE: „Hallo {name}, wir haben deine Meldung vom {Datum} ({ref}) geprüft. Entscheidung: {wir haben den Inhalt entfernt | wir haben den Inhalt unsichtbar gemacht | wir haben das Konto gesperrt | wir haben nichts geändert}. Grund: {kurze Begründung; bei „nichts geändert“: warum wir den Inhalt nicht für rechtswidrig halten oder ihn nicht finden konnten}. Die Entscheidung hat ein Mensch getroffen, ohne automatische Mittel. Wenn du nicht einverstanden bist, antworte auf diese E-Mail, dann prüfen wir noch einmal. Du kannst außerdem die Zivilgerichte anrufen oder dich bei der Koordinierungsstelle für digitale Dienste der Bundesnetzagentur beschweren. – Snacklist Support“
> EN: "Hi {name}, we've reviewed your report of {date} ({ref}). Decision: {we removed the content | we made the content invisible | we suspended the account | we changed nothing}. Reason: {short reason; for 'changed nothing': why we don't consider the content illegal or couldn't find it}. A person made this decision, without automated means. If you disagree, reply to this e-mail and we'll review it again. You can also go to the civil courts or complain to the Digital Services Coordinator at the Bundesnetzagentur. – Snacklist Support"

### B.6b Statement of reasons to the affected user (Art. 17(3)(a)–(f))

Send it whenever Snacklist removes, hides or restricts content or an account for illegality or a
rule breach and knows the user's e-mail (every app account has one), from support@snacklist.app.
Name the reporter only where strictly necessary, which is normally never (N-233).

Subject DE „Wir haben einen Inhalt in Snacklist {entfernt/eingeschränkt} – Begründung“ / EN "We {removed/restricted} content in Snacklist – statement of reasons".

> DE:
> „Hallo {Anzeigename},
> **Was wir getan haben (a):** {Wir haben den Eintrag / die Liste / den Haushaltsnamen / das Foto „{Kurzbezeichnung}“ im Haushalt „{Haushalt}“ entfernt | unsichtbar gemacht | dein Konto {bis {Datum} | dauerhaft} gesperrt}. Gilt für: {alle Länder | …}; Dauer: {dauerhaft | bis {Datum}}.
> **Warum (b):** Grundlage ist {eine Meldung nach Art. 16 DSA vom {Datum} | unsere eigene Prüfung}. {Tatsachen und Umstände, kurz}. (Wer gemeldet hat, nennen wir nur, wenn es unbedingt nötig ist.)
> **Automatische Mittel (c):** Wir haben keine automatischen Mittel eingesetzt; ein Mensch hat den Inhalt gefunden bzw. geprüft und entschieden.
> **Rechtsgrund (d)** – nur bei rechtswidrigen Inhalten: {z. B. § 185 StGB (Beleidigung), § 22 KUG (Bildnis ohne Einwilligung), § 97 UrhG}; {Erläuterung, warum der Inhalt darunter fällt}.
> **Regelverstoß (e)** – nur bei Verstoß gegen unsere Regeln: {Abschnitt „Regeln für Inhalte“ auf snacklist.app/inhalte-melden#regeln}; {Erläuterung}.
> **Was du tun kannst (f):** Antworte auf diese E-Mail, wenn du die Entscheidung für falsch hältst; wir prüfen sie dann noch einmal, kostenlos. Du kannst außerdem die Zivilgerichte anrufen oder dich bei der Koordinierungsstelle für digitale Dienste der Bundesnetzagentur beschweren (Art. 53 DSA). Ein internes Beschwerdeverfahren nach Art. 20 und eine außergerichtliche Streitbeilegung nach Art. 21 DSA gibt es für Snacklist nicht, weil Snacklist keine Online-Plattform ist.
> – Snacklist Support“

> EN:
> "Hi {display name},
> **What we did (a):** {We removed | We made invisible} the {item / list / household name / photo} "{short label}" in the household "{household}" | {We suspended your account until {date} | permanently}. Applies to: {all countries | …}; duration: {permanent | until {date}}.
> **Why (b):** Based on {a notice under Art. 16 DSA of {date} | our own review}. {Facts and circumstances, briefly}. (We name the reporter only where strictly necessary.)
> **Automated means (c):** We used no automated means; a person found or reviewed the content and decided.
> **Legal ground (d)** – only for illegal content: {e.g. § 185 StGB (insult), § 22 KUG (image without consent), § 97 UrhG}; {explanation of why the content falls under it}.
> **Rule breach (e)** – only for a breach of our rules: {section "Content rules" at snacklist.app/en/report#rules}; {explanation}.
> **What you can do (f):** Reply to this e-mail if you think the decision is wrong; we'll review it again, free of charge. You can also go to the civil courts or complain to the Digital Services Coordinator at the Bundesnetzagentur (Art. 53 DSA). There is no internal complaint procedure under Art. 20 or out-of-court dispute settlement under Art. 21 DSA for Snacklist, because it isn't an online platform.
> – Snacklist Support"

(Art. 17(2): only where the e-mail is known; the account e-mail is known for every app user. Art.
17(3)(d) legal grounds are examples to pick from, not legal advice per case.)

## Art. 18 runbook (B.7)

1. **Trigger:** any report or other information suggesting that a crime threatening someone's life or safety has happened, is happening or may happen (e.g. a threat of violence or suicide announced with a plan, child abuse, a planned attack).
2. **Immediate danger:** call 110 first.
3. **Report promptly ("unverzüglich")** to the BKA, the German central office under § 13 DDG: report by phone to the BKA (+49 611 55-35062, Kriminaldauerdienst outside working hours), then register (Legal B.1, N-235 accepted: Peter registers only once a case arises). Phone hours: working days 08:00–16:00; outside those hours the BKA's Kriminaldauerdienst on the same number. Registration is for the portal https://u-entrance.bka.de: an e-mail to u-entrance@bka.bund.de from a Snacklist address, asking for access as a hosting service provider (Legal's draft below). That address does **not** receive reports.
4. If the offence clearly concerns another Member State only, report to that state's authority or Europol (Art. 18(2)). Default: BKA.
5. Provide "all relevant information available": the content, the household/user reference, times. Don't delete the content before it has been secured for the authorities. Don't tell the affected user if that could endanger anyone.
6. Log: date, time, what was reported, the BKA reference. Keep it as long as the case requires.

**Registration, once a case arises** (N-235 accepted 16 Nov 2026: not in advance; only Peter can
send it). After the phone report, from support@snacklist.app to u-entrance@bka.bund.de, Legal's
draft unchanged:

- Subject: „Zugang zum Meldeportal nach Art. 18 DSA – Snacklist (Hostingdiensteanbieter)“
- Body: „Guten Tag, ich betreibe als Einzelunternehmer die App Snacklist (Einkaufslisten für Haushalte, snacklist.app) und bin damit Hostingdiensteanbieter im Sinne des DSA. Ich bitte um einen Zugang zum Meldeportal für Meldungen nach Art. 18 DSA für die Adresse support@snacklist.app. Anbieter: Peter Trost, Yalovastr. 5, 72108 Rottenburg am Neckar. Mit freundlichen Grüßen, Peter Trost“

While a case needs the report longer than 12 months after it
closed, set `retain_until` and `retain_reason` on its row; the purge leaves it alone until then.

## Retention

`public.purge_content_reports()` runs daily at 03:27 UTC (pg_cron `purge-content-reports`). It
deletes a report, with its decisions, 12 months after its latest decision (`closed_at`), unless
`retain_until` is still in the future (privacy policy §10, "Meldungen rechtswidriger Inhalte").
Reports never decided are never purged: decide every report, spam included (`no_change`).

## Changing the texts

Every text on the report page, in the confirmation and decision mails, the Impressum's contact
point and privacy §10 is Legal's. Change them only with a new Legal Review text and its hash GO.
A significant change to the content rules must be announced in the app (Art. 14(2)).
