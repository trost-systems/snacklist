-- Job 169b wave 1: a user can be in several households (docs/households/W1.md, PLAN.md section 2).
-- One membership per user is the default: old store builds read it (the select policy shows a
-- user's own row only where is_default), and Siri, Alexa and AI connections act there. Every
-- function that read "the" membership with a single-row select now reads the given household, or
-- the default.

-- Memberships ------------------------------------------------------------------------------------

-- squawk-ignore ban-drop-constraint -- the one-household rule ends here (DECISIONS 1.2 superseded): old apps keep one visible row through the default-only select policy below
alter table public.household_members drop constraint household_members_user_id_key;
alter table public.household_members add column is_default boolean not null default false;
-- Today every user has one membership: it becomes their default.
update public.household_members set is_default = true;
create unique index household_members_one_default on public.household_members (user_id)
  where is_default;
create index household_members_user_idx on public.household_members (user_id, joined_at);

alter table public.household_members drop constraint household_members_role_check;
-- squawk-ignore constraint-missing-not-valid -- widens the check: every row passes
alter table public.household_members add constraint household_members_role_check
  check (role in ('owner', 'admin', 'member'));

-- Serializes the membership changes of one user: the default trigger, the promotion and
-- set_default_household see each other's committed rows, so a join racing a leave never leaves a
-- user with memberships but no default.
create function public.lock_memberships(p_user uuid) returns void
language sql security definer set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended('household_members:' || p_user::text, 0))
$$;
revoke execute on function public.lock_memberships(uuid) from public, anon, authenticated;

-- The user's first membership is their default.
create function public.household_members_first_default() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_memberships(new.user_id);
  new.is_default := not exists (
    select from public.household_members m where m.user_id = new.user_id and m.is_default
  );
  return new;
end $$;
revoke execute on function public.household_members_first_default() from public, anon, authenticated;
create trigger household_members_first_default before insert on public.household_members
  for each row execute function public.household_members_first_default();

-- Every exit (leave, removal, a deleted household, account deletion) hands the default to the
-- user's oldest remaining membership in the same transaction. The pick is locked: without
-- `for update`, two leaves at once can pick a row the other one just deleted and the user ends
-- with memberships but no default (docs/households/proofs/concurrent-leave.sh).
create function public.household_members_promote_default() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.is_default then
    perform public.lock_memberships(old.user_id);
    update public.household_members set is_default = true
    where (household_id, user_id) = (
      select m.household_id, m.user_id from public.household_members m
      where m.user_id = old.user_id
      order by m.joined_at, m.household_id
      limit 1
      for update
    );
  end if;
  return null;
end $$;
revoke execute on function public.household_members_promote_default() from public, anon, authenticated;
create trigger household_members_default_promote after delete on public.household_members
  for each row execute function public.household_members_promote_default();

