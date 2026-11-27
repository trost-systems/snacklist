-- Job 472 (SR1): shopping reminders, one row each (20261127000000_shopping_reminders.sql,
-- docs/PUSH.md). The evidence for Legal's SR1 review, section 6: C1 one store (the old table is a
-- view, the export, deletion), C2 nothing without an explicit add (refresh, the household-add
-- alert, the migration's mapping sends nothing), C3 isolation and sending (other members read
-- nothing, the cap, duplicates, per-reminder marking, the times around midnight, saved late) and
-- C4 the frozen texts. Fictional people, no real ids. 2026-12-03 is a Thursday; Berlin is UTC+1.
begin;
select plan(107);

\set dora '''00000000-0000-4000-8000-000000472a01'''
\set fritz '''00000000-0000-4000-8000-000000472b01'''
\set gina '''00000000-0000-4000-8000-000000472c01'''
\set hanno '''00000000-0000-4000-8000-000000472d01'''

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
create function pg_temp.mine() returns int language sql as $$
  select count(*)::int from public.shopping_reminders
$$;
-- The title and body of every post to this file's people, sorted (a run sends in no set order).
create function pg_temp.posts() returns text language sql as $$
  select coalesce(string_agg(x.b #>> '{recipients,0,title}' || ' / ' || (x.b #>> '{recipients,0,body}'), ' | '
                             order by x.b #>> '{recipients,0,title}'), '')
  from net.http_request_queue q, lateral (select convert_from(q.body, 'utf8')::jsonb as b) x
  where x.b #>> '{recipients,0,user_id}' like '00000000-0000-4000-8000-000000472%'
$$;
create function pg_temp.sent_on(p_weekday int, p_offset int, p_time time) returns date language sql as $$
  select last_sent_on from public.shopping_reminders
  where user_id = '00000000-0000-4000-8000-000000472a01'
    and shopping_weekday = p_weekday and offset_days = p_offset and local_time = p_time
$$;

insert into auth.users (id, email) values
  (:dora, 'dora472@fg.test'), (:fritz, 'fritz472@fg.test'), (:gina, 'gina472@fg.test'), (:hanno, 'hanno472@fg.test');

select pg_temp.login(:dora);
create temp table home as select id from public.create_household(gen_random_uuid(), 'Zuhause');
select pg_temp.as_postgres();
insert into public.household_members (household_id, user_id, role) select id, :fritz, 'member' from home;
insert into public.items (household_id, name) select id, 'Milch' from home;
insert into public.items (household_id, name) select id, 'Brot' from home;
insert into public.items (household_id, name) select id, 'Eier' from home;
insert into public.push_tokens (user_id, token, platform) values (:dora, 'test-token-reminders-d', 'ios');

-- C2: nothing without an explicit add ----------------------------------------------------------
select is((select count(*)::int from public.shopping_reminders where user_id in (:dora, :fritz, :gina, :hanno)), 0,
  'no reminder exists before anyone adds one');
select pg_temp.login(:dora);
select lives_ok($$ select public.refresh_shopping_day_reminder('Europe/Berlin', 'de') $$, 'opening the screen refreshes zone and language');
select is(pg_temp.mine(), 0, 'and a refresh without reminders creates none');
select lives_ok($$ select public.set_push_household_add(true, 'de') $$, 'Dora turns the household-add alert on');
select is(pg_temp.mine(), 0, 'the household-add alert alone creates no reminder');
select pg_temp.as_postgres();
create temp table queued as select count(*)::int as n from net.http_request_queue;
insert into public.shopping_day_reminders (user_id, weekdays, time_zone, locale, last_sent_on)
values (:hanno, array[5, 2, 5]::smallint[], 'Europe/Berlin', 'en', '2026-11-20');
select is(
  (select string_agg(shopping_weekday || '/' || offset_days || '/' || local_time || '/' || time_zone || '/' || locale || '/' || last_sent_on, ',' order by shopping_weekday)
   from public.shopping_reminders where user_id = :hanno),
  '2/-1/19:00:00/Europe/Berlin/en/2026-11-20,5/-1/19:00:00/Europe/Berlin/en/2026-11-20',
  'an old-style row (the migration''s path) becomes one day-before 19:00 reminder per weekday, last_sent_on copied');
select is((select count(*)::int from net.http_request_queue), (select n from queued), 'and nothing is sent for it');
select is((select weekdays from public.shopping_day_reminders where user_id = :hanno), array[2, 5]::smallint[],
  'the view shows the weekdays again, sorted, each once');

-- C1: one store --------------------------------------------------------------------------------
select is((select relkind::text from pg_class where oid = 'public.shopping_day_reminders'::regclass), 'v',
  'shopping_day_reminders is a view, not a table');
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and exists (select from pg_attribute a where a.attrelid = c.oid and a.attname in ('last_sent_on', 'weekdays', 'shopping_weekday'))),
  array['shopping_reminders'],
  'only shopping_reminders holds reminder data');

