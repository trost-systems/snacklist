-- Job 281: reports from the app (migration *_content_reports_app.sql). anon and authenticated reach
-- neither new table nor function; an app report is stored trimmed with its target, its screenshot
-- and a sender row; every one with an address is confirmed (no per-address cap); the per-user and
-- the overall app limit store nothing and say which refused, and count apart from web reports; the
-- checks keep web rows without a target and app rows with a consistent one; the purge takes the
-- screenshot along; sender rows go after an hour. Addresses: test+…@snacklist.app only.
begin;
select plan(51);

create function pg_temp.png(p_size integer default 16) returns bytea language sql as $$
  select '\x89504e470d0a1a0a'::bytea || decode(repeat('00', p_size - 8), 'hex');
$$;

create function pg_temp.submit(
  p_user uuid,
  p_at timestamptz,
  p_kind text default 'item',
  p_target uuid default '7c9e6679-7425-40de-944b-e07fc1f90ae7',
  p_email text default '',
  p_shot bytea default null,
  p_max_user integer default 5,
  p_max integer default 200
) returns table (id uuid, ref text, confirm boolean, refused text) language sql as $$
  select * from public.content_report_submit_app(p_user, 'en', 'personal_rights', p_kind, p_target,
    'item "Foto" in list "Einkauf", household "WG"', 'This item names me without my consent.', '',
    p_email, p_shot, p_at, p_max_user, p_max);
$$;

-- A report in a given state, straight into the table.
create function pg_temp.seed(
  p_ref text, p_source text, p_kind text, p_target uuid, p_created timestamptz default now(),
  p_closed timestamptz default null
) returns void language sql as $$
  insert into public.content_reports (ref, created_at, source, locale, category, location, reason,
    good_faith, target_kind, target_id, closed_at)
  values (p_ref, p_created, p_source, 'en', 'other', 'somewhere', 'a reason of twenty letters', true,
    p_kind, p_target, p_closed);
$$;

create function pg_temp.reports() returns integer language sql as $$
  select count(*)::integer from public.content_reports;
$$;

-- Schema ------------------------------------------------------------------------------------------

select columns_are('public', 'content_report_screenshots', array['report_id', 'png'],
  'a screenshot is its report''s PNG and nothing else');
select columns_are('public', 'content_report_app_senders', array['user_id', 'at'],
  'a sender row is a user and a time, for the limit');
select is((select count(*)::integer from pg_policies where schemaname = 'public'
           and tablename in ('content_report_screenshots', 'content_report_app_senders')),
  0, 'no policy opens either new table');
select is((select count(*)::integer from pg_constraint
           where conrelid = 'public.content_report_app_senders'::regclass and contype = 'f'),
  0, 'sender rows have no foreign key to auth.users (its lock would deadlock delete_account)');
select is((select count(*)::integer from pg_publication_tables
           where tablename in ('content_report_screenshots', 'content_report_app_senders')),
  0, 'neither new table is in a realtime publication');
select is((select command from cron.job where jobname = 'prune-content-report-app-senders'),
  'select public.prune_content_report_app_senders()', 'sender rows are pruned by the cron job');
select is((select schedule from cron.job where jobname = 'prune-content-report-app-senders'),
  '20 * * * *', 'every hour, so a row lives under two hours: the policy says a day at most (Legal N-283)');

-- Privileges --------------------------------------------------------------------------------------

