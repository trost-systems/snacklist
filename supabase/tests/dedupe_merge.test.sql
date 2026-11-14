-- Job 32b: the duplicate hint's similar_items, merge_items (one transaction, merge rule) and
-- unmerge_items (both rows back exactly), and that both stay inside the household.
begin;
select plan(58);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'peter@example.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'lea@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Trost');
create temp table inv as select * from public.create_invite((select id from ha));
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
do $$ begin perform public.join_household((select code from inv)); end $$;
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb as select id from public.create_household('Bob');
grant select on ha, hb to authenticated;

-- Peter has Möhren on the list; Lea adds Karotten (another spelling of the same thing).
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
insert into public.items (id, household_id, name, quantity) select '10000000-0000-4000-8000-000000000001', id, 'Möhren', '500 g' from ha;
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
insert into public.items (id, household_id, name, quantity) select '10000000-0000-4000-8000-000000000002', id, 'Karotten', '1 kg' from ha;
insert into public.items (id, household_id, name) select '10000000-0000-4000-8000-000000000003', id, 'Milch' from ha;

-- similar_items ----------------------------------------------------------------------------
select is(
  (select array_agg(name) from public.similar_items('10000000-0000-4000-8000-000000000002')),
  array['Möhren'], 'Karotten finds the open Möhren'
);
select is(
  (select count(*)::int from public.similar_items('10000000-0000-4000-8000-000000000003')), 0,
  'Milch has nothing similar'
);
insert into public.items (id, household_id, name, properties) select '10000000-0000-4000-8000-000000000004', id, 'Windeln', 'Größe 3' from ha;
insert into public.items (id, household_id, name, properties) select '10000000-0000-4000-8000-000000000005', id, 'Windeln', 'Größe 4' from ha;
insert into public.items (id, household_id, name) select '10000000-0000-4000-8000-000000000006', id, 'Windeln' from ha;
select is(
  (select count(*)::int from public.similar_items('10000000-0000-4000-8000-000000000005')
   where id = '10000000-0000-4000-8000-000000000004'), 0,
  'different properties tell items apart (Größe 3 vs Größe 4)'
);
select is(
  (select count(*)::int from public.similar_items('10000000-0000-4000-8000-000000000006')), 2,
  'an item without details is similar to both sizes'
);
update public.items set status = 'bought' where id = '10000000-0000-4000-8000-000000000004';
select is(
  (select count(*)::int from public.similar_items('10000000-0000-4000-8000-000000000006')), 1,
  'only open items count'
);
delete from public.items where name = 'Windeln';

-- merge_quantities (the full table is supabase/tests/merge_quantities.tsv) ------------------
select is(public.merge_quantities('500 g', '1 kg'), '1,5 kg', 'g and kg sum');
select is(public.merge_quantities('1,5 l', '500 ml'), '2 l', 'l and ml sum');
select is(public.merge_quantities('2', '3 Stück'), '5 Stück', 'pieces sum');
select is(public.merge_quantities(null, null), '2', 'no quantities: 1 + 1 = 2');
select is(public.merge_quantities('1 Bund', '500 g'), '1 Bund + 500 g', 'other units: a note');
select is(public.merge_quantities('2 Stück', '1 kg'), '2 Stück + 1 kg', 'Stück never sums with g');
select is(public.merge_quantities(null, '500 g'), '500 g', 'no quantity with a unit: the unit stays');
select throws_ok($$ select public.merge_quantities('Großpackung mit vielen Rollen', 'Kleinpackung mit vielen Rollen') $$,
  '22001', null, 'a merged quantity longer than the column is refused');

-- merge_items --------------------------------------------------------------------------------
create temp table karotten as select * from public.items where id = '10000000-0000-4000-8000-000000000002';
create temp table moehren as select * from public.items where id = '10000000-0000-4000-8000-000000000001';
grant select on karotten, moehren to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table merged as select public.merge_items(
  '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'
) as r;
grant select on merged to authenticated;
select is((select r -> 'kept' ->> 'quantity' from merged), '1,5 kg', 'the merge answers with the kept row');
select ok((select (r -> 'merged') = 'null'::jsonb from merged), 'and no merged row');
select is((select name from public.items where id = '10000000-0000-4000-8000-000000000001'), 'Möhren',
  'the open item keeps its text');
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000001'), '1,5 kg',
  '500 g + 1 kg = 1,5 kg');
select is((select count(*)::int from public.items where id = '10000000-0000-4000-8000-000000000002'), 0,
  'the second item is gone');
select is((select count(*)::int from public.items where household_id = (select id from ha) and status = 'active'), 2,
  'one Möhren and the Milch are left');
