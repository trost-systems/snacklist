-- Job 21: public.feedback (docs/FEEDBACK.md). Insert-only for the sender, checks, the household
-- and is_internal set by the database, idempotent ids, the 12-month purge and its cron job.
begin;
select plan(52);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- One note as the app sends it: context fields filled, no household, no created_at.
create function pg_temp.send(p_id uuid, p_message text, p_extra jsonb default '{}') returns void
language plpgsql as $$
declare
  v jsonb := jsonb_build_object('app_version', '0.1.0', 'build', '42', 'platform', 'android',
    'os_version', 'Android 14 (SDK 34)', 'locale', 'de', 'screen', 'list') || p_extra;
begin
  insert into public.feedback (id, message, category, contact_ok, app_version, build, platform,
    os_version, locale, screen, is_internal)
  values (p_id, p_message, v ->> 'category', coalesce((v ->> 'contact_ok')::boolean, false),
    v ->> 'app_version', v ->> 'build', v ->> 'platform', v ->> 'os_version', v ->> 'locale',
    v ->> 'screen', coalesce((v ->> 'is_internal')::boolean, false));
end $$;
grant execute on function pg_temp.send(uuid, text, jsonb) to authenticated, anon;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'anna@gmail.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'ben@web.de'),
  ('00000000-0000-0000-0000-0000000000c1', 'peter@fg.test'),
  ('00000000-0000-0000-0000-0000000000d1', 'tester.run1@fg-test.invalid'),
  ('00000000-0000-0000-0000-0000000000e1', 'e2e@example.com'),
  ('00000000-0000-0000-0000-0000000000f1', 'nohome@gmx.at');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Anna');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb as select id from public.create_household('Ben');
grant select on ha, hb to authenticated, anon;

-- AC2 and AC5: the sender inserts their own note.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select lives_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000001', '  Der Haken reagiert spät.  ') $$,
  'a signed-in user inserts their own note');
select throws_ok($$ select * from public.feedback $$, '42501', null, 'the sender cannot read it back');
select throws_ok($$ update public.feedback set message = 'x' $$, '42501', null, 'nor change it');
select throws_ok($$ delete from public.feedback $$, '42501', null, 'nor delete it');
select throws_ok(
  $$ insert into public.feedback (id, user_id, message, app_version, build, platform, os_version, locale, screen)
     values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', 'Im Namen von Ben', '0.1.0', '1', 'web',
       'Chrome on macOS', 'de', 'list') $$,
  '42501', null, 'a note in another user''s name is refused');
-- Job 169b: the app names the household it shows; one the sender is not in becomes their default.
select lives_ok(
  $$ insert into public.feedback (id, household_id, message, app_version, build, platform, os_version, locale, screen)
     values ('10000000-0000-4000-8000-0000000001b9', (select id from hb), 'Fremder Haushalt', '0.1.0', '1', 'web',
       'Chrome on macOS', 'de', 'list') $$,
  'the client may name a household');
select pg_temp.as_postgres();
select is((select household_id from public.feedback where id = '10000000-0000-4000-8000-0000000001b9'),
  (select id from ha), 'a household the sender is not in is replaced by their default');
delete from public.feedback where id = '10000000-0000-4000-8000-0000000001b9';
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ insert into public.feedback (id, created_at, message, app_version, build, platform, os_version, locale, screen)
     values (gen_random_uuid(), now() - interval '2 years', 'Alt', '0.1.0', '1', 'web', 'Chrome on macOS', 'de',
       'list') $$,
  '42501', null, 'nor the time');

-- Idempotency: the same id again (double tap, retry after a lost answer) stays one row.
select lives_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000001', 'Der Haken reagiert spät.') $$,
  'repeating the sender''s own id succeeds');
select lives_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000001', 'Der Haken reagiert spät.') $$,
  'also a third time');

