-- Job 377 (P1): the household-add alert behind the PostHog flag push-household-add. When someone
-- adds an item, the other members who switched the alert on get a push ("Lea hat Milch
-- hinzugefügt"); adds within a few minutes become one push ("Lea hat 4 Einträge hinzugefügt").
-- Sending goes through job 376's push function (docs/PUSH.md); this file decides who, when and
-- what text. The server switch app_switches.push_household_add stays off until Legal's GO.

-- Who wants it ------------------------------------------------------------------------------------
-- One row per user: P2 (job 378) adds its columns here. household_add defaults off (opt-in, the
-- text names a member and an item); language is the app's, as the server knows no locale.

create table public.push_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  household_add boolean not null default false,
  language text not null default 'de' check (language in ('de', 'en')),
  updated_at timestamptz not null default now()
);
alter table public.push_preferences enable row level security;
revoke all on public.push_preferences from public, anon, authenticated;
create policy push_preferences_read_own on public.push_preferences for select to authenticated
  using (user_id = (select auth.uid()));
grant select on public.push_preferences to authenticated;
comment on table public.push_preferences is
  'Job 377: which pushes a user wants (household_add) and in which language the text is written. Written only by set_push_household_add; exported by export_my_data; gone with the account.';

-- Switches the alert for the caller. [p_language] is the app's language ("de" or "en").
create function public.set_push_household_add(p_on boolean, p_language text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_on is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if p_language is null or p_language not in ('de', 'en') then
    raise exception 'invalid_language' using errcode = '22023';
  end if;
  insert into public.push_preferences as p (user_id, household_add, language)
  values (v_user, p_on, p_language)
  on conflict (user_id) do update
    set household_add = excluded.household_add, language = excluded.language, updated_at = now();
end $$;
revoke execute on function public.set_push_household_add(boolean, text) from public, anon;
grant execute on function public.set_push_household_add(boolean, text) to authenticated;

-- What was added ----------------------------------------------------------------------------------
-- A pending add lives here until its group is sent (or 1 hour at most): item names are not kept.

create table public.push_add_queue (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  list_id uuid,
  actor uuid not null references auth.users (id) on delete cascade,
  item_name text not null,
  created_at timestamptz not null default now()
);
create index push_add_queue_group_idx on public.push_add_queue (household_id, actor, created_at);
alter table public.push_add_queue enable row level security;
revoke all on public.push_add_queue from public, anon, authenticated;
-- No grant: the policy keeps households apart should one be added later.
create policy push_add_queue_member on public.push_add_queue for select to authenticated
  using (public.is_household_member(household_id));
comment on table public.push_add_queue is
  'Job 377: adds waiting to be batched into one push. Written by the items trigger, emptied by push_add_flush; no client access.';

insert into public.app_switches (key, enabled) values ('push_household_add', false);

-- Whether [p_user] has ticked in [p_household] within the last 10 minutes: job 352's "a trip may
-- still be going on" (detect_due_households, T1a). The running trip of trip mode lives on the
-- device only, so this is the server's signal for "shopping now".
create function public.on_a_trip(p_household uuid, p_user uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select from public.item_events e
    where e.household_id = p_household and e.actor = p_user and e.source = 'app'
      and e.action in ('bought', 'restored') and e.created_at > now() - interval '10 minutes')
$$;
revoke execute on function public.on_a_trip(uuid, uuid) from public, anon, authenticated;

create function public.items_push_add_enqueue() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.added_by is null or not public.app_switch('push_household_add') then
    return null;
  end if;
  -- (a) not for my own adds: only members other than the adder count; none wants it, no row.
  if not exists (
    select from public.household_members m
    join public.push_preferences p on p.user_id = m.user_id and p.household_add
    where m.household_id = new.household_id and m.user_id <> new.added_by
  ) then
    return null;
  end if;
  -- (d) none while the adder is shopping.
  if public.on_a_trip(new.household_id, new.added_by) then
    return null;
  end if;
  insert into public.push_add_queue (household_id, list_id, actor, item_name)
  values (new.household_id, new.list_id, new.added_by, left(new.name, 120));
  return null;
end $$;
revoke execute on function public.items_push_add_enqueue() from public, anon, authenticated;

create trigger items_push_add_enqueue after insert on public.items
  for each row execute function public.items_push_add_enqueue();

-- Batching: a group (household, list, adder) goes out when its newest add is 2 minutes old, or
-- its oldest 5 minutes. Takes the due groups out of the queue and returns one push request per
-- group in the push function's shape. The adder is never a recipient; a recipient without the
-- switch, or no longer a member, is left out. Text: "<name> hat <item> hinzugefügt" /
-- "<name> hat <n> Einträge hinzugefügt" and the English "<name> added <item>" /
-- "<name> added <n> items".
create function public.push_add_take() returns table (household_id uuid, request jsonb)
language plpgsql security definer set search_path = '' as $$
declare
  v_group record;
  v_names text[];
  v_who text;
  v_recipients jsonb;
begin
  delete from public.push_add_queue q where q.created_at < now() - interval '1 hour';
  for v_group in
    select q.household_id, q.list_id, q.actor
    from public.push_add_queue q
    group by q.household_id, q.list_id, q.actor
    having max(q.created_at) <= now() - interval '2 minutes' or min(q.created_at) <= now() - interval '5 minutes'
    order by min(q.id)
  loop
    with taken as (
      delete from public.push_add_queue q
      where q.household_id = v_group.household_id and q.list_id is not distinct from v_group.list_id
        and q.actor = v_group.actor
      returning q.item_name, q.id
    )
    select array_agg(t.item_name order by t.id) into v_names from taken t;
    continue when v_names is null;
    select coalesce(nullif(btrim(p.display_name), ''), '') into v_who
    from public.profiles p where p.id = v_group.actor;
    v_who := coalesce(v_who, '');
    select jsonb_agg(jsonb_build_object(
      'user_id', m.user_id,
      'title', 'Snacklist',
      'body', case
        when pr.language = 'en' then
          coalesce(nullif(v_who, ''), 'Someone') || ' added '
          || case when cardinality(v_names) = 1 then v_names[1] else cardinality(v_names) || ' items' end
        else
          coalesce(nullif(v_who, ''), 'Jemand') || ' hat '
          || case when cardinality(v_names) = 1 then v_names[1] else cardinality(v_names) || ' Einträge' end
          || ' hinzugefügt'
      end) order by m.user_id)
    into v_recipients
    from public.household_members m
    join public.push_preferences pr on pr.user_id = m.user_id and pr.household_add
    where m.household_id = v_group.household_id and m.user_id <> v_group.actor;
    continue when v_recipients is null or v_group.list_id is null;
    household_id := v_group.household_id;
    request := jsonb_build_object('household_id', v_group.household_id, 'list_id', v_group.list_id,
      'recipients', v_recipients, 'ttl_seconds', 3600);
    return next;
  end loop;
end $$;
revoke execute on function public.push_add_take() from public, anon, authenticated;

-- Posts what push_add_take returns to the push function, once a minute (push_household_add_set).
create function public.push_add_flush() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_row record;
  v_url text;
  v_secret text;
  v_sent integer := 0;
begin
  select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'push_url';
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'push_send_secret';
  if v_url is null or v_secret is null or not public.app_switch('push_household_add') then
    return 0;
  end if;
  for v_row in select * from public.push_add_take() loop
    perform net.http_post(url := v_url,
      headers := jsonb_build_object('content-type', 'application/json', 'x-push-secret', v_secret),
      body := v_row.request, timeout_milliseconds := 30000);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $$;
revoke execute on function public.push_add_flush() from public, anon, authenticated;

-- Ops switch, for the service role by hand: push_household_add_set(true, '<push function URL>')
-- needs the vault secrets push_send_secret (the function's PUSH_SEND_SECRET) and nothing else.
create function public.push_household_add_set(p_on boolean, p_url text default null) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not p_on then
    update public.app_switches set enabled = false, changed_at = now() where key = 'push_household_add';
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'push-household-add';
    return 'off';
  end if;
  if p_url is null or p_url !~ '^(https://|http://(localhost|127\.0\.0\.1|kong)(:[0-9]+)?/)' then
    raise exception 'push_household_add_set(true, url) needs the push function''s https URL'
      using errcode = '22023';
  end if;
  if not exists (select from vault.decrypted_secrets where name = 'push_send_secret') then
    raise exception 'vault secret push_send_secret is missing' using errcode = '22023',
      hint = 'select vault.create_secret(''<PUSH_SEND_SECRET>'', ''push_send_secret'');';
  end if;
  delete from vault.secrets where name = 'push_url';
  perform vault.create_secret(p_url, 'push_url');
  insert into public.app_switches (key, enabled) values ('push_household_add', true)
  on conflict (key) do update set enabled = true, changed_at = now();
  perform cron.schedule('push-household-add', '* * * * *', 'select public.push_add_flush()');
  return 'on';
end $$;
revoke execute on function public.push_household_add_set(boolean, text)
  from public, anon, authenticated, service_role;

-- Data export: the user's push preferences. Otherwise unchanged from 20261122183000_push_tokens.sql.
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
    ), '[]'::jsonb),
    'push_preferences', (
      select jsonb_build_object('household_add', p.household_add, 'language', p.language,
        'updated_at', p.updated_at)
      from public.push_preferences p where p.user_id = v_user
    )
  );
end $$;
