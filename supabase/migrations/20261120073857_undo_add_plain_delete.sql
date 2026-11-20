-- Job 322: the add sheet's Rückgängig is a plain delete again (Peter, t1071u). It no longer takes
-- back what the added item's details taught; a wrong lesson is fixed on the next add. This undoes
-- job 315's behaviour (20261119070000_undo_added_details.sql):
--
-- - items_learn and items_unlearn_delete are their definitions from before job 315 again
--   (20261115205907_category_usual_store.sql and 20261029105411_suggest_entries.sql, verbatim).
-- - public.undo_add stays, since store builds with job 315's app still call it, and deletes the
--   item as the app's plain DELETE does.
-- - The edit_* columns stay (old apps and the compat rules) and are no longer written.
--
-- Pinned by supabase/tests/undo_added_details.test.sql.

create or replace function public.items_learn() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_key text := public.item_key(new.name);
begin
  if v_key = '' or coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  if new.category_id is distinct from old.category_id then
    insert into public.category_memory as m (household_id, item_key, category_id)
    values (new.household_id, v_key, new.category_id)
    on conflict (household_id, item_key, category_id)
      do update set corrections = m.corrections + 1, updated_at = clock_timestamp();
  end if;
  if new.store_id is distinct from old.store_id and new.store_id is null then
    delete from public.item_store_memory where household_id = new.household_id and item_key = v_key;
    -- A store deleted takes its items' store away (on delete set null); nobody picked "Ohne Laden".
    if exists (select from public.stores s where s.id = old.store_id) then
      insert into public.item_store_cleared as c (household_id, item_key)
      values (new.household_id, v_key)
      on conflict (household_id, item_key) do update set updated_at = clock_timestamp();
    end if;
  elsif new.store_id is distinct from old.store_id
     or (new.store_id is not null and new.status = 'bought' and old.status = 'active') then
    insert into public.item_store_memory as m (household_id, item_key, store_id)
    values (new.household_id, v_key, new.store_id)
    on conflict (household_id, item_key, store_id)
      do update set times = m.times + 1, updated_at = clock_timestamp();
  end if;
  return null;
end $function$;

create or replace function public.items_unlearn_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  delete from public.category_memory m using old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and m.undo_at > clock_timestamp() - interval '10 minutes'
    and (m.undo_prev_at is null or m.corrections <= m.undo_by);
  update public.category_memory m
  set corrections = m.corrections - m.undo_by, updated_at = m.undo_prev_at,
    undo_item = null, undo_by = null, undo_prev_at = null, undo_at = null
  from old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and m.undo_at > clock_timestamp() - interval '10 minutes';
  delete from public.item_store_memory m using old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and m.undo_at > clock_timestamp() - interval '10 minutes'
    and (m.undo_prev_at is null or m.times <= m.undo_by);
  update public.item_store_memory m
  set times = m.times - m.undo_by, updated_at = m.undo_prev_at,
    undo_item = null, undo_by = null, undo_prev_at = null, undo_at = null
  from old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and m.undo_at > clock_timestamp() - interval '10 minutes';
  return null;
end $$;

-- As the caller, so the items policies decide; an item already gone is no error.
create or replace function public.undo_add(p_item uuid) returns void
language sql set search_path = '' as $$
  delete from public.items where id = p_item;
$$;

comment on column public.category_memory.edit_item is
  'Job 315, unused since job 322 (undo_add is a plain delete): no longer written.';
comment on column public.item_store_memory.edit_item is
  'Job 315, unused since job 322 (undo_add is a plain delete): no longer written.';
comment on column public.item_store_cleared.edit_stores is
  'Job 315, unused since job 322 (undo_add is a plain delete): no longer written.';
