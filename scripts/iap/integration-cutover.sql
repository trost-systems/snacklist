-- Job 50: which households the integration lock would lock when app_switches.integration_lock
-- goes on (docs/NEEDS_LEAD.md "Job 50"). Read-only: one SELECT, nothing written. It uses the
-- server's own rule (household_has_premium, job 49), so a promotional grant (testers) or an active plan counts
-- exactly as the endpoints count it.
--
-- Run it in the Supabase SQL editor (or psql as postgres) of the project you want to know about:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f scripts/iap/integration-cutover.sql
-- One row per household that would be locked AND uses an integration now, then a total line.
-- No names, emails or list contents: ids, counts and dates only.
begin read only;

with household as (
  select h.id,
         (select count(*) from public.household_members m where m.household_id = h.id) as members,
         (select count(*) from public.personal_access_tokens t
          where t.household_id = h.id and t.revoked_at is null and t.kind = 'pat') as shortcut_tokens,
         (select count(*) from public.personal_access_tokens t
          where t.household_id = h.id and t.revoked_at is null and t.kind = 'siri') as siri_iphones,
         (select count(*) from public.personal_access_tokens t
          where t.household_id = h.id and t.revoked_at is null and t.kind = 'api') as api_keys,
         (select count(*) from public.alexa_links l
          join public.household_members m on m.user_id = l.user_id and m.is_default
          where m.household_id = h.id) as alexa_links,
         (select count(*) from auth.sessions s
          join public.household_members m on m.user_id = s.user_id and m.is_default
          where m.household_id = h.id and s.oauth_client_id is not null
            and (s.not_after is null or s.not_after > now())) as oauth_connections,
         (select max(t.last_used_at) from public.personal_access_tokens t
          where t.household_id = h.id and t.revoked_at is null) as token_last_used,
         public.household_has_premium(h.id) as premium
  from public.households h
)
select id as household_id, members, shortcut_tokens, siri_iphones, api_keys, alexa_links,
       oauth_connections, token_last_used
from household
where not premium and shortcut_tokens + siri_iphones + api_keys + alexa_links + oauth_connections > 0
order by token_last_used desc nulls last;

with household as (
  select h.id, public.household_has_premium(h.id) as premium,
         exists (select from public.personal_access_tokens t
                 where t.household_id = h.id and t.revoked_at is null)
         or exists (select from public.alexa_links l join public.household_members m on m.user_id = l.user_id and m.is_default
                    where m.household_id = h.id)
         or exists (select from auth.sessions s join public.household_members m on m.user_id = s.user_id and m.is_default
                    where m.household_id = h.id and s.oauth_client_id is not null
                      and (s.not_after is null or s.not_after > now())) as integrated
  from public.households h
)
select count(*) as households,
       count(*) filter (where premium) as with_premium,
       count(*) filter (where not premium) as would_be_locked,
       count(*) filter (where not premium and integrated) as locked_with_integrations
from household;

rollback;