select is(
  public.merge_items('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'),
  (select r from merged), 'a retried merge changes nothing and answers the same'
);
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000001'), '1,5 kg',
  'the retry did not sum again');
select is((select count(*)::int from public.item_merges), 1, 'members see their household''s merge');
select throws_ok($$ insert into public.item_merges (id, household_id, kept_id, kept_before, kept_after, merged_row)
                    select gen_random_uuid(), id, gen_random_uuid(), '{}', '{}', '{}' from ha $$,
  '42501', null, 'clients cannot write merges directly');

-- unmerge_items ------------------------------------------------------------------------------
-- Lea undoes Peter's merge (she synced it): both rows come back exactly.
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
create temp table undone as select public.unmerge_items('20000000-0000-4000-8000-000000000001') as r;
grant select on undone to authenticated;
select is((select r -> 'merged' ->> 'name' from undone), 'Karotten', 'the undo answers with the restored row');
select is((select r -> 'kept' ->> 'quantity' from undone), '500 g', 'and the kept row as it was');
select is(
  (select (name, quantity, brand, properties, category_id, store_id, sort_key, status, added_by, created_at, categorized_via, canonical_key)::text
   from public.items where id = '10000000-0000-4000-8000-000000000002'),
  (select (name, quantity, brand, properties, category_id, store_id, sort_key, status, added_by, created_at, categorized_via, canonical_key)::text
   from karotten),
  'Karotten is back with its id, text, quantity, category, store, place, author and time'
);
select is(
  (select (name, quantity, brand, properties, category_id, store_id, sort_key, status, added_by, created_at)::text
   from public.items where id = '10000000-0000-4000-8000-000000000001'),
  (select (name, quantity, brand, properties, category_id, store_id, sort_key, status, added_by, created_at)::text
   from moehren),
  'Möhren is back as it was'
);
select is((select added_by from public.items where id = '10000000-0000-4000-8000-000000000002'),
  '00000000-0000-0000-0000-0000000000a2'::uuid, 'who added the second item survives the undo');
select is(public.unmerge_items('20000000-0000-4000-8000-000000000001'), (select r from undone),
  'a retried undo changes nothing and answers the same');
select is((select count(*)::int from public.items where household_id = (select id from ha) and status = 'active'), 3,
  'three items again, nothing doubled');
select throws_ok($$ select public.unmerge_items(gen_random_uuid()) $$, 'P0002', null, 'an unknown merge');

-- An edit after the merge wins over the undo's quantity; the second item still comes back.
do $$ begin perform public.merge_items('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'); end $$;
update public.items set quantity = '2 kg' where id = '10000000-0000-4000-8000-000000000001';
do $$ begin perform public.unmerge_items('20000000-0000-4000-8000-000000000002'); end $$;
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000001'), '2 kg',
  'a quantity changed after the merge is kept');
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000002'), '1 kg',
  'the second item is back anyway');

-- A kept item deleted after the merge stays deleted; the second item comes back.
update public.items set quantity = '500 g' where id = '10000000-0000-4000-8000-000000000001';
do $$ begin perform public.merge_items('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'); end $$;
delete from public.items where id = '10000000-0000-4000-8000-000000000001';
do $$ begin perform public.unmerge_items('20000000-0000-4000-8000-000000000003'); end $$;
select is((select count(*)::int from public.items where id = '10000000-0000-4000-8000-000000000001'), 0,
  'a kept item deleted since stays deleted');
select is((select count(*)::int from public.items where id = '10000000-0000-4000-8000-000000000002'), 1,
  'no item is dropped');
insert into public.items (id, household_id, name, quantity) select '10000000-0000-4000-8000-000000000001', id, 'Möhren', '1 Bund' from ha;

-- Merge rule cases through the RPC.
do $$ begin perform public.merge_items('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'); end $$;
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000001'), '1 Bund + 1 kg',
  'a bunch and a kilo: the other quantity becomes a note');
do $$ begin perform public.unmerge_items('20000000-0000-4000-8000-000000000004'); end $$;
update public.items set quantity = null where id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002');
do $$ begin perform public.merge_items('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'); end $$;
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000001'), '2',
  'two items without a quantity merge as 2');
do $$ begin perform public.unmerge_items('20000000-0000-4000-8000-000000000005'); end $$;
select is((select quantity from public.items where id = '10000000-0000-4000-8000-000000000001'), null,
  'and the undo clears it again');

-- Refusals: nothing changes.
select throws_ok($$ select public.merge_items(gen_random_uuid(), '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001') $$,
  '22023', null, 'an item cannot merge into itself');
