-- Job 275: DSA notices (migration *_content_reports.sql, Legal Addendum B).
-- anon and authenticated reach neither table nor any function; a report is stored trimmed with a
-- Crockford ref and '' as null; the checks refuse what the form would refuse; the hour's limit
-- stores nothing; every report with an address is to be confirmed, however many it sent (Legal
-- N-241); a decision closes the report and is logged; the purge keeps 12 months after closing and
-- waits for retain_until. Addresses: test+…@snacklist.app only.
begin;
select plan(66);

create function pg_temp.submit(
  p_at timestamptz,
  p_email text default '',
  p_name text default '',
  p_max integer default 200,
  p_location text default 'Haushalt WG, Liste Einkauf',
  p_reason text default 'Der Eintrag beleidigt mich mit vollem Namen.'
) returns table (id uuid, ref text, confirm boolean) language sql as $$
  select * from public.content_report_submit('de', 'hate', p_location, p_reason, p_name, p_email,
    p_at, p_max);
$$;

create function pg_temp.report(p_ref text) returns public.content_reports language sql as $$
  select * from public.content_reports where ref = p_ref;
$$;

-- A report in a given state, straight into the table.
create function pg_temp.seed(
  p_ref text, p_created timestamptz, p_closed timestamptz default null,
  p_retain timestamptz default null
) returns void language sql as $$
  insert into public.content_reports (ref, created_at, source, locale, category, location, reason,
    good_faith, closed_at, retain_until, retain_reason)
  values (p_ref, p_created, 'web', 'en', 'other', 'somewhere', 'a reason of twenty letters', true,
    p_closed, p_retain, case when p_retain is not null then 'proceedings' end);
$$;

-- Schema ------------------------------------------------------------------------------------------

select columns_are('public', 'content_reports', array[
  'id', 'ref', 'created_at', 'source', 'locale', 'category', 'location', 'reason', 'reporter_name',
  'reporter_email', 'good_faith', 'confirmation_sent_at', 'closed_at', 'retain_until', 'retain_reason'],
  'a report holds what the form asked, its times and the hold; no IP, no user, no household');
select columns_are('public', 'content_report_decisions', array[
  'id', 'report_id', 'decided_at', 'outcome', 'ground', 'notified_at'],
  'a decision holds date, outcome, ground and when the notifier was told (N-230)');
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relname like 'content_report%'
     and c.relkind = 'r' and c.relrowsecurity),
  array['content_report_decisions', 'content_reports'],
  'RLS is on for both tables');
select is((select count(*)::integer from pg_policies where schemaname = 'public'
           and tablename in ('content_reports', 'content_report_decisions')),
  0, 'and no policy opens either');
select is((select count(*)::integer from pg_publication_tables
           where tablename in ('content_reports', 'content_report_decisions')),
  0, 'neither table is in a realtime publication');
select is((select schedule from cron.job where jobname = 'purge-content-reports'), '27 3 * * *',
  'the purge runs daily at 03:27 UTC');
select is((select command from cron.job where jobname = 'purge-content-reports'),
  'select public.purge_content_reports()', 'with the default time');

-- Privileges --------------------------------------------------------------------------------------

select is(
  (select count(*)::integer from (values ('anon'), ('authenticated')) r(role),
     (values ('public.content_reports'), ('public.content_report_decisions')) t(tab),
     (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'), ('references'), ('trigger')) p(priv)
   where has_table_privilege(r.role, t.tab, p.priv)),
  0, 'anon and authenticated hold no privilege on either table');
select is(
  (select array_agg(distinct r.role order by r.role) from pg_proc f,
     (values ('anon'), ('authenticated'), ('public')) r(role)
   where f.pronamespace = 'public'::regnamespace
     and (f.proname like 'content_report%' or f.proname = 'purge_content_reports')
     and case when r.role = 'public'
           then exists (select from aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) a
                        where a.grantee = 0 and a.privilege_type = 'EXECUTE')
           else has_function_privilege(r.role, f.oid, 'execute') end),
  null, 'no report function is executable by anon, authenticated or public');
