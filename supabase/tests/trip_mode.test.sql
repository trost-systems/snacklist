-- Job 234: trip mode. save_trip_session (validation, upsert, the log rows per store),
-- trip_session (Free sees no lines), mark_trip_line_planned (Premium), delete_trip_session and
-- delete_trip, and what happens to sessions when a member leaves, an account or the household goes.
begin;
select plan(62);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- The tables as stored, for checks while signed in.
create function pg_temp.sessions() returns setof public.trip_sessions language sql security definer as $$
  select * from public.trip_sessions
$$;
create function pg_temp.trips() returns setof public.trips language sql security definer as $$
  select * from public.trips
$$;

-- A line as FinishedTrip.toJson writes it.
create function pg_temp.line(p_key text, p_name text, p_planned boolean, p_bought boolean,
  p_store uuid default null, p_store_name text default null, p_added_by uuid default null,
  p_planned_cents int default null, p_paid_cents int default null) returns jsonb
language sql as $$
  select jsonb_build_object('key', p_key, 'name', p_name, 'planned', p_planned, 'bought', p_bought,
    'quantity', null, 'store_id', p_store, 'store_name', p_store_name, 'marked_planned', false,
    'by_other', p_added_by is not null, 'added_by', p_added_by, 'planned_cents', p_planned_cents,
    'paid_cents', p_paid_cents)
$$;

-- A finished trip as FinishedTrip.toJson writes it: 25 minutes this morning, 5 of them paused.
create function pg_temp.trip(p_id uuid, p_lines jsonb) returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'household_id', null, 'list_id', null,
    'started_by', null, 'started_at', '2026-11-14T09:00:00.000Z', 'ended_at', '2026-11-14T09:25:00.000Z',
    'active_seconds', 1200, 'end_reason', 'user', 'source', 'ask', 'currency', 'EUR',
    'shopped_on', current_date::text,
    'pauses', '[{"from": "2026-11-14T09:10:00.000Z", "to": "2026-11-14T09:15:00.000Z", "auto": false}]'::jsonb,
    'lines', p_lines, 'bought', 0, 'stores', '[]'::jsonb)
$$;

grant execute on all functions in schema pg_temp to authenticated;

\set lea '''00000000-0000-0000-0000-000000234a01'''
\set pia '''00000000-0000-0000-0000-000000234a02'''
\set kim '''00000000-0000-0000-0000-000000234a03'''
\set olaf '''00000000-0000-0000-0000-000000234a04'''
\set tom '''00000000-0000-0000-0000-000000234a05'''
\set ute '''00000000-0000-0000-0000-000000234a06'''
\set vic '''00000000-0000-0000-0000-000000234a07'''
\set s1 '''00000000-0000-0000-0000-000000234c01'''
\set s2 '''00000000-0000-0000-0000-000000234c02'''

insert into auth.users (id, email) values
  (:lea, 'lea234@example.com'), (:pia, 'pia234@example.com'), (:kim, 'kim234@example.com'),
  (:olaf, 'olaf234@example.com'), (:tom, 'tom234@example.com'), (:ute, 'ute234@example.com'),
  (:vic, 'vic234@example.com');

select pg_temp.login(:lea);
create temp table home as select id from public.create_household('Zuhause', false, '{Lidl,Rewe}');
select pg_temp.login(:olaf);
create temp table away as select id from public.create_household('Olafs', false, '{Aldi}');
select pg_temp.logout();
insert into public.household_members (household_id, user_id, role)
select id, u, 'member' from home, unnest(array[:pia, :kim, :tom]::uuid[]) u;
create temp table lidl as
  select s.id from public.stores s join home h on s.household_id = h.id where s.name = 'Lidl';
create temp table rewe as
  select s.id from public.stores s join home h on s.household_id = h.id where s.name = 'Rewe';
grant select on home, away, lidl, rewe to authenticated;

