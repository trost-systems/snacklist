begin;
select plan(44);

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

-- One feedback note as the app sends it (job 21).
create function pg_temp.feedback(p_id uuid, p_message text) returns void language sql as $$
  insert into public.feedback (id, message, app_version, build, platform, os_version, locale, screen)
  values (p_id, p_message, '0.1.0', '1', 'web', 'Chrome on macOS', 'de', 'list');
$$;

create function pg_temp.hash(token text) returns text language sql as $$
  select encode(extensions.digest(token, 'sha256'), 'hex');
$$;

-- Rows per household-owned table; every table that carries household_id is listed.
create function pg_temp.household_rows(p_household uuid) returns table (tbl text, n int)
language sql as $$
  select 'households', count(*)::int from public.households where id = p_household
  union all select 'household_members', count(*)::int from public.household_members where household_id = p_household
  union all select 'invites', count(*)::int from public.invites where household_id = p_household
  union all select 'categories', count(*)::int from public.categories where household_id = p_household
  union all select 'stores', count(*)::int from public.stores where household_id = p_household
  union all select 'store_category_order', count(*)::int from public.store_category_order where household_id = p_household
  union all select 'items', count(*)::int from public.items where household_id = p_household
  union all select 'item_events', count(*)::int from public.item_events where household_id = p_household
  union all select 'category_memory', count(*)::int from public.category_memory where household_id = p_household
  union all select 'item_store_memory', count(*)::int from public.item_store_memory where household_id = p_household
  union all select 'personal_access_tokens', count(*)::int from public.personal_access_tokens where household_id = p_household
  union all select 'household_brands', count(*)::int from public.household_brands where household_id = p_household
  union all select 'feedback', count(*)::int from public.feedback where household_id = p_household
  union all select 'item_merges', count(*)::int from public.item_merges where household_id = p_household
  union all select 'entitlements', count(*)::int from public.entitlements where household_id = p_household
  union all select 'household_departures', count(*)::int from public.household_departures where household_id = p_household
  union all select 'integration_blocks', count(*)::int from public.integration_blocks where household_id = p_household
  union all select 'api_household_days', count(*)::int from public.api_household_days where household_id = p_household;
$$;

select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind = 'r' and a.attname = 'household_id' and not a.attisdropped),
  (select array_agg(tbl order by tbl) from pg_temp.household_rows(null) where tbl <> 'households'),
  'household_rows covers every household-owned table'
);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'carl@example.com'),
  ('00000000-0000-0000-0000-0000000000d1', 'dora@example.com'),
  ('00000000-0000-0000-0000-0000000000e1', 'emil@example.com'),
  ('00000000-0000-0000-0000-0000000000f1', 'frida@example.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'gina@example.com');

-- Alice owns the household; Carl joined before Bob.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table h as select id from public.create_household('WG');
-- Invites are single use (job 22): one per person who joins.
create temp table inv as select code from public.create_invite((select id from h));
create temp table inv2 as select code from public.create_invite((select id from h));
create temp table inv3 as select code from public.create_invite((select id from h));
create temp table pat_a as select token from public.create_personal_access_token('Siri');
grant select on h, inv, inv2, inv3, pat_a to authenticated;
insert into public.items (household_id, name) select id, 'Milch' from h;
insert into public.items (household_id, name) select id, 'Kaffee' from h;
update public.items set status = 'bought' where name = 'Kaffee';
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select public.join_household((select code from inv));
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select public.join_household((select code from inv2));
insert into public.items (household_id, name) select id, 'Brot' from h;
select pg_temp.feedback('40000000-0000-4000-8000-0000000000b1', 'Bob');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select pg_temp.feedback('40000000-0000-4000-8000-0000000000a1', 'Alice');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select pg_temp.feedback('40000000-0000-4000-8000-0000000000c1', 'Carl');
-- Gina sent a note while in the household and left it since.
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select public.join_household((select code from inv3));
select pg_temp.feedback('40000000-0000-4000-8000-0000000000a2', 'Gina');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
update public.items set status = 'bought' where name = 'Milch';
update public.items set added_by = null where name = 'Milch';
select is((select added_by from public.items where name = 'Milch'),
  '00000000-0000-0000-0000-0000000000a1'::uuid, 'a client cannot clear who added an item');

select pg_temp.as_postgres();
update public.household_members set joined_at = now() - interval '2 days'
where user_id = '00000000-0000-0000-0000-0000000000c1';
update public.household_members set joined_at = now() - interval '1 day'
where user_id = '00000000-0000-0000-0000-0000000000b1';
delete from public.household_members where user_id = '00000000-0000-0000-0000-0000000000a2';
-- Backdate without triggers so a bump of updated_at is visible inside this transaction.
set local session_replication_role = replica;
update public.items set updated_at = updated_at - interval '1 hour';
set local session_replication_role = origin;
create temp table items_before as select id, updated_at from public.items;
create temp table events_before as select count(*)::int as n from public.item_events;
grant select on items_before, events_before to authenticated;

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select throws_ok(
  $$ select public.delete_account('00000000-0000-0000-0000-0000000000a1') $$,
  '42501', null, 'a signed-in user cannot delete an account, not even someone else''s'
);
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok(
  $$ select public.delete_account(auth.uid()) $$,
  '42501', null, 'nor their own through the API; only the edge function can'
);

-- A member deletes the account: the owner, who added items and bought one.
select pg_temp.as_postgres();
select is(public.delete_account('00000000-0000-0000-0000-0000000000a1'), 'kept',
  'the household stays while others remain');
select is(
  (select user_id from public.household_members where household_id = (select id from h) and role = 'owner'),
  '00000000-0000-0000-0000-0000000000c1'::uuid,
  'ownership passes to the longest-standing member'
);
select is((select count(*)::int from public.household_members where household_id = (select id from h)), 2,
  'the other members stay');
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000000a1'), 0,
  'the user is gone');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'), 0,
  'and so is their profile');
