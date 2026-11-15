-- Job 251: Legal GL-2 adds DocMorris (a mail-order pharmacy whose name has none of the words)
-- to the pharmacy names of trip mode: Store.pharmacyWords in the app, is_pharmacy_store here. Its
-- lines in stored sessions and their automatic log rows go, as in 20261114213100.

create or replace function public.is_pharmacy_store(p_words text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(p_words, '') ~* '(apotheke|pharmacy|pharmacie|farmacia|apteka|eczane|docmorris)'
$$;

update public.trip_sessions s set
  lines = public.trip_lines_without_pharmacy(s.household_id, s.lines),
  updated_at = now()
where s.lines <> public.trip_lines_without_pharmacy(s.household_id, s.lines);

delete from public.trips t
where t.session_id is not null
  and public.is_pharmacy_store(concat_ws(' ', t.store_name, (
    select concat_ws(' ', st.name, st.seed_key) from public.stores st
    where st.id = t.store_id and st.household_id = t.household_id)));
