-- As 20261108125048_households_multi.sql, but only the app's own sign-in may make a token (job 389):
-- an OAuth access token (an MCP connection) reaches PostgREST as `authenticated` too, and a token
-- it made never expires and outlives the grant. Same check as create_api_token and
-- create_siri_credential; the one-argument form delegates here.
create or replace function public.create_personal_access_token(p_name text, p_household uuid)
returns table (id uuid, name text, token text)
language plpgsql security definer set search_path = '' as $$
declare
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_household uuid;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_claims ? 'client_id' or nullif(v_claims ->> 'session_id', '') is null then
    raise exception 'session_required' using errcode = '42501';
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
