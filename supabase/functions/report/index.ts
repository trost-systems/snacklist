// The DSA report endpoints: /functions/v1/report for the site's form (job 275), /report/app for
// the app (job 281). Not wrapped in withTelemetry: nothing about a report leaves the function but
// the confirmation mail.
import { authenticateSession } from '../_shared/auth.ts';
import { serviceDb } from '../_shared/db.ts';
import { configFrom, createHandler } from './handler.ts';
import { sqlAppStore, sqlStore } from './store.ts';

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const { config, mailer } = configFrom(Deno.env);
// As in the waitlist function: the local stack's workers may drop waitUntil work, so there the
// answer waits for the mail.
const local = Deno.env.get('SUPABASE_URL') === 'http://kong:8000';

Deno.serve(createHandler({
  config,
  mailer,
  store: sqlStore(serviceDb),
  app: { authenticate: (req) => authenticateSession(req), store: sqlAppStore(serviceDb) },
  now: () => new Date(),
  random: (bytes) => crypto.getRandomValues(new Uint8Array(bytes)),
  defer: (work) => local ? work() : EdgeRuntime.waitUntil(Promise.resolve().then(work)),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
}));
