-- Job 82: the hummlist.com waitlist (migration 20261102213606_waitlist.sql, docs/WAITLIST.md).
-- anon and authenticated reach nothing; a sign-up is one row per address in any letter case, a
-- known unconfirmed one is re-sent at most once per 24 h, a confirmed one never; a token confirms
-- once within 48 h; unsubscribing deletes and leaves proof only for confirmed rows; the purge
-- keeps every retention period to the minute; the rate counters hold their limits.
-- Addresses: hello+…@hummlist.com only.
begin;
select plan(108);

create function pg_temp.hex(t text) returns text language sql as $$
  select encode(extensions.digest(t, 'sha256'), 'hex');
$$;

create function pg_temp.signup(
  p_email text, p_at timestamptz, p_token text,
  p_platform text default 'ios', p_locale text default 'de', p_news boolean default false
) returns setof uuid language sql as $$
  select id from public.waitlist_signup(p_email, pg_temp.hex(lower(p_email)), p_platform, p_locale,
    p_news, 'waitlist-' || p_locale || '-v1', pg_temp.hex(p_token), p_at);
$$;

create function pg_temp.confirm(p_token text, p_at timestamptz) returns setof uuid language sql as $$
  select id from public.waitlist_confirm(pg_temp.hex(p_token), p_at);
$$;

create function pg_temp.row_of(p_email text) returns public.waitlist language sql as $$
  select * from public.waitlist where lower(email) = lower(p_email);
$$;

create function pg_temp.proofs(p_email text) returns setof text language sql as $$
  select end_reason from public.waitlist_consent_proof where email_hmac = pg_temp.hex(lower(p_email));
$$;

-- A row in a given state, straight into the table.
create function pg_temp.seed(
  p_email text, p_created timestamptz, p_confirmed timestamptz default null,
  p_news boolean default false, p_invited timestamptz default null,
  p_launch_mail timestamptz default null, p_last_mail timestamptz default null
) returns void language sql as $$
  insert into public.waitlist (email, email_hmac, platform, locale, launch_news,
    consent_text_version, created_at, confirm_token_hash, confirm_expires_at, confirmed_at,
    invite_sent_at, launch_mail_sent_at, last_mail_at)
  values (p_email, pg_temp.hex(lower(p_email)), 'android', 'en', p_news, 'waitlist-en-v1', p_created,
    case when p_confirmed is null then pg_temp.hex('seed:' || p_email) end,
    case when p_confirmed is null then p_created + interval '48 hours' end,
    p_confirmed, p_invited, p_launch_mail, coalesce(p_last_mail, p_created));
$$;

create function pg_temp.exists_(p_email text) returns boolean language sql as $$
  select exists (select from public.waitlist where lower(email) = lower(p_email));
$$;

-- Schema (AC8) -----------------------------------------------------------------------------------

select columns_are('public', 'waitlist', array[
  'id', 'email', 'email_hmac', 'platform', 'locale', 'launch_news', 'consent_text_version',
  'created_at', 'confirm_token_hash', 'confirm_expires_at', 'confirmed_at', 'invite_sent_at',
  'launch_mail_sent_at', 'last_mail_at'],
  'AC8: waitlist keeps the address, platform, locale, consent version and times; no IP, no user agent');
select hasnt_column('public', 'waitlist', 'unsubscribed_at',
  'AC12: unsubscribing deletes the row, so there is no unsubscribed_at (Legal handoff §3)');
select columns_are('public', 'waitlist_consent_proof', array[
  'id', 'email_hmac', 'consent_text_version', 'locale', 'launch_news', 'created_at',
  'confirmed_at', 'last_mail_at', 'ended_at', 'end_reason'],
  'the proof record holds no address');
select columns_are('public', 'waitlist_rate', array['key_hash', 'window_start', 'hits'],
  'a rate counter holds only the hashed key, its window and the count');
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relname like 'waitlist%' and c.relkind = 'r'
     and c.relrowsecurity),
  array['waitlist', 'waitlist_consent_proof', 'waitlist_rate'],
  'RLS is on for all three tables');
select is((select count(*)::integer from pg_policies where schemaname = 'public' and tablename like 'waitlist%'),
  0, 'and no policy opens any of them');
