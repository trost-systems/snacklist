-- Job 472 (SR1): shopping reminders, several per person (docs/PUSH.md, "Shopping reminders"). Each
-- reminder names the shopping weekday, whether it goes out the day before or on the day, and a
-- local time. Job 378's one-row-per-person table becomes a read-only view over the new one, so old
-- app builds and the flag-off screen keep reading `weekdays`, and its RPCs keep working on the new
-- rows. Legal SR1 review C1: after this migration exactly one table holds reminder data.
--
-- When it fires: unchanged cron (shopping_day_run every 10 minutes, UTC). A reminder's fire instant
-- is (fire date + local time) at its zone, the fire date being the shopping date plus offset_days.
-- It is due from that instant for 30 minutes, once per fire date (last_sent_on). Comparing
-- absolute instants, not local wall-clock readings, means a time inside a DST gap or overlap
-- fires exactly once, and a late-evening reminder still catches up after local midnight.

create table public.shopping_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  shopping_weekday smallint not null check (shopping_weekday between 1 and 7),
  offset_days smallint not null check (offset_days in (-1, 0)),
  local_time time not null check (local_time = date_trunc('minute', local_time)),
  time_zone text not null check (char_length(time_zone) between 1 and 64),
  locale text not null check (locale in ('de', 'en')),
  last_sent_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, shopping_weekday, offset_days, local_time)
);

comment on table public.shopping_reminders is
  'Job 472: a person''s shopping reminders, one row each, at most 14 (docs/PUSH.md). No row means off. No household id: other members cannot learn that someone set one. Written only by the reminder RPCs, read by its owner, sent by shopping_day_run, exported by export_my_data, gone with the account (foreign key).';
comment on column public.shopping_reminders.shopping_weekday is
  'ISO weekday of the shopping day, 1 Monday to 7 Sunday.';
comment on column public.shopping_reminders.offset_days is
  'When it goes out relative to the shopping day: -1 the day before, 0 on the day.';
comment on column public.shopping_reminders.local_time is
  'Wall-clock time in time_zone, whole minutes.';
comment on column public.shopping_reminders.last_sent_on is
  'The local fire date of the occurrence that last went out (or was skipped because it was saved after its time); that occurrence never sends again.';

-- The cap holds for every writer, not only the RPCs: a superuser insert (backup fixtures, the
-- compatibility view) goes through here too. The lock is the RPCs' lock, so two concurrent adds
-- cannot both see 13.
create function public.shopping_reminders_cap() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('shopping_reminders:' || new.user_id::text, 0));
  if (select count(*) from public.shopping_reminders r
      where r.user_id = new.user_id and r.id <> new.id) >= 14 then
    raise exception 'reminder_limit' using errcode = '54000';
  end if;
  return new;
end $$;
create trigger shopping_reminders_cap before insert or update of user_id on public.shopping_reminders
  for each row execute function public.shopping_reminders_cap();
revoke execute on function public.shopping_reminders_cap() from public, anon, authenticated;

alter table public.shopping_reminders enable row level security;
create policy shopping_reminders_read_own on public.shopping_reminders for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.shopping_reminders from public, anon, authenticated;
grant select on public.shopping_reminders to authenticated;

-- Job 378's table, as a view. The name is kept because app builds already shipped read it, and
-- the flag-off screen still does; security_invoker makes the table's owner-only policy apply.
-- squawk-ignore renaming-table -- a view of the same name and columns replaces it below, in this transaction
alter table public.shopping_day_reminders rename to shopping_day_reminders_378;

create view public.shopping_day_reminders with (security_invoker = true) as
select r.user_id,
       array_agg(distinct r.shopping_weekday order by r.shopping_weekday)::smallint[] as weekdays,
       (array_agg(r.time_zone order by r.updated_at desc, r.id))[1] as time_zone,
       (array_agg(r.locale order by r.updated_at desc, r.id))[1] as locale,
       max(r.last_sent_on) as last_sent_on,
       min(r.created_at) as created_at,
       max(r.updated_at) as updated_at
from public.shopping_reminders r
group by r.user_id;

comment on view public.shopping_day_reminders is
  'Job 472: job 378''s one row per person, read from shopping_reminders for old app builds. An insert (superuser only) maps each weekday to a day-before 19:00 reminder, the SR-Q5 mapping this migration uses for the old rows.';
revoke all on public.shopping_day_reminders from public, anon, authenticated;
grant select on public.shopping_day_reminders to authenticated;

create function public.shopping_day_reminders_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
  insert into public.shopping_reminders
    (user_id, shopping_weekday, offset_days, local_time, time_zone, locale, last_sent_on, created_at, updated_at)
  select new.user_id, d.weekday, -1, time '19:00', new.time_zone, new.locale, new.last_sent_on,
         coalesce(new.created_at, now()), coalesce(new.updated_at, new.created_at, now())
  from (select distinct unnest(new.weekdays) as weekday) d;
  return new;
