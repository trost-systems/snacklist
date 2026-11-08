-- Job 169b wave 3, part L: "Ich bringe" (docs/households/W3.md). A member says they bring an
-- open item, optionally with an amount ("2 Kuchen"). A claim is a person's promise: the members
-- of the household see it, and it ends when the item is ticked or deleted or the claimant leaves
-- or is removed. Written through claim_item and unclaim_item only; MCP does not expose it.

create table public.item_claims (
  item_id uuid not null references public.items (id) on delete cascade,
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  quantity text check (quantity is null or char_length(quantity) between 1 and 40),
  created_at timestamptz not null default now(),
  primary key (item_id, user_id)
);
create index item_claims_household on public.item_claims (household_id);
create index item_claims_user on public.item_claims (user_id, household_id);
alter table public.item_claims enable row level security;
revoke all on public.item_claims from public, anon, authenticated;
grant select on public.item_claims to authenticated;
create policy item_claims_member on public.item_claims for select to authenticated
  using (public.is_household_member(household_id));
alter publication supabase_realtime add table public.item_claims;

comment on table public.item_claims is
  'Job 169b: who brings an open item ("Ich bringe"), with an optional amount. Personal data of the claimant; ends with the tick, the item or the membership.';

-- Claims [p_item] for the caller, or changes the amount of their claim; the same call twice
-- leaves one claim. item_not_found for no such item, not_a_member for another household's,
-- not_open for a ticked one, value_too_long past 40 characters.
create function public.claim_item(p_item uuid, p_quantity text) returns public.item_claims
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.items;
  v_quantity text := nullif(btrim(p_quantity), '');
  v_claim public.item_claims;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_quantity) > 40 then
    raise exception 'value_too_long: quantity <= 40 characters' using errcode = '22001';
  end if;
  -- The membership lock waits for a leave or removal in flight, the share lock for a tick or
  -- delete: a claim outlives none of them.
  perform public.lock_memberships(auth.uid());
  select * into v_item from public.items i where i.id = p_item for share;
  if not found then
    raise exception 'item_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_member(v_item.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if v_item.status <> 'active' then
    raise exception 'not_open' using errcode = '22023';
  end if;
  insert into public.item_claims as c (item_id, household_id, user_id, quantity)
  values (p_item, v_item.household_id, auth.uid(), v_quantity)
  on conflict (item_id, user_id) do update set quantity = excluded.quantity
    where c.quantity is distinct from excluded.quantity;
  select * into v_claim from public.item_claims c where c.item_id = p_item and c.user_id = auth.uid();
  return v_claim;
end $$;
revoke execute on function public.claim_item(uuid, text) from public, anon;
grant execute on function public.claim_item(uuid, text) to authenticated;

-- Ends the caller's claim on [p_item]; without one, nothing happens.
create function public.unclaim_item(p_item uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from public.item_claims c where c.item_id = p_item and c.user_id = auth.uid();
end $$;
revoke execute on function public.unclaim_item(uuid) from public, anon;
grant execute on function public.unclaim_item(uuid) to authenticated;

-- A tick ends the item's claims (a delete does through the foreign key). An item never changes
-- household in the app; should a write move one, its claims end too.
create function public.items_end_claims() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.item_claims c where c.item_id = new.id;
  return null;
end $$;
revoke execute on function public.items_end_claims() from public, anon, authenticated;
create trigger items_end_claims after update of status, household_id on public.items
  for each row
  when ((new.status = 'bought' and old.status <> 'bought') or new.household_id <> old.household_id)
  execute function public.items_end_claims();

-- Leaving or being removed ends the claimant's claims in that household.
create function public.household_member_end_claims() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.item_claims c where c.user_id = old.user_id and c.household_id = old.household_id;
  return null;
end $$;
revoke execute on function public.household_member_end_claims() from public, anon, authenticated;
create trigger household_members_end_claims after delete on public.household_members
  for each row execute function public.household_member_end_claims();
