-- Job 267 (FB2, docs/FEEDBACK.md "Screenshots"): a note may carry one annotated screenshot. The
-- app uploads the PNG to the private bucket feedback-screenshots as <user id>/<note id>.png, then
-- inserts the note naming it in feedback.screenshot. Clients may only upload, under their own id,
-- at most 10 a day and while the bucket holds fewer than 250 images; only the service role reads
-- the images. An image goes with its note: deleting a note queues its name, and the
-- feedback-screenshots function removes queued names and uploads that never got a note (or whose
-- account is gone) through the Storage API (SQL cannot delete the files themselves).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-screenshots', 'feedback-screenshots', false, 2097152, array['image/png'])
on conflict (id) do update
set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Whether the signed-in user may upload p_name: 10 in any 24 hours per user, and fewer than 250
-- images in the bucket (2 MiB each at most: 500 MiB of the free plan's 1 GB). A name the user
-- already uploaded always passes, so a retry reaches the unique key and gets the Storage API's
-- "Duplicate", which the app takes as its earlier try, instead of a refusal at the quota.
-- Security definer: the policy below calls it as the uploader, who may not read storage.objects.
-- The row being inserted is not yet visible here, so the 10th upload passes and the 11th does not.
create function public.feedback_screenshot_quota_left(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
      select from storage.objects o
      where o.bucket_id = 'feedback-screenshots' and o.name = p_name
        and o.name like (select auth.uid())::text || '/%'
    )
    or (
      (select count(*) from storage.objects o
       where o.bucket_id = 'feedback-screenshots'
         and o.name like (select auth.uid())::text || '/%'
         and o.created_at > now() - interval '24 hours') < 10
      and (select count(*) from storage.objects o where o.bucket_id = 'feedback-screenshots') < 250
    )
$$;

revoke execute on function public.feedback_screenshot_quota_left(text) from public, anon;
grant execute on function public.feedback_screenshot_quota_left(text) to authenticated;

-- Upload only: under one's own id, a lowercase uuid name ending in .png, within the quota. No
-- select, update or delete policy, so no client downloads, lists, signs, overwrites (upsert) or
-- removes an image, its own included. The bucket itself limits the size (2 MiB) and the type.
create policy feedback_screenshots_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'feedback-screenshots'
    and name ~ ('^' || (select auth.uid())::text
      || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$')
    and public.feedback_screenshot_quota_left(name)
  );

alter table public.feedback add column screenshot text
  constraint feedback_screenshot_name check (screenshot = user_id::text || '/' || id::text || '.png');
comment on column public.feedback.screenshot is
  'The annotated screenshot''s object name in the storage bucket feedback-screenshots (<user_id>/<id>.png), null without one. Open it in the dashboard under Storage. Deleted with the note.';
grant insert (screenshot) on public.feedback to authenticated;

-- Object names whose note was deleted, until the feedback-screenshots function has removed them.
create table public.feedback_screenshot_removals (
  name text primary key,
  queued_at timestamptz not null default now()
);

comment on table public.feedback_screenshot_removals is
  'Job 267: screenshots whose note is gone (purge, account deletion, by hand), waiting for the feedback-screenshots function to remove them from storage. Service connection only.';
comment on column public.feedback_screenshot_removals.name is 'The object name in the bucket feedback-screenshots.';
comment on column public.feedback_screenshot_removals.queued_at is 'When its note was deleted.';

alter table public.feedback_screenshot_removals enable row level security;
revoke all on public.feedback_screenshot_removals from public, anon, authenticated, service_role;

-- Per statement, so the daily purge and an account's cascade queue all their names in one insert.
create function public.feedback_queue_screenshot_removal() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.feedback_screenshot_removals (name)
  select o.screenshot from old_notes o where o.screenshot is not null
  on conflict (name) do nothing;
  return null;
end $$;

create trigger feedback_queue_screenshot_removal
  after delete on public.feedback
  referencing old table as old_notes
  for each statement execute function public.feedback_queue_screenshot_removal();

-- What the sweep removes next, at most p_limit names: the queue first, oldest first, then uploads
-- that no note names and that are older than 24 hours (the app uploads right before it inserts
-- the note, so a day is far beyond any retry that still succeeds) or whose folder names no
-- account (deleted: the account function's sweep right after the deletion removes them at once).
create function public.feedback_screenshots_due(p_limit integer) returns setof text
language sql stable security definer set search_path = '' as $$
  select name from (
    select r.name, 0 as rank, r.queued_at as at
    from public.feedback_screenshot_removals r
    union all
    select o.name, 1, o.created_at
    from storage.objects o
    where o.bucket_id = 'feedback-screenshots'
      and (o.created_at < now() - interval '24 hours'
        or not exists (select from auth.users u where u.id::text = split_part(o.name, '/', 1)))
      and not exists (select from public.feedback f where f.screenshot = o.name)
      and not exists (select from public.feedback_screenshot_removals r where r.name = o.name)
  ) due
  order by rank, at, name
  limit p_limit
$$;

-- After the Storage API removed them (or found them gone): the names leave the queue.
create function public.feedback_screenshots_removed(p_names text[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.feedback_screenshot_removals where name = any (p_names);
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- The function connects as the owner; neither clients nor the service key run these.
revoke execute on function public.feedback_queue_screenshot_removal()
  from public, anon, authenticated, service_role;
revoke execute on function public.feedback_screenshots_due(integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.feedback_screenshots_removed(text[])
  from public, anon, authenticated, service_role;

-- Data export: each note says which screenshot it carried (the object name); the body is
-- 20261114181718_trip_mode.sql's with that one key added.
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
        'screenshot', f.screenshot
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
        (public.trip_session_json(s, false) - '{id,list_id,started_by,lines,premium}'::text[])
        || jsonb_build_object(
          'lines', (select coalesce(jsonb_agg(e - '{key,store_id,added_by}'::text[] order by o), '[]')
                    from jsonb_array_elements(s.lines) with ordinality as x (e, o)),
          'created_at', s.created_at)
        order by s.started_at, s.id)
      from public.trip_sessions s where s.started_by = v_user
    ), '[]'::jsonb)
  );
end $$;
