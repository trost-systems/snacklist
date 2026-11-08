// AC12 proof, run by hand (never in CI): the voice function's real handler, wrapped like
// voice/index.ts, fails twice on purpose and reports both to PostHog project 319492 as internal.
// Prints what was sent (key redacted) and PostHog's answer.
//
//   set -a; source ~/groceries-ops/env; set +a
//   deno run --config supabase/functions/deno.json --allow-env --allow-net \
//     analytics/proofs/edge_exception.ts
import { createHandler } from '../../supabase/functions/voice/handler.ts';
import { telemetryFor, withTelemetry } from '../../supabase/functions/_shared/telemetry.ts';

const env = {
  get: (key: string) => (key === 'ANALYTICS_INTERNAL' ? 'true' : Deno.env.get(key)),
};

const logged: typeof fetch = async (input, init) => {
  const body = JSON.parse(String(init?.body));
  body.api_key = '<redacted>';
  console.log('sent to', String(input), JSON.stringify(body, null, 2));
  const response = await fetch(input, init);
  const copy = response.clone();
  console.log('PostHog answered', response.status, await copy.text());
  return response;
};

const telemetry = telemetryFor('voice', env, logged);
if (!telemetry.enabled) throw new Error('set POSTHOG_PROJECT_API_KEY and POSTHOG_HOST first');

// 1. A failure the handler catches: the database refuses the add, echoing the item.
const caught = withTelemetry(
  'voice',
  createHandler({
    authenticate: () => Promise.resolve({ userId: 'u', householdId: 'h' }),
    // Open, so the failure is the add itself.
    requirePremium: () => Promise.resolve('open'),
    isMember: () => Promise.resolve(false),
    addItems: () =>
      Promise.reject(
        Object.assign(new Error('duplicate key (name)=(Hafermilch) for peter@example.com'), {
          code: '23505',
        }),
      ),
    // Only mode parse splits, so this add never calls it; it would split nothing off.
    splitItems: (_caller, items) =>
      Promise.resolve(
        items.map((item) => ({
          ...item,
          brand: null,
          properties: null,
          storeId: null,
          categoryId: null,
        })),
      ),
    report: (e) => telemetry.exception(e),
  }),
  telemetry,
);

// 2. An exception nothing catches.
const uncaught = withTelemetry('voice', (_req) => {
  throw new TypeError('Job 19 forced test exception (edge function voice)');
}, telemetry);

const request = () =>
  new Request('http://localhost/functions/v1/voice', {
    method: 'POST',
    headers: { authorization: 'Bearer fgp_not-a-real-token', 'content-type': 'application/json' },
    body: JSON.stringify({ text: 'Hafermilch und Klopapier' }),
  });

for (const [name, handler] of [['caught', caught], ['uncaught', uncaught]] as const) {
  const response = await handler(request());
  console.log(name, 'answered', response.status, await response.text());
}