select is((select schedule from cron.job where jobname = 'purge-waitlist'), '23 3 * * *',
  'the purge runs daily at 03:23 UTC');

-- AC7: anon and authenticated reach nothing -------------------------------------------------------

select is(
  (select count(*)::integer from (values ('anon'), ('authenticated')) r(role),
     (values ('public.waitlist'), ('public.waitlist_consent_proof'), ('public.waitlist_rate')) t(tab),
     (values ('select'), ('insert'), ('update'), ('delete'), ('truncate'), ('references'), ('trigger')) p(priv)
   where has_table_privilege(r.role, t.tab, p.priv)),
  0, 'AC7: anon and authenticated hold no privilege on the waitlist tables');
select is(
  (select array_agg(distinct r.role order by r.role) from pg_proc f,
     (values ('anon'), ('authenticated'), ('public')) r(role)
   where f.pronamespace = 'public'::regnamespace
     and (f.proname like 'waitlist%' or f.proname = 'purge_waitlist')
     and case when r.role = 'public'
           then exists (select from aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) a
                        where a.grantee = 0 and a.privilege_type = 'EXECUTE')
           else has_function_privilege(r.role, f.oid, 'execute') end),
  null, 'AC7: no waitlist function is executable by anon, authenticated or public');
select is(
  (select count(*)::integer from pg_proc f
   where f.pronamespace = 'public'::regnamespace
     and f.proname in ('waitlist_signup', 'waitlist_confirm', 'waitlist_mailed', 'waitlist_unsubscribe',
                       'waitlist_rate_hit', 'waitlist_batch_counts', 'waitlist_batch_rows', 'purge_waitlist')
     and has_function_privilege('service_role', f.oid, 'execute')
     and f.prosecdef
     and f.proconfig @> array['search_path=""']),
  8, 'the service connection executes the eight entry points, security definer with an empty search_path');

select pg_temp.seed('hello+ac7@hummlist.com', '2026-11-10 10:00+00');

set local role anon;
select throws_ok('select * from public.waitlist', '42501', null, 'AC7: anon cannot select sign-ups');
select throws_ok('select * from public.waitlist_consent_proof', '42501', null, 'AC7: anon cannot select proof records');
select throws_ok('select * from public.waitlist_rate', '42501', null, 'AC7: anon cannot select rate counters');
select throws_ok($$insert into public.waitlist (email, email_hmac, platform, locale, consent_text_version)
  values ('hello+anon@hummlist.com', repeat('a', 64), 'ios', 'de', 'waitlist-de-v1')$$,
  '42501', null, 'AC7: anon cannot insert a sign-up');
select throws_ok($$update public.waitlist set platform = 'android'$$, '42501', null, 'AC7: anon cannot update');
select throws_ok($$delete from public.waitlist$$, '42501', null, 'AC7: anon cannot delete');
select throws_ok($$insert into public.waitlist_rate values ('all', now(), 0)$$, '42501', null,
  'AC7: anon cannot touch the rate counters');
select throws_ok($$select * from public.waitlist_signup('hello+anon@hummlist.com', repeat('a', 64), 'ios',
  'de', false, 'waitlist-de-v1', repeat('b', 64), now())$$, '42501', null, 'AC7: anon cannot call the sign-up');
select throws_ok($$select * from public.waitlist_batch_rows('2026-W47')$$, '42501', null,
  'AC7: anon cannot read a batch');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000082a1", "role": "authenticated"}', true);
select throws_ok('select * from public.waitlist', '42501', null, 'AC7: authenticated cannot select sign-ups');
select throws_ok('select * from public.waitlist_consent_proof', '42501', null, 'AC7: authenticated cannot select proof records');
select throws_ok('select * from public.waitlist_rate', '42501', null, 'AC7: authenticated cannot select rate counters');
select throws_ok($$insert into public.waitlist (email, email_hmac, platform, locale, consent_text_version)
  values ('hello+auth@hummlist.com', repeat('a', 64), 'ios', 'de', 'waitlist-de-v1')$$,
  '42501', null, 'AC7: authenticated cannot insert a sign-up');