select is(
  (select array_agg(f.proname::text order by f.proname) from pg_proc f
   where f.pronamespace = 'public'::regnamespace
     and (f.proname like 'content_report%' or f.proname = 'purge_content_reports')
     and has_function_privilege('service_role', f.oid, 'execute')
     and f.prosecdef and f.proconfig @> array['search_path=""']),
  array['content_report_confirmation_sent', 'content_report_decide', 'content_report_notified',
        'content_report_submit', 'purge_content_reports'],
  'the service connection executes the five, security definer with an empty search_path');

select pg_temp.seed('M-0000-0001', '2026-11-10 10:00+00');

set local role anon;
select throws_ok('select * from public.content_reports', '42501', null, 'anon cannot select reports');
select throws_ok('select * from public.content_report_decisions', '42501', null, 'anon cannot select decisions');
select throws_ok($$insert into public.content_reports (ref, source, locale, category, location, reason, good_faith)
  values ('M-0000-0002', 'web', 'de', 'hate', 'x', 'a reason of twenty letters', true)$$,
  '42501', null, 'anon cannot insert a report');
select throws_ok($$update public.content_reports set closed_at = now()$$, '42501', null, 'anon cannot update');
select throws_ok($$delete from public.content_reports$$, '42501', null, 'anon cannot delete');
select throws_ok($$insert into public.content_report_decisions (report_id, decided_at, outcome, ground)
  values (gen_random_uuid(), now(), 'removed', 'x')$$, '42501', null, 'anon cannot log a decision');
select throws_ok($$update public.content_report_decisions set notified_at = now()$$, '42501', null,
  'anon cannot update a decision');
select throws_ok($$delete from public.content_report_decisions$$, '42501', null, 'anon cannot delete a decision');
select throws_ok($$select * from public.content_report_submit('de', 'hate', 'x', 'a reason of twenty letters',
  '', '', now(), 200)$$, '42501', null, 'anon cannot submit');
select throws_ok($$select public.content_report_confirmation_sent(gen_random_uuid(), now())$$, '42501', null,
  'anon cannot mark a confirmation');
select throws_ok($$select public.content_report_decide('M-0000-0001', 'removed', 'x')$$, '42501', null,
  'anon cannot decide');
select throws_ok($$select public.content_report_notified(1)$$, '42501', null, 'anon cannot mark a notice');
select throws_ok($$select public.purge_content_reports()$$, '42501', null, 'anon cannot run the purge');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000027501", "role": "authenticated"}', true);
select throws_ok('select * from public.content_reports', '42501', null, 'authenticated cannot select reports');
select throws_ok('select * from public.content_report_decisions', '42501', null, 'authenticated cannot select decisions');
select throws_ok($$insert into public.content_reports (ref, source, locale, category, location, reason, good_faith)
  values ('M-0000-0003', 'web', 'de', 'hate', 'x', 'a reason of twenty letters', true)$$,
  '42501', null, 'authenticated cannot insert a report');
select throws_ok($$update public.content_reports set closed_at = now()$$, '42501', null, 'authenticated cannot update');
select throws_ok($$delete from public.content_reports$$, '42501', null, 'authenticated cannot delete');
select throws_ok($$delete from public.content_report_decisions$$, '42501', null,
  'authenticated cannot delete a decision');
select throws_ok($$select * from public.content_report_submit('de', 'hate', 'x', 'a reason of twenty letters',
  '', '', now(), 200)$$, '42501', null, 'authenticated cannot submit');
select throws_ok($$select public.content_report_confirmation_sent(gen_random_uuid(), now())$$, '42501', null,
  'authenticated cannot mark a confirmation');
select throws_ok($$select public.content_report_decide('M-0000-0001', 'removed', 'x')$$, '42501', null,
  'authenticated cannot decide');
select throws_ok($$select public.content_report_notified(1)$$, '42501', null, 'authenticated cannot mark a notice');
select throws_ok($$select public.purge_content_reports()$$, '42501', null, 'authenticated cannot run the purge');
reset role;
select set_config('request.jwt.claims', '', true);

