-- Job 336: MCP requests per user (mcp_rate, mcp_take_call, purge_mcp_rate) and items.created_at
-- kept within 2000-01-01 .. tomorrow (items_before_write).
begin;
select plan(20);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000336a1', 'peter336@example.com'),
  ('00000000-0000-0000-0000-0000000336b1', 'lea336@example.com');

-- Clients reach nothing of it ----------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000336a1","role":"authenticated"}', true);
select throws_ok($$ select * from public.mcp_rate $$, '42501', null, 'clients cannot read mcp_rate');
select throws_ok($$ select public.mcp_take_call('00000000-0000-0000-0000-0000000336a1', 20, 60, 1000) $$,
  '42501', null, 'nor count a call');
select throws_ok($$ select public.purge_mcp_rate() $$, '42501', null, 'nor purge');
reset role;

-- The bucket: 3 at once, then one a second ---------------------------------------------------

select is(
  array(select public.mcp_take_call('00000000-0000-0000-0000-0000000336a1', 3, 60, 1000) from generate_series(1, 4)),
  array[null, null, null, 1]::integer[],
  'a burst of 3 passes, the 4th waits a second');
select is((select requests from public.mcp_rate where user_id = '00000000-0000-0000-0000-0000000336a1'), 3,
  'a refused call is not counted');
select is(public.mcp_take_call('00000000-0000-0000-0000-0000000336b1', 3, 60, 1000), null,
  'another user has a bucket of their own');
update public.mcp_rate set refilled_at = refilled_at - interval '2 seconds'
where user_id = '00000000-0000-0000-0000-0000000336a1';
select is(
  array(select public.mcp_take_call('00000000-0000-0000-0000-0000000336a1', 3, 60, 1000) from generate_series(1, 3)),
  array[null, null, 1]::integer[],
  'two seconds later two more pass');

-- The day ----------------------------------------------------------------------------------

update public.mcp_rate set requests = 1000, tokens = 3 where user_id = '00000000-0000-0000-0000-0000000336a1';
select cmp_ok(public.mcp_take_call('00000000-0000-0000-0000-0000000336a1', 3, 60, 1000), '>', 1,
  'a used-up day waits for the next UTC day, though the bucket is full');
select is(public.mcp_take_call('00000000-0000-0000-0000-0000000336a1', 3, 60, 1000),
  ceil(extract(epoch from (((now() at time zone 'utc')::date + 1)::timestamp at time zone 'utc') - now()))::integer,
  'exactly until the next UTC day');
update public.mcp_rate set day = day - 1 where user_id = '00000000-0000-0000-0000-0000000336a1';
select is(public.mcp_take_call('00000000-0000-0000-0000-0000000336a1', 3, 60, 1000), null,
  'a new day starts a new count');
select is((select requests from public.mcp_rate where user_id = '00000000-0000-0000-0000-0000000336a1'), 1,
  'counted from one');

-- Retention --------------------------------------------------------------------------------

update public.mcp_rate set refilled_at = now() - interval '25 hours'
where user_id = '00000000-0000-0000-0000-0000000336b1';
select is(public.purge_mcp_rate(), 1, 'the daily purge takes a counter unused for a day');
select ok(exists (select from public.mcp_rate where user_id = '00000000-0000-0000-0000-0000000336a1'),
  'and leaves a fresh one');
select is((select count(*)::int from cron.job where jobname = 'purge-mcp-rate'), 1, 'scheduled once');
delete from auth.users where id = '00000000-0000-0000-0000-0000000336a1';
select ok(not exists (select from public.mcp_rate where user_id = '00000000-0000-0000-0000-0000000336a1'),
  'the counter goes with the account');

-- items.created_at ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000336b1","role":"authenticated"}', true);
select public.create_household('Lea');
insert into public.items (household_id, list_id, name, created_at)
select m.household_id, public.first_list(m.household_id), v.name, v.at
from public.household_members m,
  (values ('Unendlich', 'infinity'::timestamptz), ('Minus', '-infinity'), ('Fern', '10000-01-01Z'),
          ('Alt', '0001-01-01Z'), ('Morgen', now() + interval '2 days'),
          ('Gestern', now() - interval '1 day'), ('Bald', now() + interval '1 hour')) v (name, at)
where m.user_id = '00000000-0000-0000-0000-0000000336b1';
select is(
  (select array_agg(name order by name) from public.items
   where household_id in (select household_id from public.household_members
                          where user_id = '00000000-0000-0000-0000-0000000336b1')
     and created_at = now()),
  array['Alt', 'Fern', 'Minus', 'Morgen', 'Unendlich'],
  'a member''s insert outside 2000 .. tomorrow gets now()');
select is((select created_at from public.items where name = 'Gestern'), now() - interval '1 day',
  'a past moment stays');
select is((select created_at from public.items where name = 'Bald'), now() + interval '1 hour',
  'so does one within the day ahead');
reset role;

-- A row from before the migration: written past the trigger, repaired by the next update.
alter table public.items disable trigger user;
update public.items set created_at = 'infinity' where name = 'Gestern';
alter table public.items enable trigger user;
update public.items set quantity = '2' where name = 'Gestern';
select is((select created_at from public.items where name = 'Gestern'), now(),
  'an update gives an infinite created_at now()');
update public.items set created_at = 'infinity' where name = 'Bald';
select is((select created_at from public.items where name = 'Bald'), now() + interval '1 hour',
  'and still keeps a sane one');

select * from finish();
rollback;
