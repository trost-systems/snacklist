-- Job 268 (FB4, docs/FEEDBACK.md "Replies and status"): the sender reads their own notes with
-- status and reply, Peter's edits are stamped by the trigger, feedback_mark_seen, the ideas list
-- and household +1 votes, the export and the deletions.
begin;
select plan(71);

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

create function pg_temp.send(p_id uuid, p_message text) returns void language sql as $$
  insert into public.feedback (id, message, category, app_version, build, platform, os_version, locale)
  values (p_id, p_message, 'bug', '1.4.0', '42', 'android', 'Android 14 (SDK 34)', 'de')
$$;
grant execute on function pg_temp.send(uuid, text) to authenticated;

-- Anna and Ben share a household; Carl has his own; Dora has none.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000268a1', 'anna268@gmail.com'),
  ('00000000-0000-0000-0000-0000000268b1', 'ben268@web.de'),
  ('00000000-0000-0000-0000-0000000268c1', 'carl268@gmx.de'),
  ('00000000-0000-0000-0000-0000000268d1', 'dora268@gmx.de');

select pg_temp.login('00000000-0000-0000-0000-0000000268a1');
create temp table ha as select id from public.create_household('Anna 268');
create temp table inv as select code from public.create_invite((select id from ha));
select pg_temp.login('00000000-0000-0000-0000-0000000268c1');
create temp table hc as select id from public.create_household('Carl 268');
grant select on ha, hc, inv to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000268b1');
select public.join_household((select code from inv));

select pg_temp.login('00000000-0000-0000-0000-0000000268a1');
select pg_temp.send('26800000-0000-4000-8000-0000000000a1', 'Der Haken reagiert spät.');
select pg_temp.send('26800000-0000-4000-8000-0000000000a2', 'Noch eine Notiz');

-- The sender reads their notes back, with what the app shows and nothing else.
select results_eq(
  $$ select id, message, category, status, fixed_in, reply, replied_at, answered_at, seen_at
     from public.feedback order by id $$,
  $$ values ('26800000-0000-4000-8000-0000000000a1'::uuid, 'Der Haken reagiert spät.', 'bug'::text, 'sent'::text,
             null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz),
            ('26800000-0000-4000-8000-0000000000a2', 'Noch eine Notiz', 'bug', 'sent', null, null, null, null, null) $$,
  'the sender reads their own notes, status sent and no reply');
select lives_ok($$ select created_at from public.feedback $$, 'and when they arrived');
select throws_ok($$ select is_internal from public.feedback $$, '42501', null, 'but not is_internal');
select throws_ok($$ select household_id from public.feedback $$, '42501', null, 'nor household_id');
select throws_ok($$ select platform, os_version from public.feedback $$, '42501', null, 'nor the device context');
select throws_ok($$ select user_id from public.feedback $$, '42501', null, 'nor user_id');
select throws_ok($$ select contact_ok from public.feedback $$, '42501', null, 'nor contact_ok');
select throws_ok($$ select screenshot from public.feedback $$, '42501', null, 'nor the screenshot name');

-- Clients write none of it, the sender included.
select throws_ok($$ update public.feedback set status = 'fixed' $$, '42501', null, 'the sender cannot set the status');
select throws_ok($$ update public.feedback set reply = 'Selbst' $$, '42501', null, 'nor a reply');
select throws_ok($$ update public.feedback set seen_at = now() $$, '42501', null, 'nor seen_at');
select throws_ok($$ delete from public.feedback $$, '42501', null, 'nor delete a note');
select throws_ok(
  $$ insert into public.feedback (id, message, app_version, build, platform, os_version, locale, status, reply)
     values (gen_random_uuid(), 'Mit Antwort', '1.4.0', '1', 'web', 'Chrome on macOS', 'de', 'fixed', 'Ja') $$,
  '42501', null, 'nor send a note with a status or reply');