-- AC5: anon gets nothing.
select pg_temp.anon();
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'Anonym') $$, '42501', null, 'anon cannot insert');
select throws_ok($$ select * from public.feedback $$, '42501', null, 'anon cannot read');

-- Ben may not reuse Anna's id: it fails as a duplicate, Anna's note stays as it was.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000001', 'Bens Text') $$,
  '23505', null, 'someone else''s id is refused');
select lives_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000002', 'Idee: Rezepte',
  '{"category": "idea", "contact_ok": true, "platform": "ios", "os_version": "iOS 18.1", "locale": "en",
    "screen": "account"}') $$,
  'a note with category and contact');

select pg_temp.as_postgres();
select is((select count(*)::int from public.feedback where id = '10000000-0000-4000-8000-000000000001'), 1,
  'three sends of one id are one row');
select results_eq(
  $$ select user_id, household_id, message, category, contact_ok, app_version, build, platform, os_version,
            locale, screen, is_internal
     from public.feedback where id = '10000000-0000-4000-8000-000000000001' $$,
  $$ values ('00000000-0000-0000-0000-0000000000a1'::uuid, (select id from ha), 'Der Haken reagiert spät.',
             null::text, false, '0.1.0', '42', 'android', 'Android 14 (SDK 34)', 'de', 'list', false) $$,
  'the row: the sender, their household, trimmed text, no category, no contact, the context, external');
select results_eq(
  $$ select household_id, category, contact_ok, screen from public.feedback
     where id = '10000000-0000-4000-8000-000000000002' $$,
  $$ values ((select id from hb), 'idea'::text, true, 'account'::text) $$,
  'Ben''s note: his household, the category and the contact flag');

-- AC4: empty, blank and too long notes are refused by the database.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), '') $$, '23514', null, 'an empty note is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), '     ') $$, '23514', null, 'only spaces are refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), E' \n\t\r ') $$, '23514', null,
  'only line breaks and tabs are refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), E' 　﻿') $$, '23514', null,
  'only Unicode blanks are refused (as Dart''s trim sees them)');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), repeat('a', 2001)) $$, '23514', null,
  '2001 characters are refused');
select lives_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000003', '  ' || repeat('a', 2000) || E'\n') $$,
  '2000 characters with blanks around them are fine');
select lives_ok($$ select pg_temp.send('10000000-0000-4000-8000-000000000004', repeat('🛒', 2000)) $$,
  '2000 emoji are 2000 characters');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), repeat('🛒', 2001)) $$, '23514', null,
  '2001 emoji are refused');
select pg_temp.as_postgres();
select is((select char_length(message) from public.feedback where id = '10000000-0000-4000-8000-000000000003'),
  2000, 'stored trimmed');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');

-- The context fields are checked too.
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"category": "feature"}') $$, '23514', null,
  'an unknown category is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"platform": "symbian"}') $$, '23514', null,
  'an unknown platform is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"screen": "/join/ABCD2345"}') $$, '23514', null,
  'a path as the screen is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"screen": "join_ABCD2345"}') $$, '23514', null,
  'an invite code in the screen is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"screen": "Milch"}') $$, '23514', null,
  'an item name as the screen is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"screen": ""}') $$, '23514', null,
  'an empty screen is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"screen": "a2345678901234567890123456789012345678901"}') $$,
  '23514', null, 'a screen with digits is refused');
select throws_ok(format($$ select pg_temp.send(gen_random_uuid(), 'x', '{"os_version": "%s"}') $$, repeat('x', 65)),
  '23514', null, 'an os_version over 64 characters is refused');
select throws_ok(format($$ select pg_temp.send(gen_random_uuid(), 'x', '{"app_version": "%s"}') $$, repeat('1', 33)),
  '23514', null, 'an app_version over 32 characters is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"build": "12345678901234567"}') $$, '23514', null,
  'a build over 16 characters is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"locale": "Deutsch (Österreich)"}') $$, '23514', null,
  'a free-text locale is refused');
