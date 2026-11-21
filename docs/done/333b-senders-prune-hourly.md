# Job 333b: app report sender rows pruned hourly

The sender rows of app reports (user id and time, for the 5-per-hour limit) were pruned once a day,
so a row could live about 25 hours. The privacy text going out with the report-content rollout
(#588) says one day at most. The prune now runs every hour at :20, so a row lives under two hours.

- `supabase/migrations/20261121062154_content_report_senders_prune_hourly.sql`: the new schedule.
- `supabase/tests/content_reports_app.test.sql`: pins `20 * * * *`. 51/51 pass on a local stack;
  without the migration the file fails.
- `docs/MODERATION.md`, `docs/PRIVACY_DATA_MAP.md`: the retention follows.
