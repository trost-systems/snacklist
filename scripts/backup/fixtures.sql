-- Household data for the restore drill (scripts/backup/drill.sh): every public table gets rows,
-- written the way the app writes them (RPCs and triggers as the signed-in user), on top of the
-- users and identities GoTrue created. Peter and Lea share a household, Carl has his own.
\set ON_ERROR_STOP on
begin;

create function pg_temp.login(p_email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', (select id from auth.users where email = p_email), 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function pg_temp.category(p_household uuid, p_seed text) returns uuid language sql as $$
  select id from public.categories where household_id = p_household and seed_key = p_seed
$$;

create function pg_temp.store(p_household uuid, p_name text) returns uuid language sql as $$
  select id from public.stores where household_id = p_household and name = p_name
$$;

create temp table fx (key text primary key, id uuid, code text);
grant all on fx to authenticated;

-- Peter also signs in with Google: a second identity, as GoTrue links it.
insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select 'google-104857600000000000001', id,
  jsonb_build_object('sub', 'google-104857600000000000001', 'email', email, 'full_name', 'Peter Trost', 'email_verified', true),
  'google', now(), now(), now()
from auth.users where email = 'peter@backup.test';

select pg_temp.login('peter@backup.test');
insert into fx (key, id) select 'home', id from public.create_household(p_name => 'Familie Trost', p_stores => array['Supermarkt', 'Drogerie', 'Wochenmarkt']);
insert into fx select 'invite', i.id, i.code from public.create_invite((select id from fx where key = 'home')) i;
reset role;

select pg_temp.login('lea@backup.test');
select public.join_household((select code from fx where key = 'invite'));
reset role;

select pg_temp.login('peter@backup.test');
-- An open invite that nobody used.
select public.create_invite((select id from fx where key = 'home'));
select public.add_items((select id from fx where key = 'home'),
  array['2 l Milch', 'Vollkornbrot', '6 Äpfel', 'Kaffee', 'Spülmittel', 'Joghurt'],
  pg_temp.store((select id from fx where key = 'home'), 'Supermarkt'));
select public.create_category((select id from fx where key = 'home'), 'Für die Katze');
select public.set_store_layout(pg_temp.store((select id from fx where key = 'home'), 'Wochenmarkt'),
  (select array_agg(id order by sort_order desc) from public.categories
    where household_id = (select id from fx where key = 'home')),
  array[pg_temp.category((select id from fx where key = 'home'), 'drinks')]);
-- A correction the classifier learns from (category_memory) and a store change (item_store_memory).
update public.items set category_id = pg_temp.category(household_id, 'drugstore')
  where household_id = (select id from fx where key = 'home') and name = 'Spülmittel';
update public.items set store_id = pg_temp.store(household_id, 'Wochenmarkt')
  where household_id = (select id from fx where key = 'home') and name = 'Joghurt';
-- Job 15: brand and properties from the parser, a brand the household teaches (household_brands),
-- a drag in the walk order and a new store order.
select public.add_item((select id from fx where key = 'home'), 'Windeln Pampers Größe 4');
select public.add_item((select id from fx where key = 'home'), 'Windeln', p_brand => 'Lillydoo', p_properties => 'Größe 5');
select public.place_item(
  (select id from public.items where household_id = (select id from fx where key = 'home') and name = 'Joghurt'),
  (select id from public.items where household_id = (select id from fx where key = 'home') and name = 'Äpfel'),
  'before');
select public.reorder_stores((select id from fx where key = 'home'),
  array[pg_temp.store((select id from fx where key = 'home'), 'Wochenmarkt'),
        pg_temp.store((select id from fx where key = 'home'), 'Supermarkt'),
        pg_temp.store((select id from fx where key = 'home'), 'Drogerie')]);
select public.create_personal_access_token('Claude Desktop');
-- Job 21: feedback as the app sends it; household_id and is_internal come from the trigger.
insert into public.feedback (id, message, category, contact_ok, app_version, build, platform, os_version, locale, screen)
values (gen_random_uuid(), 'Der Haken reagiert erst beim zweiten Tippen.', 'bug', true, '0.1.0', '42', 'android',
  'Android 14 (SDK 34)', 'de', 'list');
reset role;

-- Lea ticks two items (bought_by and bought_at come from the trigger) and deletes one.
select pg_temp.login('lea@backup.test');
update public.items set status = 'bought'
  where household_id = (select id from fx where key = 'home') and name in ('Milch', 'Vollkornbrot');
delete from public.items where household_id = (select id from fx where key = 'home') and name = 'Kaffee';
select public.create_personal_access_token('Siri');
reset role;

select pg_temp.login('carl@backup.test');
insert into fx (key, id) select 'other', id from public.create_household('Nachbarn');
-- Job 22: a mistyped invite code is a failed attempt (invite_attempts, the rate limit's log).
select public.accept_invite('FALSCH22');
select public.add_items((select id from fx where key = 'other'), array['Bier', 'Chips']);
insert into public.feedback (id, message, app_version, build, platform, os_version, locale, screen)
values (gen_random_uuid(), 'Gibt es das auch auf Englisch?', '0.1.0', '42', 'web', 'Safari on iOS', 'en', 'more');
reset role;

-- Job 31: the app records each install's analytics answer; the alexa function's link map and
-- rate limit (service connection only).
select pg_temp.login('peter@backup.test');
select public.record_analytics_consent('6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b', true);
reset role;
select pg_temp.login('lea@backup.test');
select public.record_analytics_consent('7a2b3c4d-5e6f-4a70-8b8c-9d0e1f2a3b4c', false);
reset role;
insert into public.alexa_links (alexa_user_hash, session_id, user_id)
select encode(sha256('amzn1.ask.account.BACKUP'::bytea), 'hex'), gen_random_uuid(), id
from auth.users where email = 'peter@backup.test';
select public.alexa_take_adds((select id from auth.users where email = 'peter@backup.test'), 2);

-- Job 32b: Lea adds Karotten while Möhren is open and merges them (item_merges keeps both rows
-- for the undo).
select pg_temp.login('lea@backup.test');
select public.add_items((select id from fx where key = 'home'), array['500 g Möhren', '1 kg Karotten']);
select public.merge_items(gen_random_uuid(),
  (select id from public.items where household_id = (select id from fx where key = 'home') and name = 'Möhren'),
  (select id from public.items where household_id = (select id from fx where key = 'home') and name = 'Karotten'));
reset role;

-- Job 25 (job 43: through RevenueCat): Peter bought Lifetime (sandbox, under the old app's product id) for the household;
-- the purchases function writes through the service connection only. His claim came first; a
-- second claim waits for its webhook (purchase_claims). Carl's household has a RevenueCat promotional grant (a tester's); one webhook event id is
-- remembered; one purged purchase left its tombstone; one deleted household waits for RevenueCat.
select public.purchase_claim((select id from auth.users where email = 'peter@backup.test'),
  (select id from fx where key = 'home'), 'apple', '2000000999000001');
select public.purchase_claim((select id from auth.users where email = 'peter@backup.test'),
  (select id from fx where key = 'home'), 'apple', '2000000999000002');
select public.purchase_record('apple', '2000000999000001', '2000000999000001', repeat('b', 64),
  'com.hummlist.app.lifetime', 'premium', 'lifetime', 'Sandbox', now(), 9.99, 'EUR', 'DE', (select id from fx where key = 'home'));
select public.purchase_take_call((select id from auth.users where email = 'peter@backup.test'));
select public.promotional_premium_sync((select id from fx where key = 'other'), true, '2100-01-01T00:00:00Z');
-- Job 185: Lea bought a yearly plan for herself (App User ID = her user id).
select public.purchase_record_user('apple', '2000000999000185', '2000000999000185', repeat('d', 64),
  'com.snacklist.app.yearly', 'premium', 'yearly', 'Sandbox', now(), 24.99, 'EUR', 'DE',
  (select id from auth.users where email = 'lea@backup.test'), now(), now() + interval '365 days', true, false);
insert into public.revenuecat_events (id, type) values ('backup-drill-event', 'NON_RENEWING_PURCHASE');
insert into public.purchase_tombstones (transaction_hmac) values (repeat('c', 64));
insert into public.revenuecat_deletions (app_user_id, due_at) values (gen_random_uuid(), now() + interval '30 days');
-- Job 47: a membership that ended within the hour (the buyer's claim may still count it).
insert into public.household_departures (household_id, user_id, joined_at)
select (select id from fx where key = 'home'), id, now() - interval '1 day' from auth.users where email = 'carl@backup.test';

-- Job 50: a refusal noted while the household was locked.
insert into public.integration_blocks (household_id, integration, reported_at)
values ((select id from fx where key = 'home'), 'mcp', now() - interval '2 hours');

-- Job 73: an API key with its rate counters, a failed authentication and an idempotency record.
insert into public.personal_access_tokens (household_id, user_id, name, token_hash, token_hint, kind, scopes)
select (select id from fx where key = 'home'), id, 'Home Assistant', repeat('d', 64), 'abcd', 'api', '{read,write}'
from auth.users where email = 'peter@backup.test';
insert into public.api_token_buckets (token_id, tokens, refilled_at)
select id, 12.5, now() from public.personal_access_tokens where token_hash = repeat('d', 64);
insert into public.api_household_days (household_id, day, requests)
values ((select id from fx where key = 'home'), current_date, 8);
insert into public.api_auth_failures (ip_hash, window_start, failures) values (repeat('e', 64), now(), 3);
insert into public.api_idempotency (token_id, key, request_hash, status, body)
select id, 'backup-drill', repeat('f', 64), 201, '{"data":{"added":[]}}'
from public.personal_access_tokens where token_hash = repeat('d', 64);

-- Job 80: where a connected app was approved.
insert into public.oauth_app_devices (user_id, client_id, device)
select id, '00000000-0000-4000-8000-0000000b0080', 'Chrome · macOS' from auth.users where email = 'peter@backup.test';

-- Job 82: a confirmed waitlist sign-up, a proof record and a rate counter (test addresses only).
insert into public.waitlist (email, email_hmac, platform, locale, launch_news, consent_text_version,
  confirmed_at, last_mail_at)
values ('test+backup@snacklist.app', repeat('a', 64), 'ios', 'de', true, 'waitlist-de-v1', now(), now());
insert into public.waitlist_consent_proof (email_hmac, consent_text_version, locale, launch_news,
  created_at, confirmed_at, last_mail_at, ended_at, end_reason)
values (repeat('b', 64), 'waitlist-en-v1', 'en', false, now() - interval '2 days',
  now() - interval '2 days', now() - interval '1 day', now(), 'unsubscribed');
insert into public.waitlist_rate (key_hash, window_start, hits) values (repeat('c', 64), date_trunc('hour', now()), 2);

-- Job 169b W2: Peter's group link, opened once on the signed-out join page (a preview counter).
select pg_temp.login('peter@backup.test');
insert into fx select 'group', i.id, i.code
from public.create_invite((select id from fx where key = 'home'), 'group') i;
reset role;
select code as group_code from fx where key = 'group' \gset
select set_config('role', 'anon', true);
select set_config('request.headers', '{"x-real-ip": "192.0.2.10"}', true);
select public.preview_invite_public(:'group_code');
reset role;


-- Job 169b W3: Lea's second list with an item, her "Ich bringe" claim, and Carl asking to join
-- through the group link once Peter switched join approval on.
reset role;
select pg_temp.login('lea@backup.test');
select public.create_list((select id from fx where key = 'home'), 'Baumarkt', gen_random_uuid());
select public.add_list_item((select id from fx where key = 'home'),
  (select id from public.lists where name = 'Baumarkt'), 'Schrauben');
select public.claim_item((select id from public.items where name = 'Schrauben'), '1 Packung');
reset role;
select pg_temp.login('peter@backup.test');
select public.set_join_approval((select id from fx where key = 'home'), true);
reset role;
select pg_temp.login('carl@backup.test');
select public.accept_invite((select code from fx where key = 'group'), p_mode => 'add');
reset role;
-- Job 169b W2: Carl, whose membership ended above, was removed after he asked: invites made
-- until now don't take him back.
insert into public.household_removals (household_id, user_id)
select (select id from fx where key = 'home'), id from auth.users where email = 'carl@backup.test';

-- Job 199: Lea logged a trip to the Supermarkt.
create temp table peter as select id from auth.users where email = 'peter@backup.test';
grant select on peter to authenticated;
select pg_temp.login('lea@backup.test');
select public.save_trip((select id from fx where key = 'home'), gen_random_uuid(),
  (select id from public.stores where name = 'Supermarkt'), current_date,
  '[{"name": "Milch", "quantity": "2"}, {"name": "Brot"}]');
-- Job 234: and shopped there in trip mode: Milch was on the list, Peter added Eier on the way.
select public.save_trip_session((select id from fx where key = 'home'), jsonb_build_object(
  'id', gen_random_uuid(), 'started_at', now() - interval '30 minutes', 'ended_at', now(),
  'active_seconds', 1500, 'end_reason', 'user', 'source', 'ask', 'currency', 'EUR',
  'shopped_on', current_date::text,
  'pauses', jsonb_build_array(jsonb_build_object('from', now() - interval '20 minutes',
    'to', now() - interval '15 minutes', 'auto', false)),
  'lines', jsonb_build_array(
    jsonb_build_object('key', 'milch', 'name', 'Milch', 'planned', true, 'bought', true, 'quantity', '2',
      'store_id', (select id from public.stores where name = 'Supermarkt'), 'store_name', 'Supermarkt',
      'planned_cents', 258, 'paid_cents', 278),
    jsonb_build_object('key', 'eier', 'name', 'Eier', 'planned', false, 'bought', true, 'by_other', true,
      'added_by', (select id from peter)))), true);
reset role;

-- Job 94: an MCP client known by its Client ID Metadata Document URL.
insert into public.oauth_cimd_clients (client_id, auth_client_id, client_name, redirect_uris, fresh_until)
values ('https://client.backup.test/mcp.json', '00000000-0000-4000-8000-0000000b0094', 'Backup Client',
  array['http://127.0.0.1:8976/callback'], now() + interval '1 hour');
insert into public.oauth_cimd_rate (key, window_start, hits)
values ('fetch:client.backup.test', date_trunc('hour', now()), 1);

commit;
