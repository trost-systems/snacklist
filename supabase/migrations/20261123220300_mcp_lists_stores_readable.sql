-- Job 420: the OAuth consent page names the list and store tools only while they are served, so the
-- app reads the same switch the mcp function reads (app_switches.mcp_lists_stores).
create function public.mcp_lists_stores() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.app_switch('mcp_lists_stores')
$$;

revoke execute on function public.mcp_lists_stores() from public, anon;
grant execute on function public.mcp_lists_stores() to authenticated;
