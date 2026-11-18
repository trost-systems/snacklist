-- A display name the user chose (job 297, DN3 and DE1). Until now the only
-- mark of a chosen name was that it differed from the derived one, so a
-- confirmed Google or Apple name still followed a later provider name. The
-- app now saves the name through set_display_name, which stamps it.

alter table public.profiles add column display_name_chosen_at timestamptz;

-- A later name (Apple's first sign-in, a linked Google identity) replaces the
-- derived one, but never a name the user chose or confirmed.
create or replace function public.handle_user_metadata_update() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles
  set display_name = public.default_display_name(new.raw_user_meta_data, new.email)
  where id = new.id
    and display_name_chosen_at is null
    and display_name = public.default_display_name(old.raw_user_meta_data, old.email);
  return new;
end $$;

-- The signed-in user's name, whether they chose it, and whether it is still
-- the local part of their e-mail address (the app then asks for a name).
create function public.my_display_name()
returns table (display_name text, chosen boolean, from_email boolean)
language sql stable security definer set search_path = '' as $$
  select
    p.display_name,
    p.display_name_chosen_at is not null,
    p.display_name_chosen_at is null
      and (btrim(p.display_name) = '' or p.display_name = left(split_part(coalesce(u.email, ''), '@', 1), 80))
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = (select auth.uid())
$$;

-- Saves the signed-in user's name: spaces and control characters collapse
-- to one space, then 1 to 80 characters, not all of them invisible. Returns
-- the name as stored.
create function public.set_display_name(p_name text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '[[:space:][:cntrl:]]+', ' ', 'g'));
  v_stored text;
begin
  -- A name of only format characters (zero-width spaces, joiners, soft
  -- hyphens, bidi marks) shows as blank: it counts as empty.
  if char_length(v_name) not between 1 and 80
     or regexp_replace(v_name, '[\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\uFFF9-\uFFFB\U000E0001-\U000E007F]', '', 'g') = '' then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;
  update public.profiles
  set display_name = v_name, display_name_chosen_at = now()
  where id = (select auth.uid())
  returning display_name into v_stored;
  if v_stored is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;
  return v_stored;
end $$;

revoke execute on function public.my_display_name() from public, anon;
revoke execute on function public.set_display_name(text) from public, anon;
grant execute on function public.my_display_name() to authenticated;
grant execute on function public.set_display_name(text) to authenticated;

-- No app ever wrote profiles directly; set_display_name is the one writer,
-- so a name saved from any client is marked chosen.
revoke update (display_name) on public.profiles from authenticated;