-- Makes [p_household] [p_user]'s default; not_member when they are not in it.
create function public.make_default_household(p_user uuid, p_household uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_memberships(p_user);
  if not exists (
    select from public.household_members m where m.user_id = p_user and m.household_id = p_household
  ) then
    raise exception 'not_member' using errcode = '42501';
  end if;
  update public.household_members m set is_default = false
  where m.user_id = p_user and m.is_default and m.household_id <> p_household;
  update public.household_members m set is_default = true
  where m.user_id = p_user and m.household_id = p_household and not m.is_default;
end $$;
revoke execute on function public.make_default_household(uuid, uuid) from public, anon, authenticated;

create function public.default_household_of(p_user uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select m.household_id from public.household_members m where m.user_id = p_user and m.is_default
$$;
revoke execute on function public.default_household_of(uuid) from public, anon, authenticated;

-- Old store builds read their own membership with .maybeSingle(): they see only the default and
-- never two rows. Other members' rows of a shared household stay visible. The new app reads its
-- memberships through my_households() and member lists through household_members_of().
drop policy household_members_select on public.household_members;
create policy household_members_select on public.household_members for select to authenticated
  using (
    public.is_household_member(household_id)
    and (user_id <> (select auth.uid()) or is_default)
  );

-- Households -------------------------------------------------------------------------------------

alter table public.households add column kind text
  check (kind in ('partner', 'family', 'flat', 'club', 'solo'));
alter table public.households add column request_id uuid;
create unique index households_request on public.households (created_by, request_id);
comment on column public.households.request_id is
  'Job 169b: the new app''s create request; a retry with the same id returns the same household.';

-- The app's interface ----------------------------------------------------------------------------

create function public.my_households()
returns table (
  id uuid, name text, kind text, role text, is_default boolean, member_count integer,
  open_count integer, premium boolean, joined_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select h.id, h.name, h.kind, m.role, m.is_default,
    (select count(*)::int from public.household_members o where o.household_id = h.id),
    (select count(*)::int from public.items i where i.household_id = h.id and i.status = 'active'),
    public.household_has_premium(h.id),
    m.joined_at
  from public.household_members m
  join public.households h on h.id = m.household_id
  where m.user_id = auth.uid()
  order by m.joined_at, h.id
$$;
revoke execute on function public.my_households() from public, anon;
grant execute on function public.my_households() to authenticated;

create function public.household_members_of(p_household uuid)
returns table (user_id uuid, display_name text, role text, joined_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_member' using errcode = '42501';
  end if;
  return query
  select m.user_id, p.display_name, m.role, m.joined_at
  from public.household_members m
  left join public.profiles p on p.id = m.user_id
  where m.household_id = p_household
  order by m.joined_at, m.user_id;
end $$;
revoke execute on function public.household_members_of(uuid) from public, anon;
grant execute on function public.household_members_of(uuid) to authenticated;

create function public.set_default_household(p_household uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  perform public.make_default_household(auth.uid(), p_household);
end $$;
revoke execute on function public.set_default_household(uuid) from public, anon;
grant execute on function public.set_default_household(uuid) to authenticated;

-- Old store builds call this without a request id and treat already_in_household as "it is there
-- already": the guard stays for them. The membership lock replaces the unique (user_id) that
-- caught two devices creating at the same moment.
create or replace function public.create_household(
  p_name text default 'Unser Haushalt',
  p_default_stores boolean default false,
  p_stores text[] default '{}'
) returns public.households
language plpgsql security definer set search_path = '' as $$
declare
  v_household public.households;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  perform public.lock_memberships(auth.uid());
  if exists (select 1 from public.household_members where user_id = auth.uid()) then
    raise exception 'already_in_household' using errcode = 'P0001';
  end if;
  insert into public.households (name, created_by)
  values (coalesce(nullif(btrim(p_name), ''), 'Unser Haushalt'), auth.uid())
  returning * into v_household;
  insert into public.household_members (household_id, user_id, role)
  values (v_household.id, auth.uid(), 'owner');
  perform public.seed_household(v_household.id, coalesce(p_default_stores, false));
  for v_name in select t.name from unnest(coalesce(p_stores, '{}')) with ordinality as t (name, ord) order by t.ord
  loop
    perform public.add_store(v_household.id, v_name);
  end loop;
  return v_household;
end $$;

-- The new app's create: another household next to the ones the user has (at most 10). The same
-- request id returns the same household, so a retry or a double tap creates one. p_request_id
-- has no default so a call without it still reaches the old signature above.
create function public.create_household(
  p_request_id uuid,
  p_name text default 'Unser Haushalt',
  p_default_stores boolean default false,
  p_stores text[] default '{}',
  p_kind text default null
) returns public.households
language plpgsql security definer set search_path = '' as $$
declare
  v_household public.households;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_request_id is null then
    raise exception 'request_id_required' using errcode = '22023';
  end if;
  perform public.lock_memberships(auth.uid());
  select * into v_household from public.households h
  where h.created_by = auth.uid() and h.request_id = p_request_id;
  if found then
    return v_household;
  end if;
  if (select count(*) from public.household_members m where m.user_id = auth.uid()) >= 10 then
    raise exception 'too_many_households' using errcode = 'P0001';
  end if;
  insert into public.households (name, created_by, request_id, kind)
  values (coalesce(nullif(btrim(p_name), ''), 'Unser Haushalt'), auth.uid(), p_request_id, p_kind)
  returning * into v_household;
  insert into public.household_members (household_id, user_id, role)
  values (v_household.id, auth.uid(), 'owner');
  perform public.seed_household(v_household.id, coalesce(p_default_stores, false));
  for v_name in select t.name from unnest(coalesce(p_stores, '{}')) with ordinality as t (name, ord) order by t.ord
  loop
    perform public.add_store(v_household.id, v_name);
  end loop;
  return v_household;
end $$;
revoke execute on function public.create_household(uuid, text, boolean, text[], text) from public, anon;
grant execute on function public.create_household(uuid, text, boolean, text[], text) to authenticated;

-- Leaving ----------------------------------------------------------------------------------------

-- Ends [p_user]'s membership of [p_household]: 'none' (not a member), 'left', or for the last
-- member 'deleted', or 'archived' (p_archive, premium, the household_archive switch).
create function public.leave_household_as(p_user uuid, p_household uuid, p_archive boolean)
returns text
language plpgsql security definer set search_path = '' as $$
begin
  perform public.lock_memberships(p_user);
  delete from public.household_members m where m.user_id = p_user and m.household_id = p_household;
  if not found then
    return 'none';
  end if;
  -- Waits for a join that holds the household (accept_invite's share lock), so its new member is
  -- seen here and the household isn't archived or deleted under them.
  perform from public.households h where h.id = p_household for update;
  if exists (select from public.household_members where household_id = p_household) then
    return 'left';
  end if;
  if p_archive and public.household_has_premium(p_household) then
    if not public.app_switch('household_archive') then
      raise exception 'archive_disabled'
        using hint = 'Archiving households is switched off on this server (app_switches).';
    end if;
    update public.households set archived_at = now(), archived_by = p_user where id = p_household;
    return 'archived';
  end if;
  delete from public.households where id = p_household;
  return 'deleted';
end $$;
revoke execute on function public.leave_household_as(uuid, uuid, boolean) from public, anon, authenticated;

create function public.leave_household(p_household uuid, p_archive boolean default false)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_outcome text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  v_outcome := public.leave_household_as(auth.uid(), p_household, coalesce(p_archive, false));
  if v_outcome = 'none' then
    raise exception 'not_member' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'status', 'left', 'deleted', v_outcome = 'deleted', 'archived', v_outcome = 'archived'
  );
end $$;
revoke execute on function public.leave_household(uuid, boolean) from public, anon;
grant execute on function public.leave_household(uuid, boolean) to authenticated;

-- Old signatures: they leave the default household only (they deleted every membership before).
create or replace function public.leave_current_household(p_archive boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid := public.default_household_of(auth.uid());
begin
  if v_household is null then
    return 'none';
  end if;
  return public.leave_household_as(auth.uid(), v_household, p_archive);
end $$;

create or replace function public.leave_current_household() returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.leave_current_household(false);
end $$;

-- Joining ----------------------------------------------------------------------------------------

create function public.invalid_mode() returns jsonb
language plpgsql volatile set search_path = '' as $$
begin
  raise exception 'invalid_mode' using errcode = '22023';
end $$;
revoke execute on function public.invalid_mode() from public, anon, authenticated;

-- Checks [p_code] and uses the invite: status 'ok' with the household to join, else the answer
-- (member, invalid_invite, too_many_attempts) for the caller to return.
create function public.claim_invite(p_code text, out status text, out household_id uuid)
language plpgsql security definer set search_path = '' as $$
declare
  v_check record;
begin
  select * into v_check from public.check_invite(p_code);
  if v_check.status = 'member' then
    status := 'member';
    household_id := v_check.household_id;
    return;
  elsif v_check.status <> 'ok' then
    status := v_check.status;
    return;
  end if;
  -- Its last member may be archiving it right now: wait for that, then don't join an archived one.
  if not exists (
    select from public.households h where h.id = v_check.household_id and h.archived_at is null for share
  ) then
    status := 'invalid_invite';
    return;
  end if;

  update public.invites i set used_at = now(), used_by = auth.uid()
  where i.id = v_check.invite_id and i.used_at is null and i.revoked_at is null and i.expires_at > now()
  returning i.household_id into household_id;
  if household_id is null then
    -- Lost the race. The winner may have been this same user (a double tap): then they are in.
    if public.is_household_member(v_check.household_id) then
      status := 'member';
      household_id := v_check.household_id;
      return;
    end if;
    delete from public.invite_attempts a where a.at < now() - interval '1 day';
    insert into public.invite_attempts (user_id) values (auth.uid());
    status := 'invalid_invite';
    return;
  end if;
  status := 'ok';
end $$;
revoke execute on function public.claim_invite(text) from public, anon, authenticated;

-- Old signature: joining moves the user out of their default household (not out of the others)
-- and makes the joined one the default, so an old app shows the household it just joined.
create or replace function public.accept_invite(p_code text, p_archive boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_claim record;
  v_previous text;
begin
  select * into v_claim from public.claim_invite(p_code);
  if v_claim.status <> 'ok' then
    return jsonb_build_object('status', v_claim.status, 'household_id', v_claim.household_id);
  end if;
  v_previous := public.leave_current_household(p_archive);
  insert into public.household_members (household_id, user_id, role)
  values (v_claim.household_id, auth.uid(), 'member');
  perform public.make_default_household(auth.uid(), v_claim.household_id);
  return jsonb_build_object('status', 'joined', 'household_id', v_claim.household_id, 'previous', v_previous);
end $$;

-- The new app's join: adds a membership and leaves nothing. p_mode has no default so the old
-- one-argument call still reaches the old signature.
create function public.accept_invite(p_code text, p_mode text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_claim record;
begin
  if p_mode is distinct from 'add' then
    raise exception 'invalid_mode' using errcode = '22023';
  end if;
  select * into v_claim from public.claim_invite(p_code);
  if v_claim.status <> 'ok' then
    return jsonb_build_object('status', v_claim.status, 'household_id', v_claim.household_id);
  end if;
  insert into public.household_members (household_id, user_id, role)
  values (v_claim.household_id, auth.uid(), 'member');
  return jsonb_build_object('status', 'joined', 'household_id', v_claim.household_id);
end $$;
revoke execute on function public.accept_invite(text, text) from public, anon;
grant execute on function public.accept_invite(text, text) to authenticated;

-- Old signature: leaves the default household and makes the restored one the default.
create or replace function public.unarchive_household(p_household uuid, p_archive boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_previous text;
begin
  perform from public.households h
  where h.id = p_household and h.archived_by = auth.uid() and h.archived_at is not null
  for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  v_previous := public.leave_current_household(p_archive);
  update public.households set archived_at = null, archived_by = null where id = p_household;
  insert into public.household_members (household_id, user_id, role)
  values (p_household, auth.uid(), 'owner');
  perform public.make_default_household(auth.uid(), p_household);
  return jsonb_build_object('status', 'unarchived', 'previous', v_previous);
end $$;

-- The new app's restore: adds the household back and leaves nothing. p_archive (what to do with
-- a household the restore leaves) takes the old call's arguments but has nothing to act on here.
create function public.unarchive_household_add(p_household uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform from public.households h
  where h.id = p_household and h.archived_by = auth.uid() and h.archived_at is not null
  for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  update public.households set archived_at = null, archived_by = null where id = p_household;
  insert into public.household_members (household_id, user_id, role)
  values (p_household, auth.uid(), 'owner');
  return jsonb_build_object('status', 'unarchived', 'previous', 'none');
end $$;
revoke execute on function public.unarchive_household_add(uuid) from public, anon, authenticated;

create function public.unarchive_household(p_household uuid, p_archive boolean, p_mode text)
returns jsonb
language sql security definer set search_path = '' as $$
  select case when p_mode = 'add' then public.unarchive_household_add(p_household)
    else public.invalid_mode() end
$$;
revoke execute on function public.unarchive_household(uuid, boolean, text) from public, anon;
grant execute on function public.unarchive_household(uuid, boolean, text) to authenticated;

-- The old join screen's warnings, judged against the default household.
create or replace function public.preview_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_check record;
  v_user uuid := auth.uid();
  v_current uuid;
begin
  select * into v_check from public.check_invite(p_code);
  if v_check.status not in ('ok', 'member') then
    return jsonb_build_object('status', v_check.status, 'name', null);
  end if;
  v_current := public.default_household_of(v_user);
  return jsonb_build_object(
    'status', v_check.status,
    'name', (select h.name from public.households h where h.id = v_check.household_id),
    'unlocked', public.household_has_premium(v_check.household_id)
  ) || case when v_check.status = 'ok' then jsonb_build_object(
    'leaves_unlocked', v_current is not null
      and not exists (
        select from public.household_members m where m.household_id = v_current and m.user_id <> v_user
      )
      and public.household_has_premium(v_current),
    'recent_purchase', exists (
      select from public.purchases p
      where p.user_id = v_user and p.revoked_at is null
        and p.purchased_at > now() - interval '30 days'
    )
  ) else '{}'::jsonb end;
end $$;

-- Whether the caller is the only member of [p_household] (null: the default) and it has premium.
create function public.leaves_unlocked(p_household uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select public.household_has_premium(m.household_id)
    from public.household_members m
    where m.user_id = auth.uid()
      and m.household_id = coalesce(p_household, public.default_household_of(auth.uid()))
      and not exists (
        select from public.household_members o
        where o.household_id = m.household_id and o.user_id <> m.user_id
      )
  ), false)
$$;
revoke execute on function public.leaves_unlocked(uuid) from public, anon;
grant execute on function public.leaves_unlocked(uuid) to authenticated;

create or replace function public.leaves_unlocked() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.leaves_unlocked(null::uuid)
$$;

-- Premium page: the caller's yearly plan as seen from [p_household] (null: the default).
create function public.my_yearly_plan(p_household uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with mine as (
    select p.bound_household, p.billing_issue, p.expires_at, p.auto_renew
    from public.purchases p
    where p.user_id = auth.uid() and p.plan = 'yearly' and p.revoked_at is null
      and p.expires_at > now()
  ), here as (
    select m.household_id from public.household_members m
    where m.user_id = auth.uid()
      and m.household_id = coalesce(p_household, public.default_household_of(auth.uid()))
  )
  select jsonb_build_object(
    'subscriber', exists (select from mine where bound_household in (select household_id from here)),
    'renewing', exists (
      select from mine where bound_household in (select household_id from here) and auto_renew
    ),
    'billing_issue', exists (
      select from mine where bound_household in (select household_id from here) and billing_issue
    ),
    'until', (select max(expires_at) from mine where bound_household in (select household_id from here)),
    'elsewhere', exists (
      select from mine
      where auto_renew and bound_household is distinct from (select household_id from here)
    ),
    'household_billed', exists (
      select from public.purchases p
      where p.bound_household in (select household_id from here) and p.plan = 'yearly'
        and p.revoked_at is null and p.expires_at > now() and p.auto_renew
    )
  )
$$;
revoke execute on function public.my_yearly_plan(uuid) from public, anon;
grant execute on function public.my_yearly_plan(uuid) to authenticated;

create or replace function public.my_yearly_plan() returns jsonb
language sql stable security definer set search_path = '' as $$
  select public.my_yearly_plan(null::uuid)
$$;

-- Access keys ------------------------------------------------------------------------------------

-- A token acts in [p_household] (a membership of the caller) or, without one, the default.
create function public.token_household(p_household uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_household is null then
    return public.default_household_of(auth.uid());
  end if;
  if not public.is_household_member(p_household) then
    return null;
  end if;
  return p_household;
end $$;
revoke execute on function public.token_household(uuid) from public, anon, authenticated;

create function public.create_personal_access_token(p_name text, p_household uuid)
returns table (id uuid, name text, token text)
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  v_household := public.token_household(p_household);
  if v_household is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if (select count(*) from public.personal_access_tokens t
      where t.user_id = auth.uid() and t.revoked_at is null and t.kind = 'pat') >= 20 then
    raise exception 'too_many_tokens' using errcode = 'P0001';
  end if;
  -- 32 random bytes, base64url without padding: 43 characters after the prefix.
  v_token := 'fgp_' || rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  return query
  insert into public.personal_access_tokens as t (household_id, user_id, name, token_hash, token_hint)
  values (
    v_household,
    auth.uid(),
    coalesce(nullif(btrim(p_name), ''), 'Token'),
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    right(v_token, 4)
  )
  returning t.id, t.name, v_token;
end $$;
revoke execute on function public.create_personal_access_token(text, uuid) from public, anon;
grant execute on function public.create_personal_access_token(text, uuid) to authenticated;

create or replace function public.create_personal_access_token(p_name text)
returns table (id uuid, name text, token text)
language sql security definer set search_path = '' as $$
  select * from public.create_personal_access_token(p_name, null::uuid)
$$;

create function public.create_api_token(p_name text, p_scopes text[], p_household uuid)
returns table (id uuid, name text, token text, scopes text[])
language plpgsql security definer set search_path = '' as $$
declare
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_household uuid;
  v_scopes text[];
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.app_switch('public_api') then
    raise exception 'api_disabled' using errcode = '42501',
      hint = 'The public API is switched off on this server (app_switches.public_api).';
  end if;
  if v_claims ? 'client_id' or nullif(v_claims ->> 'session_id', '') is null then
    raise exception 'session_required' using errcode = '42501';
  end if;
  v_household := public.token_household(p_household);
  if v_household is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  select array_agg(distinct s order by s) into v_scopes from unnest(p_scopes) s;
  if v_scopes is null or v_scopes not in ('{read}'::text[], '{read,write}'::text[]) then
    raise exception 'invalid_scopes' using errcode = '22023';
  end if;
  if (select count(*) from public.personal_access_tokens t
      where t.user_id = auth.uid() and t.revoked_at is null and t.kind = 'api') >= 10 then
    raise exception 'too_many_tokens' using errcode = 'P0001';
  end if;
  -- 32 random bytes, base64url without padding: 43 characters after the prefix.
  v_token := 'fgp_' || rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  return query
  insert into public.personal_access_tokens as t
    (household_id, user_id, name, token_hash, token_hint, kind, scopes)
  values (
    v_household,
    auth.uid(),
    coalesce(nullif(btrim(p_name), ''), 'API'),
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    right(v_token, 4),
    'api',
    v_scopes
  )
  returning t.id, t.name, v_token, t.scopes;
end $$;
revoke execute on function public.create_api_token(text, text[], uuid) from public, anon;
grant execute on function public.create_api_token(text, text[], uuid) to authenticated;

create or replace function public.create_api_token(p_name text, p_scopes text[])
returns table (id uuid, name text, token text, scopes text[])
language sql security definer set search_path = '' as $$
  select * from public.create_api_token(p_name, p_scopes, null::uuid)
$$;

-- A Siri credential is per user and device: it acts in the default household at request time
-- (authenticate_access_token). household_id records the default it was made in.
create or replace function public.create_siri_credential(p_replace uuid default null)
returns table (id uuid, token text)
language plpgsql security definer set search_path = '' as $$
declare
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_session uuid;
  v_household uuid;
  v_token text;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_claims ? 'client_id' then
    raise exception 'session_required' using errcode = '42501';
  end if;
  v_session := nullif(v_claims ->> 'session_id', '')::uuid;
  if v_session is null then
    raise exception 'session_required' using errcode = '42501';
  end if;
  v_household := public.default_household_of(auth.uid());
  if v_household is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  update public.personal_access_tokens t set revoked_at = now()
  where t.id = p_replace and t.user_id = auth.uid() and t.kind = 'siri' and t.revoked_at is null;

  v_token := 'fgp_' || rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  -- clock_timestamp: several credentials made in one transaction still sort by age for the cap.
  insert into public.personal_access_tokens as t
    (household_id, user_id, name, token_hash, token_hint, kind, session_id, created_at)
  values (
    v_household,
    auth.uid(),
    'Siri',
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    right(v_token, 4),
    'siri',
    v_session,
    clock_timestamp()
  )
  returning t.id into v_id;

  update public.personal_access_tokens t set revoked_at = now()
  where t.id in (
    select s.id from public.personal_access_tokens s
    where s.user_id = auth.uid() and s.kind = 'siri' and s.revoked_at is null and s.id <> v_id
    order by s.created_at desc, s.id desc
    offset 4
  );

  return query select v_id, v_token;
end $$;

-- PATs act in the household they were made in, Siri credentials in the user's default now.
create or replace function public.authenticate_access_token(p_token_hash text)
returns table (user_id uuid, household_id uuid, kind text)
language sql security definer set search_path = '' as $$
  update public.personal_access_tokens t
  set last_used_at = now()
  from public.household_members m
  where t.token_hash = p_token_hash
    and t.revoked_at is null
    and m.user_id = t.user_id
    and case when t.kind = 'siri' then m.is_default else m.household_id = t.household_id end
    and (t.kind = 'pat' or exists (
      select from auth.sessions s
      where s.id = t.session_id and s.user_id = t.user_id
        and (s.not_after is null or s.not_after > now())
    ))
  returning t.user_id, m.household_id, t.kind;
$$;

-- Leaving a household ends the user's PATs and API keys there. Siri credentials follow the
-- default: they end only with the last membership, and otherwise move on with the user, so the
-- household's deletion (its foreign key cascades) never takes them along.
create or replace function public.household_member_end_access_tokens() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_next uuid;
begin
  if exists (select from public.households h where h.id = old.household_id)
    and exists (select from auth.users u where u.id = old.user_id) then
    update public.personal_access_tokens t set revoked_at = now()
    where t.user_id = old.user_id and t.household_id = old.household_id and t.kind <> 'siri'
      and t.revoked_at is null;
    select m.household_id into v_next from public.household_members m
    where m.user_id = old.user_id
    order by m.is_default desc, m.joined_at, m.household_id
    limit 1;
    if v_next is null then
      update public.personal_access_tokens t set revoked_at = now()
      where t.user_id = old.user_id and t.kind = 'siri' and t.revoked_at is null;
    else
      update public.personal_access_tokens t set household_id = v_next
      where t.user_id = old.user_id and t.kind = 'siri' and t.household_id = old.household_id
        and t.revoked_at is null;
    end if;
  end if;
  return null;
end $$;

create or replace function public.purge_access_tokens() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  update public.personal_access_tokens t set revoked_at = now()
  where t.revoked_at is null
    and (
      (t.kind <> 'siri' and not exists (
        select from public.household_members m
        where m.user_id = t.user_id and m.household_id = t.household_id
      ))
      or (t.kind = 'siri' and not exists (
        select from public.household_members m where m.user_id = t.user_id
      ))
      or (t.kind = 'siri' and not exists (
        select from auth.sessions s
        where s.id = t.session_id and s.user_id = t.user_id
          and (s.not_after is null or s.not_after > now())
      ))
    );
  delete from public.personal_access_tokens t where t.revoked_at < now() - interval '30 days';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- Feedback and the account -----------------------------------------------------------------------

-- Feedback files under the household the app sends when the sender is in it, else the default.
grant insert (household_id) on public.feedback to authenticated;
create or replace function public.feedback_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_domain text;
begin
  -- Only the signed-in sender's own repeat: a row claiming someone else still meets the policy.
  if new.user_id = auth.uid()
     and exists (select from public.feedback f where f.id = new.id and f.user_id = new.user_id) then
    return null;
  end if;
  new.message := public.feedback_trim(new.message);
  new.created_at := now();
  if new.household_id is null or not exists (
    select from public.household_members m
    where m.user_id = new.user_id and m.household_id = new.household_id
  ) then
    new.household_id := public.default_household_of(new.user_id);
  end if;
  v_domain := lower((select split_part(u.email, '@', 2) from auth.users u where u.id = new.user_id));
  if split_part(v_domain, '.', -1) in ('test', 'invalid', 'example', 'localhost')
     or v_domain in ('example.com', 'example.net', 'example.org')
     or v_domain like any (array['%.example.com', '%.example.net', '%.example.org']) then
    new.is_internal := true;
  end if;
  return new;
end $$;

-- Every membership goes: each household is kept (the owner role passes to its earliest-joined
-- member) or deleted with its last member. The answer is the default household's fate, the one
-- old apps showed before deleting.
create or replace function public.delete_account(p_user uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_default uuid := public.default_household_of(p_user);
  v_household uuid;
  v_role text;
  v_this text;
  v_fate text := 'none';
begin
  -- The household row locks serialize with joins (their membership insert takes a key share lock
  -- on the household) and with another member deleting their account at once. Household id
  -- order, so two deletions sharing households lock them in the same order.
  for v_household, v_role in
    select h.id, m.role
    from public.households h
    join public.household_members m on m.household_id = h.id
    where m.user_id = p_user
    order by h.id
    for update of h
  loop
    if exists (
      select from public.household_members m
      where m.household_id = v_household and m.user_id <> p_user
    ) then
      v_this := 'kept';
      if v_role = 'owner' then
        update public.household_members set role = 'owner'
        where household_id = v_household
          and user_id = (
            select m.user_id from public.household_members m
            where m.household_id = v_household and m.user_id <> p_user
            order by m.joined_at, m.user_id
            limit 1
          );
      end if;
    else
      v_this := 'deleted';
      delete from public.households where id = v_household;
    end if;
    if v_household = v_default then
      v_fate := v_this;
    end if;
  end loop;

  -- Job 43: the households they archived have no one else to come back to them.
  delete from public.households where archived_by = p_user;
  update public.item_events set actor = null where actor = p_user;
  delete from auth.users where id = p_user;
  return v_fate;
end $$;

-- The export lists every household under "households"; "household" stays the default, the shape
-- old apps know.
create or replace function public.export_my_data() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- An app connected over OAuth (MCP) acts on the list, not on the account.
  if auth.jwt() ->> 'client_id' is not null then
    raise exception 'session_required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'format', 'family-groceries-export',
    'version', 1,
    'exported_at', now(),
    'account', (
      select jsonb_build_object(
        'id', u.id,
        'email', u.email,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'providers', coalesce(
          (select jsonb_agg(distinct i.provider) from auth.identities i where i.user_id = u.id),
          '[]'::jsonb
        )
      )
      from auth.users u where u.id = v_user
    ),
    'profile', (
      select jsonb_build_object('display_name', p.display_name, 'created_at', p.created_at)
      from public.profiles p where p.id = v_user
    ),
    'household', (
      select jsonb_build_object('id', h.id, 'name', h.name, 'role', m.role, 'joined_at', m.joined_at)
      from public.household_members m
      join public.households h on h.id = m.household_id
      where m.user_id = v_user and m.is_default
    ),
    'households', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id,
        'name', h.name,
        'kind', h.kind,
        'role', m.role,
        'joined_at', m.joined_at,
        'is_default', m.is_default
      ) order by m.joined_at, h.id)
      from public.household_members m
      join public.households h on h.id = m.household_id
      where m.user_id = v_user
    ), '[]'::jsonb),
    'items_added', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', i.name,
        'brand', i.brand,
        'properties', i.properties,
        'quantity', i.quantity,
        'status', i.status,
        'category', c.name,
        'store', s.name,
        'created_at', i.created_at,
        'bought_at', i.bought_at
      ) order by i.created_at, i.id)
      from public.items i
      join public.household_members m on m.household_id = i.household_id and m.user_id = v_user
      left join public.categories c on c.id = i.category_id
      left join public.stores s on s.id = i.store_id
      where i.added_by = v_user
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', e.action,
        'item_name', e.item_name,
        'category', c.name,
        'created_at', e.created_at
      ) order by e.created_at, e.id)
      from public.item_events e
      left join public.categories c on c.id = e.category_id
      where e.actor = v_user
    ), '[]'::jsonb),
    'access_tokens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', t.name,
        'token_hint', t.token_hint,
        'created_at', t.created_at,
        'last_used_at', t.last_used_at,
        'revoked_at', t.revoked_at
      ) order by t.created_at, t.id)
      from public.personal_access_tokens t
      where t.user_id = v_user
    ), '[]'::jsonb),
    'invites_created', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', iv.code,
        'created_at', iv.created_at,
        'expires_at', iv.expires_at,
        'used_at', iv.used_at,
        'revoked_at', iv.revoked_at
      ) order by iv.created_at, iv.id)
      from public.invites iv
      where iv.created_by = v_user
    ), '[]'::jsonb),
    'feedback', coalesce((
      select jsonb_agg(jsonb_build_object(
        'created_at', f.created_at,
        'message', f.message,
        'category', f.category,
        'contact_ok', f.contact_ok,
        'screen', f.screen,
        'platform', f.platform,
        'app_version', f.app_version,
        'build', f.build,
        'os_version', f.os_version,
        'locale', f.locale,
        'household_id', f.household_id,
        'is_internal', f.is_internal
      ) order by f.created_at, f.id)
      from public.feedback f
      where f.user_id = v_user
    ), '[]'::jsonb),
    'connected_apps', coalesce((
      select jsonb_agg(jsonb_build_object(
        'client_name', oc.client_name,
        'scopes', c.scopes,
        'granted_at', c.granted_at,
        'revoked_at', c.revoked_at,
        'device', d.device
      ) order by c.granted_at, c.id)
      from auth.oauth_consents c
      join auth.oauth_clients oc on oc.id = c.client_id
      left join public.oauth_app_devices d on d.user_id = c.user_id and d.client_id = c.client_id
      where c.user_id = v_user
    ), '[]'::jsonb),
    'analytics_decisions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'install_id', a.install_id,
        'consent', a.consent,
        'internal', a.internal,
        'decided_at', a.decided_at,
        'consent_text_version', a.consent_text_version
      ) order by a.decided_at, a.install_id)
      from public.analytics_consents a
      where a.user_id = v_user
    ), '[]'::jsonb),
    'alexa_links', coalesce((
      select jsonb_agg(jsonb_build_object('last_seen', l.last_seen) order by l.last_seen)
      from public.alexa_links l
      where l.user_id = v_user
    ), '[]'::jsonb),
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'store', p.store,
        'product_id', p.product_id,
        'plan', p.plan,
        'transaction_id', p.transaction_id,
        'environment', p.environment,
        'purchased_at', p.purchased_at,
        'expires_at', p.expires_at,
        'auto_renew', p.auto_renew,
        'revoked_at', p.revoked_at,
        'price', p.price,
        'currency', p.currency,
        'country', p.country,
        'unlocks_household', (select e.household_id from public.entitlements e where e.purchase_id = p.id),
        'belongs_to_household', p.bound_household
      ) order by p.purchased_at, p.id)
      from public.purchases p
      where p.user_id = v_user
    ), '[]'::jsonb),
    'archived_households', coalesce((
      select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name, 'archived_at', h.archived_at)
        order by h.archived_at, h.id)
      from public.households h where h.archived_by = v_user
    ), '[]'::jsonb)
  );
end $$;