-- Adding, the RPC's checks ---------------------------------------------------------------------
select pg_temp.login(:dora);
select throws_ok($$ select public.add_shopping_reminder(0, true, 1140, 'Europe/Berlin', 'de') $$, '22023', 'invalid_weekday', 'no weekday 0');
select throws_ok($$ select public.add_shopping_reminder(8, true, 1140, 'Europe/Berlin', 'de') $$, '22023', 'invalid_weekday', 'no weekday 8');
select throws_ok($$ select public.add_shopping_reminder(6, true, 1440, 'Europe/Berlin', 'de') $$, '22023', 'invalid_time', 'no minute 1440');
select throws_ok($$ select public.add_shopping_reminder(6, true, -1, 'Europe/Berlin', 'de') $$, '22023', 'invalid_time', 'no minute before midnight');
select throws_ok($$ select public.add_shopping_reminder(6, null, 1140, 'Europe/Berlin', 'de') $$, '22023', 'invalid_offset', 'the day before or on the day, not unknown');
select throws_ok($$ select public.add_shopping_reminder(6, true, 1140, 'Mars/Olympus', 'de') $$, '22023', 'invalid_time_zone', 'only IANA zones');
select throws_ok($$ select public.add_shopping_reminder(6, true, 1140, 'Europe/Berlin', 'fr') $$, '22023', 'invalid_locale', 'only de and en');
select pg_temp.as_postgres();
select throws_ok($$ select public.add_shopping_reminder(6, true, 1140, 'Europe/Berlin', 'de') $$, '28000', 'not_authenticated', 'signed out is refused');
set local role anon;
select throws_ok($$ select public.add_shopping_reminder(6, true, 1140, 'Europe/Berlin', 'de') $$, '42501', null, 'anon may not call it');
select pg_temp.as_postgres();
select throws_ok($$ insert into public.shopping_reminders (user_id, shopping_weekday, offset_days, local_time, time_zone, locale)
  values ('00000000-0000-4000-8000-000000472a01', 6, -1, '19:00:30', 'Europe/Berlin', 'de') $$, '23514', null, 'whole minutes only');

select pg_temp.login(:dora);
-- Saturday the day before at 00:30 (Friday 00:30), Thursday on the day at 23:50, Friday the day
-- before at 19:00 and Thursday on the day at 19:00 (both Thursday 19:00).
create temp table r1 as select * from public.add_shopping_reminder(6, true, 30, 'Europe/Berlin', 'de');
create temp table r2 as select * from public.add_shopping_reminder(4, false, 1430, 'Europe/Berlin', 'de');
select public.add_shopping_reminder(5, true, 1140, 'Europe/Berlin', 'de');
select public.add_shopping_reminder(4, false, 1140, 'Europe/Berlin', 'de');
select is((select shopping_weekday || '/' || offset_days || '/' || local_time || '/' || time_zone || '/' || locale from r1),
  '6/-1/00:30:00/Europe/Berlin/de', 'the add returns the row: Saturday, the day before, 00:30');
select is(pg_temp.mine(), 4, 'Dora reads her four reminders');
select pg_temp.as_postgres();
-- The adds ran at the real now(), and an occurrence already past then counts as sent; the runs
-- below are in December, so start from nothing sent.
update public.shopping_reminders set last_sent_on = null where user_id = :dora;
select pg_temp.login(:dora);
select is((select weekdays from public.shopping_day_reminders), array[4, 5, 6]::smallint[], 'and the view her three shopping days');
select throws_ok($$ select public.add_shopping_reminder(6, true, 30, 'Europe/Berlin', 'en') $$, '23505', 'reminder_exists',
  'the same day, offset and time twice is refused');
