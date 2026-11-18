begin;
select plan(19);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.name_of(uid uuid) returns text language sql as $$
  select display_name from public.profiles where id = uid
$$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000297a1', 'peter@example.com', '{"full_name": "Peter Trost", "iss": "https://accounts.google.com"}'),
  ('00000000-0000-0000-0000-0000000297a2', 'x7k2p9@privaterelay.appleid.com', '{"iss": "https://appleid.apple.com"}'),
  ('00000000-0000-0000-0000-0000000297a3', 'lea.brandt87@example.com', '{}');

select pg_temp.login('00000000-0000-0000-0000-0000000297a1');
select results_eq(
  $$ select display_name, chosen, from_email from public.my_display_name() $$,
  $$ values ('Peter Trost'::text, false, false) $$,
  'a Google name is not chosen yet and not from the e-mail'
);
select pg_temp.login('00000000-0000-0000-0000-0000000297a3');
select results_eq(
  $$ select display_name, chosen, from_email from public.my_display_name() $$,
  $$ values ('lea.brandt87'::text, false, true) $$,
  'an e-mail sign-up''s name is its local part'
);

-- Confirming the Google name as it is (DN3's one tap) makes it chosen.
select pg_temp.login('00000000-0000-0000-0000-0000000297a1');
select is(public.set_display_name('Peter Trost'), 'Peter Trost', 'confirming returns the stored name');
select results_eq(
  $$ select display_name, chosen, from_email from public.my_display_name() $$,
  $$ values ('Peter Trost'::text, true, false) $$,
  'a confirmed name is chosen'
);
select pg_temp.logout();
update auth.users set raw_user_meta_data = '{"full_name": "Someone Else", "iss": "https://accounts.google.com"}'
where id = '00000000-0000-0000-0000-0000000297a1';
select is(pg_temp.name_of('00000000-0000-0000-0000-0000000297a1'), 'Peter Trost',
  'a confirmed name equal to the provider''s is never overwritten by a later OAuth name');

-- A typed name survives Apple's first sign-in name and a changed e-mail.
select pg_temp.login('00000000-0000-0000-0000-0000000297a2');
select is(public.set_display_name('  Lea   🌻 '), 'Lea 🌻', 'spaces trim and collapse, emoji stay');
select pg_temp.logout();
update auth.users set raw_user_meta_data = raw_user_meta_data || '{"full_name": "Lea Brandt"}', email = 'lea@example.org'
where id = '00000000-0000-0000-0000-0000000297a2';
select is(pg_temp.name_of('00000000-0000-0000-0000-0000000297a2'), 'Lea 🌻',
  'a chosen name is never overwritten by a later Apple name');

-- Without a choice the derived name still follows the provider.
update auth.users set raw_user_meta_data = '{"full_name": "Lea Brandt"}'
where id = '00000000-0000-0000-0000-0000000297a3';
select is(pg_temp.name_of('00000000-0000-0000-0000-0000000297a3'), 'Lea Brandt',
  'an unchosen e-mail-prefix name still takes a later provider name');

select pg_temp.login('00000000-0000-0000-0000-0000000297a3');
select throws_ok($$ select public.set_display_name('   ') $$, '22023', 'invalid_display_name', 'an empty name is refused');
select throws_ok($$ select public.set_display_name(repeat('a', 81)) $$, '22023', 'invalid_display_name', '81 characters are refused');
select throws_ok($$ select public.set_display_name(E'\u200B\u200D\uFEFF') $$, '22023', 'invalid_display_name', 'a name of only zero-width characters is refused');
select is(public.set_display_name('👨‍👩‍👧'), '👨‍👩‍👧', 'a joined emoji keeps its zero-width joiners');
select is(public.set_display_name(repeat('🌻', 80)), repeat('🌻', 80), '80 emoji fit: characters, not bytes');
select is(public.set_display_name(E'Lea\n\tBrandt'), 'Lea Brandt', 'line breaks and tabs become one space');

-- Only the RPC writes, and only the caller's own row.
select throws_ok(
  $$ update public.profiles set display_name = 'Mallory' where id = '00000000-0000-0000-0000-0000000297a3' $$,
  '42501', null, 'a client cannot write its profile directly'
);
select is(
  (select count(*)::int from public.my_display_name()), 1, 'my_display_name answers the caller''s row only'
);
select pg_temp.logout();
select is(pg_temp.name_of('00000000-0000-0000-0000-0000000297a1'), 'Peter Trost', 'another user''s name is untouched');

set local role anon;
select throws_ok($$ select public.set_display_name('x') $$, '42501', null, 'anon cannot set a name');
select throws_ok($$ select * from public.my_display_name() $$, '42501', null, 'anon cannot read a name');

select * from finish();
rollback;