-- Milch (planned, bought at Lidl), Brot (planned, not bought), Käse (Pia added it, bought at Rewe),
-- Eier (bought, no store).
create temp table lines as select jsonb_build_array(
  pg_temp.line('k1', '  Milch ', true, true, (select id from lidl), 'Lidl', null, 129, 139),
  pg_temp.line('k2', 'Brot', true, false, (select id from lidl), 'Lidl', null, 250, null),
  pg_temp.line('k3', 'Käse', false, true, (select id from rewe), 'Rewe', :pia, null, 399),
  pg_temp.line('k4', 'Eier', false, true)) as l;
grant select on lines to authenticated;

-- Saving.
select pg_temp.login(:lea);
create temp table saved as
  select public.save_trip_session((select id from home), pg_temp.trip(:s1, (select l from lines)), true) as s;
select is((select s from saved),
  jsonb_build_object('id', :s1::uuid, 'household_id', (select id from home), 'list_id', null,
    'started_by', :lea::uuid, 'started_at', '2026-11-14T09:00:00+00:00', 'ended_at', '2026-11-14T09:25:00+00:00',
    'active_seconds', 1200, 'end_reason', 'user', 'source', 'ask', 'currency', 'EUR',
    'shopped_on', current_date, 'pauses', jsonb_build_array(jsonb_build_object(
      'from', '2026-11-14T09:10:00+00:00', 'to', '2026-11-14T09:15:00+00:00', 'auto', false)),
    'lines', null, 'bought', 3, 'stores', jsonb_build_array('Lidl', 'Rewe', null), 'premium', false),
  'save_trip_session returns the session; Free: no lines, but the bought count and the stores in store order');
select is((select lines from pg_temp.sessions() where id = :s1),
  (select jsonb_set(l, '{0,name}', '"Milch"') from lines),
  'the lines are stored as sent, names trimmed');
select pg_temp.logout();
create temp table before as select ctid as at from public.trip_sessions where id = :s1;
select pg_temp.login(:lea);
select lives_ok(format($$ select public.save_trip_session(%L, %L, true) $$,
  (select id from home), pg_temp.trip(:s1, (select l from lines))), 'the same save again succeeds');
select is((select count(*)::int from pg_temp.sessions() where household_id = (select id from home)), 1,
  'and leaves one session');
select pg_temp.logout();
select is((select ctid from public.trip_sessions where id = :s1), (select at from before),
  'and writes nothing');
select pg_temp.login(:lea);

-- The log: one trip per store of the bought lines.
select results_eq(
  $$ select id, store_id, store_name, shopped_on, items, logged_by from pg_temp.trips()
     where session_id = '00000000-0000-0000-0000-000000234c01' order by store_name nulls last $$,
  $$ values
    (md5('00000000-0000-0000-0000-000000234c01:' || (select id from lidl))::uuid, (select id from lidl), 'Lidl',
     current_date, jsonb_build_array(jsonb_build_object('name', 'Milch', 'quantity', null,
       'canonical_key', public.canonical_key('Milch'))), '00000000-0000-0000-0000-000000234a01'::uuid),
    (md5('00000000-0000-0000-0000-000000234c01:' || (select id from rewe))::uuid, (select id from rewe), 'Rewe',
     current_date, jsonb_build_array(jsonb_build_object('name', 'Käse', 'quantity', null,
       'canonical_key', public.canonical_key('Käse'))), '00000000-0000-0000-0000-000000234a01'::uuid),
    (md5('00000000-0000-0000-0000-000000234c01:-')::uuid, null::uuid, null::text,
     current_date, jsonb_build_array(jsonb_build_object('name', 'Eier', 'quantity', null,
       'canonical_key', public.canonical_key('Eier'))), '00000000-0000-0000-0000-000000234a01'::uuid) $$,
  'a log entry per store of the bought lines, with deterministic ids, linked to the session');
select ok((public.trip_history((select id from home), current_date) -> 'trips')
  @> jsonb_build_array(jsonb_build_object('session_id', :s1::uuid)),
  'trip_history names the session of each entry');