-- The household partner and a stranger see none of Anna's notes.
select pg_temp.login('00000000-0000-0000-0000-0000000268b1');
select is((select count(*)::int from public.feedback), 0, 'the household partner reads none of Anna''s notes');
select pg_temp.login('00000000-0000-0000-0000-0000000268c1');
select is((select count(*)::int from public.feedback), 0, 'nor does a stranger');
select is((select count(*)::int from public.feedback where id = '26800000-0000-4000-8000-0000000000a1'), 0,
  'not even by id');
-- An app Anna connected over OAuth (MCP) acts on her list, not on her account.
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000268a1',
  'role', 'authenticated', 'client_id', 'c-268')::text, true);
select is((select count(*)::int from public.feedback), 0, 'an OAuth client''s token reads none of her notes');
select pg_temp.login('00000000-0000-0000-0000-0000000268a1');
select is((select count(*)::int from public.feedback), 2, 'her own session still does');

-- Peter answers in the Table Editor: the trigger stamps the times and trims the reply.
select pg_temp.as_postgres();
update public.feedback set status = 'read' where id = '26800000-0000-4000-8000-0000000000a1';
select results_eq(
  $$ select status, answered_at, replied_at from public.feedback where id = '26800000-0000-4000-8000-0000000000a1' $$,
  $$ values ('read'::text, now(), null::timestamptz) $$,
  'a status change stamps answered_at, not replied_at');
update public.feedback set answered_at = now() - interval '1 hour', status = 'read'
  where id = '26800000-0000-4000-8000-0000000000a1';
update public.feedback set reply = E'  Danke, ist notiert.\n' where id = '26800000-0000-4000-8000-0000000000a1';
select results_eq(
  $$ select reply, replied_at, answered_at from public.feedback where id = '26800000-0000-4000-8000-0000000000a1' $$,
  $$ values ('Danke, ist notiert.'::text, now(), now()) $$,
  'a reply is trimmed and stamps replied_at and answered_at');
update public.feedback set answered_at = now() - interval '1 hour', replied_at = now() - interval '1 hour'
  where id = '26800000-0000-4000-8000-0000000000a1';
update public.feedback set message = message where id = '26800000-0000-4000-8000-0000000000a1';
select results_eq(
  $$ select answered_at, replied_at from public.feedback where id = '26800000-0000-4000-8000-0000000000a1' $$,
  $$ values (now() - interval '1 hour', now() - interval '1 hour') $$,
  'an update that leaves status, fixed_in and reply alone moves no stamp');
update public.feedback set status = 'fixed', fixed_in = '1.4.1' where id = '26800000-0000-4000-8000-0000000000a1';
select results_eq(
  $$ select status, fixed_in, answered_at, replied_at from public.feedback
     where id = '26800000-0000-4000-8000-0000000000a1' $$,
  $$ values ('fixed'::text, '1.4.1'::text, now(), now() - interval '1 hour') $$,
  'fixed in a version stamps answered_at, the reply keeps its time');
update public.feedback set reply = null where id = '26800000-0000-4000-8000-0000000000a2';
select results_eq(
  $$ select reply, replied_at, answered_at from public.feedback where id = '26800000-0000-4000-8000-0000000000a2' $$,
  $$ values (null::text, null::timestamptz, null::timestamptz) $$,
  'setting a missing reply to null changes nothing');
update public.feedback set reply = 'Kurz' where id = '26800000-0000-4000-8000-0000000000a2';
update public.feedback set reply = null where id = '26800000-0000-4000-8000-0000000000a2';
select results_eq(
  $$ select reply, replied_at, answered_at from public.feedback where id = '26800000-0000-4000-8000-0000000000a2' $$,
  $$ values (null::text, null::timestamptz, now()) $$,
  'removing a reply clears replied_at and stamps answered_at');