select is((pg_temp.report('M-0000-0001')).closed_at, null, 'the report is untouched after all of that');
delete from public.content_reports;

-- Submit ------------------------------------------------------------------------------------------

create temp table r1 as select * from pg_temp.submit('2026-11-16 13:05+00',
  p_email => '  test+cr1@snacklist.app ', p_name => '  Anna  ',
  p_location => '  Liste Einkauf  ', p_reason => '  Der Eintrag beleidigt mich mit vollem Namen.  ');
select is((select count(*)::integer from r1), 1, 'a report is stored and returned');
select matches((select ref from r1), '^M-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  'with a ref in Crockford base32 without I L O U');
select is(
  (select row(source, locale, category, location, reason, reporter_name, reporter_email, good_faith,
              created_at, confirmation_sent_at, closed_at)::text
   from public.content_reports where id = (select id from r1)),
  row('web', 'de', 'hate', 'Liste Einkauf', 'Der Eintrag beleidigt mich mit vollem Namen.', 'Anna',
      'test+cr1@snacklist.app', true, '2026-11-16 13:05+00'::timestamptz, null::timestamptz,
      null::timestamptz)::text,
  'trimmed, created at p_now, open');
select ok((select confirm from r1), 'an address gets its confirmation');

create temp table r2 as select * from pg_temp.submit('2026-11-16 13:06+00', p_email => '', p_name => '');
select is((select row(reporter_name, reporter_email)::text from public.content_reports where id = (select id from r2)),
  row(null::text, null::text)::text, 'an empty name and address are stored as null');
select ok(not (select confirm from r2), 'and nothing is to be mailed');
select isnt((select ref from r1), (select ref from r2), 'each report has its own ref');

-- Checks ------------------------------------------------------------------------------------------

select throws_ok($$select pg_temp.seed('M-I000-0000', now())$$, '23514', null, 'a ref with I is refused');
select throws_ok($$select pg_temp.seed('m-0000-0000', now())$$, '23514', null, 'a lower-case ref is refused');
select throws_ok($$select * from public.content_report_submit('fr', 'hate', 'x', 'a reason of twenty letters', '', '', now(), 200)$$,
  '23514', null, 'an unknown locale is refused');
select throws_ok($$select * from public.content_report_submit('de', 'spam', 'x', 'a reason of twenty letters', '', '', now(), 200)$$,
  '23514', null, 'an unknown category is refused');
select throws_ok($$select * from public.content_report_submit('de', 'hate', '   ', 'a reason of twenty letters', '', '', now(), 200)$$,
  '23514', null, 'an empty location is refused');
select throws_ok($$select * from public.content_report_submit('de', 'hate', 'x', repeat('r', 19), '', '', now(), 200)$$,
  '23514', null, 'a reason under 20 characters is refused');
select throws_ok($$select * from public.content_report_submit('de', 'hate', 'x', repeat('r', 5001), '', '', now(), 200)$$,
  '23514', null, 'a reason over 5000 characters is refused');
select throws_ok($$select * from public.content_report_submit('de', 'hate', 'x', 'a reason of twenty letters', repeat('n', 201), '', now(), 200)$$,
  '23514', null, 'a name over 200 characters is refused');
select throws_ok($$insert into public.content_reports (ref, source, locale, category, location, reason, good_faith)
  values ('M-0000-0004', 'app', 'de', 'hate', 'x', 'a reason of twenty letters', true)$$,
  '23514', null, 'source is web only (the in-app job adds app)');
select throws_ok($$insert into public.content_reports (ref, source, locale, category, location, reason, good_faith)
  values ('M-0000-0005', 'web', 'de', 'hate', 'x', 'a reason of twenty letters', false)$$,
  '23514', null, 'good faith must be confirmed');
select throws_ok($$insert into public.content_reports (ref, source, locale, category, location, reason, good_faith, retain_until)
  values ('M-0000-0006', 'web', 'de', 'hate', 'x', 'a reason of twenty letters', true, now())$$,
  '23514', null, 'a hold needs its reason');

-- The hour's limit and the confirmations ----------------------------------------------------------

delete from public.content_reports;
select pg_temp.submit('2026-11-16 12:00+00');
select pg_temp.submit('2026-11-16 12:30+00');
select is((select count(*)::integer from pg_temp.submit('2026-11-16 12:59+00', p_max => 2)), 0,
  'with p_max_per_hour reports in the last hour the next gets no row');
select is((select count(*)::integer from public.content_reports), 2, 'and nothing is stored');
select is((select count(*)::integer from pg_temp.submit('2026-11-16 13:00+00', p_max => 2)), 1,
  'an hour after the first, one fits again');

delete from public.content_reports;
select is((select array_agg((select confirm from pg_temp.submit('2026-11-17 11:00+00'::timestamptz + n * interval '1 second',
  p_email => case when n % 2 = 0 then 'test+cr2@snacklist.app' else 'TEST+CR2@snacklist.app' end)) order by n)
  from generate_series(1, 5) n), array[true, true, true, true, true],
  'every report with an address is to be confirmed, also the fifth from one address in seconds (N-241)');
select ok(not public.content_report_confirmation_sent((select id from pg_temp.submit('2026-11-17 10:03+00')), now()),
  'a report without an address is never marked as mailed');

-- Decide, notify, purge ---------------------------------------------------------------------------

delete from public.content_reports;
select pg_temp.seed('M-0000-00D1', '2026-11-16 10:00+00');
create temp table d1 as select public.content_report_decide('m-0000-00d1', 'removed', '  Beleidigung nach § 185 StGB ', '2026-11-16 18:00+00') as id;
select is(
  (select row(d.outcome, d.ground, d.decided_at, d.notified_at, r.closed_at)::text
   from public.content_report_decisions d join public.content_reports r on r.id = d.report_id
   where d.id = (select id from d1)),
  row('removed', 'Beleidigung nach § 185 StGB', '2026-11-16 18:00+00'::timestamptz, null::timestamptz,
      '2026-11-16 18:00+00'::timestamptz)::text,
  'a decision is logged and closes the report at its time');
select throws_ok($$select public.content_report_decide('M-ZZZZ-ZZZZ', 'removed', 'x')$$, 'P0002', null,
  'an unknown ref raises');
select throws_ok($$select public.content_report_decide('M-0000-00D1', 'deleted', 'x')$$, '23514', null,
  'an unknown outcome is refused');
select ok(public.content_report_notified((select id from d1), '2026-11-16 18:05+00'), 'the notice is recorded');
select is((select notified_at from public.content_report_decisions where id = (select id from d1)),
  '2026-11-16 18:05+00'::timestamptz, 'at its time');

delete from public.content_reports;
select pg_temp.seed('M-0000-00P1', '2025-01-01 10:00+00', p_closed => '2025-11-16 10:00+00');
select pg_temp.seed('M-0000-00P2', '2025-01-01 10:00+00', p_closed => '2025-11-16 10:02+00');
select pg_temp.seed('M-0000-00P3', '2025-01-01 10:00+00', p_closed => '2025-01-01 10:00+00', p_retain => '2027-01-01 00:00+00');
select pg_temp.seed('M-0000-00P4', '2025-01-01 10:00+00', p_closed => '2025-01-01 10:00+00', p_retain => '2026-11-01 00:00+00');
select pg_temp.seed('M-0000-00P5', '2024-01-01 10:00+00');
insert into public.content_report_decisions (report_id, decided_at, outcome, ground)
select id, closed_at, 'no_change', 'not found' from public.content_reports where ref = 'M-0000-00P1';
select is(public.purge_content_reports('2026-11-16 10:01+00'), 2,
  'the purge removes what closed over 12 months ago and whose hold has ended');
select is((select array_agg(ref order by ref) from public.content_reports),
  array['M-0000-00P2', 'M-0000-00P3', 'M-0000-00P5'],
  'it keeps a case closed a minute too late, a held one and an open one however old');
select is((select count(*)::integer from public.content_report_decisions), 0, 'decisions go with their report');

select * from finish();
rollback;
