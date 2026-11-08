-- Job 169b wave 3, part L: "Ich bringe" claims (docs/households/W3.md). A member claims an open
-- item with an optional amount; the same claim twice is one; a claim ends with the tick, the item,
-- its list, or the claimant's membership.
begin;
select plan(27);

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

-- Every claim in the database, as "item name:claimant's email:amount", for checks across RLS.
create function pg_temp.claims() returns text language sql security definer as $$
  select coalesce(string_agg(i.name || ':' || split_part(u.email, '@', 1) || ':' || coalesce(c.quantity, '-'),
    ', ' order by i.name, u.email), '')
  from public.item_claims c join public.items i on i.id = c.item_id join auth.users u on u.id = c.user_id
$$;

create function pg_temp.item(p_name text) returns uuid language sql security definer as $$
  select id from public.items where name = p_name
$$;

grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'olga@example.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'mia@example.com'),
  ('00000000-0000-0000-0000-0000000000a3', 'tom@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

-- The Sportverein: Olga owns it, Mia and Tom joined. Mia has a household of her own too.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table club as select id from public.create_household('Sportverein');
create temp table inv_mia as select code from public.create_invite((select id from club));
create temp table inv_tom as select code from public.create_invite((select id from club));
insert into public.items (household_id, name) select id, n from club, unnest(array['Kuchen', 'Salat', 'Grillkohle', 'Becher', 'Servietten']) n;
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
create temp table mias as select id from public.create_household('Bei Mia');
insert into public.items (household_id, name) select id, 'Blumen' from mias;
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table bobs as select id from public.create_household('Bob');
grant select on club, inv_mia, inv_tom, mias, bobs to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select public.accept_invite((select code from inv_mia), p_mode => 'add');
select pg_temp.login('00000000-0000-0000-0000-0000000000a3');
select public.accept_invite((select code from inv_tom), p_mode => 'add');

-- Claiming ----------------------------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
create temp table c1 as select * from public.claim_item(pg_temp.item('Kuchen'), ' 2 Kuchen ');
grant select on c1 to authenticated;
select results_eq($$ select household_id, user_id, quantity from c1 $$,
  $$ values ((select id from club), '00000000-0000-0000-0000-0000000000a2'::uuid, '2 Kuchen') $$,
  'claim_item answers the claim, its amount trimmed');
select lives_ok($$ select public.claim_item(pg_temp.item('Kuchen'), '2 Kuchen') $$, 'the same claim again');
select is(pg_temp.claims(), 'Kuchen:mia:2 Kuchen', 'is still one claim');
select is((select quantity from public.claim_item(pg_temp.item('Kuchen'), '1 Kuchen')), '1 Kuchen',
  'claiming again changes the amount');
select is((select quantity from public.claim_item(pg_temp.item('Salat'), '  ')), null, 'a blank amount is none');
select pg_temp.login('00000000-0000-0000-0000-0000000000a3');
select public.claim_item(pg_temp.item('Kuchen'), '1');
select public.claim_item(pg_temp.item('Grillkohle'), null);
select public.claim_item(pg_temp.item('Becher'), null);
select is((select count(*)::int from public.item_claims), 5, 'members see every claim of the household');
select is(pg_temp.claims(),
  'Becher:tom:-, Grillkohle:tom:-, Kuchen:mia:1 Kuchen, Kuchen:tom:1, Salat:mia:-', 'two bring Kuchen');

select throws_ok($$ select public.claim_item(gen_random_uuid(), null) $$, 'P0002', 'item_not_found',
  'claiming an unknown item');
select throws_ok($$ select public.claim_item(pg_temp.item('Blumen'), null) $$, '42501', 'not_a_member',
  'claiming another household''s item is refused');
select throws_ok($$ select public.claim_item(pg_temp.item('Becher'), repeat('x', 41)) $$, '22001', null,
  'an amount past 40 characters is refused');
select throws_ok($$ insert into public.item_claims (item_id, household_id, user_id)
  values (pg_temp.item('Servietten'), (select id from club), auth.uid()) $$, '42501', null,
  'claims are written through claim_item only');
select throws_ok($$ delete from public.item_claims $$, '42501', null, 'and removed through unclaim_item');
select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from public.item_claims), 0, 'another household sees no claim');
select lives_ok($$ select public.unclaim_item(pg_temp.item('Kuchen')) $$,
  'unclaiming without a claim does nothing');
select ok(pg_temp.claims() like '%Kuchen:mia%', 'and touches nobody else''s claim');

-- Unclaiming ----------------------------------------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select public.unclaim_item(pg_temp.item('Salat'));
select lives_ok($$ select public.unclaim_item(pg_temp.item('Salat')) $$, 'unclaiming twice is fine');
select is(pg_temp.claims(), 'Becher:tom:-, Grillkohle:tom:-, Kuchen:mia:1 Kuchen, Kuchen:tom:1',
  'only Mia''s Salat claim ended');

-- A claim ends with the tick, the item and its list --------------------------------------------

update public.items set status = 'bought' where id = pg_temp.item('Kuchen');
select is(pg_temp.claims(), 'Becher:tom:-, Grillkohle:tom:-', 'ticking ends every claim on the item');
update public.items set status = 'active' where id = pg_temp.item('Kuchen');
select is(pg_temp.claims(), 'Becher:tom:-, Grillkohle:tom:-', 'unticking brings none back');
update public.items set status = 'bought' where id = pg_temp.item('Salat');
select throws_ok($$ select public.claim_item(pg_temp.item('Salat'), null) $$, '22023', 'not_open',
  'a ticked item cannot be claimed');
update public.items set quantity = '3' where id = pg_temp.item('Grillkohle');
select is(pg_temp.claims(), 'Becher:tom:-, Grillkohle:tom:-', 'other edits keep the claims');
delete from public.items where id = pg_temp.item('Grillkohle');
select is(pg_temp.claims(), 'Becher:tom:-', 'deleting an item ends its claims');
select public.create_list((select id from club), 'Sommerfest', 'f0000000-0000-4000-8000-000000000001');
select public.put_item(p_id => '10000000-0000-4000-8000-000000000001', p_household => (select id from club),
  p_list => 'f0000000-0000-4000-8000-000000000001', p_name => 'Bierbänke');
select public.claim_item('10000000-0000-4000-8000-000000000001', null);
select public.delete_list('f0000000-0000-4000-8000-000000000001');
select is(pg_temp.claims(), 'Becher:tom:-', 'deleting a list ends the claims on its items');

-- A claim ends with the claimant's membership --------------------------------------------------

select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select public.claim_item(pg_temp.item('Blumen'), null);
select public.claim_item(pg_temp.item('Servietten'), '100');
select is(pg_temp.claims(), 'Becher:tom:-, Blumen:mia:-, Servietten:mia:100', 'Mia brings for two households');
select public.leave_household((select id from club));
select is(pg_temp.claims(), 'Becher:tom:-, Blumen:mia:-', 'leaving ends her claims in that household only');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select public.claim_item(pg_temp.item('Servietten'), null);
select public.remove_member((select id from club), '00000000-0000-0000-0000-0000000000a3');
select is(pg_temp.claims(), 'Blumen:mia:-, Servietten:olga:-', 'a removal ends the removed member''s claims');
select pg_temp.as_postgres();
delete from auth.users where id = '00000000-0000-0000-0000-0000000000a1';
select is(pg_temp.claims(), 'Blumen:mia:-', 'a deleted account takes its claims');

select * from finish();
rollback;
