-- Job 169b wave 2: the invite loop (docs/households/W2.md). Person invites (any member, 7 days, one
-- use) and group links (owner and admins, 30 days, 50 uses, one open per household) count their
-- uses under the invite's row lock; every join is a row in invite_uses. Owners name admins, owners
-- and admins remove members, and ownership passes on whenever the owner goes. A signed-out join
-- page previews a code through preview_invite_public, rate-limited per hashed client and per code.

-- Invites ----------------------------------------------------------------------------------------

alter table public.invites
  add column kind text not null default 'person' check (kind in ('person', 'group')),
  add column max_uses integer not null default 1 check (max_uses between 1 and 50),
  add column use_count integer not null default 0,
  add column preview_count integer not null default 0;
update public.invites set use_count = 1 where used_at is not null;
-- squawk-ignore constraint-missing-not-valid -- invites is small (open ones last 7 days) and the update above makes every row pass
alter table public.invites add constraint invites_use_count_check
  check (use_count between 0 and max_uses);

comment on column public.invites.max_uses is 'Joins the invite allows: 1 for a person invite, 50 for a group link.';
comment on column public.invites.use_count is 'Joins so far; the invite is used up at max_uses (used_at is set then).';
comment on column public.invites.preview_count is 'How often the signed-out join page showed it (a counter, no identities).';

-- One row per join through an invite: the "joined" lists read it.
create table public.invite_uses (
  invite_id uuid not null references public.invites (id) on delete cascade,
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (invite_id, user_id)
);
create index invite_uses_household on public.invite_uses (household_id);
create index invite_uses_user on public.invite_uses (user_id);
alter table public.invite_uses enable row level security;
revoke all on public.invite_uses from public, anon, authenticated;
grant select on public.invite_uses to authenticated;
create policy invite_uses_select on public.invite_uses for select to authenticated
  using (public.is_household_member(household_id));
alter publication supabase_realtime add table public.invite_uses;

comment on table public.invite_uses is
  'Job 169b: who joined through which invite, for the household''s members. Written by claim_invite only.';

-- The caller's role in [p_household], null when they are not in it.
create function public.my_role_in(p_household uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.role from public.household_members m
  where m.household_id = p_household and m.user_id = auth.uid()
$$;
revoke execute on function public.my_role_in(uuid) from public, anon, authenticated;

-- A person invite (any member) or the household's group link (owner and admins). A group link
-- while one is open answers that one, so a second admin or a retry gets the same code; after a
-- revoke, an expiry or the 50th join the next call makes a new one. p_kind has no default so the
-- old one-argument call still reaches the old signature.
create function public.create_invite(p_household uuid, p_kind text) returns public.invites
language plpgsql security definer set search_path = '' as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_role text := public.my_role_in(p_household);
  v_bytes bytea;
  v_code text;
  v_invite public.invites;
begin
  if p_kind is null or p_kind not in ('person', 'group') then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if v_role is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if p_kind = 'group' then
    if v_role = 'member' then
      raise exception 'not_admin' using errcode = '42501';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('group_invite:' || p_household::text, 0));
    select * into v_invite from public.invites i
    where i.household_id = p_household and i.kind = 'group' and i.revoked_at is null
      and i.expires_at > now() and i.use_count < i.max_uses
    order by i.created_at desc, i.id
    limit 1;
    if found then
      return v_invite;
    end if;
  end if;
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, 1 + get_byte(v_bytes, i) % 32, 1);
    end loop;
    exit when not exists (select from public.invites i where i.code = v_code);
  end loop;
  insert into public.invites (household_id, code, created_by, kind, max_uses, expires_at)
  values (
    p_household, v_code, auth.uid(), p_kind,
    case p_kind when 'group' then 50 else 1 end,
    now() + case p_kind when 'group' then interval '30 days' else interval '7 days' end
  )
  returning * into v_invite;
  return v_invite;
end $$;
revoke execute on function public.create_invite(uuid, text) from public, anon;
grant execute on function public.create_invite(uuid, text) to authenticated;

-- Old store builds: a person invite, the same row and errors as before.
create or replace function public.create_invite(p_household uuid) returns public.invites
language plpgsql security definer set search_path = '' as $$
begin
  return public.create_invite(p_household, 'person');
end $$;

