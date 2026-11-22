-- Access key retention (Legal Review 2026-11-01, N-4 (b)): every key that stops working gets
-- revoked_at as the time it ended, and purge_access_tokens deletes keys 30 days after that.
-- Ada and Ben share a household; Ada has a PAT and a Siri key per session.
begin;
select plan(26);

create function pg_temp.login(uid uuid, claims jsonb default '{}') returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    (jsonb_build_object('sub', uid, 'role', 'authenticated') || claims)::text, true);
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.works(token text) returns boolean language sql as $$
  select exists (select from public.authenticate_access_token(encode(extensions.digest(token, 'sha256'), 'hex')));
$$;

create function pg_temp.ended(p_id uuid) returns boolean language sql as $$
  select revoked_at is not null from public.personal_access_tokens where id = p_id;
$$;

create function pg_temp.kept(p_id uuid) returns boolean language sql as $$
  select exists (select from public.personal_access_tokens where id = p_id);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000e7aa1', 'ret-ada@example.com'),
  ('00000000-0000-0000-0000-0000000e7bb1', 'ret-ben@example.com');
insert into auth.sessions (id, user_id, not_after) values
  ('00000000-0000-0000-0000-00000e7a5e51', '00000000-0000-0000-0000-0000000e7aa1', null),
  ('00000000-0000-0000-0000-00000e7a5e52', '00000000-0000-0000-0000-0000000e7aa1', null),
  ('00000000-0000-0000-0000-00000e7a5e53', '00000000-0000-0000-0000-0000000e7aa1', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000e7b5e51', '00000000-0000-0000-0000-0000000e7bb1', null);

-- Ada: a household, a PAT, and three Siri keys, one per session.
select pg_temp.login('00000000-0000-0000-0000-0000000e7aa1', '{"session_id": "00000000-0000-0000-0000-00000e7a5e51"}');
create temp table h as select id from public.create_household('Ada');
create temp table inv as select code from public.create_invite((select id from h));
create temp table pat as select * from public.create_personal_access_token('Claude');
create temp table s_live as select * from public.create_siri_credential();
select pg_temp.login('00000000-0000-0000-0000-0000000e7aa1', '{"session_id": "00000000-0000-0000-0000-00000e7a5e52"}');
create temp table s_signed_out as select * from public.create_siri_credential();
select pg_temp.login('00000000-0000-0000-0000-0000000e7aa1', '{"session_id": "00000000-0000-0000-0000-00000e7a5e53"}');
create temp table s_expired as select * from public.create_siri_credential();
grant select on h, inv, pat, s_live, s_signed_out, s_expired to authenticated;

-- Ben joins and has a PAT and a Siri key.
select pg_temp.login('00000000-0000-0000-0000-0000000e7bb1', '{"session_id": "00000000-0000-0000-0000-00000e7b5e51"}');
select public.join_household((select code from inv));
create temp table ben_pat as select * from public.create_personal_access_token('MCP');
create temp table ben_siri as select * from public.create_siri_credential();
create temp table ben_old as select * from public.create_personal_access_token('Old');
grant select on ben_pat, ben_siri, ben_old to authenticated;

-- 1. A client's revocation is stamped now(), whatever time it sends.
update public.personal_access_tokens set revoked_at = now() - interval '400 days' where id = (select id from ben_old);
select pg_temp.as_postgres();
select ok(
  (select revoked_at > now() - interval '1 minute' from public.personal_access_tokens where id = (select id from ben_old)),
  'a client cannot backdate a revocation'
);
select pg_temp.login('00000000-0000-0000-0000-0000000e7bb1');
update public.personal_access_tokens set revoked_at = null where id = (select id from ben_old);
select pg_temp.as_postgres();
select ok(pg_temp.ended((select id from ben_old)), 'revocation is still one-way');
select pg_temp.login('00000000-0000-0000-0000-0000000e7aa1', '{"session_id": "00000000-0000-0000-0000-00000e7a5e51"}');
create temp table ada_future as select * from public.create_personal_access_token('Future');
grant select on ada_future to authenticated;
update public.personal_access_tokens set revoked_at = now() + interval '10 years' where id = (select id from ada_future);
select pg_temp.as_postgres();
select ok(
  (select revoked_at <= now() from public.personal_access_tokens where id = (select id from ada_future)),
  'nor postpone one'
);

-- 2. The daily job ends Siri keys whose session is gone or past not_after.
delete from auth.sessions where id = '00000000-0000-0000-0000-00000e7a5e52';
update auth.sessions set not_after = now() - interval '1 minute' where id = '00000000-0000-0000-0000-00000e7a5e53';
select ok(not pg_temp.works((select token from s_signed_out)), 'a signed-out Siri key does not work');
select ok(not pg_temp.ended((select id from s_signed_out)), 'but nothing has marked it ended yet');
select is(public.purge_access_tokens(), 0, 'the first run deletes nothing: nothing ended 30 days ago');
select ok(pg_temp.ended((select id from s_signed_out)), 'a Siri key whose session was deleted is ended');
select ok(pg_temp.ended((select id from s_expired)), 'a Siri key whose session passed not_after is ended');
select ok(not pg_temp.ended((select id from s_live)), 'a Siri key with a live session is not');
select ok(pg_temp.works((select token from s_live)), 'and still works');
select ok(not pg_temp.ended((select id from pat)) and pg_temp.works((select token from pat)),
  'a PAT of a member is not ended');

-- 3. Leaving the household ends the leaver's keys at once, for good; the others' stay.
select pg_temp.login('00000000-0000-0000-0000-0000000e7bb1', '{"session_id": "00000000-0000-0000-0000-00000e7b5e51"}');
select public.leave_current_household();
select pg_temp.as_postgres();
select ok(pg_temp.ended((select id from ben_pat)) and pg_temp.ended((select id from ben_siri)),
  'leaving ends the leaver''s PAT and Siri key');
select ok(not pg_temp.ended((select id from pat)) and not pg_temp.ended((select id from s_live)),
  'the remaining member''s keys are untouched');
select pg_temp.login('00000000-0000-0000-0000-0000000e7aa1');
create temp table inv2 as select code from public.create_invite((select id from h));
grant select on inv2 to authenticated;
select pg_temp.login('00000000-0000-0000-0000-0000000e7bb1', '{"session_id": "00000000-0000-0000-0000-00000e7b5e51"}');
select public.join_household((select code from inv2));
select pg_temp.as_postgres();
select ok(not pg_temp.works((select token from ben_pat)), 'rejoining does not bring an ended key back');

-- A key that stopped working before this job existed (membership row gone without the trigger).
alter table public.household_members disable trigger household_members_end_access_tokens;
delete from public.household_members where user_id = '00000000-0000-0000-0000-0000000e7bb1';
alter table public.household_members enable trigger household_members_end_access_tokens;
insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint)
values ((select id from h), '00000000-0000-0000-0000-0000000e7bb1', 'Stray', repeat('e', 64), 'eeee');
select public.purge_access_tokens();
select ok(
  (select revoked_at is not null from public.personal_access_tokens where name = 'Stray'),
  'the job ends a key whose creator is not a member, as a backstop'
);