select throws_ok($$update public.waitlist set platform = 'android'$$, '42501', null, 'AC7: authenticated cannot update');
select throws_ok($$delete from public.waitlist$$, '42501', null, 'AC7: authenticated cannot delete');
select throws_ok($$select public.waitlist_confirm(repeat('a', 64), now())$$, '42501', null,
  'AC7: authenticated cannot call confirm');
select throws_ok($$select public.waitlist_unsubscribe(gen_random_uuid(), now())$$, '42501', null,
  'AC7: authenticated cannot call unsubscribe');
select throws_ok($$select public.purge_waitlist(now())$$, '42501', null,
  'AC7: authenticated cannot run the purge');
reset role;
select set_config('request.jwt.claims', '', true);

select ok(pg_temp.exists_('hello+ac7@hummlist.com'), 'the row is still there after all of that');
delete from public.waitlist;

-- Sign-up (AC6) -----------------------------------------------------------------------------------

select is((select count(*)::integer from pg_temp.signup('hello+wl1@hummlist.com', '2026-11-10 10:00+00', 'tok-a')),
  1, 'a new address is stored and its confirmation goes out');
select is((pg_temp.row_of('hello+wl1@hummlist.com')).confirm_expires_at, '2026-11-12 10:00+00'::timestamptz,
  'its link expires 48 h after the mail');
select is((pg_temp.row_of('hello+wl1@hummlist.com')).last_mail_at, '2026-11-10 10:00+00'::timestamptz,
  'and last_mail_at says the mail went out');
select is((select count(*)::integer from pg_temp.signup('Hello+WL1@hummlist.com', '2026-11-11 09:59+00', 'tok-b', 'android')),
  0, 'the same address in other letters 23:59 h later sends nothing');
select is((select count(*)::integer from public.waitlist where lower(email) = 'hello+wl1@hummlist.com'), 1,
  'and makes no second row');
select is((pg_temp.row_of('hello+wl1@hummlist.com')).platform, 'ios', 'nor changes the first one');
select is((select count(*)::integer from pg_temp.signup('HELLO+wl1@hummlist.com', '2026-11-11 10:00+00', 'tok-b', 'android', 'en', true)),
  1, 'after 24 h the confirmation goes out again');
select is(
  (select row(email, platform, locale, launch_news, consent_text_version, confirm_token_hash,
              confirm_expires_at, last_mail_at)::text
   from public.waitlist where lower(email) = 'hello+wl1@hummlist.com'),
  row('hello+wl1@hummlist.com', 'android', 'en', true, 'waitlist-en-v1', pg_temp.hex('tok-b'),
      '2026-11-13 10:00+00'::timestamptz, '2026-11-11 10:00+00'::timestamptz)::text,
  'with the new answers and a new token, the address as first typed');
select throws_ok($$insert into public.waitlist (email, email_hmac, platform, locale, consent_text_version, confirm_token_hash, confirm_expires_at)
  values ('hello+WL1@hummlist.com', repeat('a', 64), 'ios', 'de', 'waitlist-de-v1', repeat('c', 64), now())$$,
  '23505', null, 'Foo@x and foo@x are one row: the unique index is on lower(email)');
select is((select count(*)::integer from pg_temp.signup(' hello+wl3@hummlist.com ', '2026-11-10 10:00+00', 'tok-c')),
  1, 'a padded address is stored');
select ok(pg_temp.exists_('hello+wl3@hummlist.com') and (pg_temp.row_of('hello+wl3@hummlist.com')).email = 'hello+wl3@hummlist.com',
  'trimmed');

-- Confirm (AC11) ----------------------------------------------------------------------------------

select is((select count(*)::integer from pg_temp.confirm('tok-a', '2026-11-11 11:00+00')), 0,
  'the token the re-send replaced confirms nothing');
select is((select count(*)::integer from pg_temp.confirm('tok-unknown', '2026-11-11 11:00+00')), 0,
  'an unknown token confirms nothing');
select is((select count(*)::integer from pg_temp.confirm('tok-b', '2026-11-13 10:00+00')), 0,
  'a token at its 48 h mark confirms nothing');
