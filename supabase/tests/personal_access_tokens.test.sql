begin;
select plan(21);

-- The app's own sign-in: its tokens carry a session_id and no client_id.
create function pg_temp.login(uid uuid, extra jsonb default jsonb_build_object('session_id', gen_random_uuid()))
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    (jsonb_build_object('sub', uid, 'role', 'authenticated') || extra)::text, true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.hash(token text) returns text language sql as $$
  select encode(extensions.digest(token, 'sha256'), 'hex');
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.com'),
  ('00000000-0000-0000-0000-0000000000a2', 'anna@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'carl@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Alice');
create temp table inv as select code from public.create_invite((select id from ha));
create temp table ta as select * from public.create_personal_access_token('  Claude  ');
grant select on ha, inv, ta to authenticated;

select ok((select token ~ '^fgp_[A-Za-z0-9_-]{43}$' from ta), 'the plaintext token is returned once, prefixed');
select is((select name from ta), 'Claude', 'the token name is trimmed');
select is(
  (select token_hint from public.personal_access_tokens),
  (select right(token, 4) from ta),
  'the owner sees the token with its hint'
);
select throws_ok(
  $$ select token_hash from public.personal_access_tokens $$,
  '42501', null, 'the hash is not readable by clients'
);
select throws_ok(
  $$ insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint)
     select id, auth.uid(), 'x', repeat('0', 64), 'abcd' from ha $$,
  '42501', null, 'tokens are created only through the RPC'
);

-- An OAuth client (an MCP connection) gets a session_id and its client_id; a token that never
-- expires would outlive the grant the user can revoke.
select pg_temp.login('00000000-0000-0000-0000-0000000000a1',
  '{"session_id": "00000000-0000-0000-0000-0000000a5e51", "client_id": "00000000-0000-0000-0000-00000000c11e"}');
select throws_ok($$ select public.create_personal_access_token('x') $$, '42501', 'session_required',
  'an OAuth-connected app cannot make a token');
select throws_ok($$ select public.create_personal_access_token('x', (select id from ha)) $$, '42501',
  'session_required', 'an OAuth-connected app cannot make a token for a named household');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1', '{}');
select throws_ok($$ select public.create_personal_access_token('x') $$, '42501', 'session_required',
  'a token without a session cannot make a token');
select pg_temp.login('00000000-0000-0000-0000-0000000000a1', '{"session_id": ""}');
select throws_ok($$ select public.create_personal_access_token('x') $$, '42501', 'session_required',
  'an empty session_id is no session');
select is((select count(*)::int from public.personal_access_tokens), 1, 'refused calls leave no token');

select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select public.join_household((select code from inv));
select is((select count(*)::int from public.personal_access_tokens), 0,
  'a member of the same household does not see someone else''s tokens');
update public.personal_access_tokens set revoked_at = now();

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
select public.create_household('Bob');
select is((select count(*)::int from public.personal_access_tokens), 0,
  'tokens of another household are invisible');
update public.personal_access_tokens set revoked_at = now();

select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select throws_ok(
  $$ select public.create_personal_access_token('x') $$,
  '42501', 'not_a_member', 'a user without a household cannot create a token'
);
select throws_ok(
  $$ select public.authenticate_personal_access_token(repeat('0', 64)) $$,
  '42501', null, 'clients cannot resolve token hashes'
);

select pg_temp.as_postgres();
select results_eq(
  $$ select user_id, household_id from public.authenticate_personal_access_token(pg_temp.hash((select token from ta))) $$,
  $$ select '00000000-0000-0000-0000-0000000000a1'::uuid, id from ha $$,
  'a valid token resolves to its user and household, untouched by other users'' revoke attempts'
);
select isnt((select last_used_at from public.personal_access_tokens), null, 'use is recorded');
select is_empty(
  $$ select * from public.authenticate_personal_access_token(pg_temp.hash('fgp_wrong')) $$,
  'an unknown token resolves to nothing'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
update public.personal_access_tokens set revoked_at = now();
update public.personal_access_tokens set revoked_at = null;
select isnt((select revoked_at from public.personal_access_tokens), null, 'revocation cannot be undone');

select pg_temp.as_postgres();
select is_empty(
  $$ select * from public.authenticate_personal_access_token(pg_temp.hash((select token from ta))) $$,
  'a revoked token resolves to nothing'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table tb as select * from public.create_personal_access_token('Siri');
grant select on tb to authenticated;
select public.leave_current_household();
select pg_temp.as_postgres();
select is_empty(
  $$ select * from public.authenticate_personal_access_token(pg_temp.hash((select token from tb))) $$,
  'a token stops working once its creator leaves the household'
);

select pg_temp.login('00000000-0000-0000-0000-0000000000a2');
select public.leave_current_household();
select pg_temp.as_postgres();
select is((select count(*)::int from public.personal_access_tokens), 0,
  'tokens go with their household');

select * from finish();
rollback;