-- A re-save after "Weiter einkaufen": Käse not bought after all, Brot bought at Lidl.
select public.save_trip_session((select id from home), pg_temp.trip(:s1,
  (select jsonb_set(jsonb_set(l, '{2,bought}', 'false'), '{1,bought}', 'true') from lines)), true);
select is((select jsonb_agg(store_name order by store_name nulls last) from pg_temp.trips() where session_id = :s1),
  '["Lidl", null]'::jsonb, 'the Rewe entry goes once nothing is bought there');
select is((select items from pg_temp.trips() where session_id = :s1 and store_name = 'Lidl'),
  jsonb_build_array(
    jsonb_build_object('name', 'Milch', 'quantity', null, 'canonical_key', public.canonical_key('Milch')),
    jsonb_build_object('name', 'Brot', 'quantity', null, 'canonical_key', public.canonical_key('Brot'))),
  'and the Lidl entry has the bought lines in line order');
select public.save_trip_session((select id from home), pg_temp.trip(:s1, (select l from lines)), false);
select is((select count(*)::int from pg_temp.trips() where session_id = :s1), 2,
  'a save without the log leaves the entries alone');
select is((select lines -> 2 ->> 'bought' from pg_temp.sessions() where id = :s1), 'true',
  'but saves the session');
select public.save_trip_session((select id from home), pg_temp.trip(:s1, (select l from lines)), true);

select pg_temp.login(:pia);
select public.save_trip_session((select id from home), pg_temp.trip(:s1, (select l from lines)), true);
select is((select started_by from pg_temp.sessions() where id = :s1), :lea::uuid,
  'a save by another member keeps who started it');

-- A line's added_by stays only for a member; a store of another household logs without a store.
select pg_temp.login(:olaf);
select public.save_trip_session((select id from away), pg_temp.trip(:s2, jsonb_build_array(
  pg_temp.line('x', 'Wurst', false, true, (select id from lidl), 'Lidl', :lea))), true);
select is((select lines -> 0 -> 'added_by' from pg_temp.sessions() where id = :s2), 'null'::jsonb,
  'added_by of someone outside the household is dropped');
select is((select (store_id, store_name)::text from pg_temp.trips() where session_id = :s2),
  (null::uuid, 'Lidl')::text, 'another household''s store is logged by the line''s name only');

-- Refusals.
select pg_temp.login(:lea);
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"started_at": "gestern"}'), '22023', 'invalid_trip',
  'a start that is no time is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"ended_at": "2026-11-14T08:00:00Z"}'), '22023', 'invalid_trip',
  'an end before the start is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"active_seconds": 1501}'), '22023', 'invalid_trip',
  'more active time than the trip lasted is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"end_reason": "crash"}'), '22023', 'invalid_trip',
  'an unknown end reason is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"currency": "eur"}'), '22023', 'invalid_trip',
  'a currency that is no ISO code is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"id": "abc"}'), '22023', 'invalid_trip',
  'an id that is no uuid is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || '{"pauses": [{"from": "2026-11-14T09:10:00Z", "to": "2026-11-14T09:05:00Z"}]}'),
  '22023', 'invalid_trip', 'a pause that ends before it starts is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', '  ', true, true)))),
  '22023', 'invalid_line', 'a blank name is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', 'X', true, true) || jsonb_build_object('quantity', repeat('x', 41))))),
  '22023', 'invalid_line', 'a quantity over 40 characters is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', 'X', true, true) || '{"paid_cents": 1.5}'))),
  '22023', 'invalid_line', 'cents that are no whole number are refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', 'X', true, true, null, null, null, 1000000)))),
  '22023', 'invalid_line', 'cents beyond 999999 are refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', 'X', true, true) || '{"planned_cents": "1"}'))),
  '22023', 'invalid_line', 'cents as text are refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', 'X', true, true), pg_temp.line('a', 'Y', true, true)))),
  '22023', 'invalid_line', 'a key twice is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), jsonb_build_array(pg_temp.line('a', 'X', true, true) || '{"store_id": "lidl"}'))),
  '22023', 'invalid_line', 'a store id that is no uuid is refused');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), (select jsonb_agg(pg_temp.line('k' || n, 'X', true, true)) from generate_series(1, 401) n))),
  '22023', 'too_many_lines', 'more than 400 lines are refused');
