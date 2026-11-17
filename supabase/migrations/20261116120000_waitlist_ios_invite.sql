-- Job 280: the iOS beta invite sender, scripts/waitlist/ios-invite.ts (docs/WAITLIST.md "iOS
-- invite"). Recipients are confirmed iOS rows without an invite; an unsubscribed row is deleted,
-- so it is never one. invite_sent_at is the per-recipient sent state: the sender claims a row
-- before its send and releases it only when Resend refused the mail, so no rerun, crash or second
-- run mails a row twice.

-- The dry run's counts per locale, never an address.
create function public.waitlist_ios_invite_counts()
returns table (locale text, confirmed integer, invited integer, to_invite integer)
language sql stable security definer set search_path = '' as $$
  select w.locale, count(*)::integer,
         count(w.invite_sent_at)::integer,
         (count(*) - count(w.invite_sent_at))::integer
  from public.waitlist w
  where w.platform = 'ios' and w.confirmed_at is not null
  group by w.locale
  order by w.locale;
$$;

-- The next p_limit uninvited iOS rows, earliest confirmation first; null means all.
create function public.waitlist_ios_invite_rows(p_limit integer)
returns table (id uuid, email text, locale text)
language sql stable security definer set search_path = '' as $$
  select w.id, w.email, w.locale
  from public.waitlist w
  where w.platform = 'ios' and w.confirmed_at is not null and w.invite_sent_at is null
  order by w.confirmed_at, w.id
  limit p_limit;
$$;

-- Marks the row invited before its send; false when it is gone, not an iOS recipient or claimed.
create function public.waitlist_invite_claim(p_id uuid, p_now timestamptz)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.waitlist w set invite_sent_at = p_now
  where w.id = p_id and w.platform = 'ios' and w.confirmed_at is not null
    and w.invite_sent_at is null;
  return found;
end $$;

-- Undoes this run's claim (p_claimed_at) after Resend refused the mail.
create function public.waitlist_invite_release(p_id uuid, p_claimed_at timestamptz)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.waitlist w set invite_sent_at = null
  where w.id = p_id and w.invite_sent_at = p_claimed_at;
  return found;
end $$;

revoke execute on function public.waitlist_ios_invite_counts() from public, anon, authenticated;
revoke execute on function public.waitlist_ios_invite_rows(integer) from public, anon, authenticated;
revoke execute on function public.waitlist_invite_claim(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.waitlist_invite_release(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.waitlist_ios_invite_counts() to service_role;
grant execute on function public.waitlist_ios_invite_rows(integer) to service_role;
grant execute on function public.waitlist_invite_claim(uuid, timestamptz) to service_role;
grant execute on function public.waitlist_invite_release(uuid, timestamptz) to service_role;