select throws_ok($$ select public.merge_items(gen_random_uuid(), '10000000-0000-4000-8000-000000000001', gen_random_uuid()) $$,
  'P0002', null, 'a gone item: nothing to merge');
update public.items set status = 'bought' where id = '10000000-0000-4000-8000-000000000003';
select throws_ok($$ select public.merge_items(gen_random_uuid(), '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003') $$,
  '22023', null, 'a ticked item does not merge');
update public.items set quantity = 'Großpackung mit vielen Rollen' where id = '10000000-0000-4000-8000-000000000001';
update public.items set quantity = 'Kleinpackung mit vielen Rollen' where id = '10000000-0000-4000-8000-000000000002';
select throws_ok($$ select public.merge_items(gen_random_uuid(), '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002') $$,
  '22001', null, 'a merged quantity too long for the column is refused');
select is((select count(*)::int from public.items where id = '10000000-0000-4000-8000-000000000002'), 1,
  'and both items stay');

-- Job 246: a merge keeps no price. Both rows priced, merged, then undone.
update public.items set quantity = null where id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002');
update public.items set price_unit_micros = case id when '10000000-0000-4000-8000-000000000001' then 1290000 else 990000 end,
  price_basis = 'unit', price_per = 'piece', price_currency = 'EUR', priced_at = now()
where id in ('10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002');
do $$ begin perform public.merge_items('20000000-0000-4000-8000-000000000246', '10000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002'); end $$;
select is((select merged_row ->> 'name' from public.item_merges where id = '20000000-0000-4000-8000-000000000246'),
  'Karotten', 'the merge is stored, with the merged-in row');
select is(
  (select count(*)::int from public.item_merges m, jsonb_object_keys(m.kept_before || m.merged_row || m.kept_after) k
   where m.id = '20000000-0000-4000-8000-000000000246' and (k like 'price%' or k = 'priced_at')), 0,
  'a merge stores neither row''s price');
select is((select price_unit_micros from public.items where id = '10000000-0000-4000-8000-000000000001'), 1290000::bigint,
  'the kept item keeps its own price');
update public.items set price_unit_micros = null, price_basis = null, price_per = null, price_currency = null, priced_at = null
where id = '10000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.item_merges where to_jsonb(item_merges)::text ~ '(1290000|990000)'), 0,
  'with the kept item''s price cleared, no merge holds either price');
do $$ begin perform public.unmerge_items('20000000-0000-4000-8000-000000000246'); end $$;
select is(
  (select (price_unit_micros, price_basis, price_per, price_currency, priced_at) is null
   from public.items where id = '10000000-0000-4000-8000-000000000002'), true,
  'the undo brings the merged-in item back without a price');
select is((select name from public.items where id = '10000000-0000-4000-8000-000000000002'), 'Karotten',
  'and with the rest of its row');

-- Job 246: merges go after 30 days, every household's, daily.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select throws_ok($$ select public.purge_item_merges() $$, '42501', null, 'members cannot run the purge');
reset role;
update public.item_merges set created_at = now() - interval '30 days 1 minute' where id = '20000000-0000-4000-8000-000000000246';
create temp table newer as select id from public.item_merges where created_at > now() - interval '30 days';
select is(public.purge_item_merges(), 1, 'the purge deletes the merge older than 30 days');
select set_eq('select id from public.item_merges', 'select id from newer', 'and keeps the newer ones');
select results_eq(
  $$ select schedule, command, active from cron.job where jobname = 'purge-item-merges' $$,
  $$ values ('53 3 * * *'::text, 'select public.purge_item_merges()'::text, true) $$,
  'the purge runs daily at 03:53 UTC');

-- RLS: Bob's household and Peter's do not mix.
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
insert into public.items (id, household_id, name) select '10000000-0000-4000-8000-0000000000b1', id, 'Karotten' from hb;
select throws_ok($$ select public.merge_items(gen_random_uuid(), '10000000-0000-4000-8000-0000000000b1', '10000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'merging another household''s item is denied');
select throws_ok($$ select public.unmerge_items('20000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'undoing another household''s merge is denied');
select throws_ok($$ select public.merge_items('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-0000000000b1', '10000000-0000-4000-8000-0000000000b1') $$,
  '42501', null, 'replaying another household''s merge id is denied');
select is((select count(*)::int from public.item_merges), 0, 'another household''s merges are invisible');
select is((select count(*)::int from public.similar_items('10000000-0000-4000-8000-0000000000b1')), 0,
  'similar items never come from another household');

select * from finish();
rollback;
