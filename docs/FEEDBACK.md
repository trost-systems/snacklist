# In-app feedback

Job 21 (Spec #2, Peter's decisions of 2026-10-27 in DECISIONS.md "Job 21"). Testers and
customers send a short note from **Mehr → Feedback senden** on iOS, Android and the web. The
note goes into one table, `public.feedback`. Only Peter reads it, by hand in the Supabase
dashboard (his GDPR rule of 2026-11-01, Legal N-174): no bot, connector or agent reads the
notes. The one routine is the daily digest (below, off until Legal's GO), which mails new notes
to him alone.

Since job 267 (FB2, behind the PostHog flag `feedback-fb2`) a note can carry one annotated
screenshot. The image lives in a private Storage bucket next to the table; see "Screenshots"
below.

## What is stored

One row per note (`supabase/migrations/20261030070000_feedback.sql`; every column has a
`comment`, shown in the dashboard):

| Column | What |
| --- | --- |
| `id` | Made by the app once per note. Retrying the same note (double tap, Retry after a lost answer) stays one row. |
| `created_at` | When it arrived, UTC (set by the database). |
| `user_id` | The sender. Deleting the account deletes their notes. |
| `household_id` | The sender's household when sending, set by the database from `household_members` (never from the app). Null without one, or once that household is deleted. |
| `message` | The typed note, trimmed, 1 to 2,000 characters. |
| `category` | `bug`, `idea`, `other`, or null when none was picked. |
| `contact_ok` | The sender ticked "Peter darf mich dazu kontaktieren". The e-mail is **not** copied. |
| `app_version`, `build` | `0.1.0`, `1023` (package_info_plus, like the version line in More). |
| `platform` | `ios`, `android`, `web`, `linux`, `macos`, `windows`. |
| `os_version` | `Android 14 (SDK 34)`, `iOS 18.1`; on the web only the browser family and OS (`Safari on iOS`), never the user agent. |
| `locale` | The app's language when sending (`de`, `en`). |
| `screen` | Null for a note written from More's row (job 259: the form is about no screen, so none is sent). Notes from before job 259, and the shake entry (job 138, not shipped), carry the screen the note is about, a fixed name: the last screen before the More tab (`list` almost always) or the live one. Never a path, an invite code or an item. The names are `screenNames` in `app/lib/app/router.dart`. |
| `screenshot` | Null without a screenshot. Otherwise the image's object name in the bucket `feedback-screenshots`: `<user_id>/<id>.png`. The database refuses any other name, so a note can only name its sender's image for this note. |
| `is_internal` | Peter's household (the `ANALYTICS_INTERNAL_HOUSEHOLDS` define), a debug, profile or preview build, an install marked internal under More, or a test account. The database forces it for test accounts (`.test`, `.invalid`, `.example`, `.localhost`, `example.com/.net/.org`), whatever the app says. |

Nothing from the list is attached: no item, category or store names, no household name. The
form says so ("App-Version, Gerät und Sprache. Keine Listeneinträge."). With the flag
`feedback-fb2` (job 267) the screen name and a screenshot follow that line as switches. A screen
name shows no list item, so the line stays as it is; only while a screenshot is attached and
switched on does it shorten to "App-Version, Gerät und Sprache."
No device model, no e-mail. The one exception is a screenshot the sender chose to attach: it
shows whatever was on screen, list entries included, except what they painted over. Nothing is
blacked out automatically.

## Who can read it

- **Clients** (the app, MCP, anyone with the publishable key) may only insert, only as
  themselves (`user_id = auth.uid()`). No select, update or delete, not even of their own notes;
  anon gets nothing. RLS policy `feedback_insert_own` plus column grants; proven in
  `supabase/tests/feedback.test.sql`, `rls.test.sql` and `e2e/tests/rls.spec.ts`.
- **Peter** reads with the service role, by hand: the dashboard's Table Editor
  (`public.feedback`) or SQL editor, project `jdwqrallbpdbshrdhenk`. Once switched on, the
  daily digest mails him the new notes.
- **The sender** gets their own notes in "Meine Daten exportieren" (section `feedback`, with
  each note's `screenshot` name).
- **Screenshots**: clients may only upload them, never read them back, their own included. Peter
  opens them in the dashboard (see "Screenshots").

## Retention

- A daily pg_cron job, `purge-old-feedback` (03:17 UTC), runs `public.purge_old_feedback()`,
  which deletes notes older than 12 months and returns how many. Only the service connection
  may run it.
- Deleting an account deletes the user's notes at once (`on delete cascade`). A deleted
  household leaves its members' notes, without the household id.
- A note's screenshot goes with the note, whichever way the note is deleted (the purge, the
  account, by hand). An account deletion takes every image in the account's folder, uploads that
  never got a note included: the account function removes them right after the deletion, and if
  that fails, the next daily sweep does (see "Screenshots").
- The encrypted nightly backups (docs/BACKUP.md) keep a deleted note for up to 90 more days.

Check the schedule: `select jobname, schedule, command, active from cron.job;` and its runs:
`select status, return_message, start_time from cron.job_run_details order by start_time desc limit 7;`

## Monday summary

Peter can run these by hand in the dashboard's SQL editor (project `jdwqrallbpdbshrdhenk`)
on a Monday. Both are read-only. "Last week" is the previous full
calendar week in Berlin time, Monday 00:00 to Monday 00:00, so consecutive Mondays never
overlap or miss a note (daylight-saving weeks included). External notes come first.

All notes of last week:

<!-- monday-sql:notes -->
```sql
with week as (
  select (date_trunc('week', now() at time zone 'Europe/Berlin') - interval '1 week')
           at time zone 'Europe/Berlin' as starts,
         date_trunc('week', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin' as ends
)
select case when f.is_internal then 'internal' else 'external' end as audience,
       to_char(f.created_at at time zone 'Europe/Berlin', 'YYYY-MM-DD HH24:MI') as created_berlin,
       coalesce(f.category, 'none') as category,
       f.message,
       f.screen,
       f.screenshot,
       f.platform,
       f.app_version || ' (' || f.build || ')' as app_version,
       f.os_version,
       f.locale,
       f.household_id,
       f.user_id,
       f.contact_ok
from public.feedback f, week
where f.created_at >= week.starts and f.created_at < week.ends
order by f.is_internal, f.created_at, f.id;
```
<!-- /monday-sql -->

How many, per category and per platform:

<!-- monday-sql:counts -->
```sql
with week as (
  select (date_trunc('week', now() at time zone 'Europe/Berlin') - interval '1 week')
           at time zone 'Europe/Berlin' as starts,
         date_trunc('week', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin' as ends
),
last_week as (
  select f.* from public.feedback f, week
  where f.created_at >= week.starts and f.created_at < week.ends
)
select case when is_internal then 'internal' else 'external' end as audience,
       'category' as by, coalesce(category, 'none') as value, count(*) as notes
from last_week group by is_internal, category
union all
select case when is_internal then 'internal' else 'external' end, 'platform', platform, count(*)
from last_week group by is_internal, platform
order by audience, by, notes desc, value;
```
<!-- /monday-sql -->

When a note has `contact_ok = true`, Peter (only he contacts anyone) looks up the address:

<!-- monday-sql:contact -->
```sql
select u.email from auth.users u
where u.id = (select f.user_id from public.feedback f where f.id = :'feedback_id' and f.contact_ok);
```
<!-- /monday-sql -->

In the dashboard's SQL editor, replace `:'feedback_id'` with the note's id in quotes.

`scripts/feedback-monday.sh` (run by the db gate) seeds fake notes on the local stack, runs the
three blocks above exactly as written here and checks the result, so this page and the queries
can't drift apart. Its output on fake data is in the PR of job 21.

## Screenshots

Job 267. From the shake sheet or the form, the sender can attach the current screen, painted
over in the app's annotator. The app uploads the PNG, then inserts the note naming it.

**Where.** The private Storage bucket `feedback-screenshots` of the same Supabase project (EU,
Frankfurt), created by `supabase/migrations/20261115160000_feedback_screenshots.sql`. It takes
PNG only, at most 2 MiB per image. The object name is `<user_id>/<note id>.png`, and
`public.feedback.screenshot` holds the same name.

**Who can do what.**

- A signed-in user may upload into their own folder only, with a lowercase UUID as the name and
  `.png` (storage policy `feedback_screenshots_insert_own`).
- Two quotas keep one account from filling the free plan's 1 GB of Storage
  (`public.feedback_screenshot_quota_left(name)`): at most 10 uploads per user in any 24 hours,
  and no upload at all while the bucket holds 250 images or more (at most 2 MiB each, so about
  500 MiB at worst). Two uploads at the same moment can both pass the last free place; the quotas
  are against abuse, not a contract.
- Over a quota the Storage API refuses the upload (403; too big or not a PNG: 413 or 415), and the
  form says "Das Bildschirmfoto wurde nicht angenommen. Schalte es aus, dann geht deine Nachricht
  ohne Bild." The text, category and screenshot stay. With the screenshot switched off the note
  sends.
- Nobody but the service role reads, lists, signs, overwrites or removes an image: there is no
  other policy. A second upload of the same name answers "already exists" (409, `Duplicate`),
  which the app takes as its own earlier try. That holds at a quota too: a name the user already
  uploaded passes the quotas and reaches the unique key.
- Signed out: nothing.

**Raising the quotas.** Both numbers live in `public.feedback_screenshot_quota_left(text)`. Write
a new migration that runs `create or replace function public.feedback_screenshot_quota_left(p_name
text)` with the body of `20261115160000_feedback_screenshots.sql` and the new numbers (`< 10` per
user, `< 250` for the bucket), then land it like any migration (docs/DEPLOY.md). Before raising
the bucket cap, check the project's Storage use in the dashboard (Settings, Usage): the cap times
2 MiB has to fit next to everything else in the plan's Storage.

**How Peter views an image.** In the dashboard (project `jdwqrallbpdbshrdhenk`), open
**Storage**, then the bucket `feedback-screenshots`, then the folder named by the note's
`user_id`, then the file named by the note's `id`. The preview shows the image; **Download**
saves it. The note's `screenshot` column has the full path. Do not share a link from **Get URL**:
a signed URL opens the image for anyone who has it until it expires.

**Deletion.** SQL cannot delete a stored file (`storage.protect_delete` refuses it, and a
deleted row would leave the file behind), so the Storage API does:

1. Any delete of a note with a screenshot (the 12-month purge, an account deletion, Peter by
   hand) queues the name in `public.feedback_screenshot_removals` (trigger
   `feedback_queue_screenshot_removal`).
2. The sweep lists what is due (`public.feedback_screenshots_due`): the queue, then uploads that
   no note names and that are either older than 24 hours (the app's upload succeeded but its note
   never arrived) or in the folder of an account that no longer exists, whatever their age. It
   removes at most 500 names per run through the Storage API with the project's secret key, then
   drops them from the queue (`public.feedback_screenshots_removed`). A name whose file is
   already gone just leaves the queue, so a repeated or interrupted run does no harm.
3. The sweep runs in the `account` function right after a successful deletion (best effort,
   at most 5 seconds; the answer to the app does not change), and daily in **Keepalive**
   (`.github/workflows/keepalive.yml`, 05:23 UTC), which posts to
   `POST /functions/v1/feedback-screenshots/sweep`. The route takes no key: it only removes what
   the database says is due. It answers `{"removed": n}`, or 503 with `storage_failed` or
   `db_error`. Its logs say `feedback-screenshots: removed 3` or `storage_failed 500`, never a
   name (each starts with a user id).

So an image outlives its note by at most a day, and an orphan upload by at most two. When an
account is deleted, all of its images (with a note or without) are due at once: the account
function's sweep removes them before it answers, and only if that sweep fails do they wait for
the next daily one. If the
sweep step of Keepalive fails, the Keepalive issue says so; look at the function's logs in the
dashboard (Edge Functions, `feedback-screenshots`). Queued names wait until a sweep succeeds:

```sql
select count(*), min(queued_at) from public.feedback_screenshot_removals;
```

The nightly backups (docs/BACKUP.md) hold the notes and the queue, not the images.

Tests: `supabase/tests/feedback_screenshots.test.sql` (bucket, policy, quota, name check, queue,
due list, privileges, export), `supabase/functions/_shared/feedback_screenshots_test.ts` and
`feedback-screenshots/handler_test.ts` (the sweep and its route), and
`feedback-screenshots/sweep_integration_test.ts` in the db gate (the real Storage API: uploads,
refused reads, both quotas, a retry at a quota, and the sweep after a deleted note, an account
deletion with and without notes and an old orphan).

## Daily digest (off until Legal GO)

Job 225. Once switched on, Peter gets one mail a day with every external note since the last
digest, so nobody has to open the table to see new feedback. It ships **off**: the migration
(`supabase/migrations/20261114001000_feedback_digest.sql`) seeds the switch
`app_switches.feedback_digest` off and schedules nothing. It goes on only after Legal Review GO,
by hand (NEEDS_PETER "Job 225"). Only Peter reads the digest: it goes to
`hello@snacklist.app`, from `"Peter · Snacklist" <hello@snacklist.app>`, through Resend. No bot,
routine or agent reads or relays it.

**The mail.** Subject `Snacklist feedback digest YYYY-MM-DD (N new)`; no mail when N is 0. Plain
text and simple HTML, English labels. One entry per note, oldest first: the time (Berlin), the
category (or "none"), the note, `platform · version (build)`, `Premium: yes/no` (the sender's
household or own Premium when the digest runs), `Reply allowed: yes/no`, and `Email: <address>`
only when the sender allowed a reply. Internal notes (`is_internal`) are left out. In the plain
text part each line of the note starts with `> `, so a typed "Email: ..." line can't pass for
the entry's own. The mail has
no links, images or tracking pixel.

**The day.** The digest of day D holds the notes after the watermark and before D 07:59 Berlin.
The minute's margin is for notes still being written: `created_at` is the start of the inserting
transaction. A note from 07:59:30 goes into the next day's mail.

**The schedule.** `public.feedback_digest_set(true, <function url>)` (an `https://` URL; plain
`http://` only to the local stack) switches it on and creates
the pg_cron job `feedback-digest`, hourly at minute 0 (pg_cron runs in UTC; hourly avoids
daylight-saving arithmetic). The job posts to the `feedback-digest` function through pg_net with
the header `x-feedback-digest-secret`, read from the vault secret `feedback_digest_secret` at
run time, so `cron.job` never holds it. The function needs the same value as
`FEEDBACK_DIGEST_SECRET`. The run after 08:00 Berlin sends; later runs that day find an empty
window. `feedback_digest_set(false)` switches it off and removes the job; nothing else turns it
on or off.

**The watermark.** `public.feedback_digest_state` keeps the last mailed note's `created_at` and
`id`. The first switch-on sets it to that moment, so older notes are never mailed; a later
switch-on keeps it, so a pause delays notes and loses none. A run mails first and then moves the
watermark only if it is still where the run read it. So:

- A failed send leaves the watermark; the next hourly run mails the same notes plus any new ones.
- A run whose watermark move failed after the send mails the same window again with the same
  payload and the same Resend idempotency key (`feedback-digest/<day>/<payload hash>`), and
  Resend delivers it once within 24 hours.
- Of two runs at once, only one moves the watermark; the other answers `raced`.
- Accepted repeats: if the retry's mail differs (a sender's Premium or address changed, a note
  was deleted), its key differs and Resend sends it again; and two runs at once on either side
  of 08:00 Berlin can both mail the notes they share (DECISIONS "Job 225", 4).

**Failures.** Each run records `last_run_at`, `last_ok_at` and a fixed `last_error` code
(`send_failed`, `db_error`, `mail_not_configured`). `GET /functions/v1/feedback-digest/status`
answers only `{"enabled": bool, "healthy": bool}`, without a key; healthy means off, or no error
and a good run in the last three hours. The workflow **Feedback digest watch**
(`.github/workflows/feedback-digest-watch.yml`, daily at 07:40 UTC) reads it and fails when the
digest is on and unhealthy or the function does not answer. A failed run opens or comments on
the issue "Feedback digest failed", which names no content; the next green run closes it. A 404
(the function not deployed yet) is only a notice. So the watch can't tell a digest whose
function went missing after switching on; `net._http_response` then shows 404s. A notice in the
watch after switching on means: look at the runs below. The watch runs once a day, so a digest
that starts failing after the 08:00 run is reported at the next 07:40 UTC; the hourly retries
send the day's mail as soon as the cause is gone. The function's logs and answers carry fixed
codes only (`feedback-digest: sent`, `send_failed 422`, `db_error 23505`), never a note or an
address; pg_net keeps answers in `net._http_response`, so they carry none either.

**Resend tracking.** Open and click tracking are Resend domain settings, not per mail. With
open tracking on, Resend adds a 1x1 pixel to the HTML of every mail the domain sends, the digest
included, and records each opening; with click tracking on, it rewrites links. So both must be
off for the sending domain, `snacklist.app`, before the digest is switched on (NEEDS_PETER "Job
225", step 3). The waitlist mails want them off too (docs/WAITLIST.md). Should another mail ever
need tracking on `snacklist.app`, the digest moves to its own sending subdomain with tracking
off first.

**Look at the runs** (SQL editor, service role):

```sql
select status, return_message, start_time from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'feedback-digest')
order by start_time desc limit 24;
select id, status_code, content, created from net._http_response order by id desc limit 24;
select last_digest_on, last_run_at, last_ok_at, last_error from public.feedback_digest_state;
```

Tests: `supabase/tests/feedback_digest.test.sql` (switch, schedule, day window across 08:00 and
both DST days, empty and internal-only windows, address, Premium, watermark),
`supabase/functions/feedback-digest/*_test.ts` (routes, mail, rerun key, no content in logs) and
`digest_integration_test.ts` in the db gate (empty day, internal-only day, mixed day, rerun,
failed send, the settle minute, the reply-allowed toggle, over the real database).
