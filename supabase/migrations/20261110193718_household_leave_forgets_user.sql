-- Legal review N-115: leaving a household or being removed from it unlinks the user from that
-- household's content, as deleting the account does (foreign keys on delete set null, and
-- delete_account and item_merges_forget_user for the columns without one). The items, lists and
-- history stay for the other members, without the user's id. The user's other households keep it.
--
-- Not touched: households.archived_by (set only once nobody is left), purchases.user_id and
-- granted_by (the buyer keeps their plan while the account exists), entitlements.tester.

-- items_before_write keeps added_by and bought_by on every update but the null an account
-- deletion's foreign keys write. It now also lets a user's id go once they are no longer a member
-- of the item's household. Otherwise unchanged from 20261030110000_classifier_variants.sql.
create or replace function public.items_before_write() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_guess record;
begin
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - '{added_by,bought_by}'::text[]) = (to_jsonb(old) - '{added_by,bought_by}'::text[])
     and (new.added_by, new.bought_by) is distinct from (old.added_by, old.bought_by)
     and (new.added_by is not distinct from old.added_by
          or (new.added_by is null
              and (not exists (select from auth.users u where u.id = old.added_by)
                   or not exists (select from public.household_members m
                                  where m.household_id = old.household_id and m.user_id = old.added_by))))
     and (new.bought_by is not distinct from old.bought_by
          or (new.bought_by is null
              and (not exists (select from auth.users u where u.id = old.bought_by)
                   or not exists (select from public.household_members m
                                  where m.household_id = old.household_id and m.user_id = old.bought_by))))
  then
    return new;
  end if;
  new.name := btrim(new.name);
  new.quantity := nullif(btrim(new.quantity), '');
  new.brand := nullif(btrim(new.brand), '');
  new.properties := nullif(btrim(new.properties), '');
  new.normalized_name := public.normalize_item_name(new.name);
  if tg_op = 'INSERT' or new.category_id is null then
    v_guess := public.classify_item_detail(new.household_id, new.name);
    new.canonical_key := v_guess.canonical_key;
    if new.category_id is null then
      new.category_id := v_guess.category_id;
      new.categorized_via := v_guess.via;
    elsif tg_op = 'INSERT' then
      new.categorized_via := case when new.category_id = v_guess.category_id then v_guess.via else 'picked' end;
    end if;
  elsif new.name is distinct from old.name then
    new.canonical_key := public.canonical_key(new.name);
  end if;
  if tg_op = 'INSERT' and new.store_id is null then
    new.store_id := public.suggest_store(new.household_id, new.name);
  end if;
  if new.sort_key is null
     or (tg_op = 'UPDATE'
         and (new.store_id, new.category_id) is distinct from (old.store_id, old.category_id)
         and new.sort_key is not distinct from old.sort_key
         and coalesce(current_setting('family_groceries.sort_key', true), '') <> 'keep') then
    new.sort_key := coalesce(
      (select max(i.sort_key) from public.items i
       where i.household_id = new.household_id and i.category_id = new.category_id
         and i.store_id is not distinct from new.store_id and i.id <> new.id),
      0
    ) + 1024;
  end if;
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
    new.added_by := old.added_by;
    new.updated_at := now();
  end if;
  if new.status = 'bought' and (tg_op = 'INSERT' or old.status is distinct from 'bought') then
    new.bought_at := now();
    new.bought_by := auth.uid();
  elsif new.status = 'active' then
    new.bought_at := null;
    new.bought_by := null;
  end if;
  return new;
end $$;

create function public.household_member_forget_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_user text := old.user_id::text;
begin
  -- A deleted household takes its rows with it. The last member leaving archives or deletes it
  -- (leave_household_as): an archive is theirs to bring back as it was, and a delete goes anyway.
  if not exists (select from public.households h where h.id = old.household_id)
     or not exists (select from public.household_members m where m.household_id = old.household_id) then
    return null;
  end if;
  update public.items i set
    added_by = case when i.added_by = old.user_id then null else i.added_by end,
    bought_by = case when i.bought_by = old.user_id then null else i.bought_by end
  where i.household_id = old.household_id and old.user_id in (i.added_by, i.bought_by);
  update public.item_events e set actor = null
  where e.household_id = old.household_id and e.actor = old.user_id;
  update public.lists l set created_by = null
  where l.household_id = old.household_id and l.created_by = old.user_id;
  update public.item_merges m set
    merged_by = case when m.merged_by = old.user_id then null else m.merged_by end,
    merged_row = public.forget_user_in_row(m.merged_row, v_user),
    kept_before = public.forget_user_in_row(m.kept_before, v_user)
  where m.household_id = old.household_id
    and (m.merged_by = old.user_id
         or v_user in (m.merged_row ->> 'added_by', m.merged_row ->> 'bought_by',
                       m.kept_before ->> 'added_by', m.kept_before ->> 'bought_by'));
  update public.invites v set
    created_by = case when v.created_by = old.user_id then null else v.created_by end,
    used_by = case when v.used_by = old.user_id then null else v.used_by end
  where v.household_id = old.household_id and old.user_id in (v.created_by, v.used_by);
  update public.join_requests r set decided_by = null
  where r.household_id = old.household_id and r.decided_by = old.user_id;
  update public.households h set created_by = null
  where h.id = old.household_id and h.created_by = old.user_id;
  return null;
end $$;
revoke execute on function public.household_member_forget_user() from public, anon, authenticated;
create trigger household_members_forget_user after delete on public.household_members
  for each row execute function public.household_member_forget_user();
