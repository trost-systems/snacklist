-- Alexa keep-warm every minute instead of every five (docs/ALEXA.md, "Keep-warm").
-- Replaces the setter and, if the job is already on, reschedules it with the
-- same URL so a local stack that turned it on keeps its own endpoint.

create or replace function public.alexa_keep_warm_set(p_on boolean, p_url text default null) returns text
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
    '* * * * *',
    format(
      $cmd$select net.http_post(url := %L, headers := jsonb_build_object('content-type', 'application/json'), body := '{}'::jsonb, timeout_milliseconds := 8000)$cmd$,
      p_url
    )
  );
  return 'on';
end $$;

revoke execute on function public.alexa_keep_warm_set(boolean, text)
  from public, anon, authenticated, service_role;

do $$
declare
  v_cmd text;
  v_url text;
begin
  select j.command into v_cmd from cron.job j where j.jobname = 'alexa-keep-warm';
  if v_cmd is null then
    return;
  end if;
  v_url := substring(v_cmd from $re$url := '([^']+)'$re$);
  if v_url is not null then
    perform public.alexa_keep_warm_set(true, v_url);
  end if;
end $$;