select ok((pg_temp.row_of('hello+wl1@hummlist.com')).confirmed_at is null, 'the row is still unconfirmed');
select is((select row(w.email, w.locale, w.launch_news)::text
           from public.waitlist_confirm(pg_temp.hex('tok-b'), '2026-11-13 09:59+00') w),
  row('hello+wl1@hummlist.com', 'en', true)::text,
  'a minute earlier it confirms and returns what the welcome mail needs');
select is(
  (select row(confirmed_at, confirm_token_hash, confirm_expires_at)::text
   from public.waitlist where lower(email) = 'hello+wl1@hummlist.com'),
  row('2026-11-13 09:59+00'::timestamptz, null::text, null::timestamptz)::text,
  'confirmed_at is set and the token is gone');
select is((select count(*)::integer from pg_temp.confirm('tok-b', '2026-11-13 09:59:30+00')), 0,
  'the same token a second time confirms nothing');
select is((pg_temp.row_of('hello+wl1@hummlist.com')).confirmed_at, '2026-11-13 09:59+00'::timestamptz,
  'and leaves the first confirmation as it was');
select is((select count(*)::integer from pg_temp.signup('hello+wl1@hummlist.com', '2026-12-20 10:00+00', 'tok-d', 'ios')),
  0, 'a confirmed address signing up again sends nothing');
select is((select row(platform, confirmed_at)::text from public.waitlist where lower(email) = 'hello+wl1@hummlist.com'),
  row('android', '2026-11-13 09:59+00'::timestamptz)::text, 'and changes nothing');
select throws_ok($$update public.waitlist set confirm_token_hash = repeat('e', 64), confirm_expires_at = now()
  where lower(email) = 'hello+wl1@hummlist.com'$$, '23514', null, 'a confirmed row cannot hold a token');

-- Mails ---------------------------------------------------------------------------------------------

select ok(public.waitlist_mailed((pg_temp.row_of('hello+wl1@hummlist.com')).id, 'welcome', '2026-11-13 10:00+00'),
  'the welcome mail is recorded');
select is((select row(last_mail_at, invite_sent_at)::text from public.waitlist where lower(email) = 'hello+wl1@hummlist.com'),
  row('2026-11-13 10:00+00'::timestamptz, null::timestamptz)::text, 'as last_mail_at only');
select ok(public.waitlist_mailed((pg_temp.row_of('hello+wl1@hummlist.com')).id, 'invite', '2026-11-20 10:00+00'),
  'the invite is recorded');
select ok(public.waitlist_mailed((pg_temp.row_of('hello+wl1@hummlist.com')).id, 'invite', '2026-11-21 10:00+00'),
  'a repeated invite too');
select is((select row(last_mail_at, invite_sent_at)::text from public.waitlist where lower(email) = 'hello+wl1@hummlist.com'),
  row('2026-11-21 10:00+00'::timestamptz, '2026-11-20 10:00+00'::timestamptz)::text,
  'invite_sent_at keeps the first invite, last_mail_at the latest mail');
select ok(not public.waitlist_mailed((pg_temp.row_of('hello+wl3@hummlist.com')).id, 'invite', '2026-11-20 10:00+00'),
  'an unconfirmed row takes no mail');
select ok((pg_temp.row_of('hello+wl3@hummlist.com')).invite_sent_at is null, 'and is not invited');
select throws_ok($$select public.waitlist_mailed(gen_random_uuid(), 'launch', now())$$, '22023', null,
  'only welcome and invite are known');

-- Unsubscribe (AC12) ------------------------------------------------------------------------------

select ok(public.waitlist_unsubscribe((pg_temp.row_of('hello+wl3@hummlist.com')).id, '2026-11-11 12:00+00'),
  'an unconfirmed row unsubscribes');
select ok(not pg_temp.exists_('hello+wl3@hummlist.com'), 'and is gone');
select is((select count(*)::integer from pg_temp.proofs('hello+wl3@hummlist.com')), 0, 'without a proof record');
select ok(public.waitlist_unsubscribe((pg_temp.row_of('hello+wl1@hummlist.com')).id, '2026-11-25 12:00+00'),
  'a confirmed row unsubscribes');
