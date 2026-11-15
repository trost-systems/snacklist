-- Job 267 and its review 0: feedback screenshots (docs/FEEDBACK.md, "Screenshots"). The bucket,
-- no client upload (no storage policy), the function's check (its lock, 10 a day, 250 in the
-- bucket, a stored name passes) and who may run it, feedback.screenshot, the removal queue its
-- deletes fill (stored names only), the sweep's due list (queue, then orphans older than a day or
-- without an account) and the export. The function and the Storage API are driven by
-- feedback-screenshots/screenshots_integration_test.ts.
begin;
select plan(51);

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

-- An object as the Storage API writes its row: a client under RLS, or the function's secret key.
create function pg_temp.upload(p_name text, p_bucket text default 'feedback-screenshots') returns void
language sql as $$
  insert into storage.objects (bucket_id, name, owner_id) values (p_bucket, p_name, auth.uid()::text)
$$;
grant execute on function pg_temp.upload(text, text) to authenticated, anon;

create function pg_temp.admit(p_user uuid, p_id uuid) returns text language sql as $$
  select public.feedback_screenshot_admit(p_user, p_id)
$$;

create function pg_temp.note(p_id uuid, p_screenshot text) returns void language sql as $$
  insert into public.feedback (id, message, app_version, build, platform, os_version, locale, screenshot)
  values (p_id, 'Siehe Bild', '1.0.0', '1', 'ios', 'iOS 18.1', 'de', p_screenshot)
$$;
grant execute on function pg_temp.note(uuid, text) to authenticated, anon;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000267a1', 'anna267@gmail.com'),
  ('00000000-0000-0000-0000-0000000267b1', 'ben267@web.de'),
  ('00000000-0000-0000-0000-0000000267c1', 'cora267@gmx.de');

-- The bucket: private, 2 MiB, PNG only.
select results_eq(
  $$ select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'feedback-screenshots' $$,
  $$ values (false, 2097152::bigint, array['image/png']) $$,
  'the bucket is private, takes up to 2 MiB and only PNG');

-- Clients store nothing: no policy lets them, not even into their own folder with the app's name
-- shape (a signed upload URL tests the same insert).
select pg_temp.login('00000000-0000-0000-0000-0000000267a1');
select throws_ok($$ select pg_temp.upload('00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png') $$,
  '42501', null, 'a signed-in user uploads nothing, not into their own folder');
select pg_temp.anon();
select throws_ok($$ select pg_temp.upload('00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000007.png') $$,
  '42501', null, 'anon uploads nothing');
select pg_temp.as_postgres();
select ok(not exists (select from pg_policies where schemaname = 'storage' and tablename = 'objects'
                        and (qual like '%feedback-screenshots%' or with_check like '%feedback-screenshots%')),
  'no storage policy names the bucket');
select ok(not has_function_privilege(r, 'public.feedback_screenshot_quota_left(text)', 'execute'),
  r || ' cannot ask the old quota helper whether the bucket is full')
from unnest(array['anon', 'authenticated']) r;
select ok(not has_function_privilege(r, 'public.feedback_screenshot_admit(uuid, uuid)', 'execute'),
  r || ' cannot run the function''s quota check')
from unnest(array['anon', 'authenticated', 'service_role']) r;

-- The function's check, as its connection runs it: the lock first, then the quotas.
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '10000000-0000-4000-8000-000000000001'), 'new',
  'a first image may be stored');
select ok(exists (select from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and granted),
  'the check holds the bucket''s lock until the transaction ends');
select pg_temp.upload('00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '10000000-0000-4000-8000-000000000001'), 'exists',
  'a stored name is there already');
insert into storage.buckets (id, name, public) values ('other-267', 'other-267', false);
select pg_temp.upload('00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000006.png', 'other-267');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '10000000-0000-4000-8000-000000000006'), 'new',
  'the same name in another bucket is another object');

-- No reading back, overwriting or removing, not even one's own.
select pg_temp.login('00000000-0000-0000-0000-0000000267a1');
select is((select count(*)::int from storage.objects where bucket_id = 'feedback-screenshots'), 0,
  'the uploader sees no object, not even their own');