end $$;
create trigger shopping_day_reminders_insert instead of insert on public.shopping_day_reminders
  for each row execute function public.shopping_day_reminders_insert();
revoke execute on function public.shopping_day_reminders_insert() from public, anon, authenticated;

-- Through the view, so the mapping that moves the old rows is the one pgTAP tests. Nothing is
-- sent here: only shopping_day_run posts.
insert into public.shopping_day_reminders (user_id, weekdays, time_zone, locale, last_sent_on, created_at, updated_at)
select o.user_id, o.weekdays, o.time_zone, o.locale, o.last_sent_on, o.created_at, o.updated_at
from public.shopping_day_reminders_378 o;

-- squawk-ignore ban-drop-table -- its rows moved through the view above, which old builds read (Legal C1: one store)
drop table public.shopping_day_reminders_378;

-- The occurrence of one reminder that fired last at or before p_now, if it fired today or
-- yesterday in its zone (yesterday: a late-evening time is still in its window after midnight).
-- At most one of the two dates can match, since they are different weekdays. Saving and sending
-- both read it, so "saved after its time" and "due" cannot disagree about which date that is.
create function public.shopping_reminder_last_fire(
  p_weekday smallint, p_offset_days smallint, p_local_time time, p_time_zone text, p_now timestamptz)
returns table (fire_on date, fire_at timestamptz)
language sql stable set search_path = '' as $$
  select d.fire_on, (d.fire_on + p_local_time) at time zone p_time_zone
  from (select (p_now at time zone p_time_zone)::date - g as fire_on from generate_series(0, 1) g) d
  where extract(isodow from d.fire_on - p_offset_days) = p_weekday
    and (d.fire_on + p_local_time) at time zone p_time_zone <= p_now
$$;
revoke execute on function public.shopping_reminder_last_fire(smallint, smallint, time, text, timestamptz)
  from public, anon, authenticated, service_role;

-- Saved at or after this reminder's time today (or a late time of yesterday's that is still in
-- its window), that occurrence counts as sent: adding a reminder late does not ping at once
-- (SR-Q7). A reminder already exists with the same day, offset and time: reminder_exists, so the
-- app can say so instead of failing on the constraint.
create function public.add_shopping_reminder(
  p_weekday integer, p_day_before boolean, p_minute integer, p_time_zone text, p_locale text)
returns public.shopping_reminders
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_offset smallint;
  v_time time;
  v_row public.shopping_reminders;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_weekday is null or p_weekday not between 1 and 7 then
    raise exception 'invalid_weekday' using errcode = '22023';
  end if;
  if p_day_before is null then
    raise exception 'invalid_offset' using errcode = '22023';
  end if;
  if p_minute is null or p_minute not between 0 and 1439 then
    raise exception 'invalid_time' using errcode = '22023';
  end if;
  if p_time_zone is null
     or not exists (select from pg_catalog.pg_timezone_names z where z.name = p_time_zone) then
    raise exception 'invalid_time_zone' using errcode = '22023';
  end if;
  if p_locale is null or p_locale not in ('de', 'en') then
    raise exception 'invalid_locale' using errcode = '22023';
  end if;
  v_offset := case when p_day_before then -1 else 0 end;
  v_time := time '00:00' + make_interval(mins => p_minute);
  perform pg_advisory_xact_lock(hashtextextended('shopping_reminders:' || v_user::text, 0));
  if exists (select from public.shopping_reminders r
             where r.user_id = v_user and r.shopping_weekday = p_weekday
               and r.offset_days = v_offset and r.local_time = v_time) then
    raise exception 'reminder_exists' using errcode = '23505';
  end if;
  if (select count(*) from public.shopping_reminders r where r.user_id = v_user) >= 14 then
    raise exception 'reminder_limit' using errcode = '54000';
  end if;
  insert into public.shopping_reminders
    (user_id, shopping_weekday, offset_days, local_time, time_zone, locale, last_sent_on)
  values (v_user, p_weekday, v_offset, v_time, p_time_zone, p_locale,
          (select f.fire_on from public.shopping_reminder_last_fire(
             p_weekday::smallint, v_offset, v_time, p_time_zone, now()) f))
  returning * into v_row;
  return v_row;
end $$;
revoke execute on function public.add_shopping_reminder(integer, boolean, integer, text, text) from public, anon;
grant execute on function public.add_shopping_reminder(integer, boolean, integer, text, text) to authenticated;

