-- Job 315: the add sheet's Rückgängig takes back the store and category picked in the details of
-- the item just added (flag add-feedback-list).
--
-- A pick with the add (the old chips) reaches items_learn_insert, which marks the memory row it
-- taught (undo_item, undo_by, undo_prev_at, undo_at), and items_unlearn_delete takes a marked
-- lesson back when the item is deleted within 10 minutes. A pick in the details comes after the
-- insert, as an update of the item (the app's edit op), and items_learn learned it unmarked: the
-- Rückgängig deleted the item and the next add still took the pick.
--
-- Any other delete keeps what an edit taught: the spec's classifier test moves an item, deletes
-- it and adds it again, and the new one lands where it was moved. So the Rückgängig says what it
-- is, through public.undo_add, and only that delete takes back an edit's lessons:
--
-- - edit_item, edit_by, edit_prev_at, edit_at (new, on category_memory and item_store_memory):
--   items_learn marks what a store or category change teaches, as the insert marks its own; a
--   second change of the same item adds to its own mark, so the undo goes back to the state
--   before the first one. A buy's store lesson (a tick in a store too) stays unmarked.
-- - A change to no store deletes the key's store memory. The deleted rows go into the key's
--   item_store_cleared row (edit_stores, new, with the same marks), so the undo can put them back.
-- - public.undo_add(p_item) (new) deletes the item with the transaction-local setting
--   family_groceries.undo_add on. items_unlearn_delete then first puts stashed store memory back
--   (over a row only this item taught since; not of a store deleted since), resets or removes the
--   cleared row and takes back the marked edits, and then, as for every delete, the insert's
--   marked lessons. A lesson taught after the item's last change (another item, another member)
--   leaves the mark stale, so the undo keeps it. The undo has no time limit (an undo queued
--   offline still applies), for the insert's marks either; without the setting a delete does what
--   it did.
-- - items_learn_insert and the app's other deletes are unchanged; an app without undo_add keeps
--   its plain delete.
--
-- Pinned by supabase/tests/undo_added_details.test.sql.

alter table public.category_memory
  add column edit_item uuid,
  add column edit_by integer,
  add column edit_prev_at timestamptz,
  add column edit_at timestamptz;

alter table public.item_store_memory
  add column edit_item uuid,
  add column edit_by integer,
  add column edit_prev_at timestamptz,
  add column edit_at timestamptz;

alter table public.item_store_cleared
  add column edit_item uuid,
  add column edit_stores jsonb,
  add column edit_prev_at timestamptz,
  add column edit_at timestamptz;

comment on column public.category_memory.edit_item is
  'Job 315: the item whose category change last taught this row; public.undo_add of that item takes it back (edit_by corrections, updated_at back to edit_prev_at) while updated_at = edit_at.';
comment on column public.item_store_memory.edit_item is
  'Job 315: the item whose store change last taught this row; public.undo_add of that item takes it back (edit_by times, updated_at back to edit_prev_at) while updated_at = edit_at.';
comment on column public.item_store_cleared.edit_stores is
  'Job 315: the store memory rows (item_store_memory) the change to no store of edit_item deleted, put back by public.undo_add of that item.';

create or replace function public.items_learn() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare
  v_key text := public.item_key(new.name);
  v_now timestamptz := clock_timestamp();
  v_stash jsonb;
begin
  if v_key = '' or coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  if new.category_id is distinct from old.category_id then
    insert into public.category_memory as m
      (household_id, item_key, category_id, updated_at, edit_item, edit_by, edit_at)
    values (new.household_id, v_key, new.category_id, v_now, new.id, 1, v_now)
    on conflict (household_id, item_key, category_id)
      do update set corrections = m.corrections + 1, updated_at = v_now, edit_item = new.id,
        edit_by = case when m.edit_item = new.id and m.updated_at = m.edit_at then m.edit_by + 1 else 1 end,
        edit_prev_at = case when m.edit_item = new.id and m.updated_at = m.edit_at then m.edit_prev_at else m.updated_at end,
        edit_at = v_now;
  end if;
  if new.store_id is distinct from old.store_id and new.store_id is null then
    with gone as (
      delete from public.item_store_memory m
      where m.household_id = new.household_id and m.item_key = v_key
      returning m.*
    )
    select jsonb_agg(to_jsonb(gone)) into v_stash from gone;
    -- A store deleted takes its items' store away (on delete set null); nobody picked "Ohne Laden".
    if exists (select from public.stores s where s.id = old.store_id) then
      insert into public.item_store_cleared as c
        (household_id, item_key, updated_at, edit_item, edit_stores, edit_at)
      values (new.household_id, v_key, v_now, new.id, coalesce(v_stash, '[]'), v_now)
      on conflict (household_id, item_key) do update set updated_at = v_now, edit_item = new.id,
        -- A second change to no store of the same item keeps what the first one deleted, and adds
        -- what was learned since.
        edit_stores = case
          when c.edit_item = new.id and c.updated_at = c.edit_at then c.edit_stores || coalesce((
            select jsonb_agg(e) from jsonb_array_elements(v_stash) e
            where not exists (
              select from jsonb_array_elements(c.edit_stores) f where f->>'store_id' = e->>'store_id')
          ), '[]')
          else coalesce(v_stash, '[]') end,
        edit_prev_at = case when c.edit_item = new.id and c.updated_at = c.edit_at then c.edit_prev_at else c.updated_at end,
        edit_at = v_now;
    end if;
  elsif new.store_id is distinct from old.store_id and new.status = old.status then
    insert into public.item_store_memory as m
      (household_id, item_key, store_id, updated_at, edit_item, edit_by, edit_at)
    values (new.household_id, v_key, new.store_id, v_now, new.id, 1, v_now)
    on conflict (household_id, item_key, store_id)
      do update set times = m.times + 1, updated_at = v_now, edit_item = new.id,
        edit_by = case when m.edit_item = new.id and m.updated_at = m.edit_at then m.edit_by + 1 else 1 end,
        edit_prev_at = case when m.edit_item = new.id and m.updated_at = m.edit_at then m.edit_prev_at else m.updated_at end,
        edit_at = v_now;
  elsif new.store_id is distinct from old.store_id
     or (new.store_id is not null and new.status = 'bought' and old.status = 'active') then
    -- A buy in a store (a tick that also sets it): learned, not an edit to take back.
    insert into public.item_store_memory as m (household_id, item_key, store_id)
    values (new.household_id, v_key, new.store_id)
    on conflict (household_id, item_key, store_id)
      do update set times = m.times + 1, updated_at = v_now;
  end if;
  return null;
end $function$;

create or replace function public.items_unlearn_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_undo boolean := coalesce(current_setting('family_groceries.undo_add', true), '') = 'on';
begin
  if coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  if v_undo then
    insert into public.item_store_memory as m
    select r.*
    from public.item_store_cleared c
    join old_items o on o.household_id = c.household_id and o.id = c.edit_item
    cross join lateral jsonb_populate_recordset(null::public.item_store_memory, c.edit_stores) r
    -- A store deleted since took its memory along (on delete cascade).
    join public.stores s on s.id = r.store_id and s.household_id = r.household_id
    where c.updated_at = c.edit_at
    on conflict (household_id, item_key, store_id) do update
      set times = excluded.times, updated_at = excluded.updated_at,
        undo_item = excluded.undo_item, undo_by = excluded.undo_by, undo_prev_at = excluded.undo_prev_at,
        undo_at = excluded.undo_at, edit_item = excluded.edit_item, edit_by = excluded.edit_by,
        edit_prev_at = excluded.edit_prev_at, edit_at = excluded.edit_at
      where m.updated_at = m.edit_at and m.edit_item in (select id from old_items);
    delete from public.item_store_cleared c using old_items o
    where c.household_id = o.household_id and c.edit_item = o.id and c.updated_at = c.edit_at
      and c.edit_prev_at is null;
    update public.item_store_cleared c
    set updated_at = c.edit_prev_at, edit_item = null, edit_stores = null, edit_prev_at = null, edit_at = null
    from old_items o
    where c.household_id = o.household_id and c.edit_item = o.id and c.updated_at = c.edit_at;
    delete from public.category_memory m using old_items o
    where m.household_id = o.household_id and m.edit_item = o.id and m.updated_at = m.edit_at
      and (m.edit_prev_at is null or m.corrections <= m.edit_by);
    update public.category_memory m
    set corrections = m.corrections - m.edit_by, updated_at = m.edit_prev_at,
      edit_item = null, edit_by = null, edit_prev_at = null, edit_at = null
    from old_items o
    where m.household_id = o.household_id and m.edit_item = o.id and m.updated_at = m.edit_at;
    delete from public.item_store_memory m using old_items o
    where m.household_id = o.household_id and m.edit_item = o.id and m.updated_at = m.edit_at
      and (m.edit_prev_at is null or m.times <= m.edit_by);
    update public.item_store_memory m
    set times = m.times - m.edit_by, updated_at = m.edit_prev_at,
      edit_item = null, edit_by = null, edit_prev_at = null, edit_at = null
    from old_items o
    where m.household_id = o.household_id and m.edit_item = o.id and m.updated_at = m.edit_at;
  end if;
  delete from public.category_memory m using old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and (v_undo or m.undo_at > clock_timestamp() - interval '10 minutes')
    and (m.undo_prev_at is null or m.corrections <= m.undo_by);
  update public.category_memory m
  set corrections = m.corrections - m.undo_by, updated_at = m.undo_prev_at,
    undo_item = null, undo_by = null, undo_prev_at = null, undo_at = null
  from old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and (v_undo or m.undo_at > clock_timestamp() - interval '10 minutes');
  delete from public.item_store_memory m using old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and (v_undo or m.undo_at > clock_timestamp() - interval '10 minutes')
    and (m.undo_prev_at is null or m.times <= m.undo_by);
  update public.item_store_memory m
  set times = m.times - m.undo_by, updated_at = m.undo_prev_at,
    undo_item = null, undo_by = null, undo_prev_at = null, undo_at = null
  from old_items o
  where m.household_id = o.household_id and m.undo_item = o.id and m.updated_at = m.undo_at
    and (v_undo or m.undo_at > clock_timestamp() - interval '10 minutes');
  return null;
end $$;

-- The add sheet's Rückgängig: deletes the item just added and takes back what its edits taught
-- (items_unlearn_delete). As the caller, so the items policies decide; an item already gone is no
-- error, so a retried undo is harmless.
create function public.undo_add(p_item uuid) returns void
language plpgsql set search_path = '' as $$
begin
  perform set_config('family_groceries.undo_add', 'on', true);
  delete from public.items where id = p_item;
  perform set_config('family_groceries.undo_add', '', true);
end $$;

revoke execute on function public.undo_add(uuid) from public, anon;
grant execute on function public.undo_add(uuid) to authenticated;
