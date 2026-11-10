-- Legal review N-113: the join page's rate-limit rows of past hours go hourly, without traffic.
begin;
select plan(6);

select is((select schedule || ' ' || command from cron.job where jobname = 'purge-invite-preview-rate'),
  '0 * * * * select public.purge_invite_preview_rate()', 'the purge runs at the start of every hour');

delete from public.invite_preview_rate;
insert into public.invite_preview_rate (key_hash, window_start, hits) values
  (repeat('a', 64), date_trunc('hour', now()) - interval '1 hour', 5),
  (repeat('b', 64), date_trunc('hour', now()) - interval '2 days', 1),
  (repeat('c', 64), date_trunc('hour', now()), 3),
  (repeat('d', 64), date_trunc('hour', now()) - interval '1 hour', 30);

select is(public.purge_invite_preview_rate(), 3, 'it deletes every row of a past hour');
select is((select array_agg(key_hash) from public.invite_preview_rate), array[repeat('c', 64)],
  'and keeps the current hour''s');
select is(public.purge_invite_preview_rate(), 0, 'a second run finds nothing');

select ok(not has_function_privilege('anon', 'public.purge_invite_preview_rate()', 'execute'),
  'signed out nobody calls it');
select ok(not has_function_privilege('authenticated', 'public.purge_invite_preview_rate()', 'execute'),
  'nor a signed-in user');

select * from finish();
rollback;