-- A new time on the same days keeps last_sent_on, never moved back, so moving a reminder that
-- already went out today to a later time today does not send it a second time. A new shopping day
-- or offset makes it another reminder: the old date goes, and only the saved-late rule applies, so
-- a reminder moved onto today's evening still comes as the app shows.
create function public.update_shopping_reminder(
  p_id uuid, p_weekday integer, p_day_before boolean, p_minute integer, p_time_zone text, p_locale text)
returns public.shopping_reminders
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_offset smallint;
  v_time time;
  v_row public.shopping_reminders;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_weekday is null or p_weekday not between 1 and 7 then
    raise exception 'invalid_weekday' using errcode = '22023';
  end if;
  if p_day_before is null then
    raise exception 'invalid_offset' using errcode = '22023';
  end if;
  if p_minute is null or p_minute not between 0 and 1439 then
    raise exception 'invalid_time' using errcode = '22023';
  end if;
  if p_time_zone is null
     or not exists (select from pg_catalog.pg_timezone_names z where z.name = p_time_zone) then
    raise exception 'invalid_time_zone' using errcode = '22023';
  end if;
  if p_locale is null or p_locale not in ('de', 'en') then
    raise exception 'invalid_locale' using errcode = '22023';
  end if;
  v_offset := case when p_day_before then -1 else 0 end;
  v_time := time '00:00' + make_interval(mins => p_minute);
  perform pg_advisory_xact_lock(hashtextextended('shopping_reminders:' || v_user::text, 0));
  if not exists (select from public.shopping_reminders r where r.id = p_id and r.user_id = v_user) then
    raise exception 'reminder_not_found' using errcode = 'P0002';
  end if;
  if exists (select from public.shopping_reminders r
             where r.user_id = v_user and r.id <> p_id and r.shopping_weekday = p_weekday
               and r.offset_days = v_offset and r.local_time = v_time) then
    raise exception 'reminder_exists' using errcode = '23505';
  end if;
  update public.shopping_reminders r
  set shopping_weekday = p_weekday, offset_days = v_offset, local_time = v_time,
      time_zone = p_time_zone, locale = p_locale,
      last_sent_on = greatest(
        case when r.shopping_weekday = p_weekday and r.offset_days = v_offset then r.last_sent_on end,
        (select f.fire_on from public.shopping_reminder_last_fire(
           p_weekday::smallint, v_offset, v_time, p_time_zone, now()) f)),
      updated_at = now()
  where r.id = p_id
  returning * into v_row;
  return v_row;
end $$;
revoke execute on function public.update_shopping_reminder(uuid, integer, boolean, integer, text, text) from public, anon;
grant execute on function public.update_shopping_reminder(uuid, integer, boolean, integer, text, text) to authenticated;