-- The checks.
select throws_ok($$ update public.feedback set status = 'done' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  '23514', null, 'an unknown status is refused');
select throws_ok($$ update public.feedback set status = 'fixed', fixed_in = 'v1.4' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  '23514', null, 'a fixed_in that is not a version is refused');
select throws_ok($$ update public.feedback set status = 'fixed', fixed_in = '1.4.1-beta' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  '23514', null, 'nor with a suffix');
select throws_ok($$ update public.feedback set status = 'planned', fixed_in = '1.4.1' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  '23514', null, 'fixed_in only with status fixed');
select throws_ok($$ update public.feedback set status = 'planned' where id = '26800000-0000-4000-8000-0000000000a1' $$,
  '23514', null, 'leaving fixed keeps no fixed_in behind');
select throws_ok($$ update public.feedback set reply = E' \n ' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  '23514', null, 'a blank reply is refused');
select throws_ok(format($$ update public.feedback set reply = '%s' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  repeat('a', 4001)), '23514', null, 'a reply over 4000 characters is refused');
select lives_ok(format($$ update public.feedback set reply = '  %s  ' where id = '26800000-0000-4000-8000-0000000000a2' $$,
  repeat('a', 4000)), '4000 characters with blanks around them are fine');
update public.feedback set reply = null where id = '26800000-0000-4000-8000-0000000000a2';
update public.feedback set answered_at = null where id = '26800000-0000-4000-8000-0000000000a2';

-- Seen: only the sender's own answered note.
select pg_temp.login('00000000-0000-0000-0000-0000000268c1');
select lives_ok($$ select public.feedback_mark_seen('26800000-0000-4000-8000-0000000000a1') $$,
  'a stranger marking Anna''s note seen gets no error');
select lives_ok($$ select public.feedback_mark_seen(gen_random_uuid()) $$, 'nor does an unknown id');
select pg_temp.as_postgres();
select is((select seen_at from public.feedback where id = '26800000-0000-4000-8000-0000000000a1'), null,
  'and nothing changed');
update public.feedback set answered_at = now() - interval '1 hour' where id = '26800000-0000-4000-8000-0000000000a1';
select pg_temp.login('00000000-0000-0000-0000-0000000268a1');
select public.feedback_mark_seen('26800000-0000-4000-8000-0000000000a2');
select public.feedback_mark_seen('26800000-0000-4000-8000-0000000000a1');
select results_eq(
  $$ select id, seen_at, answered_at from public.feedback order by id $$,
  $$ values ('26800000-0000-4000-8000-0000000000a1'::uuid, now(), now() - interval '1 hour'),
            ('26800000-0000-4000-8000-0000000000a2', null, null) $$,
  'the sender marks an answered note seen, answered_at stays; an unanswered one stays unseen');
select pg_temp.as_postgres();
select ok(not has_function_privilege('anon', 'public.feedback_mark_seen(uuid)', 'execute'), 'anon cannot mark seen');
select ok(not has_function_privilege('authenticated', 'public.feedback_before_update()', 'execute'),
  'clients cannot run the trigger function');

-- Ideas: Peter lists three, one hidden.
insert into public.feedback_ideas (id, title_de, title_en, status, position, created_at) values
  ('26800000-0000-4000-8000-00000000f001', 'Rezepte', 'Recipes', 'planned', 2, now() - interval '3 days'),
  ('26800000-0000-4000-8000-00000000f002', 'Dunkles Design', 'Dark mode', 'considering', 1, now() - interval '2 days'),
  ('26800000-0000-4000-8000-00000000f003', 'Preise', 'Prices', 'considering', 2, now() - interval '1 day');
insert into public.feedback_ideas (id, title_de, title_en, listed) values
  ('26800000-0000-4000-8000-00000000f004', 'Versteckt', 'Hidden', false);
select throws_ok($$ insert into public.feedback_ideas (title_de, title_en) values ('  ', 'Blank') $$,
  '23514', null, 'a blank title is refused');
select throws_ok(format($$ insert into public.feedback_ideas (title_de, title_en) values ('Lang', '%s') $$, repeat('x', 121)),
  '23514', null, 'a title over 120 characters is refused');