-- 4. 30 days after the end, the job deletes keys of both kinds.
-- Backdating needs the one-way trigger off: it keeps the first revoked_at.
alter table public.personal_access_tokens disable trigger personal_access_tokens_keep_revoked;
update public.personal_access_tokens set revoked_at = now() - interval '30 days 1 minute'
where id in ((select id from ben_pat), (select id from s_signed_out));
update public.personal_access_tokens set revoked_at = now() - interval '29 days'
where id = (select id from s_expired);
alter table public.personal_access_tokens enable trigger personal_access_tokens_keep_revoked;
select is(public.purge_access_tokens(), 2, 'the purge reports two deleted keys');
select ok(not pg_temp.kept((select id from ben_pat)), 'a PAT ended 30 days and a minute ago is gone');
select ok(not pg_temp.kept((select id from s_signed_out)), 'a Siri key ended 30 days and a minute ago is gone');
select ok(pg_temp.kept((select id from s_expired)), 'a key ended 29 days ago stays');
select ok(pg_temp.kept((select id from pat)) and pg_temp.kept((select id from s_live)), 'working keys stay');
select is(public.purge_access_tokens(), 0, 'a second run deletes nothing');

-- 5. Zugänge and the data export still read the rows that are left.
select pg_temp.login('00000000-0000-0000-0000-0000000e7aa1');
select results_eq(
  $$ select id from public.personal_access_tokens where revoked_at is null order by created_at desc, id $$,
  $$ select id from (select id, 1 as o from s_live union all select id, 2 from pat) x order by o $$,
  'Zugänge lists Ada''s working keys'
);
select is(
  (select jsonb_array_length(public.export_my_data() -> 'access_tokens')),
  (select count(*)::int from public.personal_access_tokens),
  'the export lists every key still stored, ended ones included'
);
select throws_ok($$ select public.purge_access_tokens() $$, '42501', null, 'clients cannot run the purge');

-- 6. Scheduled daily, once.
select pg_temp.as_postgres();
select results_eq(
  $$ select schedule, command, active from cron.job where jobname = 'purge-access-tokens' $$,
  $$ values ('23 3 * * *'::text, 'select public.purge_access_tokens()'::text, true) $$,
  'the purge is scheduled daily'
);
select cron.schedule('purge-access-tokens', '23 3 * * *', 'select public.purge_access_tokens()');
select is((select count(*)::int from cron.job where jobname = 'purge-access-tokens'), 1,
  'applying the schedule twice leaves one job');

select * from finish();
rollback;
