# Job 333: report content rollout (RC2 to all users)

The rollout PR for `report-content-entry`. Not merged: it waits for Legal's hash GO and for both
store builds containing #524 to be live (Legal 2026-11-21, Addendum B item 7).

## What changed

- `site/content/legal/impressum.md`, `imprint.md`: the report line names the in-app path
  (Mehr, then „Inhalt melden“ / More, then "Report content"), N-281, verbatim.
- `site/content/legal/datenschutz.md` `#meldungen`, `privacy.md` `#reports`: what an app report
  stores (ID and name of the picked item, list or household; no account link; user ID and time
  only for the 5-per-hour limit, a day at most, none for CSAM), N-283, verbatim.
- `updated:` and Stand / Last updated on the four pages: 2026-11-21 (N-279; the lander moves it to
  the merge date).
- `scripts/backup/dump.sh`: `--exclude-table-data=public.content_report_app_senders` (N-284 a);
  `scripts/backup/drill.sh` checks excluded tables come back empty; `docs/BACKUP.md` and two
  `docs/PRIVACY_DATA_MAP.md` rows follow.
- `releases/flags.json`: `report-content-entry` `full`.

## Verified

- Labels on main: `tabMore` Mehr/More, `reportContent` Inhalt melden/Report content
  (`app/l10n/app_de.arb`, `app_en.arb`).
- Backup drill on a local stack: PASS, `content_report_app_senders` 0 rows after restore, every
  other table identical. With a typo in the excluded name: FAIL naming the table.
- Gates: see the PR body.

## Review 0

- The one-day retention in the new text did not hold (daily prune, up to about 25 hours). #591
  (job 333b, merged as 8ea2757f) runs the prune hourly; this PR is rebased onto it.
- The drill's PASS line counts the table left empty apart from the identical ones.

## Open

- Follow-up after merge: the verify-snacklist feature file `report-content.md`, its `SKILL.md`
  flag line and FEATURES-FOR-WRITERS still describe the flag as off.

- The PostHog flag `report-content-entry` must go to all users when this merges (Peter or lead).
- Store builds: every build from 1414 on contains #524. Play: 1414 on alpha (closed testing) in
  review on 2026-11-19; production empty then. App Store: unknown from this box.