select throws_ok($$ insert into public.feedback_ideas (title_de, title_en, status) values ('a', 'a', 'fixed') $$,
  '23514', null, 'an idea is considering or planned');
-- Votes from before the hidden idea was hidden stay counted for Peter.
insert into public.feedback_idea_votes (idea_id, household_id)
  select '26800000-0000-4000-8000-00000000f004', id from hc;

select pg_temp.login('00000000-0000-0000-0000-0000000268a1');
select results_eq(
  $$ select id, title_de, title_en, status, votes, voted from public.feedback_ideas((select id from ha))
     where id::text like '26800000-0000-4000-8000-00000000f%' $$,
  $$ values ('26800000-0000-4000-8000-00000000f002'::uuid, 'Dunkles Design'::text, 'Dark mode'::text, 'considering'::text, 0, false),
            ('26800000-0000-4000-8000-00000000f001', 'Rezepte', 'Recipes', 'planned', 0, false),
            ('26800000-0000-4000-8000-00000000f003', 'Preise', 'Prices', 'considering', 0, false) $$,
  'listed ideas by position, then age; the hidden one is not there');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f001', (select id from ha), true), 1,
  'a +1 returns the new total');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f001', (select id from ha), true), 1,
  'a second +1 from the same household changes nothing');
select pg_temp.login('00000000-0000-0000-0000-0000000268b1');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f001', (select id from ha), true), 1,
  'nor one from the partner: votes are per household');
select pg_temp.login('00000000-0000-0000-0000-0000000268c1');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f001', (select id from hc), true), 2,
  'another household''s +1 counts');
select results_eq(
  $$ select id, votes, voted from public.feedback_ideas((select id from hc))
     where id::text like '26800000-0000-4000-8000-00000000f%' $$,
  $$ values ('26800000-0000-4000-8000-00000000f002'::uuid, 0, false),
            ('26800000-0000-4000-8000-00000000f001', 2, true),
            ('26800000-0000-4000-8000-00000000f003', 0, false) $$,
  'the totals span households, voted is Carl''s household''s');
select pg_temp.login('00000000-0000-0000-0000-0000000268b1');
select results_eq(
  $$ select id, votes, voted from public.feedback_ideas((select id from ha))
     where id::text like '26800000-0000-4000-8000-00000000f%' $$,
  $$ values ('26800000-0000-4000-8000-00000000f002'::uuid, 0, false),
            ('26800000-0000-4000-8000-00000000f001', 2, true),
            ('26800000-0000-4000-8000-00000000f003', 0, false) $$,
  'Ben sees his household''s vote as voted');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f001', (select id from ha), false), 1,
  'taking the +1 back returns the new total');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f001', (select id from ha), false), 1,
  'taking it back twice changes nothing');
select is(public.vote_feedback_idea('26800000-0000-4000-8000-00000000f003', (select id from ha), true), 1,
  'Ben votes for another idea');

select throws_ok($$ select * from public.feedback_ideas((select id from hc)) $$, '42501', 'not_a_member',
  'the ideas of a household one is not in are refused');
select throws_ok($$ select public.vote_feedback_idea('26800000-0000-4000-8000-00000000f002', (select id from hc), true) $$,
  '42501', 'not_a_member', 'voting for a household one is not in is refused');
select throws_ok($$ select public.vote_feedback_idea('26800000-0000-4000-8000-00000000f004', (select id from ha), true) $$,
  'P0002', 'idea_not_found', 'a hidden idea cannot be voted for');
select throws_ok($$ select public.vote_feedback_idea('26800000-0000-4000-8000-00000000f004', (select id from ha), false) $$,
  'P0002', 'idea_not_found', 'nor its vote taken back');
select throws_ok($$ select public.vote_feedback_idea(gen_random_uuid(), (select id from ha), true) $$,
  'P0002', 'idea_not_found', 'an unknown idea is refused');
select pg_temp.login('00000000-0000-0000-0000-0000000268d1');
select throws_ok($$ select * from public.feedback_ideas((select id from ha)) $$, '42501', 'not_a_member',
  'someone without a household gets no ideas');