select throws_ok($$ select public.update_shopping_reminder((select id from r2), 6, true, 30, 'Europe/Berlin', 'de') $$, '23505', 'reminder_exists',
  'an update onto another reminder is refused');
select throws_ok($$ select public.update_shopping_reminder(gen_random_uuid(), 6, true, 60, 'Europe/Berlin', 'de') $$, 'P0002', 'reminder_not_found',
  'an unknown id is not found');
select pg_temp.as_postgres();
select throws_ok($$ insert into public.shopping_reminders (user_id, shopping_weekday, offset_days, local_time, time_zone, locale)
  values ('00000000-0000-4000-8000-000000472a01', 6, -1, '00:30', 'Europe/Berlin', 'de') $$, '23505', null,
  'the table refuses a duplicate too');

-- C3: only the owner ----------------------------------------------------------------------------
select pg_temp.login(:fritz);
select is(pg_temp.mine(), 0, 'Fritz, in the same household, reads none of her reminders');
select is((select count(*)::int from public.shopping_day_reminders), 0, 'nor her row in the view');
select throws_ok($$ select public.update_shopping_reminder((select id from r1), 1, true, 60, 'Europe/Berlin', 'de') $$, 'P0002', 'reminder_not_found',
  'he cannot change hers');
select lives_ok($$ select public.delete_shopping_reminder((select id from r1)) $$, 'deleting hers is a no-op for him');
select throws_ok($$ insert into public.shopping_reminders (user_id, shopping_weekday, offset_days, local_time, time_zone, locale)
  values ('00000000-0000-4000-8000-000000472b01', 1, -1, '19:00', 'Europe/Berlin', 'de') $$, '42501', null, 'no direct insert');
select throws_ok($$ update public.shopping_reminders set local_time = '20:00' $$, '42501', null, 'no direct update');
select throws_ok($$ delete from public.shopping_reminders $$, '42501', null, 'no direct delete');
select pg_temp.login(:gina);
select is(pg_temp.mine(), 0, 'Gina, outside the household, reads none');
select is((select count(*)::int from public.shopping_day_reminders), 0, 'nor any row in the view');
select pg_temp.login(:dora);
select is(pg_temp.mine(), 4, 'Dora still has all four');
select pg_temp.as_postgres();
select is((select count(*)::int from pg_publication_tables where schemaname = 'public'
           and tablename in ('shopping_reminders', 'shopping_day_reminders')), 0, 'in no publication, realtime included');
select is((select array_agg(policyname::text order by policyname) from pg_policies where schemaname = 'public' and tablename = 'shopping_reminders'),
  array['shopping_reminders_read_own'], 'one policy, the owner''s read; none for the household');

-- C3: sending, one reminder at a time -----------------------------------------------------------
select vault.create_secret('test-secret-472', 'push_send_secret');
select is(public.shopping_day_set(true, 'https://push.example.test/functions/v1/push'), 'on', 'the server switch on, for the runs');
delete from net.http_request_queue;
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 17:59:59+00'), 0, 'nothing a second before Thursday 19:00 local');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 18:00:00+00'), 2, 'two reminders at 19:00 the same run: both sent');
select is(pg_temp.posts(),
  'Heute ist Einkaufstag / 3 Artikel stehen auf der Liste. Schau kurz rein. | Morgen ist Einkaufstag / 3 Artikel stehen auf der Liste. Schau kurz rein.',
  'the day before says tomorrow, on the day says today');
select is((select array_agg(distinct (convert_from(body, 'utf8')::jsonb ->> 'ttl_seconds')) from net.http_request_queue),
  array['14400'], 'each post expires after four hours (ttl_seconds 14400)');
select is(pg_temp.sent_on(5, -1, '19:00'), date '2026-12-03', 'the day-before one is marked for its fire date, Thursday');
select is(pg_temp.sent_on(4, 0, '19:00'), date '2026-12-03', 'and the on-the-day one');
select is(pg_temp.sent_on(4, 0, '23:50'), null::date, 'the 23:50 one is not marked');
select is(pg_temp.sent_on(6, -1, '00:30'), null::date, 'nor the Friday 00:30 one');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 18:20:00+00'), 0, 'a second run in the window sends nothing');

