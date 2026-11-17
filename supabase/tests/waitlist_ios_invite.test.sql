-- Job 280: the iOS invite sender's recipients and sent state
-- (migration 20261116120000_waitlist_ios_invite.sql, docs/WAITLIST.md "iOS invite").
-- Recipients are confirmed iOS rows without an invite, in their sign-up locale; Android,
-- unconfirmed, invited and unsubscribed rows never are. A claim succeeds once per row, a release
-- undoes only its own claim, and the service role alone may call any of it.
-- Addresses: test+…@snacklist.app only.
begin;
select plan(17);

create function pg_temp.seed(
  p_email text, p_platform text, p_locale text, p_confirmed timestamptz,
  p_invited timestamptz default null
) returns uuid language sql as $$
  insert into public.waitlist (email, email_hmac, platform, locale, consent_text_version,
    created_at, confirm_token_hash, confirm_expires_at, confirmed_at, invite_sent_at)
  values (p_email, encode(extensions.digest(lower(p_email), 'sha256'), 'hex'), p_platform,
    p_locale, 'waitlist-' || p_locale || '-v2', '2026-11-01 09:00Z',
    case when p_confirmed is null then encode(extensions.digest('t:' || p_email, 'sha256'), 'hex') end,
    case when p_confirmed is null then timestamptz '2026-11-03 09:00Z' end,
    p_confirmed, p_invited)
  returning id;
$$;

-- The counts cover the whole table: start it empty (the test rolls back).
delete from public.waitlist;

select pg_temp.seed('test+ios-de@snacklist.app', 'ios', 'de', '2026-11-02 10:00Z');
select pg_temp.seed('test+ios-en@snacklist.app', 'ios', 'en', '2026-11-02 09:00Z');
select pg_temp.seed('test+ios-late@snacklist.app', 'ios', 'de', '2026-11-05 09:00Z');
select pg_temp.seed('test+android@snacklist.app', 'android', 'de', '2026-11-01 10:00Z');
select pg_temp.seed('test+unconfirmed@snacklist.app', 'ios', 'en', null);
select pg_temp.seed('test+invited@snacklist.app', 'ios', 'en', '2026-11-01 10:00Z', '2026-11-08 10:00Z');
select pg_temp.seed('test+gone@snacklist.app', 'ios', 'de', '2026-11-01 11:00Z');
select public.waitlist_unsubscribe(
  (select id from public.waitlist where email = 'test+gone@snacklist.app'), '2026-11-09 10:00Z');

select results_eq(
  $$select email, locale from public.waitlist_ios_invite_rows(null) where email like 'test+%'$$,
  $$values ('test+ios-en@snacklist.app', 'en'), ('test+ios-de@snacklist.app', 'de'),
           ('test+ios-late@snacklist.app', 'de')$$,
  'recipients: confirmed iOS rows without an invite, earliest confirmation first, with their locale');
select is(
  (select count(*)::integer from public.waitlist_ios_invite_rows(2) where email like 'test+%'), 2,
  'the limit is the batch size');
select set_eq(
  $$select locale, confirmed, invited, to_invite from public.waitlist_ios_invite_counts()$$,
  $$values ('de', 2, 0, 2), ('en', 2, 1, 1)$$,
  'counts per locale: confirmed iOS rows, already invited, to invite; no Android, unconfirmed or unsubscribed row');

select ok(
  public.waitlist_invite_claim(
    (select id from public.waitlist where email = 'test+ios-de@snacklist.app'), '2026-11-16 10:00Z'),
  'a claim marks an uninvited row');
select is(
  (select invite_sent_at from public.waitlist where email = 'test+ios-de@snacklist.app'),
  timestamptz '2026-11-16 10:00Z', 'the claim is the sent state');
select ok(
  not public.waitlist_invite_claim(
    (select id from public.waitlist where email = 'test+ios-de@snacklist.app'), '2026-11-16 10:05Z'),
  'a second claim of the same row fails: a rerun never mails it again');
select ok(
  not exists (select from public.waitlist_ios_invite_rows(null) where email = 'test+ios-de@snacklist.app'),
  'a claimed row is no recipient any more');
select ok(
  not public.waitlist_invite_claim(
    (select id from public.waitlist where email = 'test+android@snacklist.app'), '2026-11-16 10:00Z'),
  'an Android row cannot be claimed');
select ok(
  not public.waitlist_invite_claim(
    (select id from public.waitlist where email = 'test+unconfirmed@snacklist.app'), '2026-11-16 10:00Z'),
  'an unconfirmed row cannot be claimed');
select ok(
  not public.waitlist_invite_claim(
    (select id from public.waitlist where email = 'test+invited@snacklist.app'), '2026-11-16 10:00Z'),
  'an invited row cannot be claimed');
select ok(
  not public.waitlist_invite_claim(gen_random_uuid(), '2026-11-16 10:00Z'),
  'a deleted (unsubscribed) row cannot be claimed');

select ok(
  not public.waitlist_invite_release(
    (select id from public.waitlist where email = 'test+invited@snacklist.app'), '2026-11-16 10:00Z'),
  'a release with another time leaves an earlier invite alone');
select is(
  (select invite_sent_at from public.waitlist where email = 'test+invited@snacklist.app'),
  timestamptz '2026-11-08 10:00Z', 'the earlier invite stays recorded');
select ok(
  public.waitlist_invite_release(
    (select id from public.waitlist where email = 'test+ios-de@snacklist.app'), '2026-11-16 10:00Z'),
  'a release undoes its own claim');
select ok(
  exists (select from public.waitlist_ios_invite_rows(null) where email = 'test+ios-de@snacklist.app'),
  'a released row is a recipient again');

select is(
  (select count(*)::integer
   from pg_proc f, (values ('anon'), ('authenticated')) r(role)
   where f.pronamespace = 'public'::regnamespace
     and f.proname in ('waitlist_ios_invite_counts', 'waitlist_ios_invite_rows',
                       'waitlist_invite_claim', 'waitlist_invite_release')
     and has_function_privilege(r.role, f.oid, 'execute')),
  0, 'anon and authenticated cannot call the sender''s functions');
select is(
  (select count(*)::integer from pg_proc f
   where f.pronamespace = 'public'::regnamespace
     and f.proname in ('waitlist_ios_invite_counts', 'waitlist_ios_invite_rows',
                       'waitlist_invite_claim', 'waitlist_invite_release')
     and has_function_privilege('service_role', f.oid, 'execute')),
  4, 'the service role can');

select * from finish();
rollback;