select ok(not pg_temp.exists_('hello+wl1@hummlist.com'), 'and is gone at once');
select is(
  (select row(consent_text_version, locale, launch_news, created_at, confirmed_at, last_mail_at, ended_at, end_reason)::text
   from public.waitlist_consent_proof where email_hmac = pg_temp.hex('hello+wl1@hummlist.com')),
  row('waitlist-en-v1', 'en', true, '2026-11-10 10:00+00'::timestamptz, '2026-11-13 09:59+00'::timestamptz,
      '2026-11-21 10:00+00'::timestamptz, '2026-11-25 12:00+00'::timestamptz, 'unsubscribed')::text,
  'leaving a proof record (unsubscribed) keyed by the address''s HMAC');
select ok(not public.waitlist_unsubscribe(gen_random_uuid(), '2026-11-25 12:00+00'), 'an unknown id deletes nothing');

-- Purge (AC13) ------------------------------------------------------------------------------------
-- p = 2027-06-01 12:00 UTC; each rule has a row a minute past its period and one a minute short.

delete from public.waitlist;
delete from public.waitlist_consent_proof;
delete from public.waitlist_rate;
select pg_temp.seed('hello+unc-old@hummlist.com', timestamptz '2027-06-01 12:00+00' - interval '7 days 1 minute');
select pg_temp.seed('hello+unc-new@hummlist.com', timestamptz '2027-06-01 12:00+00' - interval '7 days' + interval '1 minute');
select pg_temp.seed('hello+inv-old@hummlist.com', '2027-01-01 00:00+00', '2027-01-02 00:00+00', false,
  timestamptz '2027-06-01 12:00+00' - interval '3 months 1 minute');
select pg_temp.seed('hello+inv-new@hummlist.com', '2027-01-01 00:00+00', '2027-01-02 00:00+00', false,
  timestamptz '2027-06-01 12:00+00' - interval '3 months' + interval '1 minute');
select pg_temp.seed('hello+waiting@hummlist.com', '2026-11-15 00:00+00', '2026-11-16 00:00+00');
select pg_temp.seed('hello+news-old@hummlist.com', '2027-01-01 00:00+00', '2027-01-02 00:00+00', true,
  '2027-01-10 00:00+00', timestamptz '2027-06-01 12:00+00' - interval '30 days 1 minute');
select pg_temp.seed('hello+news-new@hummlist.com', '2027-01-01 00:00+00', '2027-01-02 00:00+00', true,
  '2027-01-10 00:00+00', timestamptz '2027-06-01 12:00+00' - interval '30 days' + interval '1 minute');
select pg_temp.seed('hello+news-invited@hummlist.com', '2026-11-15 00:00+00', '2026-11-16 00:00+00', true,
  '2026-11-20 00:00+00');
insert into public.waitlist_consent_proof (email_hmac, consent_text_version, locale, launch_news,
  created_at, confirmed_at, last_mail_at, ended_at, end_reason) values
  (pg_temp.hex('hello+proof-old@hummlist.com'), 'waitlist-de-v1', 'de', false, '2024-01-01+00', '2024-01-01+00',
   timestamptz '2027-06-01 12:00+00' - interval '3 years 1 minute',
   timestamptz '2027-06-01 12:00+00' - interval '3 years 2 minutes', 'unsubscribed'),
  (pg_temp.hex('hello+proof-ended@hummlist.com'), 'waitlist-de-v1', 'de', false, '2024-01-01+00', '2024-01-01+00',
   '2024-01-02+00', timestamptz '2027-06-01 12:00+00' - interval '3 years' + interval '1 minute', 'deletion_request'),
  (pg_temp.hex('hello+proof-mailed@hummlist.com'), 'waitlist-de-v1', 'de', false, '2024-01-01+00', '2024-01-01+00',
   timestamptz '2027-06-01 12:00+00' - interval '3 years' + interval '1 minute', '2024-01-02+00', 'purpose_done');
insert into public.waitlist_rate values
  (pg_temp.hex('client-old'), timestamptz '2027-06-01 12:00+00' - interval '2 hours 1 second', 3),
  (pg_temp.hex('client-new'), timestamptz '2027-06-01 12:00+00' - interval '2 hours' + interval '1 second', 3);