select throws_ok($$ select pg_temp.send(gen_random_uuid(), 'x', '{"app_version": ""}') $$, '23514', null,
  'an empty context field is refused');

-- AC11: test accounts are internal whatever the client says; a client may say internal.
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select pg_temp.send('20000000-0000-4000-8000-0000000000c1', 'fg.test');
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select pg_temp.send('20000000-0000-4000-8000-0000000000d1', 'fg-test.invalid');
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
select pg_temp.send('20000000-0000-4000-8000-0000000000e1', 'example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select pg_temp.send('20000000-0000-4000-8000-0000000000f1', 'gmx.at, debug build', '{"is_internal": true}');
select pg_temp.send('20000000-0000-4000-8000-0000000000f2', 'gmx.at, release build');
select pg_temp.as_postgres();
select results_eq(
  $$ select message, is_internal from public.feedback where id::text like '20000000%' order by id $$,
  $$ values ('fg.test', true), ('fg-test.invalid', true), ('example.com', true),
            ('gmx.at, debug build', true), ('gmx.at, release build', false) $$,
  'test domains are forced internal; others keep what the app said');
select is((select count(*)::int from public.feedback where user_id = '00000000-0000-0000-0000-0000000000f1'
  and household_id is null), 2, 'a user without a household sends with household_id null');

-- Retention: older than 12 months goes, daily.
select ok(not has_function_privilege('authenticated', 'public.purge_old_feedback()', 'execute'),
  'clients cannot run the purge');
select ok(not has_function_privilege('anon', 'public.purge_old_feedback()', 'execute'), 'nor can anon');
update public.feedback set created_at = now() - interval '12 months' - interval '1 day'
  where id = '20000000-0000-4000-8000-0000000000f1';
update public.feedback set created_at = now() - interval '11 months'
  where id = '20000000-0000-4000-8000-0000000000f2';
select is(public.purge_old_feedback(), 1, 'the purge reports one deleted row');
select is((select count(*)::int from public.feedback where id = '20000000-0000-4000-8000-0000000000f1'), 0,
  'a note 12 months and a day old is gone');
select is((select count(*)::int from public.feedback where id = '20000000-0000-4000-8000-0000000000f2'), 1,
  'an 11-month-old note stays');
select is(public.purge_old_feedback(), 0, 'a second run deletes nothing');
select results_eq(
  $$ select schedule, command, active from cron.job where jobname = 'purge-old-feedback' $$,
  $$ values ('17 3 * * *'::text, 'select public.purge_old_feedback()'::text, true) $$,
  'the purge is scheduled daily');
-- The migration's statement, run again (a second apply).
select cron.schedule('purge-old-feedback', '17 3 * * *', 'select public.purge_old_feedback()');
select is((select count(*)::int from cron.job where jobname = 'purge-old-feedback'), 1,
  'applying the schedule twice leaves one job');

-- AC12 basics (the deletion paths are in account_deletion.test.sql).
delete from auth.users where id = '00000000-0000-0000-0000-0000000000f1';
select is((select count(*)::int from public.feedback where user_id = '00000000-0000-0000-0000-0000000000f1'), 0,
  'deleting a user deletes their notes');
delete from public.households where id = (select id from hb);
select results_eq(
  $$ select user_id, household_id from public.feedback where id = '10000000-0000-4000-8000-000000000002' $$,
  $$ values ('00000000-0000-0000-0000-0000000000b1'::uuid, null::uuid) $$,
  'a deleted household leaves the note, without its id');

-- The PM's Monday summary reads the comments in the dashboard.
select is((select count(*)::int from pg_attribute a
           where a.attrelid = 'public.feedback'::regclass and a.attnum > 0 and not a.attisdropped
             and col_description(a.attrelid, a.attnum) is null), 0, 'every column has a comment');
select isnt(obj_description('public.feedback'::regclass, 'pg_class'), null, 'the table has a comment');

select * from finish();
rollback;