delete from net.http_request_queue;
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 22:49:59+00'), 0, 'not before 23:50 local');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 23:10:00+00'), 1,
  'at 00:10 Friday the run that missed 23:50 Thursday still sends it');
select is(pg_temp.posts(), 'Heute ist Einkaufstag / 3 Artikel stehen auf der Liste. Schau kurz rein.', 'once, as the on-the-day text');
select is(pg_temp.sent_on(4, 0, '23:50'), date '2026-12-03', 'marked for Thursday, the date it was for');
select is(pg_temp.sent_on(6, -1, '00:30'), null::date, 'only that reminder is marked, not the person''s other one');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 23:15:00+00'), 0, 'after midnight it is not sent again');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 23:20:00+00'), 0, 'and is not due past its 30 minutes');

delete from net.http_request_queue;
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 23:29:59+00'), 0, 'not before Friday 00:30 local');
select is(public.shopping_day_run('https://push.example.test/functions/v1/push', '2026-12-03 23:30:00+00'), 1,
  'the day-before reminder for Saturday at 00:30 goes out Friday 00:30 local');
select is(pg_temp.posts(), 'Morgen ist Einkaufstag / 3 Artikel stehen auf der Liste. Schau kurz rein.', 'saying shopping is tomorrow');
select is(pg_temp.sent_on(6, -1, '00:30'), date '2026-12-04', 'marked for Friday, its fire date');
select is((select count(*)::int from public.shopping_day_due('2026-12-04 00:00:00+00') d where d.user_id = :dora), 0,
  'due for 30 minutes only');
select is(public.shopping_day_set(false), 'off', 'the switch off again');

-- C3: saved late, never back --------------------------------------------------------------------
-- A zone where it is between 02:00 and 21:00 now, so an hour back and two ahead are today. Gina
-- has a household and a device, so only the mark keeps her reminder from being due.
select pg_temp.login(:gina);
select public.create_household(gen_random_uuid(), 'Gina');
select pg_temp.as_postgres();
insert into public.push_tokens (user_id, token, platform) values (:gina, 'test-token-reminders-g', 'android');
create temp table zone as
select name, (now() at time zone name)::date as today, extract(isodow from (now() at time zone name)::date)::int as dow,
       (extract(hour from now() at time zone name) * 60 + extract(minute from now() at time zone name))::int as minute
from pg_catalog.pg_timezone_names where name like 'Etc/GMT%'
  and (now() at time zone name)::time between time '02:00' and time '21:00' order by name limit 1;
grant select on zone to authenticated;
select pg_temp.login(:gina);
create temp table g1 as select r.* from zone z, public.add_shopping_reminder(z.dow, false, z.minute, z.name, 'en') r;
select is((select last_sent_on from g1), (select today from zone), 'added at its own minute today: today counts as sent');
select pg_temp.as_postgres();
select is((select count(*)::int from public.shopping_day_due(now()) d where d.user_id = :gina), 0, 'so a run now does not send it');
update public.shopping_reminders set last_sent_on = null where id = (select id from g1);
select is((select count(*)::int from public.shopping_day_due(now()) d where d.user_id = :gina), 1, 'which it would without the mark');
update public.shopping_reminders set last_sent_on = (select today from zone) where id = (select id from g1);
select pg_temp.login(:gina);
create temp table g2 as
select r.* from zone z, public.add_shopping_reminder(case when z.dow = 7 then 1 else z.dow + 1 end, true, z.minute - 60, z.name, 'en') r;
select is((select last_sent_on from g2), (select today from zone), 'the same for a day-before reminder whose time today has passed');
create temp table g3 as select r.* from zone z, public.add_shopping_reminder(z.dow, false, z.minute + 60, z.name, 'en') r;
select is((select last_sent_on from g3), null::date, 'added before its time today: it still goes out today');
select pg_temp.as_postgres();
update public.shopping_reminders set last_sent_on = (select today + 1 from zone) where id = (select id from g3);
select pg_temp.login(:gina);
select is((select r.last_sent_on from zone z, public.update_shopping_reminder((select id from g3), z.dow, false, z.minute + 120, z.name, 'de') r),
  (select today + 1 from zone), 'an update never moves last_sent_on back');
select is((select r.last_sent_on from zone z, public.update_shopping_reminder((select id from g1), z.dow, false, z.minute + 90, z.name, 'en') r),
  (select today from zone), 'moving a sent reminder later today does not send it again');