select is(public.purge_waitlist('2027-06-01 12:00+00'), 5, 'the purge removes five rows');
select ok(not pg_temp.exists_('hello+unc-old@hummlist.com'), 'AC13: an unconfirmed row older than 7 days is gone');
select is((select count(*)::integer from pg_temp.proofs('hello+unc-old@hummlist.com')), 0, 'without a proof record');
select ok(pg_temp.exists_('hello+unc-new@hummlist.com'), 'AC13: one a minute younger stays');
select ok(not pg_temp.exists_('hello+inv-old@hummlist.com'), 'confirmed without launch news, invited over 3 months ago: gone');
select is(array(select pg_temp.proofs('hello+inv-old@hummlist.com')), array['purpose_done'],
  'with a proof record (purpose_done)');
select ok(pg_temp.exists_('hello+inv-new@hummlist.com'), 'invited a minute under 3 months ago: stays');
select ok(pg_temp.exists_('hello+waiting@hummlist.com'), 'confirmed and not yet invited: stays');
select ok(not pg_temp.exists_('hello+news-old@hummlist.com'), 'with launch news, launch mail over 30 days ago: gone');
select is(array(select pg_temp.proofs('hello+news-old@hummlist.com')), array['purpose_done'], 'with a proof record');
select ok(pg_temp.exists_('hello+news-new@hummlist.com'), 'launch mail a minute under 30 days ago: stays');
select ok(pg_temp.exists_('hello+news-invited@hummlist.com'), 'with launch news, invited but no launch mail yet: stays');
select is((select count(*)::integer from pg_temp.proofs('hello+proof-old@hummlist.com')), 0,
  'a proof record whose last mail and end are over 3 years ago is gone');
select is((select count(*)::integer from pg_temp.proofs('hello+proof-ended@hummlist.com')), 1,
  'one that ended a minute under 3 years ago stays');
select is((select count(*)::integer from pg_temp.proofs('hello+proof-mailed@hummlist.com')), 1,
  'one whose last mail is a minute under 3 years old stays');
select is((select count(*)::integer from public.waitlist_rate where key_hash = pg_temp.hex('client-old')), 0,
  'a rate counter over 2 hours old is gone');
select is((select count(*)::integer from public.waitlist_rate where key_hash = pg_temp.hex('client-new')), 1,
  'a younger one stays');
select is(public.purge_waitlist('2027-06-01 12:00+00'), 0, 'a second run finds nothing more');

delete from public.waitlist;
delete from public.waitlist_consent_proof;
delete from public.waitlist_rate;
select pg_temp.seed('hello+end-conf@hummlist.com', '2027-12-01 00:00+00', '2027-12-01 01:00+00');
select pg_temp.seed('hello+end-news@hummlist.com', '2027-12-01 00:00+00', '2027-12-01 01:00+00', true,
  '2027-12-20 00:00+00');
select pg_temp.seed('hello+end-unc@hummlist.com', '2027-12-30 22:00+00');
select is(public.purge_waitlist('2027-12-30 22:59+00'), 0,
  'a minute before 2027-12-31 in Berlin the rows stay');
select is(public.purge_waitlist('2027-12-30 23:00+00'), 3, 'on 2027-12-31 (Berlin) the purge ends them all');
select is((select count(*)::integer from public.waitlist), 0, 'confirmed or not, nothing stays');
select is(
  (select count(*)::integer from public.waitlist_consent_proof
   where email_hmac in (pg_temp.hex('hello+end-conf@hummlist.com'), pg_temp.hex('hello+end-news@hummlist.com'))
     and end_reason = 'purpose_done' and ended_at = '2027-12-30 23:00+00'),
  2, 'both confirmed rows left their proof record');
select is((select count(*)::integer from pg_temp.proofs('hello+end-unc@hummlist.com')), 0,
  'the unconfirmed one none');

-- Rate counters (AC9) ------------------------------------------------------------------------------
-- 2 per key and 4 in total per hour here; the function passes 5 and 300.