select lives_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip('00000000-0000-0000-0000-000000234c05',
    (select jsonb_agg(pg_temp.line('k' || n, 'X' || n, true, true) order by n) from generate_series(1, 400) n))),
  '400 lines are saved');
select is((select (jsonb_array_length(items), items #>> '{199,name}')::text from pg_temp.trips()
           where session_id = '00000000-0000-0000-0000-000000234c05'),
  (200, 'X200')::text, 'the log entry keeps the first 200');
select public.delete_trip_session('00000000-0000-0000-0000-000000234c05');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]') || jsonb_build_object('shopped_on', current_date + 2)),
  '22023', 'day_in_future', 'a day after tomorrow is refused');
select pg_temp.login(:olaf);
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]')), '42501', 'not_a_member', 'a non-member cannot save a session');
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from away),
  pg_temp.trip(:s1, '[]')), '22023', 'other_household', 'nor take over a session id of another household');
select throws_ok(format($$ select public.trip_session(%L, %L) $$, (select id from home), :s1),
  '42501', 'not_a_member', 'nor read it');
select throws_ok(format($$ select public.trip_session(%L, %L) $$, (select id from away), :s1),
  'P0002', 'trip_not_found', 'nor find it under the own household');
select throws_ok(format($$ select public.delete_trip_session(%L) $$, :s1), '42501', 'not_a_member',
  'nor delete it');
select throws_ok(format($$ select public.mark_trip_line_planned(%L, 'k3', true) $$, :s1), '42501', 'not_a_member',
  'nor mark its lines');
select pg_temp.logout();
select throws_ok(format($$ select public.save_trip_session(%L, %L, true) $$, (select id from home),
  pg_temp.trip(gen_random_uuid(), '[]')), '28000', 'not_authenticated', 'signed out, nothing is saved');

-- Reading and "War geplant": the lines are Premium's.
select pg_temp.login(:lea);
select is(public.trip_session((select id from home), :s1), (select s from saved),
  'Free reads the session as the save returned it');
select throws_ok(format($$ select public.mark_trip_line_planned(%L, 'k3', true) $$, :s1), '42501', 'premium_required',
  'Free cannot mark a line as planned');
select pg_temp.logout();
select public.promotional_premium_sync_user(:pia, true, null);
select pg_temp.login(:pia);
select is(public.trip_session((select id from home), :s1) -> 'lines',
  (select jsonb_set(l, '{0,name}', '"Milch"') from lines), 'Premium reads the lines');
select is(public.trip_session((select id from home), :s1) ->> 'premium', 'true', 'and premium is true');
select public.mark_trip_line_planned(:s1, 'k3', true);
select is(public.trip_session((select id from home), :s1) #> '{lines,2,marked_planned}', 'true'::jsonb,
  'Premium marks an extra as planned');
select lives_ok(format($$ select public.mark_trip_line_planned(%L, 'nope', true) $$, :s1),
  'an unknown key is no error');
select throws_ok($$ select public.mark_trip_line_planned(gen_random_uuid(), 'k3', true) $$, 'P0002', 'trip_not_found',
  'a missing session is');

-- Deleting.
select pg_temp.login(:lea);
select public.delete_trip(md5('00000000-0000-0000-0000-000000234c01:' || (select id from lidl))::uuid);
select is((select count(*)::int from pg_temp.sessions() where id = :s1), 1,
  'deleting one of a session''s log entries keeps the session');
select public.delete_trip(md5('00000000-0000-0000-0000-000000234c01:' || (select id from rewe))::uuid);
select public.delete_trip(md5('00000000-0000-0000-0000-000000234c01:-')::uuid);
select is((select count(*)::int from pg_temp.sessions() where id = :s1), 0,
  'deleting its last one deletes the session');
