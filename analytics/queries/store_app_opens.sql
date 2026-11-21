-- Job 335 (OS3): "Store app opens", the store_app_opened events of the last 30 days by chain,
-- country, what opened (outcome: app or store_page) and the platform, the context property every
-- event carries (ios, android, web; contextKeys in app/lib/analytics/events.dart). Not a gate
-- query: while the flag open-store-app is on for internal testers only, every event is internal,
-- so the internal filter would leave nothing. The internal column says which ones were.
-- A chain whose iOS opens stay store_page while its app is installed has a scheme or link that
-- does not open it: supabase/retailers/coverage.md says how each one opens and where that came from.
SELECT
  toString(properties.chain) AS chain,
  toString(properties.country) AS country,
  toString(properties.outcome) AS outcome,
  toString(properties.platform) AS platform,
  ifNull(toString(properties.is_internal), '') = 'true' AS internal,
  count() AS opens
FROM events
WHERE event = 'store_app_opened' AND timestamp > now() - INTERVAL 30 DAY
GROUP BY chain, country, outcome, platform, internal
ORDER BY opens DESC