select is((select count(*)::int from public.feedback where user_id = '00000000-0000-0000-0000-0000000000a1'), 0,
  'and their feedback');
select results_eq(
  $$ select message, household_id from public.feedback order by message $$,
  $$ values ('Bob', (select id from h)), ('Carl', (select id from h)), ('Gina', (select id from h)) $$,
  'the other members'' feedback stays');
select results_eq(
  $$ select name, added_by from public.items order by name $$,
  $$ values ('Brot', '00000000-0000-0000-0000-0000000000b1'::uuid), ('Kaffee', null), ('Milch', null) $$,
  'their items stay for the household, without an author'
);
select is((select bought_by from public.items where name = 'Kaffee'), null, 'and without a buyer');
select is(
  (select count(*)::int from public.items i join items_before b using (id) where i.updated_at <> b.updated_at),
  0, 'losing the author does not touch updated_at'
);
select is((select count(*)::int from public.item_events), (select n from events_before),
  'and writes no history');
select is(
  (select count(*)::int from public.item_events where actor = '00000000-0000-0000-0000-0000000000a1'),
  0, 'the history keeps their events without the author'
);
select isnt_empty(
  $$ select from public.item_events where actor is null and item_name = 'Kaffee' and action = 'bought' $$,
  'the history itself stays'
);
select is_empty(
  $$ select * from public.authenticate_personal_access_token(pg_temp.hash((select token from pat_a))) $$,
  'their tokens stop working'
);
select is(public.delete_account('00000000-0000-0000-0000-0000000000a1'), 'none',
  'deleting again changes nothing');

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select results_eq(
  $$ select name from public.items order by name $$,
  $$ values ('Brot'), ('Kaffee'), ('Milch') $$,
  'the remaining members still see the list'
);
update public.items set quantity = '2' where name = 'Kaffee';
insert into public.items (household_id, name) select id, 'Eier' from h;
select is((select count(*)::int from public.items where quantity = '2' or name = 'Eier'), 2,
  'and still change it');
select is(
  (select added_by from public.items where name = 'Kaffee'), null,
  'an edit does not claim an orphaned item'
);
update public.items set added_by = auth.uid() where name = 'Milch';
select is((select added_by from public.items where name = 'Milch'), null,
  'clients still cannot change who added an item');
select is(
  (select action from public.item_events where item_name = 'Kaffee' order by id desc limit 1), 'edited',
  'real edits are still history'
);

-- Job 32b: Bob merged his Karotten into his Möhren; the merge keeps both rows for its undo.
insert into public.items (id, household_id, name) select '32b00000-0000-4000-8000-0000000000b1', id, 'Möhren' from h;
insert into public.items (id, household_id, name) select '32b00000-0000-4000-8000-0000000000b2', id, 'Karotten' from h;
do $$ begin perform public.merge_items('32b00000-0000-4000-8000-0000000000bb',
  '32b00000-0000-4000-8000-0000000000b1', '32b00000-0000-4000-8000-0000000000b2'); end $$;

