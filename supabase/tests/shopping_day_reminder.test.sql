-- Job 378: the shopping-day reminder (20261123000000_shopping_day_reminder.sql, docs/PUSH.md).
-- Off by default and per person; weekdays, zone and language saved through set_shopping_day_reminder
-- only; due at 19:00 to 19:29 local the evening before a chosen weekday, once, in Europe/Berlin
-- on both sides of a clock change and in another zone; the send goes through pg_net with the
-- open-item count; export and account deletion. Fictional people, no real ids.
begin;
select plan(61);

\set anna '''00000000-0000-4000-8000-000000378a01'''
\set bruno '''00000000-0000-4000-8000-000000378b01'''
\set carla '''00000000-0000-4000-8000-000000378c01'''

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;
create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;
create function pg_temp.due(p_at timestamptz) returns text language sql as $$
  select coalesce(string_agg(d.user_id::text, ',' order by d.user_id), '') from public.shopping_day_due(p_at) d
  where d.user_id::text like '00000000-0000-4000-8000-000000378%'
$$;

insert into auth.users (id, email) values
  (:anna, 'anna378@fg.test'), (:bruno, 'bruno378@fg.test'), (:carla, 'carla378@fg.test');

select pg_temp.login(:anna);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select pg_temp.as_postgres();
insert into public.items (household_id, name) select id, 'Milch' from home;
insert into public.items (household_id, name) select id, 'Brot' from home;
insert into public.items (household_id, name, status) select id, 'Butter', 'bought' from home;
insert into public.push_tokens (user_id, token, platform) values (:anna, 'test-token-shopping-day-a', 'ios');

-- Off by default, per person ------------------------------------------------------------------
select is((select count(*)::int from public.shopping_day_reminders where user_id in (:anna, :bruno, :carla)), 0, 'no reminder row exists until someone opts in');
select is(pg_temp.due('2026-12-02 18:00:00+00'), '', 'nobody is due');
select pg_temp.login(:anna);
select lives_ok($$ select public.set_shopping_day_reminder(array[4, 4, 1], 'Europe/Berlin', 'de') $$, 'Anna picks Monday and Thursday');
select is((select weekdays from public.shopping_day_reminders), array[1, 4]::smallint[], 'sorted, each once');
select is((select time_zone || '/' || locale from public.shopping_day_reminders), 'Europe/Berlin/de', 'with her zone and language');
select pg_temp.login(:bruno);
select is((select count(*)::int from public.shopping_day_reminders), 0, 'Bruno reads none of hers');
select lives_ok($$ select public.set_shopping_day_reminder(array[]::integer[], 'Europe/Berlin', 'de') $$, 'no weekday is allowed and means off');
select is((select count(*)::int from public.shopping_day_reminders), 0, 'and creates nothing for Bruno');
select pg_temp.login(:anna);
select throws_ok($$ insert into public.shopping_day_reminders (user_id, weekdays, time_zone, locale)
  values ('00000000-0000-4000-8000-000000378a01', array[1]::smallint[], 'Europe/Berlin', 'de') $$, '42501', null, 'no direct insert');
select throws_ok($$ update public.shopping_day_reminders set weekdays = array[2]::smallint[] $$, '42501', null, 'no direct update');
select throws_ok($$ delete from public.shopping_day_reminders $$, '42501', null, 'no direct delete');
select throws_ok($$ select public.set_shopping_day_reminder(array[8], 'Europe/Berlin', 'de') $$, '22023', 'invalid_weekdays', 'no weekday 8');
select throws_ok($$ select public.set_shopping_day_reminder(array[0], 'Europe/Berlin', 'de') $$, '22023', 'invalid_weekdays', 'no weekday 0');
select throws_ok($$ select public.set_shopping_day_reminder(array[1], 'Mars/Olympus', 'de') $$, '22023', 'invalid_time_zone', 'only IANA zones');
select throws_ok($$ select public.set_shopping_day_reminder(array[1], null, 'de') $$, '22023', 'invalid_time_zone', 'a zone is needed');
select throws_ok($$ select public.set_shopping_day_reminder(array[1], 'Europe/Berlin', 'fr') $$, '22023', 'invalid_locale', 'only de and en');
select pg_temp.as_postgres();
select throws_ok($$ select public.set_shopping_day_reminder(array[1], 'Europe/Berlin', 'de') $$, '28000', 'not_authenticated', 'signed out is refused');

