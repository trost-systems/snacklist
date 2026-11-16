-- Job 268 (FB4, docs/FEEDBACK.md "Replies and status"): the sender sees what became of a note.
-- Peter sets status, fixed_in and reply by hand in the Table Editor; the trigger stamps the times.
-- The sender reads their own notes back, without the context columns. Ideas being considered are
-- listed by Peter in feedback_ideas; households +1 them, without any user id.

alter table public.feedback
  add column status text not null default 'sent'
    constraint feedback_status check (status in ('sent', 'read', 'planned', 'fixed')),
  add column fixed_in text
    constraint feedback_fixed_in_version check (fixed_in ~ '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'),
  add column reply text
    constraint feedback_reply_length check (char_length(public.feedback_trim(reply)) between 1 and 4000),
  add column replied_at timestamptz,
  add column answered_at timestamptz,
  add column seen_at timestamptz,
  add constraint feedback_fixed_in_only_fixed check (fixed_in is null or status = 'fixed');

comment on column public.feedback.status is
  'sent, read, planned or fixed; set by Peter by hand. The sender sees it in the app.';
comment on column public.feedback.fixed_in is
  'The app version that fixed it (1.4.1), only with status fixed. The app links that version''s changelog.';
comment on column public.feedback.reply is
  'Peter''s reply, written by hand, 1 to 4000 characters (trimmed by the trigger); null for none. The sender reads it in the app.';
comment on column public.feedback.replied_at is 'When the reply was last written (set by the trigger).';
comment on column public.feedback.answered_at is
  'When status, fixed_in or reply last changed (set by the trigger); the app shows the note as unread until seen_at passes it.';
comment on column public.feedback.seen_at is 'When the sender last opened the answered note (feedback_mark_seen).';

-- Peter edits only status, fixed_in and reply; the stamps follow here, whoever writes.
create function public.feedback_before_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.status, new.fixed_in, new.reply) is distinct from (old.status, old.fixed_in, old.reply) then
    new.answered_at := now();
  end if;
  if new.reply is distinct from old.reply then
    new.reply := public.feedback_trim(new.reply);
    new.replied_at := case when new.reply is null then null else now() end;
  end if;
  return new;
end $$;

revoke execute on function public.feedback_before_update() from public, anon, authenticated;

create trigger feedback_before_update
  before update on public.feedback
  for each row execute function public.feedback_before_update();

-- The sender reads their own notes, only the columns the app shows, in the app's own session: an
-- app connected over OAuth (MCP) acts on the list, not on the account. No update or delete.
create policy feedback_select_own on public.feedback
  for select to authenticated
  using (user_id = (select auth.uid()) and (select auth.jwt() ->> 'client_id') is null);

grant select (id, created_at, message, category, status, fixed_in, reply, replied_at, answered_at,
  seen_at) on public.feedback to authenticated;

-- Opening an answered note. Someone else's or an unknown id, or a note without an answer, changes
-- nothing and says nothing.
create function public.feedback_mark_seen(p_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.feedback f
  set seen_at = now()
  where f.id = p_id and f.user_id = (select auth.uid()) and f.answered_at is not null
$$;

revoke execute on function public.feedback_mark_seen(uuid) from public, anon;
grant execute on function public.feedback_mark_seen(uuid) to authenticated;

-- Ideas -------------------------------------------------------------------------------------------

create table public.feedback_ideas (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  title_de text not null constraint feedback_ideas_title_de check (char_length(public.feedback_trim(title_de)) between 1 and 120),
  title_en text not null constraint feedback_ideas_title_en check (char_length(public.feedback_trim(title_en)) between 1 and 120),
  status text not null default 'considering' constraint feedback_ideas_status check (status in ('considering', 'planned')),
  position integer not null default 0,
  listed boolean not null default true
);

comment on table public.feedback_ideas is
  'Job 268 (FB4, docs/FEEDBACK.md): ideas Peter lists in the app for households to +1. Written by hand; clients read them through feedback_ideas().';
comment on column public.feedback_ideas.id is 'The idea.';
comment on column public.feedback_ideas.created_at is 'When it was listed; second sort key after position.';
comment on column public.feedback_ideas.title_de is 'The German title the app shows, 1 to 120 characters.';
comment on column public.feedback_ideas.title_en is 'The English title the app shows, 1 to 120 characters.';
comment on column public.feedback_ideas.status is 'considering or planned.';
comment on column public.feedback_ideas.position is 'Order in the app, ascending.';
comment on column public.feedback_ideas.listed is 'false hides the idea in the app; its votes stay.';

alter table public.feedback_ideas enable row level security;
revoke all on public.feedback_ideas from public, anon, authenticated;

-- One +1 per household and idea. No user id: nobody, the household included, learns who voted.
create table public.feedback_idea_votes (
  idea_id uuid not null references public.feedback_ideas (id) on delete cascade,
  household_id uuid not null references public.households (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (idea_id, household_id)
);

create index feedback_idea_votes_household_id on public.feedback_idea_votes (household_id);

comment on table public.feedback_idea_votes is
  'Job 268 (FB4): a household''s +1 on an idea, written only by vote_feedback_idea(). Deleted with the household or the idea.';
comment on column public.feedback_idea_votes.idea_id is 'The idea.';
comment on column public.feedback_idea_votes.household_id is 'The household that voted; which member did is not stored.';
comment on column public.feedback_idea_votes.created_at is 'When the household voted.';

alter table public.feedback_idea_votes enable row level security;
revoke all on public.feedback_idea_votes from public, anon, authenticated;
grant select on public.feedback_idea_votes to authenticated;

create policy feedback_idea_votes_select_member on public.feedback_idea_votes
  for select to authenticated
  using (public.is_household_member(household_id));

-- The listed ideas with every household's total and whether p_household voted.
create function public.feedback_ideas(p_household uuid)
returns table (id uuid, title_de text, title_en text, status text, votes integer, voted boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  return query
  select i.id, i.title_de, i.title_en, i.status,
    (select count(*)::integer from public.feedback_idea_votes v where v.idea_id = i.id),
    exists (select from public.feedback_idea_votes v where v.idea_id = i.id and v.household_id = p_household)
  from public.feedback_ideas i
  where i.listed
  order by i.position, i.created_at, i.id;
end $$;

revoke execute on function public.feedback_ideas(uuid) from public, anon;
grant execute on function public.feedback_ideas(uuid) to authenticated;

-- p_household's +1 on or off; repeating either is a no-op. Returns the idea's new total.
create function public.vote_feedback_idea(p_idea uuid, p_household uuid, p_on boolean) returns integer
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if p_on is null then
    raise exception 'missing_argument' using errcode = '22023';
  end if;
  if not exists (select from public.feedback_ideas i where i.id = p_idea and i.listed) then
    raise exception 'idea_not_found' using errcode = 'P0002';
  end if;
  if p_on then
    insert into public.feedback_idea_votes (idea_id, household_id) values (p_idea, p_household)
    on conflict do nothing;
  else
    delete from public.feedback_idea_votes v where v.idea_id = p_idea and v.household_id = p_household;
  end if;
  return (select count(*)::integer from public.feedback_idea_votes v where v.idea_id = p_idea);
end $$;

revoke execute on function public.vote_feedback_idea(uuid, uuid, boolean) from public, anon;
grant execute on function public.vote_feedback_idea(uuid, uuid, boolean) to authenticated;

-- Data export: each note's status and reply, and the +1s of the caller's households. The body is
-- 20261115160000_feedback_screenshots.sql's with those added.
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