-- The dashboard and the admin API delete straight from auth.users.
select pg_temp.as_postgres();
select lives_ok(
  $$ delete from auth.users where id = '00000000-0000-0000-0000-0000000000b1' $$,
  'a user who added and bought items can be deleted directly'
);
select is(
  (select count(*)::int from public.item_merges
   where merged_by is not null or merged_row ->> 'added_by' is not null or kept_before ->> 'added_by' is not null),
  0, 'stored merges forget the deleted user'
);
select is(
  (select merged_row ->> 'name' from public.item_merges where id = '32b00000-0000-4000-8000-0000000000bb'),
  'Karotten', 'and keep the item for the household''s undo'
);
select results_eq(
  $$ select count(*)::int from public.items where added_by is not null or bought_by is not null $$,
  $$ values (0) $$,
  'which leaves their items without author and buyer'
);
select is((select count(*)::int from public.feedback where user_id = '00000000-0000-0000-0000-0000000000b1'), 0,
  'and takes their feedback with them');

-- The last member: Carl, now the owner, with learned memories and a token.
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
create temp table pat_c as select token from public.create_personal_access_token('MCP');
grant select on pat_c to authenticated;
update public.items
set category_id = (select id from public.categories where household_id = (select id from h) and seed_key = 'drinks'),
    store_id = public.add_store((select id from h), 'Supermarkt'),
    brand = 'Hofbäckerei Kurz'
where name = 'Brot';
select pg_temp.as_postgres();
-- Job 25 (as of job 43, through RevenueCat): Carl bought Hummlist Lifetime for the household.
select public.purchase_claim('00000000-0000-0000-0000-0000000000c1', (select id from h), 'apple', '2000000000002501');
select public.purchase_record('apple', '2000000000002501', '2000000000002501', repeat('a', 64),
  'com.hummlist.app.lifetime', 'premium', 'lifetime', 'Sandbox', now(), 9.99, 'EUR', 'DE', (select id from h));
-- Job 50: a refusal noted while the household was locked.
insert into public.integration_blocks (household_id, integration, reported_at) values ((select id from h), 'siri', now());
-- Job 73: the household's API requests today.
insert into public.api_household_days (household_id, day, requests) values ((select id from h), current_date, 3);
select is(
  (select array_agg(tbl order by tbl) from pg_temp.household_rows((select id from h)) where n = 0),
  null, 'before: every household table has rows'
);
select is(public.delete_account('00000000-0000-0000-0000-0000000000c1'), 'deleted',
  'the last member takes the household with them');
select is(
  (select array_agg(tbl order by tbl) from pg_temp.household_rows((select id from h)) where n > 0),
  null, 'after: no household table has a row left'
);
select is((select count(*)::int from public.feedback where user_id = '00000000-0000-0000-0000-0000000000c1'), 0,
  'the last member''s feedback is gone');
select results_eq(
  $$ select user_id, revoked_at from public.purchases where transaction_id = '2000000000002501' $$,
  $$ values (null::uuid, null::timestamptz) $$,
  'the purchase stays for refunds and replays, without the buyer; its unlock went with the household');
select results_eq(
  $$ select user_id, household_id from public.feedback $$,
  $$ values ('00000000-0000-0000-0000-0000000000a2'::uuid, null::uuid) $$,
  'a former member''s note stays, without the deleted household''s id');
select is_empty(
  $$ select * from public.authenticate_personal_access_token(pg_temp.hash((select token from pat_c))) $$,
  'the last member''s tokens stop working'
);

select is(public.delete_account('00000000-0000-0000-0000-0000000000d1'), 'none',
  'a user without a household is deleted too');
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000000d1'), 0,
  'and is gone');
select is(public.delete_account('00000000-0000-0000-0000-00000000dead'), 'none',
  'an unknown user returns none');

-- Export: Emil and Frida share a household; Emil connected an app.
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
create temp table he as select id from public.create_household('Emil & Frida');
create temp table inv_e as select code from public.create_invite((select id from he));
grant select on he, inv_e to authenticated;
select public.create_personal_access_token('Kurzbefehl');
insert into public.items (household_id, name, brand, properties, quantity) select id, 'Äpfel', 'Elstar', 'Bio', '1 kg' from he;
insert into public.feedback (id, message, category, contact_ok, app_version, build, platform, os_version, locale, screen)
values ('40000000-0000-4000-8000-0000000000e1', 'Bitte dunkles Design', 'idea', true, '0.1.0', '7', 'ios', 'iOS 18.1',
  'de', 'list');
