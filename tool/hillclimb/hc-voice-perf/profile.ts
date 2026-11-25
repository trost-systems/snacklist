// Where a warm request's time goes: the alexa and voice handlers wired as their index.ts wires
// them (withTelemetry around createHandler(productionDeps(...))), in this process against the
// local stack's database and Auth, every dependency call timed. The Alexa trust is the stack's
// test CA (supabase/.temp/alexa-test), handed to the real verifyRequest. Synthetic account
// (stack.ts), which said yes to analytics.
//
// Telemetry is on, sent to a stand-in for PostHog that answers after --posthog-ms (default 25,
// an assumption for eu.i.posthog.com from eu-central-1; nothing leaves this machine). With
// --edge-runtime, globalThis.EdgeRuntime.waitUntil is simulated as Supabase's runtime has it: the
// work handed to it runs on, untimed, after the answer. With --db-rtt-ms, the handlers reach the
// database through latency_proxy.ts, which adds that round trip to every wait for an answer.
//
//   deno run -A --config supabase/functions/deno.json tool/hillclimb/hc-voice-perf/profile.ts \
//     [--runs 20] [--posthog-ms 25] [--edge-runtime] [--db-rtt-ms 0]
import { productionDeps as alexaDeps } from '../../../supabase/functions/alexa/deps.ts';
import { createHandler as alexaHandler } from '../../../supabase/functions/alexa/handler.ts';
import { parseCertificates, verifyRequest } from '../../../supabase/functions/alexa/verify.ts';
import { productionDeps as voiceDeps } from '../../../supabase/functions/voice/deps.ts';
import { createHandler as voiceHandler } from '../../../supabase/functions/voice/handler.ts';
import { telemetryFor, withTelemetry } from '../../../supabase/functions/_shared/telemetry.ts';
import { latencyProxy } from './latency_proxy.ts';
import { seed, stack, teardown } from './stack.ts';

const repo = new URL('../../../', import.meta.url).pathname;
const arg = (name: string, fallback: number) => {
  const i = Deno.args.indexOf(`--${name}`);
  return i >= 0 ? Number(Deno.args[i + 1]) : fallback;
};
const runs = arg('runs', 20);
const posthogMs = arg('posthog-ms', 25);
const background: Promise<unknown>[] = [];
if (Deno.args.includes('--edge-runtime')) {
  Object.assign(globalThis, {
    EdgeRuntime: { waitUntil: (p: Promise<unknown>) => background.push(p) },
  });
}
let sent = 0;
const posthog = (async () => {
  await new Promise((r) => setTimeout(r, posthogMs));
  sent++;
  return new Response('{}');
}) as typeof fetch;
const env = (fn: string) => ({
  get: (k: string) =>
    ({ POSTHOG_PROJECT_API_KEY: `phc_voicebench${fn}`, POSTHOG_HOST: 'https://eu.i.posthog.com' })[
      k
    ],
});

const s = await stack();
const dbRtt = arg('db-rtt-ms', 0);
const db = new URL(s.dbUrl);
const proxy = dbRtt > 0
  ? latencyProxy({ hostname: db.hostname, port: Number(db.port) }, dbRtt)
  : null;
if (proxy) db.port = String(proxy.port);
Deno.env.set('SUPABASE_DB_URL', db.toString());
Deno.env.set('SUPABASE_URL', s.api);
const account = await seed(s);

const times: Record<string, number[]> = {};
function timed<T extends object>(prefix: string, deps: T): T {
  const out = { ...deps };
  for (const [k, v] of Object.entries(deps)) {
    if (typeof v !== 'function') continue;
    Reflect.set(out, k, async (...args: unknown[]) => {
      const t0 = performance.now();
      try {
        return await (v as (...a: unknown[]) => unknown)(...args);
      } finally {
        (times[`${prefix}.${k}`] ??= []).push(performance.now() - t0);
      }
    });
  }
  return out;
}