select public.save_trip_session((select id from home), pg_temp.trip(:s1, (select l from lines)), true);
select public.delete_trip_session(:s1);
select is((select count(*)::int from pg_temp.sessions() where id = :s1)
        + (select count(*)::int from pg_temp.trips() where session_id = :s1 or id = md5(:s1 || ':-')::uuid), 0,
  'delete_trip_session deletes the session and its log entries');
select lives_ok(format($$ select public.delete_trip_session(%L) $$, :s1), 'deleting it again is no error');

-- The export.
select public.save_trip_session((select id from home), pg_temp.trip(:s1, (select l from lines)), true);
select is(public.export_my_data() -> 'trip_sessions_started',
  jsonb_build_array(jsonb_build_object('household_id', (select id from home),
    'started_at', '2026-11-14T09:00:00+00:00', 'ended_at', '2026-11-14T09:25:00+00:00',
    'active_seconds', 1200, 'end_reason', 'user', 'source', 'ask', 'currency', 'EUR',
    'shopped_on', current_date, 'pauses', (select pauses from pg_temp.sessions() where id = :s1),
    'bought', 3, 'stores', jsonb_build_array('Lidl', 'Rewe', null),
    'lines', (select jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o)
              from lines, jsonb_array_elements(jsonb_set(l, '{0,name}', '"Milch"')) with ordinality as x (e, o)),
    'created_at', (select created_at from pg_temp.sessions() where id = :s1))),
  'export_my_data lists the sessions Lea started, without item, store or member ids');
select pg_temp.login(:pia);
select is(public.export_my_data() -> 'trip_sessions_started', '[]'::jsonb,
  'Pia''s export lists none: she only added a line');

-- Leaving, account deletion, household deletion.
select is(public.leave_household((select id from home)) ->> 'status', 'left', 'Pia leaves');
select pg_temp.logout();
select is((select lines #> '{2,added_by}' from pg_temp.sessions() where id = :s1), 'null'::jsonb,
  'the line she added stays, without her');
select is((select lines #> '{2,by_other}' from pg_temp.sessions() where id = :s1), 'true'::jsonb,
  'still as added by someone else');
select pg_temp.login(:kim);
select public.save_trip_session((select id from home),
  pg_temp.trip('00000000-0000-0000-0000-000000234c03', jsonb_build_array(pg_temp.line('t', 'Tee', false, true, null, null, :tom))), true);
select is(public.leave_household((select id from home)) ->> 'status', 'left', 'Kim leaves');
select pg_temp.logout();
select is((select started_by from pg_temp.sessions() where id = '00000000-0000-0000-0000-000000234c03'), null,
  'the session she started stays, without who started it');
select is(public.delete_account(:tom), 'kept', 'Tom deletes his account');
select is((select lines #> '{0,added_by}' from pg_temp.sessions() where id = '00000000-0000-0000-0000-000000234c03'),
  'null'::jsonb, 'the line he added stays, without him');

-- Ute is the last member of her household, with a line Vic saved before he left; deleting her
-- account straight from auth.users leaves the household behind, but not her id.
select pg_temp.login(:ute);
create temp table utes as select id from public.create_household('Utes', false, '{}');
select pg_temp.logout();
insert into public.household_members (household_id, user_id, role) select id, :vic, 'member' from utes;
select pg_temp.login(:vic);
select public.save_trip_session((select id from utes),
  pg_temp.trip('00000000-0000-0000-0000-000000234c04', jsonb_build_array(pg_temp.line('u', 'Obst', false, true, null, null, :ute))), true);
select public.leave_household((select id from utes));
select pg_temp.logout();
delete from auth.users where id = :ute;
select is((select lines #> '{0,added_by}' from pg_temp.sessions() where id = '00000000-0000-0000-0000-000000234c04'),
  'null'::jsonb, 'a deleted account leaves no line naming it, even where nobody is left');

select is(public.delete_account(:lea), 'deleted', 'Lea, the last member, deletes her account');
select is((select count(*)::int from pg_temp.sessions() where household_id = (select id from home)), 0,
  'the household''s sessions go with it');

select * from finish();
rollback;
