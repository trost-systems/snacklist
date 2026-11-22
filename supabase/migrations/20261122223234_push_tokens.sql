-- Job 376: devices for server push (docs/PUSH.md). One row per FCM registration token, owned by
-- the signed-in user, not by a household: the push function picks the devices of a household's
-- members at send time, so leaving a household needs no cleanup. Clients read their own rows and
-- write only through register_push_token and unregister_push_token.

create table public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null unique check (char_length(token) between 1 and 4096),
  platform text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index push_tokens_user_id_updated_at_idx on public.push_tokens (user_id, updated_at);

comment on table public.push_tokens is
  'Job 376: FCM registration tokens of a user''s devices (docs/PUSH.md). Written only by register_push_token and unregister_push_token; read by the push function over the service connection, exported by export_my_data without the token, gone with the account (foreign key) and after 270 days without a registration (purge-push-tokens).';
comment on column public.push_tokens.updated_at is
  'The last registration: the app registers again on every start while push is on.';

alter table public.push_tokens enable row level security;
create policy push_tokens_read_own on public.push_tokens for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.push_tokens from public, anon, authenticated;
grant select on public.push_tokens to authenticated;

-- Upserts the token for the caller. A token another account registered on this device moves to
-- the caller; the caller keeps their 10 most recently registered devices. The advisory lock makes
-- two registrations of one user take turns, so the cap holds; it is no row lock, so it cannot
-- wait in a circle with account deletion.
create function public.register_push_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_platform is null or p_platform not in ('ios', 'android') then
    raise exception 'invalid_platform' using errcode = '22023';
  end if;
  if p_token is null or char_length(p_token) not between 1 and 4096 then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('push_tokens:' || v_user::text, 0));
  insert into public.push_tokens as t (user_id, token, platform)
  values (v_user, p_token, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        created_at = case when t.user_id = excluded.user_id then t.created_at else now() end,
        updated_at = now();
  delete from public.push_tokens t
  where t.id in (
    select k.id from public.push_tokens k where k.user_id = v_user
    order by k.updated_at desc, k.id desc offset 10
  );
end $$;
revoke execute on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;

-- Deletes the caller's row for the token; the app calls it before sign-out. Someone else's row
-- for the same token stays.
create function public.unregister_push_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from public.push_tokens t where t.token = p_token and t.user_id = v_user;
end $$;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- A token not registered again for 270 days: FCM drops tokens of devices that stayed offline
-- that long, and the app registers again on every start while push is on.
create function public.purge_push_tokens() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.push_tokens t where t.updated_at < now() - interval '270 days';
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke execute on function public.purge_push_tokens() from public, anon, authenticated;

select cron.schedule('purge-push-tokens', '53 3 * * *', 'select public.purge_push_tokens()');

-- Data export: the user's push devices (platform and times, never the token). Otherwise unchanged
-- from 20261122020000_trip_detection.sql.
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
      select jsonb_build_object('id', h.id, 'name', h.name, 'role', m.role, 'joined_at', m.joined_at,
        'currency', h.currency)
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
    'household_removals', coalesce((
      select jsonb_agg(jsonb_build_object('household_id', r.household_id, 'removed_at', r.removed_at)
        order by r.removed_at, r.household_id)
      from public.household_removals r where r.user_id = v_user
    ), '[]'::jsonb),
    'households', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id,
        'name', h.name,
        'kind', h.kind,
        'role', m.role,
        'joined_at', m.joined_at,
        'is_default', m.is_default,
        'default_list', (select l.name from public.lists l where l.id = m.default_list_id),
        'currency', h.currency
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
        'bought_at', i.bought_at,
        'price_unit_micros', i.price_unit_micros,
        'price_basis', i.price_basis,
        'price_per', i.price_per,
        'price_currency', i.price_currency,
        'priced_at', i.priced_at
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
        'created_at', e.created_at,
        'client_at', e.client_at,
        'source', e.source
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
        'kind', iv.kind,
        'max_uses', iv.max_uses,
        'use_count', iv.use_count,
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
        'is_internal', f.is_internal,
        'screenshot', f.screenshot,
        'status', f.status,
        'fixed_in', f.fixed_in,
        'reply', f.reply,
        'replied_at', f.replied_at,
        'answered_at', f.answered_at,
        'seen_at', f.seen_at
      ) order by f.created_at, f.id)
      from public.feedback f
      where f.user_id = v_user
    ), '[]'::jsonb),
    'feedback_idea_votes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', v.household_id,
        'title_de', i.title_de,
        'title_en', i.title_en,
        'created_at', v.created_at
      ) order by v.created_at, v.household_id, v.idea_id)
      from public.feedback_idea_votes v
      join public.feedback_ideas i on i.id = v.idea_id
      join public.household_members m on m.household_id = v.household_id and m.user_id = v_user
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
    ), '[]'::jsonb),
    'trips_logged', coalesce((
      select jsonb_agg(jsonb_build_object(
        'household_id', t.household_id,
        'store_name', t.store_name,
        'shopped_on', t.shopped_on,
        'items', (select jsonb_agg(jsonb_build_object('name', i ->> 'name', 'quantity', i -> 'quantity') order by o)
                  from jsonb_array_elements(t.items) with ordinality as x (i, o)),
        'created_at', t.created_at
      ) order by t.created_at, t.id)
      from public.trips t where t.logged_by = v_user
    ), '[]'::jsonb),
    'trip_sessions_started', coalesce((
      select jsonb_agg(
        (public.trip_session_json(s, false) - '{id,list_id,started_by,lines,premium,detected_by,walked,mine}'::text[])
        || jsonb_build_object(
          'lines', (select coalesce(jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o), '[]')
                    from jsonb_array_elements(s.lines) with ordinality as x (e, o)),
          'created_at', s.created_at)
        order by s.started_at, s.id)
      from public.trip_sessions s where s.started_by = v_user and s.source <> 'detected'
    ), '[]'::jsonb),
    'trips_detected', coalesce((
      select jsonb_agg(
        (public.trip_session_json(s, false) - '{id,list_id,started_by,lines,premium,detected_by,walked,mine}'::text[])
        || jsonb_build_object(
          'lines', (select coalesce(jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o), '[]')
                    from jsonb_array_elements(s.lines) with ordinality as x (e, o)),
          'walked', s.walked,
          'with_others', cardinality(s.detected_by) > 1,
          'created_at', s.created_at)
        -- A shared trip's clock times are the others' ticks too (N-321).
        || case when s.detected_by <> array[v_user] then
             '{"started_at": null, "ended_at": null, "pauses": null, "created_at": null}'::jsonb else '{}' end
        order by s.started_at, s.id)
      from public.trip_sessions s
      where s.source = 'detected' and s.removed_at is null and v_user = any(s.detected_by)
    ), '[]'::jsonb),
    'trip_detection', (
      select jsonb_build_object('on', p.detect_ticks_from is not null,
        'counts_ticks_from', case when isfinite(p.detect_ticks_from) then p.detect_ticks_from end,
        'card_seen_at', p.detected_card_at,
        'shops_declined', coalesce((
          select jsonb_agg(jsonb_build_object('household_id', d.household_id, 'item_name', e.item_name,
            'ticked_at', e.created_at, 'declined_at', d.declined_at, 'client_at', d.client_at)
            order by d.declined_at, d.id)
          from public.shop_declines d left join public.item_events e on e.id = d.tick_id
          where d.user_id = v_user), '[]'::jsonb))
      from public.trip_detection_settings p where p.user_id = v_user
    ),
    'tester_groups', coalesce((
      select jsonb_agg(jsonb_build_object('group_name', g.group_name, 'added_at', g.added_at)
        order by g.group_name collate "C")
      from public.tester_groups g where g.user_id = v_user
    ), '[]'::jsonb),
    'push_devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'platform', t.platform, 'created_at', t.created_at, 'updated_at', t.updated_at
      ) order by t.created_at, t.id)
      from public.push_tokens t where t.user_id = v_user
    ), '[]'::jsonb)
  );
end $$;
