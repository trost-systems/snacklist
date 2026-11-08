create schema t;
create or replace function t.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.uid', true),'')::uuid $$;
create role app_user nologin; grant app_user to current_user;
create table households (id uuid primary key, name text);
create table household_members (household_id uuid references households on delete cascade, user_id uuid not null unique,
  role text default 'member', joined_at timestamptz not null default now(), primary key (household_id, user_id));
create function is_household_member(h uuid) returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from household_members where household_id = h and user_id = t.uid()) $$;
alter table households enable row level security;
alter table household_members enable row level security;
create policy hs on households for select using (is_household_member(id));
create policy hm on household_members for select using (is_household_member(household_id));
grant usage on schema t to app_user; grant select on households, household_members to app_user;
insert into households values ('00000000-0000-0000-0000-0000000000a1','Zuhause'),('00000000-0000-0000-0000-0000000000b2','Sommerfest');
-- Peter p, Lea l in Zuhause
insert into household_members values ('00000000-0000-0000-0000-0000000000a1','11111111-0000-0000-0000-000000000001','owner'),
 ('00000000-0000-0000-0000-0000000000a1','11111111-0000-0000-0000-000000000002','member'),
 ('00000000-0000-0000-0000-0000000000b2','11111111-0000-0000-0000-000000000003','owner');

-- the migration
alter table household_members drop constraint household_members_user_id_key;
alter table household_members add column is_default boolean not null default false;
update household_members set is_default = true;
create unique index one_default on household_members (user_id) where is_default;
drop policy hm on household_members;
create policy hm on household_members for select using (
  is_household_member(household_id) and (user_id <> t.uid() or is_default));
create function household_members_of(h uuid) returns table (user_id uuid, role text) language sql stable security definer set search_path = public as
  $$ select m.user_id, m.role from household_members m where m.household_id = h and is_household_member(h) $$;
grant execute on function household_members_of(uuid) to app_user;
-- Peter joins Sommerfest as a second, non-default household
-- every membership lost by any path (leave, remove, household deleted, account deleted) hands
-- the default to the user's oldest remaining membership in the same transaction
create function promote_default() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.is_default then
    update household_members set is_default = true
     where (household_id, user_id) = (select m.household_id, m.user_id from household_members m
       where m.user_id = old.user_id order by m.joined_at, m.household_id limit 1 for update);
  end if;
  return null;
end $$;
create trigger household_members_promote_default after delete on household_members
  for each row execute function promote_default();
insert into households values ('00000000-0000-0000-0000-0000000000c3','Eltern');
insert into household_members (household_id, user_id, role, is_default, joined_at) values
  ('00000000-0000-0000-0000-0000000000b2','11111111-0000-0000-0000-000000000001','member',false, now() + interval '1 day'),
  ('00000000-0000-0000-0000-0000000000c3','11111111-0000-0000-0000-000000000001','member',false, now() + interval '2 days');

set role app_user;
set request.uid = '11111111-0000-0000-0000-000000000001';
\echo 'old app query (own rows, needs exactly 1):'
select h.name from household_members m join households h on h.id = m.household_id where m.user_id = t.uid();
\echo 'is_household_member for both (both true):'
select is_household_member('00000000-0000-0000-0000-0000000000a1') a, is_household_member('00000000-0000-0000-0000-0000000000b2') b;
\echo 'plain select of Sommerfest members (hides Peter):'
select user_id from household_members where household_id = '00000000-0000-0000-0000-0000000000b2';
\echo 'household_members_of Sommerfest (Peter + owner):'
select user_id, role from household_members_of('00000000-0000-0000-0000-0000000000b2');
set request.uid = '11111111-0000-0000-0000-000000000002';
\echo 'Lea: household_members_of Sommerfest (none, not a member):'
select count(*) from household_members_of('00000000-0000-0000-0000-0000000000b2');
\echo 'Lea: Zuhause members incl. Peter (2):'
select count(*) from household_members where household_id = '00000000-0000-0000-0000-0000000000a1';

reset role;
\echo 'Peter leaves Zuhause (his default):'
delete from household_members where household_id = '00000000-0000-0000-0000-0000000000a1' and user_id = '11111111-0000-0000-0000-000000000001';
set role app_user;
set request.uid = '11111111-0000-0000-0000-000000000001';
\echo 'old app query after the leave (needs exactly 1, the oldest remaining: Sommerfest):'
select h.name from household_members m join households h on h.id = m.household_id where m.user_id = t.uid();
reset role;
\echo 'Sommerfest is deleted as a whole (cascade):'
delete from households where id = '00000000-0000-0000-0000-0000000000b2';
set role app_user;
set request.uid = '11111111-0000-0000-0000-000000000001';
\echo 'old app query after the cascade (needs exactly 1: Eltern):'
select h.name from household_members m join households h on h.id = m.household_id where m.user_id = t.uid();
reset role;
\echo 'Peter leaves his last household: no default row left, no error (0):'
delete from household_members where user_id = '11111111-0000-0000-0000-000000000001';
select count(*) from household_members where user_id = '11111111-0000-0000-0000-000000000001';
\echo 'Lea never left: still exactly one default (1):'
select count(*) from household_members where user_id = '11111111-0000-0000-0000-000000000002' and is_default;
