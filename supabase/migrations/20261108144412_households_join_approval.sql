-- Job 169b wave 3, part M: join approval (docs/households/W3.md). With households.join_approval
-- on, accepting any invite files a join request instead of a membership and answers
-- {status: 'requested', household_id}; the old accept_invite signatures pass that status on, and
-- old store builds show it as their generic error (approval is new and opt-in). The owner and
-- admins approve or decline; an approval joins the requester and counts the invite's use under
-- the invite's row lock, as a join does. Club households created from now on start with approval
-- on. The export (end of file) also lists the user's lists, claims and join requests.

alter table public.households add column join_approval boolean not null default false;
comment on column public.households.join_approval is
  'Job 169b: joins wait for an owner or admin (join_requests). Set through set_join_approval; on for new club households.';

-- Whether the caller is the owner or an admin of [p_household].
create function public.is_household_admin(p_household uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.household_members m
    where m.household_id = p_household and m.user_id = auth.uid() and m.role in ('owner', 'admin')
  )
$$;
revoke execute on function public.is_household_admin(uuid) from public, anon;
grant execute on function public.is_household_admin(uuid) to authenticated;

-- Requests ---------------------------------------------------------------------------------------

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  invite_id uuid references public.invites (id) on delete set null,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decision text check (decision in ('approved', 'declined', 'cancelled')),
  decided_by uuid references auth.users (id) on delete set null,
  check ((decision is null) = (decided_at is null))
);
-- One open request per user and household: asking again answers the open one.
create unique index join_requests_pending on public.join_requests (household_id, user_id)
  where decision is null;
create index join_requests_user on public.join_requests (user_id, created_at);
create index join_requests_decided on public.join_requests (decided_at) where decided_at is not null;
alter table public.join_requests enable row level security;
revoke all on public.join_requests from public, anon, authenticated;
grant select on public.join_requests to authenticated;
-- The requester and the household's owner and admins; plain members see no requests.
create policy join_requests_select on public.join_requests for select to authenticated
  using (
    user_id = (select auth.uid())
    or (public.is_household_member(household_id) and public.is_household_admin(household_id))
  );
alter publication supabase_realtime add table public.join_requests;

comment on table public.join_requests is
  'Job 169b: requests to join a household with join approval on. Personal data of the requester; decided ones are deleted after 7 days.';

-- Decided requests go after 7 days (my_join_requests shows them that long); open ones stay until
-- decided or cancelled.
create function public.purge_join_requests() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.join_requests r where r.decided_at < now() - interval '7 days';
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke execute on function public.purge_join_requests() from public, anon, authenticated;
select cron.schedule('purge-join-requests', '47 3 * * *', 'select public.purge_join_requests()');

-- W2's claim: with approval on, a valid invite files (or finds) the user's open request and
-- answers 'requested' without counting a use; the use is counted when an admin approves.
create or replace function public.claim_invite(p_code text, out status text, out household_id uuid)
language plpgsql security definer set search_path = '' as $$
-- The conflict target names the column, not the out parameter.
#variable_conflict use_column
declare
  v_check record;
  v_approval boolean;
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
  select h.join_approval into v_approval from public.households h
  where h.id = v_check.household_id and h.archived_at is null
  for share;
  if not found then
    status := 'invalid_invite';
    return;
  end if;

  if v_approval then
    insert into public.join_requests (household_id, user_id, invite_id)
    values (v_check.household_id, auth.uid(), v_check.invite_id)
    on conflict (household_id, user_id) where decision is null do nothing;
    status := 'requested';
    household_id := v_check.household_id;
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