-- The household's open invites, newest first: not revoked, not expired, not used up.
create function public.household_invites(p_household uuid)
returns table (
  id uuid, kind text, code text, expires_at timestamptz, max_uses integer, use_count integer,
  created_by uuid, created_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_member' using errcode = '42501';
  end if;
  return query
  select i.id, i.kind, i.code, i.expires_at, i.max_uses, i.use_count, i.created_by, i.created_at
  from public.invites i
  where i.household_id = p_household and i.revoked_at is null and i.expires_at > now()
    and i.use_count < i.max_uses
  order by i.created_at desc, i.id;
end $$;
revoke execute on function public.household_invites(uuid) from public, anon;
grant execute on function public.household_invites(uuid) to authenticated;

-- Who joined through [p_invite], in join order. not_member for an unknown invite too.
create function public.invite_joins(p_invite uuid)
returns table (user_id uuid, display_name text, joined_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_household uuid := (select i.household_id from public.invites i where i.id = p_invite);
begin
  if v_household is null or not public.is_household_member(v_household) then
    raise exception 'not_member' using errcode = '42501';
  end if;
  return query
  select u.user_id, p.display_name, u.joined_at
  from public.invite_uses u
  left join public.profiles p on p.id = u.user_id
  -- Only who is still in the household: a removed or departed member drops off the list.
  join public.household_members m on m.household_id = u.household_id and m.user_id = u.user_id
  where u.invite_id = p_invite
  order by u.joined_at, u.user_id;
end $$;
revoke execute on function public.invite_joins(uuid) from public, anon;
grant execute on function public.invite_joins(uuid) to authenticated;

-- Joining ----------------------------------------------------------------------------------------

-- Job 43's checks; an invite is open while it has uses left (used_at is null meant that for one).
create or replace function public.check_invite(p_code text, out status text, out invite_id uuid, out household_id uuid)
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_invite public.invites;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('invite_attempts:' || v_user::text, 0));
  if (select count(*) from public.invite_attempts a
      where a.user_id = v_user and a.at > now() - interval '1 hour') >= 10 then
    status := 'too_many_attempts';
    return;
  end if;
  select * into v_invite from public.invites i
  where i.code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_invite.id is not null and public.is_household_member(v_invite.household_id) then
    status := 'member';
  elsif v_invite.id is not null and v_invite.use_count < v_invite.max_uses
        and v_invite.revoked_at is null and v_invite.expires_at > now()
        and not exists (select from public.households h where h.id = v_invite.household_id and h.archived_at is not null) then
    status := 'ok';
  else
    status := 'invalid_invite';
    -- No raise anywhere on this path: it would roll this row back with the call.
    delete from public.invite_attempts a where a.at < now() - interval '1 day';
    insert into public.invite_attempts (user_id) values (v_user);
    return;
  end if;
  invite_id := v_invite.id;
  household_id := v_invite.household_id;
end $$;

-- W1's claim, counting uses: the conditional update takes the invite's row lock, and a join
-- waiting on it re-reads use_count, so a group link never takes a 51st join
-- (_shared/households_integration_test.ts).
create or replace function public.claim_invite(p_code text, out status text, out household_id uuid)
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

  update public.invites i set
    use_count = i.use_count + 1,
    used_at = case when i.use_count + 1 = i.max_uses then now() end,
    used_by = case when i.kind = 'person' then auth.uid() end
  where i.id = v_check.invite_id and i.use_count < i.max_uses and i.revoked_at is null
    and i.expires_at > now()
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
  -- Someone who left and comes back through the same link keeps one row, with the new time.
  insert into public.invite_uses as u (invite_id, household_id, user_id)
  values (v_check.invite_id, v_check.household_id, auth.uid())
  on conflict (invite_id, user_id) do update set joined_at = now();
  status := 'ok';
end $$;

-- Roles and removal ------------------------------------------------------------------------------

-- The owner role passes to the earliest-joined admin of [p_household], else its earliest-joined
-- member, never to [p_from] (the owner on their way out).
create function public.hand_over_ownership(p_household uuid, p_from uuid) returns void
language sql security definer set search_path = '' as $$
  update public.household_members m set role = 'owner'
  where m.household_id = p_household and m.user_id = (
    select o.user_id from public.household_members o
    where o.household_id = p_household and o.user_id <> p_from
    order by o.role = 'admin' desc, o.joined_at, o.user_id
    limit 1
  )
$$;
revoke execute on function public.hand_over_ownership(uuid, uuid) from public, anon, authenticated;

-- W1's leave, handing ownership on. The household lock comes before the delete: a join (its
-- share lock), a removal or a role change in the same household finishes first or waits, and
-- the handover never updates a member row another leave is deleting.
create or replace function public.leave_household_as(p_user uuid, p_household uuid, p_archive boolean)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_role text;
begin
  perform public.lock_memberships(p_user);
  perform from public.households h where h.id = p_household for update;
  delete from public.household_members m where m.user_id = p_user and m.household_id = p_household
  returning m.role into v_role;
  if not found then
    return 'none';
  end if;
  if exists (select from public.household_members where household_id = p_household) then
    if v_role = 'owner' then
      perform public.hand_over_ownership(p_household, p_user);
    end if;
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