select is(
  (select count(*)::integer from (values ('anon'), ('authenticated')) r(role),
     (values ('public.content_report_screenshots'), ('public.content_report_app_senders')) t(tab),
     (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'), ('references'), ('trigger')) p(priv)
   where has_table_privilege(r.role, t.tab, p.priv)),
  0, 'anon and authenticated hold no privilege on either new table');
select is(
  (select count(*)::integer from pg_proc f, (values ('anon'), ('authenticated')) r(role)
   where f.oid in ('public.content_report_submit_app'::regproc, 'public.prune_content_report_app_senders'::regproc)
     and has_function_privilege(r.role, f.oid, 'execute')),
  0, 'nor on either new function');
select ok(
  (select bool_and(has_function_privilege('service_role', f.oid, 'execute') and f.prosecdef
                   and f.proconfig @> array['search_path=""'])
   from pg_proc f
   where f.oid in ('public.content_report_submit_app'::regproc, 'public.prune_content_report_app_senders'::regproc)),
  'the service connection executes both, security definer with an empty search_path');

set local role anon;
select throws_ok($$select * from public.content_report_submit_app(gen_random_uuid(), 'en', 'other',
  'elsewhere', null, 'x', 'a reason of twenty letters', '', '', null, now(), 5, 200)$$, '42501', null,
  'anon cannot submit an app report');
select throws_ok('select * from public.content_report_screenshots', '42501', null,
  'anon cannot read screenshots');
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000028101", "role": "authenticated"}', true);
select throws_ok($$select * from public.content_report_submit_app('00000000-0000-0000-0000-000000028101',
  'en', 'other', 'elsewhere', null, 'x', 'a reason of twenty letters', '', '', null, now(), 5, 200)$$,
  '42501', null, 'a signed-in user cannot submit around the function');
select throws_ok('select * from public.content_report_screenshots', '42501', null,
  'authenticated cannot read screenshots');
select throws_ok('select * from public.content_report_app_senders', '42501', null,
  'authenticated cannot read sender rows');
select throws_ok('select public.prune_content_report_app_senders()', '42501', null,
  'authenticated cannot prune');
reset role;
select set_config('request.jwt.claims', '', true);

-- Submit ------------------------------------------------------------------------------------------

delete from public.content_reports;
delete from public.content_report_app_senders;

create temp table a1 as select * from public.content_report_submit_app(
  '00000000-0000-0000-0000-0000000281a1', 'en', 'personal_rights', 'item',
  '7c9e6679-7425-40de-944b-e07fc1f90ae7', '  item "Foto" in list "Einkauf"  ',
  '  This item names me without my consent.  ', '  Anna  ', ' test+app1@snacklist.app ',
  pg_temp.png(), '2026-11-17 13:00+00', 5, 200);
select is((select row(confirm, refused)::text from a1), row(true, null::text)::text,
  'an app report with an address is stored, to be confirmed');
select matches((select ref from a1), '^M-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  'with a ref like a web report''s');
select is(
  (select row(source, locale, category, target_kind, target_id, location, reason, reporter_name,
              reporter_email, good_faith, created_at)::text
   from public.content_reports where id = (select id from a1)),
  row('app', 'en', 'personal_rights', 'item', '7c9e6679-7425-40de-944b-e07fc1f90ae7'::uuid,
      'item "Foto" in list "Einkauf"', 'This item names me without my consent.', 'Anna',
      'test+app1@snacklist.app', true, '2026-11-17 13:00+00'::timestamptz)::text,
  'trimmed, with its target, created at p_now');
select is((select png from public.content_report_screenshots where report_id = (select id from a1)),
  pg_temp.png(), 'its screenshot is stored with it');
select is((select row(user_id, at)::text from public.content_report_app_senders),
  row('00000000-0000-0000-0000-0000000281a1'::uuid, '2026-11-17 13:00+00'::timestamptz)::text,
  'and one sender row');

create temp table a2 as select * from pg_temp.submit('00000000-0000-0000-0000-0000000281a1',
  '2026-11-17 13:01+00', p_kind => 'elsewhere', p_target => null);
select is((select row(target_kind, target_id, reporter_email)::text from public.content_reports
           where id = (select id from a2)),
  row('elsewhere', null::uuid, null::text)::text, 'elsewhere has no id; an empty address is null');
select ok(not (select confirm from a2), 'and nothing is to be mailed');
select is((select count(*)::integer from public.content_report_screenshots
           where report_id = (select id from a2)), 0, 'no screenshot, no row');

select is(
  (select array_agg((select confirm from pg_temp.submit(gen_random_uuid(),
     '2026-11-17 14:00+00'::timestamptz + n * interval '1 second',
     p_email => case when n % 2 = 0 then 'test+app2@snacklist.app' else 'TEST+APP2@snacklist.app' end))
   order by n) from generate_series(1, 5) n),
  array[true, true, true, true, true],
  'every app report with an address is confirmed: no per-address cap (Legal N-241)');

-- Limits ------------------------------------------------------------------------------------------

delete from public.content_reports;
delete from public.content_report_app_senders;
select pg_temp.submit('00000000-0000-0000-0000-0000000281b1', '2026-11-17 12:00+00', p_shot => pg_temp.png());
select pg_temp.submit('00000000-0000-0000-0000-0000000281b1', '2026-11-17 12:30+00');
create temp table limited as select * from pg_temp.submit('00000000-0000-0000-0000-0000000281b1',
  '2026-11-17 12:59+00', p_shot => pg_temp.png(), p_max_user => 2);
select is((select row(id, ref, confirm, refused)::text from limited),
  row(null::uuid, null::text, false, 'user')::text,
  'with p_max_per_user_hour reports in the last hour the user is refused: refused is user');
select is(
  (select row(pg_temp.reports(), (select count(*) from public.content_report_screenshots),
              (select count(*) from public.content_report_app_senders))::text),
  row(2, 1::bigint, 2::bigint)::text, 'and nothing is stored: no report, screenshot or sender row');
select is((select refused from pg_temp.submit('00000000-0000-0000-0000-0000000281b2',
  '2026-11-17 12:59+00', p_max_user => 2)), null, 'another user is limited on their own');
select is((select refused from pg_temp.submit('00000000-0000-0000-0000-0000000281b1',
  '2026-11-17 13:00+00', p_max_user => 2)), null, 'an hour after the first, the user fits again');
select is((select array_agg(at order by at) from public.content_report_app_senders
           where user_id = '00000000-0000-0000-0000-0000000281b1'),
  array['2026-11-17 12:30+00', '2026-11-17 13:00+00']::timestamptz[],
  'and that submit dropped the sender row older than an hour');

delete from public.content_reports;
delete from public.content_report_app_senders;
select pg_temp.submit(gen_random_uuid(), '2026-11-17 15:00+00');
select pg_temp.submit(gen_random_uuid(), '2026-11-17 15:10+00');
select is((select row(id, refused)::text from pg_temp.submit(gen_random_uuid(), '2026-11-17 15:20+00', p_max => 2)),
  row(null::uuid, 'global')::text,
  'with p_max_per_hour app reports in the last hour anyone is refused: refused is global');
select is(pg_temp.reports(), 2, 'and nothing is stored');
select pg_temp.seed('M-0000-0W01', 'web', null, null, '2026-11-17 15:15+00');
select pg_temp.seed('M-0000-0W02', 'web', null, null, '2026-11-17 15:16+00');
select pg_temp.seed('M-0000-0W03', 'web', null, null, '2026-11-17 15:17+00');
select is((select refused from pg_temp.submit(gen_random_uuid(), '2026-11-17 15:20+00', p_max => 3)), null,
  'web reports do not count toward the app''s hour');

-- Checks ------------------------------------------------------------------------------------------

select throws_ok($$select pg_temp.seed('M-0000-0C01', 'web', 'item', gen_random_uuid())$$, '23514', null,
  'a web report has no target kind');
select throws_ok($$select pg_temp.seed('M-0000-0C02', 'web', null, gen_random_uuid())$$, '23514', null,
  'nor a target id');
select throws_ok($$select pg_temp.seed('M-0000-0C03', 'app', null, null)$$, '23514', null,
  'an app report has a target kind');
select throws_ok($$select pg_temp.seed('M-0000-0C04', 'app', 'list', null)$$, '23514', null,
  'a picked list has its id');
select throws_ok($$select pg_temp.seed('M-0000-0C05', 'app', 'elsewhere', gen_random_uuid())$$, '23514', null,
  'elsewhere has none');
select throws_ok($$select pg_temp.seed('M-0000-0C06', 'app', 'photo', gen_random_uuid())$$, '23514', null,
  'an unknown target kind is refused');
select throws_ok($$select pg_temp.seed('M-0000-0C07', 'mail', null, null)$$, '23514', null,
  'an unknown source is refused');
select lives_ok($$select pg_temp.seed('M-0000-0C08', 'app', 'household', gen_random_uuid())$$,
  'a picked household with its id is fine');
select throws_ok($$select * from pg_temp.submit(gen_random_uuid(), '2026-11-17 16:00+00', p_shot => '\x89504e470d0a1a'::bytea)$$,
  '23514', null, 'a screenshot under 8 bytes is refused');
select throws_ok($$select * from pg_temp.submit(gen_random_uuid(), '2026-11-17 16:00+00', p_shot => pg_temp.png(2097153))$$,
  '23514', null, 'a screenshot over 2 MiB is refused');
select is((select refused from pg_temp.submit(gen_random_uuid(), '2026-11-17 16:00+00', p_shot => pg_temp.png(2097152))),
  null, 'a screenshot of exactly 2 MiB is stored');

-- Child sexual abuse material ---------------------------------------------------------------------

delete from public.content_report_app_senders;
select is((select refused from public.content_report_submit_app('00000000-0000-0000-0000-000000028199',
    'de', 'csam', 'elsewhere', null, 'irgendwo', 'Ein Bericht mit zwanzig Zeichen.', '', '', null,
    '2026-11-17 17:00+00', 0, 200)),
  null, 'a CSAM report is stored even when the per-user limit is used up (it does not count)');
select is((select count(*)::integer from public.content_report_app_senders), 0,
  'and leaves no sender row, so nothing ties it to the account');
select is((select reporter_email from public.content_reports
           where category = 'csam' and created_at = '2026-11-17 17:00+00'), null,
  'and carries no address when none was given');

-- Purge and prune ---------------------------------------------------------------------------------

delete from public.content_reports;
create temp table old as select * from pg_temp.submit(gen_random_uuid(), '2025-01-01 10:00+00', p_shot => pg_temp.png());
update public.content_reports set closed_at = '2025-01-02 10:00+00' where id = (select id from old);
select is(public.purge_content_reports('2026-11-17 10:00+00'), 1, 'the purge removes a closed app report');
select is((select count(*)::integer from public.content_report_screenshots), 0, 'and its screenshot with it');

delete from public.content_report_app_senders;
insert into public.content_report_app_senders (user_id, at) values
  (gen_random_uuid(), '2026-11-17 08:00+00'),
  (gen_random_uuid(), '2026-11-17 09:00+00'),
  (gen_random_uuid(), '2026-11-17 09:30+00');
select is(public.prune_content_report_app_senders('2026-11-17 10:00+00'), 2,
  'the daily prune removes sender rows an hour old or older');
select is((select array_agg(at) from public.content_report_app_senders),
  array['2026-11-17 09:30+00'::timestamptz], 'and keeps the last hour''s');

select * from finish();
rollback;
