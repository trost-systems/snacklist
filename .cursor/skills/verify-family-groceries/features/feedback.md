# Feedback

Mehr → "Feedback senden" (`more-feedback`) opens a sheet where the user writes a short note (1 to 2,000 characters), optionally picks Bug, Idee or Sonstiges and ticks "Snacklist Support darf mich dazu kontaktieren", and sends it. The note goes into `public.feedback` with the app version, build, platform, OS version, app language (no screen name since job 259), and nothing from the list. Clients can only insert; reading is for the service role (`docs/FEEDBACK.md`). On success the sheet closes and "Danke!" shows; on a failure the note stays with "Erneut senden".

## Sub-features

- `fb-open` `more-feedback` (first in the group below Einstellungen and Nutzungsdaten, with "Hilfe & Kontakt" below it and the legal rows after the group) opens the sheet. Its key `feedback-sheet` sits on a layout widget that `fg find` and `fg wait` don't list; wait for `feedback-message` instead.
- `fb-send` `feedback-message` takes the note; `feedback-send` ("Senden") is enabled once it has a non-blank character. One row lands; the sheet closes; the snackbar `feedback-thanks` reads "Danke!".
- `fb-options` `feedback-category-bug` / `-idea` / `-other` (a second tap unpicks), `feedback-contact` (off by default; a pointy hex `HexCheckboxListTile` since job 57, still role checkbox). `feedback-attached` names what goes along.
- `fb-limits` from 1,800 characters `feedback-counter` shows "N / 2000"; over 2,000 the field says "Höchstens 2000 Zeichen" and Send is disabled. Blank notes can't be sent.
- `fb-retry` without a connection `feedback-error` ("Nicht gesendet. …") shows, the note stays, and `feedback-retry` ("Erneut senden") replaces Send. Closing (`feedback-close`) keeps the note for the next open.
- `fb-screen` the row's `screen` is null (More's row attaches none).
- `fb-fb2` with the PostHog flag `feedback-fb2` (job 267): the form from More offers `feedback-add-screenshot` once the More tab was entered by its tab (the screen left is pictured); it opens the annotator (`annotator-canvas`, tools `annotator-tool-pen` / `-rectangle` / `-text` / `-cover` (job 290: „Verdecken“, an opaque filled box flattened into the PNG), `annotator-undo` for the last mark of any tool, `annotator-close` ✕ without a picture, `annotator-done`). After „Fertig“ the form shows `feedback-send-screenshot` (switch „Bildschirmfoto“) and `feedback-screenshot-preview`; the PNG is uploaded to the private bucket `feedback-screenshots` as `<uid>/<note id>.png` before the row, whose `screenshot` column names it. A shake (iOS and Android only) shows `shake-sheet` („Problem mit diesem Bildschirm melden?“, `shake-with-screenshot`, `shake-without`, `shake-close`), then the form with `feedback-send-screen` („Bildschirmname“ and the live screen's name). Einstellungen shows `settings-shake` („Schütteln für Feedback“) on phones with the flag on.

## How to get to it (user POV)

- Tap "Mehr", scroll to "Feedback senden", tap it, type, tap "Senden".

## Driving it with fg

Preconditions: the baseline from `features/README.md`; peter signed in on the list.

- **`fb-open`, `fb-send`.** From the list: `fg tap --key tab-more`, `fg wait --key more-screen`, `fg marionette -- scroll-to --key more-feedback`, `fg screenshot --name fb-more`, `fg tap --key more-feedback`, `fg wait --key feedback-message`, `fg screenshot --name fb-empty`. `fg tap --key feedback-message`, `fg type --input "Beim Abhaken springt die Liste."`, `fg screenshot --name fb-filled`, `fg tap --key feedback-send`, `fg wait --text Danke!`, `fg screenshot --name fb-thanks`. Check: `fg db query "select message, category, contact_ok, screen, platform, locale, app_version, build, os_version, is_internal, household_id is not null as has_household from feedback order by created_at desc limit 1"` returns the text, category null, contact_ok false, screen null, platform `linux`, locale `de`, is_internal true (fg.test and a debug build).
- **`fb-options`.** Open the sheet again (it is blank after a send), type a note, `fg tap --key feedback-category-bug`, `fg tap --key feedback-contact`, `fg tap --key feedback-send`; the newest row has category `bug`, contact_ok true.
- **`fb-limits`.** `fg tap --key feedback-message`, `fg type --input "   "`: `fg find --key feedback-send` is disabled. A 2,001-character input (`fg type --input "$(printf 'a%.0s' {1..2001})"`) shows `feedback-counter` "2001 / 2000" and "Höchstens 2000 Zeichen".
- **`fb-retry`.** Not reliably drivable on linux (fg can't cut one client off the local stack); the web e2e tests "offline: …" and "a lost answer: …" (`e2e/tests/feedback.spec.ts`) and the widget test `test/feedback/feedback_sheet_test.dart` cover it. Report it as skipped with that pointer.
- **RLS.** `fg db query "select count(*) from feedback" --as peter` fails with permission denied: the sender can't read their own notes from the table (their data export, `features/account.md`, does include them).
- **Proof.** Screenshots `fb-more`, `fb-empty`, `fb-filled`, `fb-thanks` and the db query output.

## Daily digest (server only, off by default)

`fd-digest` (job 225, `docs/FEEDBACK.md` "Daily digest") has no app UI. Prove it on the local stack only, never against the hosted project, with synthetic notes:

- **Off.** `curl -s $API_URL/functions/v1/feedback-digest/status` answers `{"enabled":false,"healthy":true}`; `select count(*) from cron.job where jobname = 'feedback-digest'` is 0.
- **A run through pg_cron's command.** Serve the functions with an env file holding `FEEDBACK_DIGEST_SECRET`, and `RESEND_API_KEY` plus `RESEND_API_URL` pointing at a throwaway fake (an untracked function under `supabase/functions/` that logs the request and answers 200; remove it afterwards): `supabase functions serve --env-file <file> --no-verify-jwt`. As postgres: `select vault.create_secret('<same secret>', 'feedback_digest_secret')`, `select public.feedback_digest_set(true, 'http://kong:8000/functions/v1/feedback-digest')`, move the watermark back (`update feedback_digest_state set since_created_at = <two days ago>`), insert a note for a non-test address and set its `created_at` to yesterday morning. Run the job's command by hand (`select command from cron.job where jobname = 'feedback-digest'`, then execute it), wait a few seconds: `select status_code, content from net._http_response order by id desc limit 1` is `200 {"status":"sent","count":1}`, the fake logged one mail to hello@snacklist.app with the idempotency key `feedback-digest/<day>/<hash>`, and a second run answers `empty`.
- **Clean up.** `select feedback_digest_set(false)`, delete the vault secret, the user and reset `feedback_digest_state`; stop `functions serve` by its pid.
- The pgTAP file `supabase/tests/feedback_digest.test.sql` and `feedback-digest/digest_integration_test.ts` (db gate) cover the windows, reruns and failures.

## Gotchas

- The sheet covers the tabs: close it (`feedback-close` or `fg back`) before `fg tap --key tab-list`.
- The note is kept when the sheet is closed without sending; a recipe that expects a blank form sends first or types over it: `fg type --key feedback-message --input <text>` replaces the field's text.
- `screen` is null from More's row; only the shake entry (job 267, flag `feedback-fb2`, iOS and Android) takes the live screen. Linux has no accelerometer: the shake flow is covered by `app/test/feedback/fb2_test.dart`, not drivable with fg.
- With the flag on, check an upload with `fg db query "select screenshot from feedback order by created_at desc limit 1"` and `select name from storage.objects where bucket_id = 'feedback-screenshots'`.
- The server deletes notes 12 months after `created_at` (pg_cron `purge-old-feedback`); nothing in the app shows it.
