-- Legal review N-113: the join page's rate-limit rows of a past hour go even when no join page is
-- opened after it. preview_invite_public still deletes them on each call as well. The salt stays:
-- it is one secret that never rotates, and no row keyed by it outlives its hour.
create function public.purge_invite_preview_rate() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.invite_preview_rate r where r.window_start < date_trunc('hour', now());
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke execute on function public.purge_invite_preview_rate() from public, anon, authenticated;

-- The same name replaces the job, so applying this again keeps one.
select cron.schedule('purge-invite-preview-rate', '0 * * * *', 'select public.purge_invite_preview_rate()');

comment on table public.invite_preview_rate is
  'Job 169b: join page previews per salted SHA-256 of the client IP or the code, per hour; no raw IP or code. No client access. Past hours deleted hourly (purge-invite-preview-rate) and on each preview.';
