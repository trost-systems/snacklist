-- Job 473: the device reads homographs as the server does. The add sheet's match rows key both
-- sides with the device's canonical key, which had no homograph_pick (#536): typed "Schäufele"
-- offered to merge into "Schaufel", "Beeren" into "beer". The device needs each shared form's
-- spellings, three of which are synonyms it has no other way to know (beer, rolls, sage), so the
-- catalog carries classifier_lexicon.homographs as a fourth table.
--
-- Apps that predate it ignore the new key of catalog_delta's answer (parseCatalogDelta reads
-- version, full, terms, forms and brands only); the version changes once, with no row changes
-- for them.

-- The version every app released so far may bundle keeps a snapshot, so catalog_delta answers it
-- with changes rather than every row.
insert into public.catalog_snapshots (version, terms, forms, brands)
select public.catalog_digest(r), r -> 'terms', r -> 'forms', r -> 'brands'
from public.catalog_rows() r
on conflict (version) do nothing;

-- Null in the snapshots taken before this migration.
alter table public.catalog_snapshots add column homographs jsonb;

-- As in 20261116012830_catalog_version.sql, plus homographs [form, surface, canonical, category,
-- synonym], one row per spelling of a form shared by words of different categories, in form then
-- spelling order.
create or replace function public.catalog_rows() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'terms', coalesce((
      select jsonb_agg(jsonb_build_array(t.term, t.key, t.category) order by t.term collate "C")
      from public.classifier_terms t), '[]'),
    'forms', coalesce((
      select jsonb_agg(jsonb_build_array(l.form, l.canonical, l.category, l.synonym) order by l.form collate "C")
      from public.classifier_lexicon l), '[]'),
    'brands', coalesce((
      select jsonb_agg(jsonb_build_array(b.key, b.brand, b.product, b.store_seed) order by b.key collate "C")
      from public.brands b), '[]'),
    'homographs', coalesce((
      select jsonb_agg(
        jsonb_build_array(l.form, e ->> 'surface', e ->> 'canonical', e ->> 'category', (e ->> 'synonym')::boolean)
        order by l.form collate "C", e ->> 'surface' collate "C")
      from public.classifier_lexicon l, jsonb_array_elements(l.homographs) e), '[]')
  )
$$;

-- As in 20261116114343_catalog_snapshot_outgoing.sql, with the homographs.
create or replace function public.catalog_snapshot_outgoing() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if coalesce(current_setting('family_groceries.catalog_outgoing', true), '') = '' then
    perform set_config('family_groceries.catalog_outgoing', 'taken', true);
    if not exists (select from public.catalog_snapshots s where s.current) then
      v_rows := public.catalog_rows();
      insert into public.catalog_snapshots (version, terms, forms, brands, homographs)
      values (public.catalog_digest(v_rows), v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands',
        v_rows -> 'homographs')
      on conflict (version) do nothing;
    end if;
  end if;
  -- Also the row lock that holds catalog_delta's computing until this transaction ends.
  update public.catalog_snapshots s set current = false where s.current;
  return null;
end $$;

-- As in 20261116114343_catalog_snapshot_outgoing.sql. An answer with tables also has every
-- homograph row (a few dozen), which replace the device's.
create or replace function public.catalog_delta(p_base text, p_have text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb;
  v_now public.catalog_snapshots;
  v_base public.catalog_snapshots;
begin
  if p_base is null or p_base !~ '^[0-9a-f]{16}$' or p_have !~ '^[0-9a-f]{16}$' then
    raise exception 'invalid_version' using errcode = '22023';
  end if;
  select * into v_now from public.catalog_snapshots s where s.current;
  if not found then
    -- After a catalog change commits, so the rows are the committed ones: its trigger's update
    -- holds this lock until then, and while this one is held the next change waits.
    lock table public.catalog_snapshots in share row exclusive mode;
    select * into v_now from public.catalog_snapshots s where s.current;
    if not found then
      v_rows := public.catalog_rows();
      insert into public.catalog_snapshots as s (version, terms, forms, brands, homographs, current)
      values (public.catalog_digest(v_rows), v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands',
        v_rows -> 'homographs', true)
      on conflict (version) do update set current = true
      returning * into v_now;
    end if;
  end if;
  if v_now.version in (p_base, p_have) then
    return jsonb_build_object('version', v_now.version, 'full', false);
  end if;
  select * into v_base from public.catalog_snapshots s where s.version = p_base;
  if not found then
    return jsonb_build_object(
      'version', v_now.version,
      'full', true,
      'terms', jsonb_build_object('put', v_now.terms, 'drop', '[]'::jsonb),
      'forms', jsonb_build_object('put', v_now.forms, 'drop', '[]'::jsonb),
      'brands', jsonb_build_object('put', v_now.brands, 'drop', '[]'::jsonb),
      'homographs', v_now.homographs
    );
  end if;
  return jsonb_build_object(
    'version', v_now.version,
    'full', false,
    'terms', public.catalog_changes(v_base.terms, v_now.terms),
    'forms', public.catalog_changes(v_base.forms, v_now.forms),
    'brands', public.catalog_changes(v_base.brands, v_now.brands),
    'homographs', v_now.homographs
  );
end $$;

-- The current snapshot's version was taken without the homographs: the next call takes the new one.
update public.catalog_snapshots s set current = false where s.current;
