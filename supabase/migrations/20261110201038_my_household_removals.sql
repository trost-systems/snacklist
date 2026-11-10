-- Legal review N-114: the app tells a removed person about the 30-day rule, on every device they
-- sign in on, and only when someone removed them: a household left on another device has no
-- record here. The caller's own removals that still refuse old invites (purge_household_removals
-- deletes them after 30 days, at 03:47; this hides them from the moment they expire). A removal
-- goes with its household (on delete cascade), so each row has a name.
create function public.my_household_removals()
returns table (household_id uuid, household_name text, removed_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select r.household_id, h.name, r.removed_at
  from public.household_removals r
  join public.households h on h.id = r.household_id
  where r.user_id = auth.uid() and r.removed_at >= now() - interval '30 days'
  order by r.removed_at, r.household_id
$$;
revoke execute on function public.my_household_removals() from public, anon;
grant execute on function public.my_household_removals() to authenticated;
