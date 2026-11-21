-- Job 336 (J2, job 331 F4): items.created_at stays a moment the API's cursors can carry.
--
-- items_before_write pinned created_at on update only. A member's own PostgREST insert with
-- created_at = infinity, -infinity or the year 10000 then stopped GET /v1/items paging for the
-- whole household with 400 invalid_cursor partway through: the cursor carries created_at, and
-- those values are no date it accepts. The app, put_item, the API, MCP, Siri and Alexa never send
-- created_at; seeds and tests send past moments, which stay.
--
-- An insert outside 2000-01-01 .. tomorrow gets now(). A row already outside it gets now() on its
-- next update, and the update below gives every such row now() once. The day ahead is slack, not
-- meaning: a statement's now() is its transaction's start, so a row a later transaction added can
-- be a little newer than that.

create or replace function public.items_before_write() returns trigger
language plpgsql security definer set search_path = '' as $function$
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
    new.store_id := case
      when current_setting('family_groceries.category_store', true) = 'on'
        then public.guess_store(new.household_id, new.name, new.brand, new.category_id, true)
      else public.suggest_store(new.household_id, new.name)
    end;
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
  if tg_op = 'INSERT' and new.created_at not between '2000-01-01 00:00:00+00' and now() + interval '1 day' then
    new.created_at := now();
  elsif tg_op = 'UPDATE' then
    new.created_at := case when old.created_at between '2000-01-01 00:00:00+00' and now() + interval '1 day' then old.created_at else now() end;
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
end $function$;

update public.items i set created_at = now() where i.created_at not between '2000-01-01 00:00:00+00' and now() + interval '1 day';