select is((select count(*)::int from storage.buckets where id = 'feedback-screenshots'), 0, 'nor the bucket');
update storage.objects set name = name || '.x';
select pg_temp.as_postgres();
select is((select count(*)::int from storage.objects
           where name = '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png'), 1,
  'an update as the uploader changes nothing');

-- The quota: 10 per user in any 24 hours.
select pg_temp.upload(format('00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-%s.png', lpad(n::text, 12, '0')))
from generate_series(2, 9) n;
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '20000000-0000-4000-8000-000000000010'), 'new',
  'the 10th of the day may be stored');
select pg_temp.upload('00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000010.png');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '20000000-0000-4000-8000-000000000021'), 'quota',
  'the 11th is refused');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '20000000-0000-4000-8000-000000000005'), 'exists',
  'a retry of a stored name at the quota is still there');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267b1', '30000000-0000-4000-8000-000000000001'), 'new',
  'another user''s quota is their own');
select pg_temp.upload('00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png');
update storage.objects set created_at = now() - interval '24 hours 1 minute'
where name = '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000002.png';
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267a1', '20000000-0000-4000-8000-000000000022'), 'new',
  'an upload older than 24 hours no longer counts');
select pg_temp.upload('00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000022.png');
select pg_temp.login('00000000-0000-0000-0000-0000000267a1');

-- feedback.screenshot names exactly the sender's object for this note.
select lives_ok($$ select pg_temp.note('10000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png') $$,
  'a note names its screenshot');
select lives_ok($$ select pg_temp.note('10000000-0000-4000-8000-000000000008', null) $$, 'a note without one');
select throws_ok($$ select pg_temp.note('10000000-0000-4000-8000-000000000009',
  '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png') $$,
  '23514', null, 'not another note''s screenshot');
select throws_ok($$ select pg_temp.note('10000000-0000-4000-8000-000000000009',
  '00000000-0000-0000-0000-0000000267b1/10000000-0000-4000-8000-000000000009.png') $$,
  '23514', null, 'not one in another user''s folder');
select throws_ok($$ select pg_temp.note('10000000-0000-4000-8000-000000000009',
  'https://example.com/10000000-0000-4000-8000-000000000009.png') $$, '23514', null, 'not a URL');
select throws_ok($$ select screenshot from public.feedback $$, '42501', null, 'the sender cannot read it back');

-- The export lists each note's screenshot.
select is(
  (select jsonb_agg(e -> 'screenshot' order by e ->> 'screenshot' nulls last)
   from jsonb_array_elements(public.export_my_data() -> 'feedback') e),
  '["00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png", null]'::jsonb,
  'the export names each note''s screenshot');

-- The queue: deleting a note with a screenshot queues its name, once.
select pg_temp.as_postgres();
select is((select count(*)::int from public.feedback_screenshot_removals), 0, 'the queue starts empty');
delete from public.feedback where id = '10000000-0000-4000-8000-000000000008';
select is((select count(*)::int from public.feedback_screenshot_removals), 0, 'a note without a screenshot queues nothing');
delete from public.feedback where id = '10000000-0000-4000-8000-000000000001';
select results_eq($$ select name from public.feedback_screenshot_removals $$,
  $$ values ('00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png') $$,
  'deleting a note queues its screenshot');
insert into public.feedback (id, user_id, message, app_version, build, platform, os_version, locale, screenshot)
values ('10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-0000000267a1', 'Noch mal', '1', '1', 'ios',
  'iOS', 'de', '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png');
delete from public.feedback where id = '10000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.feedback_screenshot_removals), 1, 'a name is queued once');
insert into public.feedback (id, user_id, message, app_version, build, platform, os_version, locale, screenshot)
values ('10000000-0000-4000-8000-00000000000c', '00000000-0000-0000-0000-0000000267a1', 'Ohne Datei', '1', '1', 'ios',
  'iOS', 'de', '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-00000000000c.png');
delete from public.feedback where id = '10000000-0000-4000-8000-00000000000c';
select is((select count(*)::int from public.feedback_screenshot_removals), 1,
  'a note naming an image that was never stored queues nothing');