const dir = `${repo}supabase/.temp/alexa-test`;
const anchors = parseCertificates(await Deno.readTextFile(`${dir}/root.pem`));
const chain = await Deno.readTextFile(`${dir}/chain.pem`);
const skillId = 'amzn1.ask.skill.00000000-0000-4000-8000-00000000e2e0';
const trust = { anchors, fetchChain: () => Promise.resolve(chain), skillIds: [skillId] };
const alexaTelemetry = telemetryFor('alexa', env('alexa'), posthog);
const voiceTelemetry = telemetryFor('voice', env('voice'), posthog);
const alexa = withTelemetry(
  'alexa',
  alexaHandler(timed('alexa', {
    ...alexaDeps(
      alexaTelemetry,
      (headers, body) => verifyRequest(headers, body, { ...trust, now: () => new Date() }),
    ),
    log: () => {},
  })),
  alexaTelemetry,
);
const voice = withTelemetry(
  'voice',
  voiceHandler(timed('voice', { ...voiceDeps(voiceTelemetry), log: () => {} })),
  voiceTelemetry,
);

const der = Uint8Array.from(
  atob(
    (await Deno.readTextFile(`${dir}/leaf.key`)).replace(/-----[^-]+-----/g, '').replace(
      /\s+/g,
      '',
    ),
  ),
  (c) => c.charCodeAt(0),
);
const key = await crypto.subtle.importKey(
  'pkcs8',
  der,
  { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
  false,
  ['sign'],
);

async function alexaCall(request: Record<string, unknown>) {
  const user = { userId: 'amzn1.ask.account.VOICEBENCH', accessToken: account.alexaToken };
  const body = JSON.stringify({
    version: '1.0',
    context: { System: { application: { applicationId: skillId }, user } },
    request: { timestamp: new Date().toISOString(), locale: 'de-DE', ...request },
  });
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(body));
  const res = await alexa(
    new Request('http://local/alexa', {
      method: 'POST',
      headers: {
        signaturecertchainurl: 'https://s3.amazonaws.com/echo.api/echo-api-cert-test.pem',
        'signature-256': btoa(String.fromCharCode(...new Uint8Array(sig))),
      },
      body,
    }),
  );
  return await res.text();
}

const voiceCall = async (payload: unknown) =>
  await (await voice(
    new Request('http://local/voice', {
      method: 'POST',
      headers: { authorization: `Bearer ${account.siriToken}`, 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    }),
  )).text();

const { default: postgres } = await import('postgres');
const sql = postgres(s.dbUrl, { max: 1, prepare: false, onnotice: () => {} });
const baseline = (await sql<{ id: string }[]>`
  select id from public.items where household_id = ${account.householdId}`).map((r) => r.id);
const undo = async () => {
  await sql`delete from public.items where household_id = ${account.householdId}
            and not (id = any(${baseline}::uuid[]))`;
  await sql`delete from public.alexa_rate where user_id = ${account.userId}`;
};

const add = {
  type: 'IntentRequest',
  intent: {
    name: 'AddItemIntent',
    confirmationStatus: 'NONE',
    slots: { items: { name: 'items', value: 'Milch, Eier und Brot' } },
  },
};
/** Each path's request, and what undoes it (untimed). */
const paths: Record<string, [() => Promise<unknown>, () => Promise<void>]> = {
  'alexa_launch': [() => alexaCall({ type: 'LaunchRequest' }), () => Promise.resolve()],
  'alexa_add': [() => alexaCall(add), undo],
  'siri_read': [() => voiceCall({ mode: 'read', lang: 'de' }), () => Promise.resolve()],
  'siri_add': [() => voiceCall({ text: 'Milch, Eier und Brot', lang: 'de' }), undo],
};

const median = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] ?? NaN;
try {
  for (const [name, [run, after]] of Object.entries(paths)) {
    const once = async () => {
      const t0 = performance.now();
      await run();
      const ms = performance.now() - t0;
      await Promise.all(background.splice(0));
      await after();
      return ms;
    };
    for (let w = 0; w < 3; w++) await once();
    for (const k of Object.keys(times)) delete times[k];
    const total: number[] = [];
    sent = 0;
    for (let r = 0; r < runs; r++) total.push(await once());
    console.log(
      `\n${name}: median ${median(total).toFixed(1)} ms ` +
        `PostHog batches ${(sent / runs).toFixed(1)} per request`,
    );
    for (const [k, v] of Object.entries(times)) {
      console.log(`  ${k.padEnd(22)} ${median(v).toFixed(2)} ms x${(v.length / runs).toFixed(0)}`);
    }
  }
} finally {
  await sql.end();
  await teardown(s, account);
  Deno.exit(0);
}
