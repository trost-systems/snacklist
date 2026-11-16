-- Job 274 review: every catalog version a device may have bundled keeps its snapshot, and
-- catalog_delta stops recomputing the catalog on every call.
--
-- - catalog_snapshots.current marks the snapshot of the current version. catalog_delta reads it
--   instead of catalog_rows() and its sha256 (about 20 ms); when none is marked it computes them
--   once and marks that version.
-- - catalog_snapshot_outgoing, a statement trigger before any write to classifier_terms,
--   classifier_lexicon or brands: the first such statement of a transaction snapshots the version
--   in force before it (none to compute when it is the marked one, which has its snapshot), and
--   every such statement unmarks the current version. So a device on any version that was live
--   gets changes, never the full catalog, even if no device asked while it was live; a migration
--   that writes these tables in many statements stores one snapshot.
-- - catalog_delta refuses a p_base or p_have that is no version (16 hex digits): an unknown version
--   costs the full catalog in the answer, so only version-shaped ones get it.

alter table public.catalog_snapshots add column current boolean not null default false;
create unique index catalog_snapshots_current on public.catalog_snapshots (current) where current;

create function public.catalog_snapshot_outgoing() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb;
begin
  if coalesce(current_setting('family_groceries.catalog_outgoing', true), '') = '' then
    perform set_config('family_groceries.catalog_outgoing', 'taken', true);
    if not exists (select from public.catalog_snapshots s where s.current) then
      v_rows := public.catalog_rows();
      insert into public.catalog_snapshots (version, terms, forms, brands)
      values (public.catalog_digest(v_rows), v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands')
      on conflict (version) do nothing;
    end if;
  end if;
  -- Also the row lock that holds catalog_delta's computing until this transaction ends.
  update public.catalog_snapshots s set current = false where s.current;
  return null;
end $$;
revoke execute on function public.catalog_snapshot_outgoing() from public, anon, authenticated;

create trigger classifier_terms_catalog_outgoing
  before insert or update or delete or truncate on public.classifier_terms
  for each statement execute function public.catalog_snapshot_outgoing();
create trigger classifier_lexicon_catalog_outgoing
  before insert or update or delete or truncate on public.classifier_lexicon
  for each statement execute function public.catalog_snapshot_outgoing();
create trigger brands_catalog_outgoing
  before insert or update or delete or truncate on public.brands
  for each statement execute function public.catalog_snapshot_outgoing();

-- As in 20261116013636_catalog_delta.sql, but from the marked snapshot, and only for versions.
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
      insert into public.catalog_snapshots as s (version, terms, forms, brands, current)
      values (public.catalog_digest(v_rows), v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands', true)
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
      'brands', jsonb_build_object('put', v_now.brands, 'drop', '[]'::jsonb)
    );
  end if;
  return jsonb_build_object(
    'version', v_now.version,
    'full', false,
    'terms', public.catalog_changes(v_base.terms, v_now.terms),
    'forms', public.catalog_changes(v_base.forms, v_now.forms),
    'brands', public.catalog_changes(v_base.brands, v_now.brands)
  );
end $$;
