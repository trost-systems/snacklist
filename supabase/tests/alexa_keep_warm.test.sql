-- Alexa keep-warm setter (docs/ALEXA.md, "Keep-warm"): off by default, no job until
-- turned on; clients cannot switch it; the URL must be the pinned alexa endpoint;
-- the job posts unsigned, with no secret in the command.
begin;
select plan(17);

create function pg_temp.as_role(p_role text) returns void language plpgsql as $$
begin
  perform set_config('role', p_role, true);
  perform set_config('request.jwt.claims',
    case when p_role = 'authenticated'
      then json_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated')::text
      else '' end, true);
end $$;

select is((select count(*)::int from cron.job where jobname = 'alexa-keep-warm'), 0,
  'the migration schedules no alexa-keep-warm job');

select pg_temp.as_role('authenticated');
select throws_ok($$ select public.alexa_keep_warm_set(false) $$, '42501', null,
  'a signed-in user cannot switch it');
select pg_temp.as_role('anon');
select throws_ok($$ select public.alexa_keep_warm_set(true, 'https://fn.test/functions/v1/alexa?forceFunctionRegion=eu-central-1') $$,
  '42501', null, 'anon cannot switch it');
select pg_temp.as_role('service_role');
select throws_ok($$ select public.alexa_keep_warm_set(true, 'https://fn.test/functions/v1/alexa?forceFunctionRegion=eu-central-1') $$,
  '42501', null, 'the service key cannot switch it');
select pg_temp.as_role('postgres');

select throws_ok($$ select public.alexa_keep_warm_set(true) $$, '22023', null, 'on without a URL is refused');
select throws_ok($$ select public.alexa_keep_warm_set(true, 'file:///etc/passwd') $$, '22023', null,
  'on with a non-HTTP URL is refused');
select throws_ok($$ select public.alexa_keep_warm_set(true, 'http://fn.test/functions/v1/alexa?forceFunctionRegion=eu-central-1') $$,
  '22023', null, 'plain http to a real host is refused');
select throws_ok($$ select public.alexa_keep_warm_set(true, 'https://fn.test/functions/v1/alexa') $$,
  '22023', null, 'https without the region pin is refused');
select is(public.alexa_keep_warm_set(true, 'http://kong:8000/functions/v1/alexa?forceFunctionRegion=eu-central-1'),
  'on', 'plain http to the local stack is allowed');
select is(public.alexa_keep_warm_set(true, 'https://fn.test/functions/v1/alexa?forceFunctionRegion=eu-central-1'),
  'on', 'on with a pinned https URL');
select is((select count(*)::int from cron.job where jobname = 'alexa-keep-warm'), 1, 'one job');
select is((select schedule from cron.job where jobname = 'alexa-keep-warm'), '*/5 * * * *',
  'every five minutes');
select ok((select command like '%net.http_post(url := ''https://fn.test/functions/v1/alexa?forceFunctionRegion=eu-central-1''%'
  from cron.job where jobname = 'alexa-keep-warm'), 'the job posts to the given URL');
select ok((select position('vault' in lower(command)) = 0
  from cron.job where jobname = 'alexa-keep-warm'), 'the job holds no vault secret');
select is(public.alexa_keep_warm_set(false), 'off', 'off');
select is((select count(*)::int from cron.job where jobname = 'alexa-keep-warm'), 0, 'the job is gone');
select is(public.alexa_keep_warm_set(false), 'off', 'off twice is fine');

select * from finish();
rollback;
