// The API's limits (docs/API.md "Limits"), the one place they are set: the database functions
// (public.api_begin) take them as arguments.

/** Per API key: a token bucket of this size... */
export const BURST = 20;
/** ...refilled at this many requests a minute. */
export const PER_MINUTE = 60;
/** Per household and UTC day, all its keys together. */
export const PER_DAY = 1000;
/** Failed authentications per address (salted SHA-256 of the IP) in one window... */
export const AUTH_FAILURES = 20;
/** ...of this many seconds; then 429 auth_throttled without looking at the key. */
export const AUTH_FAILURE_WINDOW_SECONDS = 600;
/** Items per POST /v1/items. */
export const BATCH = 50;
/** Request body bytes. */
export const BODY_BYTES = 64 * 1024;
export const PAGE_DEFAULT = 50;
export const PAGE_MAX = 100;
/** How long a POST's first successful response is replayed for its Idempotency-Key. */
export const IDEMPOTENCY_HOURS = 24;
/** Ticked things per GET /v1/items/recent (default: list.ts RECENT_SHOWN, the app's number). */
export const RECENT_MAX = 50;
/** Usuals per GET /v1/suggestions. */
export const SUGGEST_DEFAULT = 10;
export const SUGGEST_MAX = 50;
