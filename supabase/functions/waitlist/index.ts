// The hummlist.com waitlist: /functions/v1/waitlist (docs/WAITLIST.md). Not wrapped in
// withTelemetry: nothing about a request leaves the function but the mail it sends.
import { serviceDb } from '../_shared/db.ts';
import { configFrom, createHandler } from './handler.ts';
import { sqlStore } from './store.ts';

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const { config, mailer } = configFrom(Deno.env);
// The local stack's oneshot workers (DECISIONS 3.11) end with the response and drop waitUntil
// work, so there the answer waits for it; equal timing (AC6) matters only when hosted.
const local = Deno.env.get('SUPABASE_URL') === 'http://kong:8000';

Deno.serve(createHandler({
  config,
  mailer,
  store: sqlStore(serviceDb),
  now: () => new Date(),
  random: (bytes) => crypto.getRandomValues(new Uint8Array(bytes)),
  defer: (work) => local ? work() : EdgeRuntime.waitUntil(Promise.resolve().then(work)),
}));
