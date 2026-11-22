-- Job 345: the MCP tools that create and rename lists and stores and set a store's walk order
-- (create_list, rename_list, add_store, rename_store, set_store_layout) are served only while
-- app_switches.mcp_lists_stores is on. Privacy section 7 says a connected assistant reads and
-- changes the entries of the list; the switch stays off until Legal has the new text (NEEDS_LEAD
-- "Job 345: Legal text for A8 MCP"). The API's list and store writes need no switch: its paragraph
-- names lists and stores.
insert into public.app_switches (key, enabled) values ('mcp_lists_stores', false);

comment on table public.app_switches is
  'Job 47: server-side switches, set by the service role only (NEEDS_LEAD "Job 47", "Job 49", "Job 50"). household_archive: archiving a household on the last leave is allowed. premium_offer (job 49): the app may offer Snacklist Premium for sale. integration_lock (job 50): MCP and the API (job 73) need Snacklist Premium; Siri (job 184) and Alexa (job 72) stay free. public_api (job 75): the public API is served and API keys can be made. feedback_digest (job 225): the daily feedback mail runs; set only through feedback_digest_set. mcp_lists_stores (job 345): the MCP tools create_list, rename_list, add_store, rename_store and set_store_layout are served.';