-- The purge and the account deletion queue theirs too.
select pg_temp.login('00000000-0000-0000-0000-0000000267b1');
select pg_temp.note('30000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png');
select pg_temp.as_postgres();
select pg_temp.upload('00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000002.png');
insert into public.feedback (id, user_id, message, app_version, build, platform, os_version, locale, screenshot)
values ('20000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-0000000267a1', 'Alt', '1', '1', 'ios', 'iOS',
  'de', '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000003.png');
update public.feedback set created_at = now() - interval '13 months' where id = '20000000-0000-4000-8000-000000000003';
select is(public.purge_old_feedback(), 1, 'the purge deletes the old note');
select ok(exists (select from public.feedback_screenshot_removals
  where name = '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000003.png'),
  'and queues its screenshot');
delete from auth.users where id = '00000000-0000-0000-0000-0000000267b1';
select ok(exists (select from public.feedback_screenshot_removals
  where name = '00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png'),
  'deleting the account queues the screenshots of its notes');

-- Due: the queue first, then uploads no note names: older than a day, or at once once their
-- account is gone.
update public.feedback_screenshot_removals set queued_at = now() - interval '1 hour'
where name like '00000000-0000-0000-0000-0000000267b1/%';
insert into public.feedback (id, user_id, message, app_version, build, platform, os_version, locale, screenshot)
values ('20000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-0000000267a1', 'Mit Bild', '1', '1', 'ios',
  'iOS', 'de', '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000004.png');
update storage.objects set created_at = now() - interval '25 hours'
where name in ('00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000003.png',
               '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000004.png',
               '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000005.png');
select is(
  (select array_agg(n) from public.feedback_screenshots_due(100) n),
  array['00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png',
        '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png',
        '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000003.png',
        '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000005.png',
        '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000002.png',
        '00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000002.png'],
  'due: the queue oldest first, then the orphans older than a day or of a deleted account; not one a note names, not a young one');
select is((select array_agg(n) from public.feedback_screenshots_due(2) n),
  array['00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png',
        '00000000-0000-0000-0000-0000000267a1/10000000-0000-4000-8000-000000000001.png'],
  'at most the limit');
select is(public.feedback_screenshots_removed(array[
  '00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png',
  '00000000-0000-0000-0000-0000000267a1/20000000-0000-4000-8000-000000000005.png']), 1,
  'removed: the queued name leaves the queue (an orphan was never in it)');
select is(public.feedback_screenshots_removed(array[
  '00000000-0000-0000-0000-0000000267b1/30000000-0000-4000-8000-000000000001.png']), 0, 'a second time is a no-op');

-- The bucket-wide cap: nothing new while the bucket holds 250 images, whoever uploads.
insert into storage.objects (bucket_id, name)
select 'feedback-screenshots', format('00000000-0000-0000-0000-0000000267a1/%s.png', gen_random_uuid())
from generate_series(1, 249 - (select count(*) from storage.objects where bucket_id = 'feedback-screenshots'));
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267c1', '40000000-0000-4000-8000-000000000001'), 'new',
  'the 250th image in the bucket may be stored');
select pg_temp.upload('00000000-0000-0000-0000-0000000267c1/40000000-0000-4000-8000-000000000001.png');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267c1', '40000000-0000-4000-8000-000000000002'), 'quota',
  'at 250 images the bucket refuses the next, with the user''s own quota left');
select is(pg_temp.admit('00000000-0000-0000-0000-0000000267c1', '40000000-0000-4000-8000-000000000001'), 'exists',
  'a retry at the bucket cap is still there');

-- Only the owner (the function's connection) runs the sweep's SQL or reads the queue.
select ok(not has_function_privilege(r, 'public.feedback_screenshots_due(integer)', 'execute'),
  r || ' cannot list what is due')
from unnest(array['anon', 'authenticated', 'service_role']) r;
select ok(not has_function_privilege(r, 'public.feedback_screenshots_removed(text[])', 'execute'),
  r || ' cannot mark names removed')
from unnest(array['anon', 'authenticated', 'service_role']) r;
select ok(not has_table_privilege('authenticated', 'public.feedback_screenshot_removals', 'select, insert, update, delete'),
  'clients cannot touch the queue');
select ok(not has_table_privilege('service_role', 'public.feedback_screenshot_removals', 'select, insert, update, delete'),
  'nor can the service key');

select * from finish();
rollback;
