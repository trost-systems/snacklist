-- Job 274: the catalog the app bundles for its on-device suggestions (the add sheet's rows in the
-- same frame as the key): the rows of classifier_terms, classifier_lexicon and brands, and a
-- version that names them. supabase/classifier/client_catalog.sh writes them into
-- app/lib/list/catalog/catalog_index.g.dart; the device and catalog_delta compare versions.

-- Each table's rows as arrays in its primary key's byte order, the key first: terms
-- [term, key, category], forms [form, canonical, category, synonym], brands
-- [key, brand, product, store_seed].
create function public.catalog_rows() returns jsonb
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
      from public.brands b), '[]')
  )
$$;

-- jsonb's text form is canonical (object keys sorted, arrays in order), so equal rows give
-- equal versions on every server.
create function public.catalog_digest(p_rows jsonb) returns text
language sql immutable set search_path = '' as $$
  select left(encode(sha256(convert_to(p_rows::text, 'UTF8')), 'hex'), 16)
$$;

create function public.catalog_version() returns text
language sql stable set search_path = '' as $$
  select public.catalog_digest(public.catalog_rows())
$$;

revoke execute on function
  public.catalog_rows(),
  public.catalog_digest(jsonb),
  public.catalog_version()
from public, anon, authenticated;
grant execute on function public.catalog_version() to authenticated, service_role;
grant execute on function public.catalog_rows(), public.catalog_digest(jsonb) to service_role;
