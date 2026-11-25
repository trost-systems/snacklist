-- Keep the Alexa edge function warm in eu-central-1 (docs/ALEXA.md, "Keep-warm").
-- The migration only creates the setter. A local stack must not ping the hosted
-- project; on the hosted project, turn the job on with:
--   select public.alexa_keep_warm_set(
--     true,
--     'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/alexa?forceFunctionRegion=eu-central-1'
--   );
-- The POST is unsigned and carries no user data and no secrets. The function
-- answers 400 missing_signature. Off unschedules the job.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create function public.alexa_keep_warm_set(p_on boolean, p_url text default null) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not p_on then
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'alexa-keep-warm';
    return 'off';
  end if;
  if p_url is null
     or p_url !~ '^(https://[^/]+|http://(localhost|127\.0\.0\.1|kong)(:[0-9]+)?)/functions/v1/alexa[?]forceFunctionRegion=eu-central-1$' then
    raise exception 'alexa_keep_warm_set(true, url) needs the alexa function''s https URL pinned to eu-central-1'
      using errcode = '22023';
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'alexa-keep-warm';
  perform cron.schedule(
    'alexa-keep-warm',
    '*/5 * * * *',
    format(
      $cmd$select net.http_post(url := %L, headers := jsonb_build_object('content-type', 'application/json'), body := '{}'::jsonb, timeout_milliseconds := 8000)$cmd$,
      p_url
    )
  );
  return 'on';
end $$;

revoke execute on function public.alexa_keep_warm_set(boolean, text)
  from public, anon, authenticated, service_role;