-- The owner and admins remove members; an admin removes neither the owner nor another admin, and
-- nobody removes themselves (that is leaving). The removed user's default moves on and their keys
-- for the household end (the household_members triggers).
create function public.remove_member(p_household uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_mine text;
  v_theirs text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  -- leave_household_as's lock order: the removed user's memberships, then the household.
  perform public.lock_memberships(p_user);
  perform from public.households h where h.id = p_household for update;
  v_mine := public.my_role_in(p_household);
  if v_mine is null then
    raise exception 'not_member' using errcode = '42501';
  elsif v_mine = 'member' then
    raise exception 'not_admin' using errcode = '42501';
  elsif p_user = auth.uid() then
    raise exception 'cannot_remove_self' using errcode = '22023';
  end if;
  select m.role into v_theirs from public.household_members m
  where m.household_id = p_household and m.user_id = p_user;
  if v_theirs is null then
    raise exception 'not_member' using errcode = '42501';
  elsif v_theirs = 'owner' then
    raise exception 'cannot_remove_owner' using errcode = '42501';
  elsif v_theirs = 'admin' and v_mine <> 'owner' then
    raise exception 'cannot_remove_admin' using errcode = '42501';
  end if;
  perform public.leave_household_as(p_user, p_household, false);
end $$;
revoke execute on function public.remove_member(uuid, uuid) from public, anon;
grant execute on function public.remove_member(uuid, uuid) to authenticated;

-- The owner names (admin) and un-names (member) admins. The owner's own role does not change here.
create function public.set_member_role(p_household uuid, p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_mine text;
  v_theirs text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_role is null or p_role not in ('admin', 'member') then
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  perform from public.households h where h.id = p_household for update;
  v_mine := public.my_role_in(p_household);
  if v_mine is null then
    raise exception 'not_member' using errcode = '42501';
  elsif v_mine <> 'owner' then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  select m.role into v_theirs from public.household_members m
  where m.household_id = p_household and m.user_id = p_user;
  if v_theirs is null then
    raise exception 'not_member' using errcode = '42501';
  elsif v_theirs = 'owner' then
    raise exception 'cannot_change_owner' using errcode = '42501';
  end if;
  update public.household_members m set role = p_role
  where m.household_id = p_household and m.user_id = p_user;
end $$;
revoke execute on function public.set_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;

-- W1's account deletion, with the handover to an admin first. The user's membership lock comes
-- first, as in leave_household_as and remove_member, so neither waits on the other in a cycle.
create or replace function public.delete_account(p_user uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_default uuid := public.default_household_of(p_user);
  v_household uuid;
  v_role text;
  v_this text;
  v_fate text := 'none';
begin
  perform public.lock_memberships(p_user);
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
        perform public.hand_over_ownership(v_household, p_user);
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

-- The signed-out join page -----------------------------------------------------------------------

-- The salt for the preview's client keys: made here at random, never in the repo, readable by no
-- client. Rows keyed by it are gone within the hour, so it never needs to rotate.
create table public.invite_preview_salt (
  id boolean primary key default true check (id),
  salt bytea not null default extensions.gen_random_bytes(32)
);
alter table public.invite_preview_salt enable row level security;
revoke all on public.invite_preview_salt from public, anon, authenticated;
insert into public.invite_preview_salt default values;

comment on table public.invite_preview_salt is
  'Job 169b: the secret that salts invite_preview_rate''s keys; generated in the database. No client access.';

-- Preview opens per salted key and hour: one key per client (X-Real-IP) and one per code. Only
-- the current hour's rows are kept.
create table public.invite_preview_rate (
  key_hash text not null check (key_hash ~ '^[0-9a-f]{64}$'),
  window_start timestamptz not null,
  hits integer not null check (hits > 0),
  primary key (key_hash, window_start)
);
create index invite_preview_rate_window on public.invite_preview_rate (window_start);
alter table public.invite_preview_rate enable row level security;
revoke all on public.invite_preview_rate from public, anon, authenticated;

comment on table public.invite_preview_rate is
  'Job 169b: join page previews per salted SHA-256 of the client IP or the code, per hour; no raw IP or code. No client access.';

-- Counts one open for [p_key] (client or code, unsalted) in this hour; true when that is past
-- [p_limit].
create function public.invite_preview_hit(p_key text, p_limit integer) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_hits integer;
begin
  insert into public.invite_preview_rate as r (key_hash, window_start, hits)
  values (
    encode(extensions.digest(
      (select s.salt from public.invite_preview_salt s) || convert_to(p_key, 'UTF8'), 'sha256'), 'hex'),
    date_trunc('hour', now()),
    1
  )
  on conflict (key_hash, window_start) do update set hits = r.hits + 1
  returning r.hits into v_hits;
  return v_hits > p_limit;
end $$;
revoke execute on function public.invite_preview_hit(text, integer) from public, anon, authenticated;

-- What a link holder sees before signing in: {status, household, kind, inviter, members,
-- open_items, premium, invite_kind}. status ok, invalid (unknown, revoked, expired, a used person
-- invite, an archived household), full (a group link at 50) or rate_limited; every other field
-- is null unless ok. inviter is the creator's first name, if they set one. No ids, no emails, no
-- item names.
create function public.preview_invite_public(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_code text := upper(regexp_replace(left(coalesce(p_code, ''), 64), '[^A-Za-z0-9]', '', 'g'));
  v_client text := coalesce(
    nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-real-ip', '');
  v_invite public.invites;
  v_household public.households;
  v_status text;
begin
  delete from public.invite_preview_rate r where r.window_start < date_trunc('hour', now());
  if public.invite_preview_hit('client:' || v_client, 30) then
    v_status := 'rate_limited';
  elsif public.invite_preview_hit('code:' || v_code, 60) then
    v_status := 'rate_limited';
  else
    select * into v_invite from public.invites i where i.code = v_code;
    select * into v_household from public.households h where h.id = v_invite.household_id;
    if v_household.id is null or v_household.archived_at is not null
       or v_invite.revoked_at is not null or v_invite.expires_at <= now() then
      v_status := 'invalid';
    elsif v_invite.use_count >= v_invite.max_uses then
      v_status := case v_invite.kind when 'group' then 'full' else 'invalid' end;
    else
      v_status := 'ok';
    end if;
  end if;

  if v_status <> 'ok' then
    return jsonb_build_object(
      'status', v_status, 'household', null, 'kind', null, 'inviter', null, 'members', null,
      'open_items', null, 'premium', null, 'invite_kind', null
    );
  end if;
  update public.invites i set preview_count = i.preview_count + 1 where i.id = v_invite.id;
  return jsonb_build_object(
    'status', 'ok',
    'household', v_household.name,
    'kind', v_household.kind,
    -- A profile's name starts as the email's local part (handle_new_user): that one is not shown.
    'inviter', (
      select nullif(split_part(btrim(p.display_name), ' ', 1), '')
      from public.profiles p join auth.users u on u.id = p.id
      where p.id = v_invite.created_by
        and p.display_name is distinct from left(split_part(u.email, '@', 1), 80)
    ),
    'members', (
      select count(*)::int from public.household_members m where m.household_id = v_household.id
    ),
    'open_items', (
      select count(*)::int from public.items i
      where i.household_id = v_household.id and i.status = 'active'
    ),
    'premium', public.household_has_premium(v_household.id),
    'invite_kind', v_invite.kind
  );
end $$;
revoke execute on function public.preview_invite_public(text) from public;
grant execute on function public.preview_invite_public(text) to anon, authenticated;

-- The export lists which invites the user joined through (job 169b wave 2).
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
    'invite_uses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', u.household_id, 'invite_id', u.invite_id, 'joined_at', u.joined_at
      ) order by u.joined_at)
      from public.invite_uses u where u.user_id = v_user
    ), '[]'::jsonb),
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
