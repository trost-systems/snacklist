// The DSA report form's endpoint: /functions/v1/report (job 275). Not wrapped in withTelemetry:
// nothing about a report leaves the function but the confirmation mail.
import { serviceDb } from '../_shared/db.ts';
import { configFrom, createHandler } from './handler.ts';
import { sqlStore } from './store.ts';

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const { config, mailer } = configFrom(Deno.env);
// As in the waitlist function: the local stack's workers may drop waitUntil work, so there the
// answer waits for the mail.
const local = Deno.env.get('SUPABASE_URL') === 'http://kong:8000';

Deno.serve(createHandler({
  config,
  mailer,
  store: sqlStore(serviceDb),
  now: () => new Date(),
  random: (bytes) => crypto.getRandomValues(new Uint8Array(bytes)),
  defer: (work) => local ? work() : EdgeRuntime.waitUntil(Promise.resolve().then(work)),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
}));
