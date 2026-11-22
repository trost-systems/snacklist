-- Legal N-325 (job 360): a „Nein" answer belongs to the person who gave it. No client grant exists
-- today (the household check stays: the schema check wants it on every household_id table); if one is added later, the policy still keeps the row from other household members.
drop policy shop_declines_member on public.shop_declines;
create policy shop_declines_own on public.shop_declines for select to authenticated
  using (user_id = auth.uid() and public.is_household_member(household_id));