-- Clients read ideas only through feedback_ideas() and vote only through vote_feedback_idea().
select pg_temp.login('00000000-0000-0000-0000-0000000268b1');
select throws_ok($$ select * from public.feedback_ideas $$, '42501', null, 'the ideas table is not readable');
select throws_ok($$ insert into public.feedback_ideas (title_de, title_en) values ('Meins', 'Mine') $$, '42501', null,
  'nor writable');
select throws_ok($$ insert into public.feedback_idea_votes (idea_id, household_id)
  values ('26800000-0000-4000-8000-00000000f002', (select id from ha)) $$, '42501', null,
  'votes are not inserted directly');
select throws_ok($$ delete from public.feedback_idea_votes $$, '42501', null, 'nor deleted');
select throws_ok($$ update public.feedback_idea_votes set created_at = now() $$, '42501', null, 'nor changed');
select results_eq(
  $$ select idea_id from public.feedback_idea_votes $$,
  $$ values ('26800000-0000-4000-8000-00000000f003'::uuid) $$,
  'a member reads only the own household''s votes');
select is(
  (select array_agg(a.attname::text order by a.attnum) from pg_attribute a
   where a.attrelid = 'public.feedback_idea_votes'::regclass and a.attnum > 0 and not a.attisdropped),
  array['idea_id', 'household_id', 'created_at'], 'a vote names no person');
select pg_temp.as_postgres();
select ok(not has_function_privilege('anon', 'public.feedback_ideas(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.vote_feedback_idea(uuid, uuid, boolean)', 'execute'),
  'anon runs neither');

-- Export: Anna's notes with their answers and her household's votes, not Carl's.
select pg_temp.login('00000000-0000-0000-0000-0000000268a1');
create temp table export as select public.export_my_data() as doc;
select is(
  (select (doc -> 'feedback' -> 0) - '{created_at,household_id,message,category,contact_ok,screen,platform,app_version,build,os_version,locale,is_internal,screenshot}'::text[]
   from export),
  jsonb_build_object('status', 'fixed', 'fixed_in', '1.4.1', 'reply', 'Danke, ist notiert.',
    'replied_at', now() - interval '1 hour', 'answered_at', now() - interval '1 hour', 'seen_at', now()),
  'the export holds each note''s status, version, reply and times');
select is((select doc -> 'feedback_idea_votes' from export),
  jsonb_build_array(jsonb_build_object('household_id', (select id from ha), 'title_de', 'Preise', 'title_en', 'Prices',
    'created_at', now())),
  'and the votes of her households, none of another''s');

-- Deletions: an account takes its notes (with their replies); a household takes its votes.
select pg_temp.as_postgres();
select public.delete_account('00000000-0000-0000-0000-0000000268a1');
select is((select count(*)::int from public.feedback where id::text like '26800000-0000-4000-8000-0000000000a%'), 0,
  'deleting the account deletes the notes and their replies');
delete from public.households where id = (select id from hc);
select results_eq(
  $$ select idea_id, household_id from public.feedback_idea_votes
     where idea_id::text like '26800000-0000-4000-8000-00000000f%' order by idea_id $$,
  $$ values ('26800000-0000-4000-8000-00000000f003'::uuid, (select id from ha)) $$,
  'deleting a household deletes its votes, other households'' stay');
delete from public.feedback_ideas where id = '26800000-0000-4000-8000-00000000f003';
select is((select count(*)::int from public.feedback_idea_votes
  where idea_id::text like '26800000-0000-4000-8000-00000000f%'), 0, 'deleting an idea deletes its votes');

select is((select count(*)::int from pg_attribute a
           where a.attrelid in ('public.feedback_ideas'::regclass, 'public.feedback_idea_votes'::regclass)
             and a.attnum > 0 and not a.attisdropped
             and col_description(a.attrelid, a.attnum) is null), 0, 'every new column has a comment');

select * from finish();
rollback;
