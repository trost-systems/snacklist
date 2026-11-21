-- Sender rows of app reports (user id and time, only for the 5-per-hour limit) are pruned every
-- hour instead of daily. Pruning deletes rows older than an hour, so the daily run let a row live
-- almost 25 hours when no app report came in between; the privacy policy says one day at most
-- (Legal N-283, job 333). The same name replaces the job.
select cron.schedule('prune-content-report-app-senders', '20 * * * *',
  'select public.prune_content_report_app_senders()');
