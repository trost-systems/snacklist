-- Job 274: suggest_index gives a member what suggest_entries reads of the household (history,
-- learned brands, unserved hardware categories, older names), in the shape the device parses,
-- and nothing of another household.
begin;
select plan(17);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000274b01', 'anna274@example.com'),
  ('00000000-0000-0000-0000-000000274b02', 'bert274@example.com');
select pg_temp.login('00000000-0000-0000-0000-000000274b01');
create temp table ha as select id from public.create_household('Anna');
select pg_temp.login('00000000-0000-0000-0000-000000274b02');
create temp table hb as select id from public.create_household('Bert');
reset role;
grant select on ha, hb to authenticated;

-- Written as the bench does, so bought_at and updated_at stay as given.
set local session_replication_role = replica;
insert into public.items (household_id, list_id, category_id, name, normalized_name, brand, properties, quantity, status, bought_at, updated_at)
select h, public.first_list(h),
  (select c.id from public.categories c where c.household_id = h and c.seed_key = 'other'), v.name, public.normalize_item_name(v.name), v.brand, v.properties, v.quantity, 'bought',
  now() - v.bought, now() - v.updated
from (values
  ((select id from ha), 'Milch', null, null, null, interval '30 days', interval '30 days'),
  ((select id from ha), 'Milch', null, null, '2', interval '3 days', interval '3 days'),
  ((select id from ha), 'Milch', 'Weihenstephan', '1,5 %', null, null, interval '5 days'),
  ((select id from ha), 'Kerzen', null, null, null, interval '400 days', interval '400 days'),
  ((select id from hb), 'Geheimtee', null, null, null, interval '2 days', interval '2 days')
) as v (h, name, brand, properties, quantity, bought, updated);
set local session_replication_role = origin;
insert into public.household_brands (household_id, brand_key, brand) values
  ((select id from ha), public.brand_key('Lillydoo'), 'Lillydoo'),
  ((select id from ha), public.brand_key('Milch'), 'Milch'),
  ((select id from hb), public.brand_key('Geheimmarke'), 'Geheimmarke');

-- Stores: dm (seed key dm), Krume (none). Memory as the items triggers would write it: Milch at
-- Krume, then at dm; Brot cleared. Bert's household has its own.
insert into public.stores (household_id, name, seed_key, sort_order) values
  ((select id from ha), 'dm', 'dm', 10), ((select id from ha), 'Krume', null, 20),
  ((select id from hb), 'Geheimladen', 'edeka', 10);
insert into public.item_store_memory (household_id, item_key, store_id, times, updated_at) values
  ((select id from ha), public.item_key('Milch'), (select id from public.stores where name = 'Krume'), 3, now() - interval '2 days'),
  ((select id from ha), public.item_key('Milch'), (select id from public.stores where name = 'dm'), 1, now() - interval '1 day'),
  ((select id from hb), public.item_key('Geheimtee'), (select id from public.stores where name = 'Geheimladen'), 1, now());
insert into public.item_store_cleared (household_id, item_key) values
  ((select id from ha), public.item_key('Brot')), ((select id from hb), public.item_key('Geheimbrot'));
-- Past the triggers, so the history's times stay.
set local session_replication_role = replica;
update public.items set canonical_key = public.canonical_key(name),
  category_id = (select c.id from public.categories c where c.household_id = items.household_id and c.seed_key = 'chilled')
where household_id = (select id from ha) and name = 'Milch';
set local session_replication_role = origin;

select pg_temp.login('00000000-0000-0000-0000-000000274b01');
create temp table ia as select public.suggest_index((select id from ha)) as x;
reset role;

select is(x -> 'history', jsonb_build_array(
    jsonb_build_array('Milch', null, null, '2', 'milch', now() - interval '3 days'),
    jsonb_build_array('Milch', 'Weihenstephan', '1,5 %', null, 'milch', now() - interval '5 days')),
  'history: the latest row per name, brand and properties, newest first') from ia;