-- An unknown id is no error, so the app can retry a delete whose answer it never got. With the
-- last one gone the person has no reminder; there is no other state to clear.
create function public.delete_shopping_reminder(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from public.shopping_reminders r where r.id = p_id and r.user_id = v_user;
end $$;
revoke execute on function public.delete_shopping_reminder(uuid) from public, anon;
grant execute on function public.delete_shopping_reminder(uuid) to authenticated;

-- Job 378's save, for old app builds and the flag-off screen: the weekdays become exactly one
-- day-before 19:00 reminder each, and every other reminder of the person goes, custom times
-- included (Legal SR1 F8: a rollback deletes custom reminders). A reminder that stays keeps its id
-- and its last_sent_on, never moved back, so a new zone cannot send an occurrence twice.
create or replace function public.set_shopping_day_reminder(p_weekdays integer[], p_time_zone text, p_locale text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_weekdays is null or cardinality(p_weekdays) = 0 then
    delete from public.shopping_reminders r where r.user_id = v_user;
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
  perform pg_advisory_xact_lock(hashtextextended('shopping_reminders:' || v_user::text, 0));
  delete from public.shopping_reminders r
  where r.user_id = v_user
    and not (r.offset_days = -1 and r.local_time = time '19:00' and r.shopping_weekday = any (p_weekdays));
  insert into public.shopping_reminders as r
    (user_id, shopping_weekday, offset_days, local_time, time_zone, locale, last_sent_on)
  select v_user, d.weekday, -1, time '19:00', p_time_zone, p_locale,
         (select f.fire_on from public.shopping_reminder_last_fire(
            d.weekday, -1::smallint, time '19:00', p_time_zone, now()) f)
  from (select distinct w::smallint as weekday from unnest(p_weekdays) w) d
  on conflict (user_id, shopping_weekday, offset_days, local_time) do update
    set time_zone = excluded.time_zone,
        locale = excluded.locale,
        last_sent_on = greatest(r.last_sent_on, excluded.last_sent_on),
        updated_at = now();
end $$;

-- Zone and language follow the device on every reminder of the person; days, offsets, times and
-- last_sent_on never change here, so opening the screen just after a reminder's time cannot
-- cancel it. No reminder: nothing happens, nothing is created.
create or replace function public.refresh_shopping_day_reminder(p_time_zone text, p_locale text) returns void
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
  update public.shopping_reminders r
  set time_zone = p_time_zone, locale = p_locale, updated_at = now()
  where r.user_id = v_user and (r.time_zone, r.locale) is distinct from (p_time_zone, p_locale);
end $$;

-- One row per reminder due at p_now: a device registered, a household, its occurrence's instant
-- at most 30 minutes ago and not sent for that fire date. The list is the default household's
-- default list (else its first); the count is its open items, one indexed count.
-- squawk-ignore ban-drop-function -- internal, revoked from every API role; only shopping_day_run calls it
drop function public.shopping_day_due(timestamptz);
create function public.shopping_day_due(p_now timestamptz)
returns table (reminder_id uuid, user_id uuid, household_id uuid, list_id uuid, locale text,
               offset_days smallint, fire_on date, open_items bigint)
language sql stable security definer set search_path = '' as $$
  select r.id, r.user_id, m.household_id, l.list_id, r.locale, r.offset_days, f.fire_on,
         (select count(*) from public.items i where i.list_id = l.list_id and i.status = 'active')
  from public.shopping_reminders r
  cross join lateral public.shopping_reminder_last_fire(
    r.shopping_weekday, r.offset_days, r.local_time, r.time_zone, p_now) f
  join public.household_members m on m.user_id = r.user_id and m.is_default
  cross join lateral (
    select coalesce(m.default_list_id, public.first_list(m.household_id)) as list_id
  ) l
  where p_now < f.fire_at + interval '30 minutes'
    and (r.last_sent_on is null or r.last_sent_on < f.fire_on)
    and l.list_id is not null
    and exists (select from public.push_tokens k where k.user_id = r.user_id)
$$;
revoke execute on function public.shopping_day_due(timestamptz) from public, anon, authenticated, service_role;

-- The text of one reminder, in the person's language; the title says whether shopping is tomorrow
-- or today. The count is of open items only, never their names. Legal hashed these strings.
-- squawk-ignore ban-drop-function -- internal, revoked from every API role; only shopping_day_run calls it
drop function public.shopping_day_text(text, bigint);
create function public.shopping_day_text(p_locale text, p_open bigint, p_offset_days integer)
returns jsonb
language sql immutable set search_path = '' as $$
  select case p_locale
    when 'en' then jsonb_build_object(
      'title', case when p_offset_days = 0 then 'Shopping day today' else 'Shopping day tomorrow' end,
      'body', case
        when p_open = 1 then '1 item on the list. Have a quick look.'
        when p_open > 1 then p_open || ' items on the list. Have a quick look.'
        else 'Have a quick look at the list.' end)
    else jsonb_build_object(
      'title', case when p_offset_days = 0 then 'Heute ist Einkaufstag' else 'Morgen ist Einkaufstag' end,
      'body', case
        when p_open = 1 then '1 Artikel steht auf der Liste. Schau kurz rein.'
        when p_open > 1 then p_open || ' Artikel stehen auf der Liste. Schau kurz rein.'
        else 'Schau kurz auf die Liste.' end)
  end
$$;
revoke execute on function public.shopping_day_text(text, bigint, integer)
  from public, anon, authenticated, service_role;

-- Sends what is due at p_now through the push function (pg_net, the secret from the vault at run
-- time) and marks each reminder sent for its fire date first: at most once per occurrence, a
-- failed send is not retried. Only that reminder is marked, so another reminder of the same person
-- later that day still goes out. The advisory lock keeps an overlapping run from sending twice.
create or replace function public.shopping_day_run(p_url text, p_now timestamptz default now()) returns integer
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
    update public.shopping_reminders r set last_sent_on = v_due.fire_on where r.id = v_due.reminder_id;
    v_text := public.shopping_day_text(v_due.locale, v_due.open_items, v_due.offset_days);
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

-- Data export: one object per reminder with every column (Legal SR1 F4, C1), in place of job 378's
-- single 'shopping_day_reminder' object, which is gone and not kept as an alias. Otherwise unchanged
-- from 20261123000000_shopping_day_reminder.sql.
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
    'shopping_reminders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'user_id', s.user_id, 'shopping_weekday', s.shopping_weekday,
        'offset_days', s.offset_days, 'local_time', s.local_time, 'time_zone', s.time_zone,
        'locale', s.locale, 'last_sent_on', s.last_sent_on, 'created_at', s.created_at,
        'updated_at', s.updated_at
      ) order by s.created_at, s.id)
      from public.shopping_reminders s where s.user_id = v_user
    ), '[]'::jsonb)
  );
end $$;
