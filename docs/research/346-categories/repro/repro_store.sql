\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000346', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mock346@example.test', '{}', '{}', now(), now());
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000346","role":"authenticated"}', true);
create temp table h as select (public.create_household(gen_random_uuid(), 'Mock 346', false, array['IKEA','dm','Baumarkt','Apotheke'])).id;
create temp table mock (store text, name text, ord serial);
\copy mock (store, name) from 'items.tsv'
\echo '--- categories (household route order)'
select c.sort_order, c.seed_key, c.name from public.categories c where c.household_id = (select id from h) order by c.sort_order;
\echo '--- stores'
select s.name, s.seed_key from public.stores s where s.household_id = (select id from h) order by s.sort_order;
\echo '--- classification'
\pset format unaligned
\pset fieldsep '\t'
\o guessed.tsv
select m.store, m.name, c.name as category, coalesce((select name from public.stores where id = public.guess_store((select id from h), m.name, null, d.category_id, true)), '(Ohne Laden)') as default_store
from mock m
cross join lateral public.classify_item_detail((select id from h), m.name) d
join public.categories c on c.id = d.category_id
order by m.ord;
\o
\pset format aligned
\echo '--- per-store category order (hidden = collapsed)'
\o /dev/null
select s.name as store, o.sort_order, c.name as category, o.hidden
from public.store_category_order o join public.stores s on s.id=o.store_id join public.categories c on c.id=o.category_id
where o.household_id=(select id from h) order by s.sort_order, o.sort_order;
\o
rollback;