-- The oldest builds' join: the household's id once joined. A filed request is no membership, so
-- it answers null, as an invalid code does, rather than an id the caller cannot open.
create or replace function public.join_household(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_result jsonb := public.accept_invite(p_code);
begin
  if v_result ->> 'status' = 'too_many_attempts' then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;
  if v_result ->> 'status' = 'requested' then
    return null;
  end if;
  return (v_result ->> 'household_id')::uuid;
end $$;

-- The owner or an admin of [p_household] calling; not_member or not_admin otherwise.
create function public.require_household_admin(p_household uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.is_household_member(p_household) then
    raise exception 'not_member' using errcode = '42501';
  end if;
  if not public.is_household_admin(p_household) then
    raise exception 'not_admin' using errcode = '42501';
  end if;
end $$;
revoke execute on function public.require_household_admin(uuid) from public, anon, authenticated;

-- The owner and admins switch approval on or off. Open requests stay open either way.
create function public.set_join_approval(p_household uuid, p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_on is null then
    raise exception 'invalid_value' using errcode = '22023';
  end if;
  perform public.require_household_admin(p_household);
  update public.households h set join_approval = p_on
  where h.id = p_household and h.join_approval <> p_on;
end $$;
revoke execute on function public.set_join_approval(uuid, boolean) from public, anon;
grant execute on function public.set_join_approval(uuid, boolean) to authenticated;

-- The household's open requests, oldest first, with the requester's display name and the kind of
-- invite they came through (null when it was deleted since).
create function public.household_join_requests(p_household uuid)
returns table (
  id uuid, user_id uuid, display_name text, invite_id uuid, invite_kind text, created_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_household_admin(p_household);
  return query
  select r.id, r.user_id, p.display_name, r.invite_id, i.kind, r.created_at
  from public.join_requests r
  left join public.profiles p on p.id = r.user_id
  left join public.invites i on i.id = r.invite_id
  where r.household_id = p_household and r.decision is null
  order by r.created_at, r.id;
end $$;
revoke execute on function public.household_join_requests(uuid) from public, anon;
grant execute on function public.household_join_requests(uuid) to authenticated;

-- An admin's decision: {status, household_id, user_id}. status is 'approved' (the requester is a
-- member now, the invite's use counted), 'declined', or for a request decided before its decision
-- ('approved', 'declined', 'cancelled'), so a repeated call answers the same. 'invite_full': the
-- invite has no use left (a group link at 50, a used person invite); the request stays open.
-- request_not_found for no such request or another household's, not_admin for a plain member.
create function public.decide_join_request(p_request uuid, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_request public.join_requests;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_approve is null then
    raise exception 'invalid_value' using errcode = '22023';
  end if;
  select * into v_request from public.join_requests r where r.id = p_request;
  if not found or not public.is_household_member(v_request.household_id) then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;
  if not public.is_household_admin(v_request.household_id) then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  -- A join's lock order: the household, the invite row, then the joiner's memberships (the
  -- membership insert's trigger).
  perform from public.households h where h.id = v_request.household_id for share;
  select * into v_request from public.join_requests r where r.id = p_request for update;
  if v_request.decision is not null then
    return jsonb_build_object(
      'status', v_request.decision, 'household_id', v_request.household_id,
      'user_id', v_request.user_id);
  end if;

  if p_approve and not exists (
    select from public.household_members m
    where m.household_id = v_request.household_id and m.user_id = v_request.user_id
  ) then
    if v_request.invite_id is not null then
      update public.invites i set
        use_count = i.use_count + 1,
        used_at = case when i.use_count + 1 = i.max_uses then now() end,
        used_by = case when i.kind = 'person' then v_request.user_id end
      where i.id = v_request.invite_id and i.use_count < i.max_uses;
      if not found then
        return jsonb_build_object(
          'status', 'invite_full', 'household_id', v_request.household_id,
          'user_id', v_request.user_id);
      end if;
      insert into public.invite_uses as u (invite_id, household_id, user_id)
      values (v_request.invite_id, v_request.household_id, v_request.user_id)
      on conflict (invite_id, user_id) do update set joined_at = now();
    end if;
    insert into public.household_members (household_id, user_id, role)
    values (v_request.household_id, v_request.user_id, 'member');
  end if;

  update public.join_requests r set
    decision = case when p_approve then 'approved' else 'declined' end,
    decided_at = now(),
    decided_by = auth.uid()
  where r.id = p_request
  returning * into v_request;
  return jsonb_build_object(
    'status', v_request.decision, 'household_id', v_request.household_id,
    'user_id', v_request.user_id);
end $$;
revoke execute on function public.decide_join_request(uuid, boolean) from public, anon;
grant execute on function public.decide_join_request(uuid, boolean) to authenticated;

-- The requester withdraws: {status: 'cancelled'}, or the decision made before.
create function public.cancel_join_request(p_request uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_request public.join_requests;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_request from public.join_requests r
  where r.id = p_request and r.user_id = auth.uid()
  for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;
  if v_request.decision is null then
    update public.join_requests r set decision = 'cancelled', decided_at = now(), decided_by = auth.uid()
    where r.id = p_request
    returning * into v_request;
  end if;
  return jsonb_build_object('status', v_request.decision, 'household_id', v_request.household_id);
end $$;
revoke execute on function public.cancel_join_request(uuid) from public, anon;
grant execute on function public.cancel_join_request(uuid) to authenticated;

-- The caller's open requests and those decided in the last 7 days, newest first, with the
-- household's name.
create function public.my_join_requests()
returns table (
  id uuid, household_id uuid, household_name text, decision text, created_at timestamptz,
  decided_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select r.id, r.household_id, h.name, r.decision, r.created_at, r.decided_at
  from public.join_requests r
  join public.households h on h.id = r.household_id
  where r.user_id = auth.uid()
    and (r.decision is null or r.decided_at > now() - interval '7 days')
  order by r.created_at desc, r.id
$$;
revoke execute on function public.my_join_requests() from public, anon;
grant execute on function public.my_join_requests() to authenticated;

-- W1's create with a request id: a club starts with join approval on.
create or replace function public.create_household(
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
  insert into public.households (name, created_by, request_id, kind, join_approval)
  values (coalesce(nullif(btrim(p_name), ''), 'Unser Haushalt'), auth.uid(), p_request_id, p_kind,
          p_kind is not distinct from 'club')
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

-- The export adds the user's lists, claims and join requests, and each added item's list.
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
        'list', l.name,
        'created_at', i.created_at,
        'bought_at', i.bought_at
      ) order by i.created_at, i.id)
      from public.items i
      join public.household_members m on m.household_id = i.household_id and m.user_id = v_user
      left join public.categories c on c.id = i.category_id
      left join public.stores s on s.id = i.store_id
      left join public.lists l on l.id = i.list_id
      where i.added_by = v_user
    ), '[]'::jsonb),
    'lists_created', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', l.household_id, 'name', l.name, 'created_at', l.created_at
      ) order by l.created_at, l.id)
      from public.lists l where l.created_by = v_user
    ), '[]'::jsonb),
    'item_claims', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', c.household_id, 'item_name', i.name, 'quantity', c.quantity,
        'created_at', c.created_at
      ) order by c.created_at, c.item_id)
      from public.item_claims c join public.items i on i.id = c.item_id
      where c.user_id = v_user
    ), '[]'::jsonb),
    'join_requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', r.household_id, 'created_at', r.created_at, 'decision', r.decision,
        'decided_at', r.decided_at
      ) order by r.created_at, r.id)
      from public.join_requests r where r.user_id = v_user
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
