-- Job 378: the shopping-day reminder (docs/PUSH.md, "Shopping-day reminder"). A person picks
-- weekdays; the evening before each at 19:00 in their own time zone, the push function sends
-- "tomorrow is shopping day" to their devices. Off by default (no row), per person (not per
-- household), written only through set_shopping_day_reminder.
--
-- When it fires: pg_cron runs shopping_day_run every 10 minutes (UTC). A reminder is due when the
-- person's local clock, from the IANA zone stored with it, reads 19:00 to 19:29 on the day before
-- a chosen weekday and none was sent that local date (last_sent_on). `at time zone` follows the
-- zone's DST rules, so 19:00 stays 19:00 local on both sides of a clock change. One cron job for
-- every zone beats one job per zone: the rows are only the people who opted in, and the 30-minute
-- window lets a run that was late or failed still send within the evening, once.

create table public.shopping_day_reminders (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- ISO weekdays of the shopping days: 1 Monday to 7 Sunday, sorted, each once.
  weekdays smallint[] not null
    check (cardinality(weekdays) between 1 and 7 and weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  time_zone text not null check (char_length(time_zone) between 1 and 64),
  locale text not null check (locale in ('de', 'en')),
  last_sent_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.shopping_day_reminders is
  'Job 378: a person''s shopping-day reminder (docs/PUSH.md). No row means off. Written only by set_shopping_day_reminder, read by its owner, sent by shopping_day_run, exported by export_my_data, gone with the account (foreign key).';
comment on column public.shopping_day_reminders.last_sent_on is
  'The local date of the evening the reminder last went out; a second run that evening sends nothing.';

alter table public.shopping_day_reminders enable row level security;
create policy shopping_day_reminders_read_own on public.shopping_day_reminders for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.shopping_day_reminders from public, anon, authenticated;
grant select on public.shopping_day_reminders to authenticated;

insert into public.app_switches (key, enabled) values ('push_shopping_day', false);

-- Saves the caller's reminder; no weekday switches it off. Saved at or after 19:00 local, the
-- reminder of that evening counts as sent: turning it on late does not ping at once. A save never
-- moves last_sent_on back, so a new zone (the app saves the device's zone again when Einstellungen
-- opens) cannot send a second reminder for an evening that already had one.
create function public.set_shopping_day_reminder(p_weekdays integer[], p_time_zone text, p_locale text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_days smallint[];
  v_local timestamp;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_weekdays is null or cardinality(p_weekdays) = 0 then
    delete from public.shopping_day_reminders r where r.user_id = v_user;
    return;
  end if;
  if exists (select from unnest(p_weekdays) d where d is null or d not between 1 and 7) then
    raise exception 'invalid_weekdays' using errcode = '22023';
  end if;
  if p_time_zone is null
     or not exists (select from pg_catalog.pg_timezone_names z where z.name = p_time_zone) then
    raise exception 'invalid_time_zone' using errcode = '22023';
  end if;
  if p_locale is null or p_locale not in ('de', 'en') then
    raise exception 'invalid_locale' using errcode = '22023';
  end if;
  select array_agg(d::smallint order by d) into v_days from (select distinct unnest(p_weekdays) d) s;
  v_local := now() at time zone p_time_zone;
  insert into public.shopping_day_reminders as r (user_id, weekdays, time_zone, locale, last_sent_on)
  values (v_user, v_days, p_time_zone, p_locale,
          case when v_local::time >= time '19:00' then v_local::date end)
  on conflict (user_id) do update
    set weekdays = excluded.weekdays,
        time_zone = excluded.time_zone,
        locale = excluded.locale,
        last_sent_on = greatest(r.last_sent_on, excluded.last_sent_on),
        updated_at = now();
end $$;
revoke execute on function public.set_shopping_day_reminder(integer[], text, text) from public, anon;
grant execute on function public.set_shopping_day_reminder(integer[], text, text) to authenticated;

-- The app saves the device's zone and the language again when Einstellungen opens, for a person
-- who moved or switched language. Unlike set_shopping_day_reminder it never touches the weekdays
-- or last_sent_on, so opening the page between 19:00 and the run cannot cancel that evening's
-- reminder. No reminder: nothing happens.
create function public.refresh_shopping_day_reminder(p_time_zone text, p_locale text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_time_zone is null
     or not exists (select from pg_catalog.pg_timezone_names z where z.name = p_time_zone) then
    raise exception 'invalid_time_zone' using errcode = '22023';
  end if;
  if p_locale is null or p_locale not in ('de', 'en') then
    raise exception 'invalid_locale' using errcode = '22023';
  end if;
  update public.shopping_day_reminders r
  set time_zone = p_time_zone, locale = p_locale, updated_at = now()
  where r.user_id = v_user and (r.time_zone, r.locale) is distinct from (p_time_zone, p_locale);
end $$;
revoke execute on function public.refresh_shopping_day_reminder(text, text) from public, anon;
grant execute on function public.refresh_shopping_day_reminder(text, text) to authenticated;

-- Who is due at p_now: opted in, a device registered, a household, the evening before a shopping
-- day at 19:00 to 19:29 local, nothing sent yet that local date. The list is the default
-- household's default list (else its first); the count is its open items, one indexed count.
create function public.shopping_day_due(p_now timestamptz)
returns table (user_id uuid, household_id uuid, list_id uuid, locale text, open_items bigint)
language sql stable security definer set search_path = '' as $$
  select r.user_id, m.household_id, l.list_id, r.locale,
         (select count(*) from public.items i where i.list_id = l.list_id and i.status = 'active')
  from public.shopping_day_reminders r
  cross join lateral (select (p_now at time zone r.time_zone) as local) t
  join public.household_members m on m.user_id = r.user_id and m.is_default
  cross join lateral (
    select coalesce(m.default_list_id, public.first_list(m.household_id)) as list_id
  ) l
  where t.local::time >= time '19:00' and t.local::time < time '19:30'
    and r.last_sent_on is distinct from t.local::date
    and extract(isodow from t.local::date + 1)::smallint = any (r.weekdays)
    and l.list_id is not null
    and exists (select from public.push_tokens k where k.user_id = r.user_id)
$$;
revoke execute on function public.shopping_day_due(timestamptz) from public, anon, authenticated, service_role;

-- The text of one reminder, in the person's language. The count is of open items only, never
-- their names.
create function public.shopping_day_text(p_locale text, p_open bigint)
returns jsonb
language sql immutable set search_path = '' as $$
  select case p_locale
    when 'en' then jsonb_build_object(
      'title', 'Shopping day tomorrow',
      'body', case
        when p_open = 1 then '1 item on the list. Have a quick look.'
        when p_open > 1 then p_open || ' items on the list. Have a quick look.'
        else 'Have a quick look at the list.' end)
    else jsonb_build_object(
      'title', 'Morgen ist Einkaufstag',
      'body', case
        when p_open = 1 then '1 Artikel steht auf der Liste. Schau kurz rein.'
        when p_open > 1 then p_open || ' Artikel stehen auf der Liste. Schau kurz rein.'
        else 'Schau kurz auf die Liste.' end)
  end
$$;
revoke execute on function public.shopping_day_text(text, bigint) from public, anon, authenticated, service_role;

-- Sends what is due at p_now through the push function (pg_net, the secret from the vault at run
-- time) and marks each person sent first: at most once per evening, a failed send is not retried.
-- The advisory lock keeps an overlapping run from sending twice.
create function public.shopping_day_run(p_url text, p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_due record;
  v_text jsonb;
  v_sent integer := 0;
  v_secret text;
begin
  if not public.app_switch('push_shopping_day') then
    return 0;
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('shopping_day_run', 0)) then
    return 0;
  end if;
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'push_send_secret';
  if v_secret is null then
    raise exception 'vault secret push_send_secret is missing' using errcode = '22023';
  end if;
  for v_due in select * from public.shopping_day_due(p_now) loop
    update public.shopping_day_reminders r
    set last_sent_on = (p_now at time zone r.time_zone)::date
    where r.user_id = v_due.user_id;
    v_text := public.shopping_day_text(v_due.locale, v_due.open_items);
    perform net.http_post(
      url := p_url,
      headers := jsonb_build_object('content-type', 'application/json', 'x-push-secret', v_secret),
      body := jsonb_build_object(
        'household_id', v_due.household_id,
        'list_id', v_due.list_id,
        'recipients', jsonb_build_array(jsonb_build_object(
          'user_id', v_due.user_id, 'title', v_text ->> 'title', 'body', v_text ->> 'body')),
        'ttl_seconds', 14400),
      timeout_milliseconds := 30000);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $$;
revoke execute on function public.shopping_day_run(text, timestamptz)
  from public, anon, authenticated, service_role;

-- On: needs the push function's https URL (plain http only for the local stack) and the vault
-- secret push_send_secret (the function's PUSH_SEND_SECRET). Off: the job is removed.
create function public.shopping_day_set(p_on boolean, p_url text default null) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not p_on then
    update public.app_switches set enabled = false, changed_at = now() where key = 'push_shopping_day';
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'shopping-day-reminder';
    return 'off';
  end if;
  if p_url is null
     or p_url !~ '^(https://|http://(localhost|127\.0\.0\.1|kong)(:[0-9]+)?/)' then
    raise exception 'shopping_day_set(true, url) needs the push function''s https URL'
      using errcode = '22023';
  end if;
  if not exists (select from vault.decrypted_secrets where name = 'push_send_secret') then
    raise exception 'vault secret push_send_secret is missing'
      using errcode = '22023',
        hint = 'select vault.create_secret(''<PUSH_SEND_SECRET>'', ''push_send_secret'');';
  end if;
  update public.app_switches set enabled = true, changed_at = now() where key = 'push_shopping_day';
  perform cron.schedule('shopping-day-reminder', '*/10 * * * *',
    format('select public.shopping_day_run(%L)', p_url));
  return 'on';
end $$;
revoke execute on function public.shopping_day_set(boolean, text)
  from public, anon, authenticated, service_role;

-- Data export: the user's reminder (weekdays, zone, language). Otherwise unchanged from
-- 20261122232004_push_household_add.sql, which keeps push_devices and push_preferences (Legal N-434).
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
        'name_hidden', p.name_hidden, 'updated_at', p.updated_at)
      from public.push_preferences p where p.user_id = v_user
    ),
    'shopping_day_reminder', (
      select jsonb_build_object('weekdays', s.weekdays, 'time_zone', s.time_zone, 'locale', s.locale,
        'last_sent_on', s.last_sent_on, 'created_at', s.created_at, 'updated_at', s.updated_at)
      from public.shopping_day_reminders s where s.user_id = v_user
    )
  );
end $$;
