-- Job 274: the device's catalog follows the server's between app releases. It asks
-- catalog_delta for the changes from the version it bundles and lays them over that version;
-- the server answers them from a snapshot of that version's rows, or every row when it has none.

create table public.catalog_snapshots (
  version text primary key,
  terms jsonb not null,
  forms jsonb not null,
  brands jsonb not null,
  created_at timestamptz not null default now()
);
-- Only catalog_delta (security definer) reads and writes it: no client policy.
alter table public.catalog_snapshots enable row level security;
revoke all on public.catalog_snapshots from public, anon, authenticated;

-- One table's changes between two of catalog_rows()'s arrays: the rows that are new or differ,
-- and the keys (each row's first element) that are gone.
create function public.catalog_changes(p_base jsonb, p_now jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'put', coalesce((
      select jsonb_agg(x.e order by (x.e ->> 0) collate "C")
      from (select jsonb_array_elements(p_now) except select jsonb_array_elements(p_base)) x (e)), '[]'),
    'drop', coalesce((
      select jsonb_agg(x.k order by x.k collate "C")
      from (select e ->> 0 from jsonb_array_elements(p_base) b (e)
            except select e ->> 0 from jsonb_array_elements(p_now) n (e)) x (k)), '[]')
  )
$$;

-- {"version", "full": false} when p_base is current; else the changes per table
-- ({"put": [...], "drop": [...]}, rows as in catalog_rows) from p_base's snapshot, or with
-- "full": true every row when there is none. Each call snapshots the current version, so a later
-- catalog migration still answers devices on this one with changes only.
create function public.catalog_delta(p_base text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_rows jsonb := public.catalog_rows();
  v_version text := public.catalog_digest(v_rows);
  v_base public.catalog_snapshots;
begin
  insert into public.catalog_snapshots (version, terms, forms, brands)
  values (v_version, v_rows -> 'terms', v_rows -> 'forms', v_rows -> 'brands')
  on conflict (version) do nothing;
  if p_base = v_version then
    return jsonb_build_object('version', v_version, 'full', false);
  end if;
  select * into v_base from public.catalog_snapshots s where s.version = p_base;
  if not found then
    return jsonb_build_object(
      'version', v_version,
      'full', true,
      'terms', jsonb_build_object('put', v_rows -> 'terms', 'drop', '[]'::jsonb),
      'forms', jsonb_build_object('put', v_rows -> 'forms', 'drop', '[]'::jsonb),
      'brands', jsonb_build_object('put', v_rows -> 'brands', 'drop', '[]'::jsonb)
    );
  end if;
  return jsonb_build_object(
    'version', v_version,
    'full', false,
    'terms', public.catalog_changes(v_base.terms, v_rows -> 'terms'),
    'forms', public.catalog_changes(v_base.forms, v_rows -> 'forms'),
    'brands', public.catalog_changes(v_base.brands, v_rows -> 'brands')
  );
end $$;

revoke execute on function
  public.catalog_changes(jsonb, jsonb),
  public.catalog_delta(text)
from public, anon, authenticated;
grant execute on function public.catalog_delta(text) to authenticated, service_role;
grant execute on function public.catalog_changes(jsonb, jsonb) to service_role;

-- The version the app bundles at this migration (client_catalog.sh) answers with changes from now.
insert into public.catalog_snapshots (version, terms, forms, brands)
select public.catalog_digest(r), r -> 'terms', r -> 'forms', r -> 'brands'
from public.catalog_rows() r;