select ok(public.waitlist_rate_hit(pg_temp.hex('k1'), '2027-06-01 12:00+00', 2, 4), 'the first request of a key passes');
select ok(public.waitlist_rate_hit(pg_temp.hex('k1'), '2027-06-01 12:59+00', 2, 4), 'the second in the hour too');
select ok(not public.waitlist_rate_hit(pg_temp.hex('k1'), '2027-06-01 12:59:59+00', 2, 4), 'the third is refused');
select ok(public.waitlist_rate_hit(pg_temp.hex('k2'), '2027-06-01 12:30+00', 2, 4), 'another key passes');
select ok(not public.waitlist_rate_hit(pg_temp.hex('k3'), '2027-06-01 12:30+00', 2, 4),
  'a fifth request in the hour is refused for everyone');
select ok(public.waitlist_rate_hit(pg_temp.hex('k1'), '2027-06-01 13:00+00', 2, 4), 'the next hour starts afresh');
select is((select hits from public.waitlist_rate where key_hash = 'all' and window_start = '2027-06-01 12:00+00'), 5,
  'the total counts every request of the hour');
select is(public.purge_waitlist('2027-06-01 14:30+00'), 4, 'two hours after their window the counters go');
select is((select count(*)::integer from public.waitlist_rate), 2, 'the 13:00 window stays');
select ok(public.waitlist_rate_hit(pg_temp.hex('k4'), '2027-06-01 15:00:01+00', 2, 4),
  'a request after the 13:00 window is 2 hours old passes');
select is((select count(*)::integer from public.waitlist_rate where window_start < '2027-06-01 13:00:01+00'), 0,
  'and removed the old counters itself, without waiting for the daily purge');
select throws_ok($$insert into public.waitlist_rate values ('10.0.0.1', now(), 1)$$, '23514', null,
  'a counter key is a hash, never an address');

-- Invite batches ------------------------------------------------------------------------------------

select is(public.waitlist_batch_window('2026-W47'),
  tstzrange('2026-11-16 00:00 Europe/Berlin', '2026-11-23 00:00 Europe/Berlin', '[)'),
  '2026-W47 is Monday to Monday in Berlin');
select is(public.waitlist_batch_window('2026-W53'),
  tstzrange('2026-12-28 00:00 Europe/Berlin', '2027-01-04 00:00 Europe/Berlin', '[)'),
  '2026 has a week 53');
select throws_ok($$select public.waitlist_batch_window('2025-W53')$$, '22023', null, '2025 has none');
select throws_ok($$select public.waitlist_batch_window('2026-47')$$, '22023', null, 'a batch id looks like 2026-W47');

delete from public.waitlist;
select pg_temp.seed('hello+b1@hummlist.com', '2026-11-15 20:00+00', '2026-11-15 22:59+00');
select pg_temp.seed('hello+b2@hummlist.com', '2026-11-16 08:00+00', '2026-11-16 09:00+00');
select pg_temp.seed('hello+b3@hummlist.com', '2026-11-16 08:00+00', '2026-11-22 22:59+00', false, '2026-11-23 10:00+00');
select pg_temp.seed('hello+b4@hummlist.com', '2026-11-22 22:00+00', '2026-11-22 23:00+00');
select pg_temp.seed('hello+b5@hummlist.com', '2026-11-20 08:00+00');
update public.waitlist set platform = 'ios', locale = 'de' where email = 'hello+b2@hummlist.com';

select is(
  (select array_agg(row(platform, locale, confirmed, invited, to_invite)::text order by platform, locale)
   from public.waitlist_batch_counts('2026-W47')),
  array[row('android', 'en', 1, 1, 0)::text, row('ios', 'de', 1, 0, 1)::text],
  'the dry run counts the week''s confirmed rows (Berlin time) per platform and locale');
select is(
  (select array_agg(email order by email) from public.waitlist_batch_rows('2026-W47')),
  array['hello+b2@hummlist.com'],
  'the batch rows are the week''s confirmed, uninvited ones');
select is(
  (select array_agg(email order by email) from public.waitlist_batch_rows('2026-W48')),
  array['hello+b4@hummlist.com'],
  'Sunday 23:00 UTC is Monday in Berlin: the next batch');

select * from finish();
rollback;