select is(
  (select array_agg(e ->> 0 order by o) from jsonb_array_elements(x -> 'history') with ordinality j (e, o)),
  (select array_agg(s.name order by s.at desc) from (
     select distinct on (r.name, r.brand, r.properties) r.* from public.suggest_history((select id from ha)) r
     order by r.name, r.brand, r.properties, r.at desc) s),
  'what suggest_entries reduces suggest_history to') from ia;
select is(x -> 'brands', jsonb_build_array(jsonb_build_array('Lillydoo', public.brand_key('Lillydoo'))),
  'brands: the learned ones that are no ordinary word') from ia;
select is(x -> 'unserved', '["building", "electrical", "fasteners", "garden", "paint", "plumbing", "tools"]'::jsonb,
  'unserved: a grocery household has no hardware category') from ia;
select is(x -> 'known', jsonb_build_array(public.normalize_item_name('Kerzen')),
  'known: the names older than the history') from ia;
select is(x -> 'memory', jsonb_build_array(
    jsonb_build_array(public.item_key('Milch'), public.canonical_key('Milch'), (select id from public.stores where name = 'dm')),
    jsonb_build_array(public.item_key('Milch'), public.canonical_key('Milch'), (select id from public.stores where name = 'Krume'))),
  'memory: item key, canonical key and store, newest first, as suggest_store reads it') from ia;
select is(x -> 'cleared', jsonb_build_array(public.item_key('Brot')), 'cleared: the item keys set to no store') from ia;
select is(x -> 'stores', jsonb_build_array(jsonb_build_array('dm', (select id from public.stores where name = 'dm'))),
  'stores: the ones with a seed key') from ia;
select is(
  (select jsonb_agg(jsonb_build_array(k.id, public.category_usual_store(k.household_id, k.id), public.category_store(k.household_id, k.id))
     order by k.id::text collate "C")
   from public.categories k
   where k.household_id = (select id from ha)
     and coalesce(public.category_usual_store(k.household_id, k.id), public.category_store(k.household_id, k.id)) is not null),
  x -> 'categories',
  'categories: category_usual_store and category_store of each category that has either') from ia;
select is(x #> '{categories}' @> jsonb_build_array(jsonb_build_array(
    (select c.id from public.categories c where c.household_id = (select id from ha) and c.seed_key = 'chilled'),
    (select id from public.stores where name = 'Krume'), null)), true,
  'the usual store has the most memory times (Krume 3, dm 1)') from ia;
select is((select array_agg(k order by k) from jsonb_object_keys(x) k),
  array['brands', 'categories', 'cleared', 'history', 'known', 'memory', 'stores', 'unserved'],
  'and nothing else') from ia;

select pg_temp.login('00000000-0000-0000-0000-000000274b02');
select throws_ok($$select public.suggest_index((select id from ha))$$, '42501', 'not_a_member',
  'a non-member gets no index');
create temp table ib as select public.suggest_index((select id from hb)) as x;
select is(
  (select array_agg(e ->> 0) from jsonb_array_elements(x -> 'history') e), array['Geheimtee'],
  'another household sees only its own history') from ib;
select is(x -> 'brands', jsonb_build_array(jsonb_build_array('Geheimmarke', public.brand_key('Geheimmarke'))),
  'and its own brands') from ib;
select is(x -> 'known', '[]'::jsonb, 'and its own older names') from ib;
select is(
  jsonb_build_array(x #>> '{memory,0,0}', x -> 'cleared', x #>> '{stores,0,0}', jsonb_array_length(x -> 'memory')),
  jsonb_build_array(public.item_key('Geheimtee'), jsonb_build_array(public.item_key('Geheimbrot')), 'edeka', 1),
  'and its own store memory, cleared keys and stores') from ib;
reset role;

set local role anon;
select throws_ok($$select public.suggest_index('00000000-0000-0000-0000-000000000000')$$, '42501', null,
  'signed out, no index');
reset role;

select * from finish();
rollback;
