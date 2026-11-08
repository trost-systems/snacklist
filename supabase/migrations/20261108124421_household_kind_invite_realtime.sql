-- Job 168b: who a household shops with, from onboarding's „Mit wem kaufst du ein?“. Members may
-- set it (like the name); null for households from before, and when the question was skipped.
-- Job 169 reads the same column for invite copy and clubs.
alter table public.households add column kind text
  check (kind in ('partner', 'family', 'flat', 'club', 'solo', 'other'));

grant update (kind) on public.households to authenticated;

-- The onboarding invite step shows „beigetreten“ as soon as someone accepts one of its invites
-- (used_at set by accept_invite). Realtime applies invites_select, so members see their own
-- household's invites only.
alter publication supabase_realtime add table public.invites;
