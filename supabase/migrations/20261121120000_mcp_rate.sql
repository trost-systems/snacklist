-- Job 336 (J1, job 331 F5): MCP requests have limits like the API's.
--
-- Before this, 60 concurrent MCP tool calls with one token were all served. Now each signed-in
-- user has a token bucket (burst, refilled per minute) and a count per UTC day over all their
-- MCP requests, whichever household a call names. The mcp function passes the numbers
-- (mcp/limits.ts) and answers 429 with Retry-After when mcp_take_call says no.
--
-- One row per user, overwritten on every request. It goes with the account (cascade) and with
-- the daily purge once nobody used it for a day: a bucket left alone that long is full, and its
-- day has passed.

create table public.mcp_rate (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tokens double precision not null check (tokens >= 0),
  refilled_at timestamptz not null,
  day date not null,
  requests integer not null check (requests >= 0)
);

comment on table public.mcp_rate is
  'Job 336: each user''s MCP token bucket (fill level at refilled_at) and requests on the UTC day `day`. Service connection only. Rows untouched for a day go daily (purge-mcp-rate).';

alter table public.mcp_rate enable row level security;
revoke all on public.mcp_rate from public, anon, authenticated;

-- Counts one request for the user. Null when it may go ahead, else the seconds
-- until it may: the bucket's next token, or the next UTC day when the day's count is used up.
-- The user's share lock comes first and does not wait, like alexa_take_adds: an account that is
-- being deleted ends the call at once (lock_not_available, the function's 503).
create function public.mcp_take_call(
  p_user uuid,
  p_burst integer,
  p_per_minute integer,
  p_per_day integer
)
returns integer
language plpgsql security definer set search_path = '' set lock_timeout = '2s' as $$
declare
  v_now timestamptz := now();
  v_rate double precision := p_per_minute / 60.0;
  v_day date := (v_now at time zone 'utc')::date;
  v_day_reset integer := ceil(extract(epoch from ((v_day + 1)::timestamp at time zone 'utc') - v_now))::integer;
  v_row record;
  v_tokens double precision;
  v_requests integer;
begin
  perform from auth.users u where u.id = p_user for key share nowait;
  if not found then
    raise exception 'no such user' using errcode = 'P0002';
  end if;

  insert into public.mcp_rate (user_id, tokens, refilled_at, day, requests)
  values (p_user, p_burst, v_now, v_day, 0)
  on conflict (user_id) do nothing;
  select r.tokens, r.refilled_at, r.day, r.requests into v_row
  from public.mcp_rate r where r.user_id = p_user for update;

  v_tokens := least(p_burst::double precision,
                    v_row.tokens + greatest(extract(epoch from v_now - v_row.refilled_at), 0) * v_rate);
  v_requests := case when v_row.day = v_day then v_row.requests else 0 end;

  if v_tokens >= 1 and v_requests < p_per_day then
    update public.mcp_rate r
    set tokens = v_tokens - 1, refilled_at = v_now, day = v_day, requests = v_requests + 1
    where r.user_id = p_user;
    return null;
  end if;

  update public.mcp_rate r set tokens = v_tokens, refilled_at = v_now, day = v_day, requests = v_requests
  where r.user_id = p_user;
  return greatest(
    case when v_tokens < 1 then ceil((1 - v_tokens) / v_rate)::integer else 0 end,
    case when v_requests >= p_per_day then v_day_reset else 0 end
  );
end $$;

revoke execute on function public.mcp_take_call(uuid, integer, integer, integer)
  from public, anon, authenticated;

create function public.purge_mcp_rate() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from public.mcp_rate r where r.refilled_at < now() - interval '1 day';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke execute on function public.purge_mcp_rate() from public, anon, authenticated;

-- The same name replaces the job, so applying this again keeps one.
select cron.schedule('purge-mcp-rate', '43 3 * * *', 'select public.purge_mcp_rate()');
