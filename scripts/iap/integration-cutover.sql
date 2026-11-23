-- Jobs 50, 419: which users the integration lock would refuse when app_switches.integration_lock
-- goes on (docs/NEEDS_LEAD.md "Job 50"). Read-only: one SELECT, nothing written. It uses the
-- server's own rule since job 419 (user_has_premium: the user's own plan or grant; a household's
-- plan or grant opens nothing), so a promotional grant (testers) counts only when it is a
-- per-user grant (promotional_premium_sync_user), as the endpoints count it.
--
-- Run it in the Supabase SQL editor (or psql as postgres) of the project you want to know about:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f scripts/iap/integration-cutover.sql
-- One row per user who would be refused AND uses MCP or the API now, then a total line. Siri and
-- Alexa stay free and are not counted. No names, emails or list contents: ids, counts and dates.
begin read only;

with account as (
  select u.id,
         (select count(*) from public.personal_access_tokens t
          where t.user_id = u.id and t.revoked_at is null and t.kind = 'pat') as mcp_tokens,
         (select count(*) from public.personal_access_tokens t
          where t.user_id = u.id and t.revoked_at is null and t.kind = 'api') as api_keys,
         (select count(*) from auth.sessions s
          where s.user_id = u.id and s.oauth_client_id is not null
            and (s.not_after is null or s.not_after > now())) as oauth_connections,
         (select max(t.last_used_at) from public.personal_access_tokens t
          where t.user_id = u.id and t.revoked_at is null and t.kind in ('pat', 'api')) as token_last_used,
         public.user_has_premium(u.id) as premium
  from auth.users u
)
select id as user_id, mcp_tokens, api_keys, oauth_connections, token_last_used
from account
where not premium and mcp_tokens + api_keys + oauth_connections > 0
order by token_last_used desc nulls last;

with account as (
  select u.id, public.user_has_premium(u.id) as premium,
         exists (select from public.personal_access_tokens t
                 where t.user_id = u.id and t.revoked_at is null and t.kind in ('pat', 'api'))
         or exists (select from auth.sessions s
                    where s.user_id = u.id and s.oauth_client_id is not null
                      and (s.not_after is null or s.not_after > now())) as integrated
  from auth.users u
)
select count(*) as users,
       count(*) filter (where premium) as with_premium,
       count(*) filter (where not premium) as would_be_locked,
       count(*) filter (where not premium and integrated) as locked_with_integrations
from account;

rollback;