select is((select r.last_sent_on from zone z, public.update_shopping_reminder((select id from g1), case when z.dow = 7 then 1 else z.dow + 1 end, true, z.minute + 100, z.name, 'en') r),
  null::date, 'a new shopping day drops the old date: moved onto later today, it still comes today');
select is((select r.last_sent_on from zone z, public.update_shopping_reminder((select id from g3), case when z.dow >= 6 then z.dow - 5 else z.dow + 2 end, false, z.minute + 120, z.name, 'de') r),
  null::date, 'so does a new offset or day that does not fire today, however late its old date');

-- set_shopping_day_reminder replaces, refresh touches zone and language only --------------------
select pg_temp.login(:dora);
select lives_ok($$ select public.refresh_shopping_day_reminder('America/New_York', 'en') $$, 'a refresh');
select is((select string_agg(distinct time_zone || '/' || locale, ',') from public.shopping_reminders), 'America/New_York/en',
  'moves zone and language on every reminder');
select is((select string_agg(shopping_weekday || '/' || offset_days || '/' || local_time || '/' || coalesce(last_sent_on::text, '-'), ',' order by shopping_weekday, offset_days, local_time) from public.shopping_reminders),
  '4/0/19:00:00/2026-12-03,4/0/23:50:00/2026-12-03,5/-1/19:00:00/2026-12-03,6/-1/00:30:00/2026-12-04',
  'and nothing else');
create temp table kept as select id from public.shopping_reminders where shopping_weekday = 5 and offset_days = -1;
select lives_ok($$ select public.set_shopping_day_reminder(array[5, 1], 'Europe/Berlin', 'de') $$, 'the old screen saves Monday and Friday');
select is((select string_agg(shopping_weekday || '/' || offset_days || '/' || local_time || '/' || time_zone || '/' || locale, ',' order by shopping_weekday) from public.shopping_reminders),
  '1/-1/19:00:00/Europe/Berlin/de,5/-1/19:00:00/Europe/Berlin/de', 'its reminders are now exactly one day-before 19:00 per weekday, custom ones gone');
select is((select id from public.shopping_reminders where shopping_weekday = 5), (select id from kept), 'the one that stays keeps its id');
select is((select last_sent_on from public.shopping_reminders where shopping_weekday = 5), date '2026-12-03', 'and its last_sent_on');
select throws_ok($$ select public.set_shopping_day_reminder(array[8], 'Europe/Berlin', 'de') $$, '22023', 'invalid_weekdays', 'the old save keeps its checks');

-- C3: the cap of 14 -----------------------------------------------------------------------------
select pg_temp.login(:fritz);
select public.add_shopping_reminder(1 + g % 7, g < 7, 600 + g, 'Europe/Berlin', 'de') from generate_series(0, 13) g;
select is(pg_temp.mine(), 14, 'Fritz adds 14');
select throws_ok($$ select public.add_shopping_reminder(3, true, 1000, 'Europe/Berlin', 'de') $$, '54000', 'reminder_limit', 'a 15th is refused');
select pg_temp.as_postgres();
select throws_ok($$ insert into public.shopping_reminders (user_id, shopping_weekday, offset_days, local_time, time_zone, locale)
  values ('00000000-0000-4000-8000-000000472b01', 3, -1, '17:00', 'Europe/Berlin', 'de') $$, '54000', 'reminder_limit',
  'and by the table for a direct insert');
select throws_ok($$ insert into public.shopping_day_reminders (user_id, weekdays, time_zone, locale)
  values ('00000000-0000-4000-8000-000000472b01', array[3]::smallint[], 'Europe/Berlin', 'de') $$, '54000', 'reminder_limit',
  'and through the view');

