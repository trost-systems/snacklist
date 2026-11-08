create table households (id int primary key);
create table household_members (household_id int references households on delete cascade, user_id int not null,
  joined_at timestamptz not null, is_default boolean not null default false, primary key (household_id, user_id));
create unique index one_default on household_members (user_id) where is_default;
create function promote_default() returns trigger language plpgsql as $$
begin
  if old.is_default then
    update household_members set is_default = true
     where (household_id, user_id) = (select m.household_id, m.user_id from household_members m
       where m.user_id = old.user_id order by m.joined_at, m.household_id limit 1 LOCKCLAUSE);
  end if;
  return null;
end $$;
create trigger promote after delete on household_members for each row execute function promote_default();
insert into households values (1),(2),(3);
insert into household_members values (1,7,now(),true),(2,7,now()+interval '1 day',false),(3,7,now()+interval '2 days',false);