-- Weekday and 19:00 local, Europe/Berlin ------------------------------------------------------
-- 2026-12-02 is a Wednesday, so Thursday's reminder; Berlin is UTC+1 in winter.
select pg_temp.as_postgres();
select is(pg_temp.due('2026-12-02 18:00:00+00'), '00000000-0000-4000-8000-000000378a01', '19:00 local the evening before Thursday is due');
select is(pg_temp.due('2026-12-02 17:59:59+00'), '', 'not a second before 19:00 local');
select is(pg_temp.due('2026-12-02 18:29:59+00'), '00000000-0000-4000-8000-000000378a01', 'still due until 19:29:59, so a late run sends');
select is(pg_temp.due('2026-12-02 18:30:00+00'), '', 'not from 19:30');
select is(pg_temp.due('2026-12-01 18:00:00+00'), '', 'the evening before Wednesday is no shopping evening');
select is(pg_temp.due('2026-11-29 18:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'Sunday evening is due for Monday');
select is(pg_temp.due('2026-12-03 18:00:00+00'), '', 'the evening before Friday is not');
-- 2027-06-02 is a Wednesday; Berlin is UTC+2.
select is(pg_temp.due('2027-06-02 17:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'summer: 19:00 local is 17:00 UTC');
select is(pg_temp.due('2027-06-02 18:00:00+00'), '', 'summer: 18:00 UTC is 20:00 local, past the window');
-- Clock changes: Sunday 2027-03-28 (spring forward) before Monday; Sunday 2026-10-25 (fall back).
select is(pg_temp.due('2027-03-28 17:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'on the day clocks go forward, 19:00 is 17:00 UTC');
select is(pg_temp.due('2027-03-28 18:00:00+00'), '', 'and 18:00 UTC is 20:00 that evening');
select is(pg_temp.due('2026-10-25 18:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'on the day clocks go back, 19:00 is 18:00 UTC');
select is(pg_temp.due('2026-10-25 17:00:00+00'), '', 'and 17:00 UTC is 18:00 that evening');

-- Not due without a device, a household or a list --------------------------------------------
delete from public.push_tokens;
select is(pg_temp.due('2026-12-02 18:00:00+00'), '', 'no device, no reminder');
insert into public.push_tokens (user_id, token, platform) values (:anna, 'test-token-shopping-day-a', 'ios');

-- Opening Einstellungen refreshes zone and language without cancelling an evening's reminder.
select pg_temp.login(:anna);
select public.refresh_shopping_day_reminder('Europe/Lisbon', 'en');
select is((select time_zone || '/' || locale || '/' || weekdays::text from public.shopping_day_reminders), 'Europe/Lisbon/en/{1,4}', 'the zone and language move, the days stay');
select public.refresh_shopping_day_reminder('Europe/Berlin', 'de');
select throws_ok($$ select public.refresh_shopping_day_reminder('Mars/Olympus', 'de') $$, '22023', 'invalid_time_zone', 'a refresh takes IANA zones only');
select pg_temp.as_postgres();
select is(pg_temp.due('2026-12-02 18:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'a refresh at 19:00 local leaves the reminder due');
select pg_temp.as_postgres();

-- No household: not due either (a person without one has no list to open).
select pg_temp.login(:bruno);
select public.set_shopping_day_reminder(array[4], 'Europe/Berlin', 'de');
select pg_temp.as_postgres();
insert into public.push_tokens (user_id, token, platform) values (:bruno, 'test-token-shopping-day-b', 'ios');
select is(pg_temp.due('2026-12-02 18:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'Bruno has devices but no household: not due');
delete from public.shopping_day_reminders where user_id = :bruno;

-- Saving late counts as sent: a zone where it is 19:00 or later now, one where it is earlier.
select pg_temp.login(:bruno);
select public.set_shopping_day_reminder(array[1], z.name, 'de')
from (select name from pg_catalog.pg_timezone_names where name like 'Etc/GMT%'
        and (now() at time zone name)::time >= time '19:00' order by name limit 1) z;
select is((select last_sent_on from public.shopping_day_reminders where user_id = :bruno),
  (select (now() at time zone time_zone)::date from public.shopping_day_reminders where user_id = :bruno),
  'saved at or after 19:00 local: that evening counts as sent');
select public.set_shopping_day_reminder(array[1], z.name, 'de')
from (select name from pg_catalog.pg_timezone_names where name like 'Etc/GMT%'
        and (now() at time zone name)::time < time '19:00' order by name limit 1) z;
select is((select last_sent_on from public.shopping_day_reminders where user_id = :bruno),
  (select (now() at time zone z.name)::date from (select name from pg_catalog.pg_timezone_names where name like 'Etc/GMT%'
        and (now() at time zone name)::time >= time '19:00' order by name limit 1) z),
  'a save before 19:00 in a new zone keeps the date already sent');
select pg_temp.as_postgres();
delete from public.shopping_day_reminders where user_id = :bruno;
select pg_temp.login(:bruno);
select public.set_shopping_day_reminder(array[1], z.name, 'de')
from (select name from pg_catalog.pg_timezone_names where name like 'Etc/GMT%'
        and (now() at time zone name)::time < time '19:00' order by name limit 1) z;
select is((select last_sent_on from public.shopping_day_reminders where user_id = :bruno), null::date,
  'saved before 19:00 local: nothing marked sent');
select pg_temp.as_postgres();
delete from public.shopping_day_reminders where user_id = :bruno;

-- Another zone: 19:00 in New York (UTC-5 in December) is 00:00 UTC the next day -------------
select pg_temp.login(:carla);
select public.set_shopping_day_reminder(array[4], 'America/New_York', 'en');
create temp table carla_h as select id from public.create_household(gen_random_uuid(), 'Home');
select pg_temp.as_postgres();
insert into public.push_tokens (user_id, token, platform) values (:carla, 'test-token-shopping-day-c', 'android');
select is(pg_temp.due('2026-12-03 00:00:00+00'), '00000000-0000-4000-8000-000000378c01', 'New York: Wednesday 19:00 local is Thursday 00:00 UTC');
select is(pg_temp.due('2026-12-02 18:00:00+00'), '00000000-0000-4000-8000-000000378a01', 'and Berlin at its own 19:00 does not pull New York along');

-- Sending ---------------------------------------------------------------------------------------
select pg_temp.as_postgres();
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-02 18:00:00+00'), 0, 'the switch is off: nothing sent');
select throws_ok($$ select public.shopping_day_set(true, 'http://evil.example/push') $$, '22023', null, 'the switch needs an https URL');
select throws_ok($$ select public.shopping_day_set(true, 'https://push.example.test/functions/v1/push') $$, '22023', null, 'and the vault secret');
select vault.create_secret('test-secret-378', 'push_send_secret');
select is(public.shopping_day_set(true, 'https://push.example.test/functions/v1/push'), 'on', 'on');
select is((select schedule from cron.job where jobname = 'shopping-day-reminder'), '*/10 * * * *', 'every ten minutes');
delete from net.http_request_queue;
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-02 18:00:00+00'), 1, 'Anna is sent her reminder');
select is((select convert_from(body, 'utf8')::jsonb #>> '{recipients,0,body}' from net.http_request_queue),
  '2 Artikel stehen auf der Liste. Schau kurz rein.', 'in German, with the open items counted (bought ones not)');
select is((select convert_from(body, 'utf8')::jsonb ->> 'household_id' from net.http_request_queue), (select id::text from home),
  'the request names the household, which a tap opens (kind list, push foundation)');
select is((select convert_from(body, 'utf8')::jsonb ->> 'list_id' from net.http_request_queue), (select public.first_list(id)::text from home),
  'and its list');
select is((select headers ->> 'x-push-secret' from net.http_request_queue), 'test-secret-378', 'with the vault secret');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-02 18:10:00+00'), 0, 'a second run the same evening sends nothing');
select is((select last_sent_on from public.shopping_day_reminders where user_id = :anna), date '2026-12-02', 'the local date is remembered');
select is(public.shopping_day_text('en', 0)::text, '{"body": "Have a quick look at the list.", "title": "Shopping day tomorrow"}', 'English without a count');
select is(public.shopping_day_text('de', 1) ->> 'body', '1 Artikel steht auf der Liste. Schau kurz rein.', 'one item in German');
select is(public.shopping_day_set(false), 'off', 'off');
select is((select count(*)::int from cron.job where jobname = 'shopping-day-reminder'), 0, 'the job is gone');

-- Export and deletion ---------------------------------------------------------------------------
select pg_temp.login(:anna);
select is(public.export_my_data() #>> '{shopping_day_reminder,time_zone}', 'Europe/Berlin', 'the export has the reminder');
-- Legal N-434: this migration replaces export_my_data after the household-add alert's one, and keeps its keys.
select public.set_push_household_add(true, 'de');
select is(public.export_my_data() #>> '{push_preferences,household_add}', 'true', 'the export keeps push_preferences');
select ok(public.export_my_data() ? 'push_devices', 'the export keeps push_devices');
select is(public.export_my_data() #>> '{shopping_day_reminder,time_zone}', 'Europe/Berlin', 'and the reminder is still in it');
select pg_temp.as_postgres();
delete from auth.users where id = :anna;
select is((select count(*)::int from public.shopping_day_reminders where user_id = :anna), 0, 'the reminder goes with the account');

select * from finish();
rollback;