select pg_temp.login('00000000-0000-0000-0000-0000000000f1');
select public.join_household((select code from inv_e));
insert into public.items (household_id, name) select id, 'Fridas Geheimnis' from he;
select pg_temp.as_postgres();
insert into auth.oauth_clients (id, registration_type, redirect_uris, grant_types, client_name, client_type, token_endpoint_auth_method)
values ('00000000-0000-0000-0000-00000000c11e', 'dynamic', 'https://claude.ai/cb', 'authorization_code', 'Claude', 'public', 'none');
insert into auth.oauth_consents (id, user_id, client_id, scopes)
values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-00000000c11e', 'openid email');

create temp table emil as select created_at from auth.users where email = 'emil@example.com';
grant select on emil to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
create temp table export as select public.export_my_data() as doc;
select is(
  (select array_agg(k order by k) from export, jsonb_object_keys(doc) k),
  array['access_tokens', 'account', 'alexa_links', 'analytics_decisions', 'archived_households', 'connected_apps', 'exported_at',
        'feedback', 'format', 'history', 'household', 'households', 'invites_created', 'items_added',
        'profile', 'purchases', 'version'],
  'the export has the documented sections'
);
select is(
  (select doc - 'exported_at' from export),
  jsonb_build_object(
    'format', 'family-groceries-export',
    'version', 1,
    'account', jsonb_build_object('id', '00000000-0000-0000-0000-0000000000e1', 'email', 'emil@example.com',
      'created_at', (select created_at from emil),
      'last_sign_in_at', null, 'providers', '[]'::jsonb),
    'profile', jsonb_build_object('display_name', 'emil', 'created_at', now()),
    'household', jsonb_build_object('id', (select id from he), 'name', 'Emil & Frida', 'role', 'owner', 'joined_at', now()),
    'households', jsonb_build_array(jsonb_build_object('id', (select id from he), 'name', 'Emil & Frida',
      'kind', null, 'role', 'owner', 'joined_at', now(), 'is_default', true)),
    'items_added', jsonb_build_array(jsonb_build_object('name', 'Äpfel', 'brand', 'Elstar', 'properties', 'Bio',
      'quantity', '1 kg', 'status', 'active',
      'category', 'Obst & Gemüse', 'store', null, 'created_at', now(), 'bought_at', null)),
    'history', jsonb_build_array(jsonb_build_object('action', 'added', 'item_name', 'Äpfel',
      'category', 'Obst & Gemüse', 'created_at', now())),
    'access_tokens', jsonb_build_array(jsonb_build_object('name', 'Kurzbefehl',
      'token_hint', (select token_hint from public.personal_access_tokens where name = 'Kurzbefehl'),
      'created_at', now(), 'last_used_at', null, 'revoked_at', null)),
    -- Job 22: Emil's invite, which Frida used; not who used it.
    'invites_created', jsonb_build_array(jsonb_build_object('code', (select code from inv_e),
      'created_at', now(), 'expires_at', now() + interval '7 days', 'used_at', now(), 'revoked_at', null)),
    'feedback', jsonb_build_array(jsonb_build_object('created_at', now(), 'message', 'Bitte dunkles Design',
      'category', 'idea', 'contact_ok', true, 'screen', 'list', 'platform', 'ios', 'app_version', '0.1.0',
      'build', '7', 'os_version', 'iOS 18.1', 'locale', 'de', 'household_id', (select id from he),
      'is_internal', true)),
    'connected_apps', jsonb_build_array(jsonb_build_object('client_name', 'Claude', 'scopes', 'openid email',
      'granted_at', now(), 'revoked_at', null, 'device', null)),
    'analytics_decisions', '[]'::jsonb,
    'alexa_links', '[]'::jsonb,
    -- Job 25: Emil bought nothing (purchases.test.sql covers a buyer's export).
    'purchases', '[]'::jsonb,
    'archived_households', '[]'::jsonb
  ),
  'the export holds the user''s own data and nothing of the other member''s'
);
select ok(
  (select doc::text !~ '[0-9a-f]{64}' and doc::text !~* 'hash' from export),
  'the export carries no token hashes'
);

select set_config('request.jwt.claims', json_build_object(
  'sub', '00000000-0000-0000-0000-0000000000e1', 'role', 'authenticated',
  'client_id', '00000000-0000-0000-0000-00000000c11e')::text, true);
select throws_ok(
  $$ select public.export_my_data() $$,
  '42501', 'session_required', 'an app connected over OAuth cannot export the account'
);
select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
select throws_ok(
  $$ select public.export_my_data() $$,
  '28000', 'not_authenticated', 'export needs a user'
);

select * from finish();
rollback;