-- C1: export and deletion -----------------------------------------------------------------------
select pg_temp.login(:dora);
create temp table doc as select public.export_my_data() as d;
select ok(not ((select d from doc) ? 'shopping_day_reminder'), 'the export has no shopping_day_reminder key any more');
select is((select jsonb_typeof(d -> 'shopping_reminders') from doc), 'array', 'shopping_reminders is an array');
select is((select array_agg(k order by k collate "C") from doc, jsonb_object_keys(d #> '{shopping_reminders,0}') k),
  array['created_at', 'id', 'last_sent_on', 'local_time', 'locale', 'offset_days', 'shopping_weekday', 'time_zone', 'updated_at', 'user_id'],
  'each reminder with every column');
select is((select e from doc, jsonb_array_elements(d -> 'shopping_reminders') e where e ->> 'shopping_weekday' = '5'),
  (select jsonb_build_object('id', id, 'user_id', user_id, 'shopping_weekday', 5, 'offset_days', -1, 'local_time', '19:00:00',
     'time_zone', 'Europe/Berlin', 'locale', 'de', 'last_sent_on', '2026-12-03', 'created_at', created_at, 'updated_at', updated_at)
   from public.shopping_reminders where shopping_weekday = 5),
  'with its values');
select is((select jsonb_array_length(d -> 'shopping_reminders') from doc), 2, 'one object per reminder');
select pg_temp.login(:hanno);
select lives_ok($$ select public.set_shopping_day_reminder(array[]::integer[], 'Europe/Berlin', 'en') $$, 'Hanno clears every day on the old screen');
select is(pg_temp.mine(), 0, 'which deletes all his reminders');
select is(public.export_my_data() -> 'shopping_reminders', '[]'::jsonb, 'without reminders: an empty array');
select pg_temp.login(:dora);
select public.delete_shopping_reminder(id) from public.shopping_reminders;
select is(pg_temp.mine(), 0, 'deleting the last reminder leaves none');
select is((select count(*)::int from public.shopping_day_reminders), 0, 'and no row in the view');
select lives_ok($$ select public.delete_shopping_reminder((select id from kept)) $$, 'deleting again is a no-op');
select pg_temp.as_postgres();
delete from auth.users where id in (:fritz, :gina);
select is((select count(*)::int from public.shopping_reminders where user_id in (:fritz, :gina)), 0, 'reminders go with the account');

-- C4: the frozen texts ----------------------------------------------------------------------------
select is(public.shopping_day_text('de', 0, -1), '{"title": "Morgen ist Einkaufstag", "body": "Schau kurz auf die Liste."}'::jsonb, 'de, day before, none open');
select is(public.shopping_day_text('de', 1, -1), '{"title": "Morgen ist Einkaufstag", "body": "1 Artikel steht auf der Liste. Schau kurz rein."}'::jsonb, 'de, day before, one');
select is(public.shopping_day_text('de', 5, -1), '{"title": "Morgen ist Einkaufstag", "body": "5 Artikel stehen auf der Liste. Schau kurz rein."}'::jsonb, 'de, day before, five');
select is(public.shopping_day_text('de', 0, 0), '{"title": "Heute ist Einkaufstag", "body": "Schau kurz auf die Liste."}'::jsonb, 'de, on the day, none open');
select is(public.shopping_day_text('de', 1, 0), '{"title": "Heute ist Einkaufstag", "body": "1 Artikel steht auf der Liste. Schau kurz rein."}'::jsonb, 'de, on the day, one');
select is(public.shopping_day_text('de', 5, 0), '{"title": "Heute ist Einkaufstag", "body": "5 Artikel stehen auf der Liste. Schau kurz rein."}'::jsonb, 'de, on the day, five');
select is(public.shopping_day_text('en', 0, -1), '{"title": "Shopping day tomorrow", "body": "Have a quick look at the list."}'::jsonb, 'en, day before, none open');
select is(public.shopping_day_text('en', 1, -1), '{"title": "Shopping day tomorrow", "body": "1 item on the list. Have a quick look."}'::jsonb, 'en, day before, one');
select is(public.shopping_day_text('en', 5, -1), '{"title": "Shopping day tomorrow", "body": "5 items on the list. Have a quick look."}'::jsonb, 'en, day before, five');
select is(public.shopping_day_text('en', 0, 0), '{"title": "Shopping day today", "body": "Have a quick look at the list."}'::jsonb, 'en, on the day, none open');
select is(public.shopping_day_text('en', 1, 0), '{"title": "Shopping day today", "body": "1 item on the list. Have a quick look."}'::jsonb, 'en, on the day, one');
select is(public.shopping_day_text('en', 5, 0), '{"title": "Shopping day today", "body": "5 items on the list. Have a quick look."}'::jsonb, 'en, on the day, five');

select * from finish();
rollback;
