-- Job 420: the app reads app_switches.mcp_lists_stores through public.mcp_lists_stores(), the same
-- switch the mcp function reads, so the OAuth consent page names the list and store tools only
-- while they are served.
begin;
select plan(5);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000420a01', 'alma@example.com');

select is((select enabled from public.app_switches where key = 'mcp_lists_stores'), false,
  'the switch is seeded off');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000420a01","role":"authenticated"}', true);
select is(public.mcp_lists_stores(), false, 'a member reads it as off');

reset role;
update public.app_switches set enabled = true where key = 'mcp_lists_stores';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000420a01","role":"authenticated"}', true);
select is(public.mcp_lists_stores(), true, 'a member reads it as on');

reset role;
set local role anon;
select throws_ok($$ select public.mcp_lists_stores() $$, '42501', null, 'anonymous callers cannot read it');
reset role;
select is(public.mcp_lists_stores(), true, 'the service side reads the same switch');

select * from finish();
rollback;
