// The voice latency benchmark (docs/hillclimb/hc-voice-perf.md): Alexa and Siri against this
// checkout's local stack, over HTTP through Kong and the edge runtime, as Alexa and the app call
// them. Synthetic data only (stack.ts seeds a fresh account and removes it at the end).
//
//   deno run -A --config tool/hillclimb/hc-voice-perf/deno.json tool/hillclimb/hc-voice-perf/bench.ts \
//     [--cold 5] [--warm 30] [--warmup 5] [--only alexa_add,siri_add] [--label baseline] [--out f.json]
//
// Paths:
//   alexa_launch  LaunchRequest ("Alexa, öffne Snacklist"), signed with the test CA.
//   alexa_add     AddItemIntent "Milch, Eier und Brot", signed.
//   siri_read     POST /voice {"mode": "read", "lang": "de"} with the Siri credential.
//   siri_add      POST /voice {"text": "Milch, Eier und Brot", "lang": "de"} with the Siri credential.
// Each add is undone after it is timed (the three items deleted, Alexa's rate window cleared), so
// every add times the same work: three new items on a list of 24.
//
// Metrics:
//   cold  the first request a fresh worker of the function answers: the edge runtime container is
//         restarted, the main worker is woken through the `health` function (another function, so
//         this function's worker is still unborn), then one request is timed. It includes the
//         worker boot, the module graph, the first database connections and the first auth
//         discovery and key fetch. Median (min-max) of --cold samples per path.
//   warm  the same requests against the worker that is already up, after --warmup requests per
//         path: p50 and p95 of --warm requests per path, the paths taken in turns (round-robin) so
//         host noise spreads over all of them.
// Both are wall time at the client, Kong included. The function's own `ms=` from its request line
// (the handler's time, without worker boot, module graph and routing) is collected too, from
// `docker logs`: its median for the cold requests, its p50 for the warm ones.
import postgres from 'postgres';
import { type Account, seed, type Stack, stack, teardown } from './stack.ts';

const repo = new URL('../../../', import.meta.url).pathname;

function flag(name: string, fallback: string): string {
  const i = Deno.args.indexOf(`--${name}`);
  return i >= 0 ? Deno.args[i + 1] ?? fallback : fallback;
}

const coldRuns = Number(flag('cold', '5'));
const warmRuns = Number(flag('warm', '30'));
const warmup = Number(flag('warmup', '5'));
const label = flag('label', 'run');
const out = flag('out', '');
const allPaths = ['alexa_launch', 'alexa_add', 'siri_read', 'siri_add'] as const;
type PathName = typeof allPaths[number];
const only = flag('only', allPaths.join(',')).split(',');
const paths = allPaths.filter((p) => only.includes(p));

const skillId = 'amzn1.ask.skill.00000000-0000-4000-8000-00000000e2e0';
const certUrl = 'https://s3.amazonaws.com/echo.api/echo-api-cert-test.pem';
const addText = 'Milch, Eier und Brot';

async function signer(): Promise<(body: string) => Promise<string>> {
  const pem = await Deno.readTextFile(`${repo}supabase/.temp/alexa-test/leaf.key`);
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return async (body) => {
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(body));
    return btoa(String.fromCharCode(...new Uint8Array(sig)));
  };
}

interface Sample {
  ms: number;
  ok: boolean;
  detail: string;
}

function alexaEnvelope(token: string, request: Record<string, unknown>) {
  const user = { userId: 'amzn1.ask.account.VOICEBENCH', accessToken: token };
  return {
    version: '1.0',
    session: {
      new: true,
      sessionId: `amzn1.echo-api.session.${crypto.randomUUID()}`,
      application: { applicationId: skillId },
      user,
    },
    context: { System: { application: { applicationId: skillId }, user } },
    request: {
      requestId: `amzn1.echo-api.request.${crypto.randomUUID()}`,
      timestamp: new Date().toISOString(),
      locale: 'de-DE',
      ...request,
    },
  };
}

function runner(s: Stack, a: Account, sign: (body: string) => Promise<string>) {
  const fn = `${s.api}/functions/v1`;
  const sql = postgres(s.dbUrl, { max: 1, prepare: false, onnotice: () => {} });
  let baseline: string[] = [];

  async function snapshot() {
    baseline = (await sql<{ id: string }[]>`
      select id from public.items where household_id = ${a.householdId}`).map((r) => r.id);
  }

  /** Undoes an add: the new items go, and Alexa's rate window starts over. */
  async function undo() {
    await sql`delete from public.items where household_id = ${a.householdId}
              and not (id = any(${baseline}::uuid[]))`;
    await sql`delete from public.alexa_rate where user_id = ${a.userId}`;
  }

  async function alexa(request: Record<string, unknown>, expect: RegExp): Promise<Sample> {
    const body = JSON.stringify(alexaEnvelope(a.alexaToken, request));
    const headers = {
      'content-type': 'application/json',
      signaturecertchainurl: certUrl,
      'signature-256': await sign(body),
    };
    const t0 = performance.now();
    const res = await fetch(`${fn}/alexa`, { method: 'POST', headers, body });
    const text = await res.text();
    const ms = performance.now() - t0;
    return { ms, ok: res.ok && expect.test(text), detail: `${res.status} ${text.slice(0, 160)}` };
  }

  async function voice(payload: Record<string, unknown>, expect: RegExp): Promise<Sample> {
    const body = JSON.stringify(payload);
    const headers = {
      'content-type': 'application/json',
      authorization: `Bearer ${a.siriToken}`,
      'x-snacklist-client': 'voice-bench',
    };
    const t0 = performance.now();
    const res = await fetch(`${fn}/voice`, { method: 'POST', headers, body });
    const text = await res.text();
    const ms = performance.now() - t0;
    return { ms, ok: res.ok && expect.test(text), detail: `${res.status} ${text.slice(0, 160)}` };
  }

  const run: Record<PathName, () => Promise<Sample>> = {
    'alexa_launch': () => alexa({ type: 'LaunchRequest' }, /Dialog\.ElicitSlot/),
    'alexa_add': async () => {
      const r = await alexa({
        type: 'IntentRequest',
        intent: {
          name: 'AddItemIntent',
          confirmationStatus: 'NONE',
          slots: { items: { name: 'items', value: addText } },
        },
      }, /Milch.*Eier.*Brot/);
      await undo();
      return r;
    },
    'siri_read': () => voice({ mode: 'read', lang: 'de' }, /"outcome":"read".*"total":24/),
    'siri_add': async () => {
      const r = await voice({ text: addText, lang: 'de' }, /"outcome":"added"/);
      await undo();
      return r;
    },
  };
  return { run, snapshot, close: () => sql.end() };
}

async function sh(cmd: string, args: string[]): Promise<string> {
  const o = await new Deno.Command(cmd, { args, stdout: 'piped', stderr: 'piped' }).output();
  if (!o.success) {
    throw new Error(`${cmd} ${args.join(' ')}: ${new TextDecoder().decode(o.stderr)}`);
  }
  return new TextDecoder().decode(o.stdout) + new TextDecoder().decode(o.stderr);
}

/** A fresh edge runtime whose main worker is up and whose function workers are not born yet. */
async function coldRuntime(s: Stack) {
  await sh('docker', ['restart', '-t', '2', s.edgeContainer]);
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${s.api}/functions/v1/health`);
      await res.body?.cancel();
      if (res.ok) return;
    } catch {
      // Not listening yet.
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('edge runtime did not come back');
}

const pct = (xs: number[], p: number) => {
  const sorted = [...xs].sort((x, y) => x - y);
  const i = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[i] ?? NaN;
};
const r1 = (x: number) => Math.round(x * 10) / 10;

/** The functions' own `ms=` per path between [since] and [until], from their request lines. */
async function serverMs(
  s: Stack,
  since: string,
  until?: string,
): Promise<Record<string, number[]>> {
  const log = await sh('docker', [
    'logs',
    '--since',
    since,
    ...(until ? ['--until', until] : []),
    s.edgeContainer,
  ]);
  const found: Record<string, number[]> = {};
  for (const line of log.split('\n')) {
    const m = /(alexa|voice): (\S+) (\S+) .*?ms=(\d+)/.exec(line);
    if (!m) continue;
    const [, fn = '', a1 = '', a2 = '', ms = '0'] = m;
    const path = fn === 'alexa'
      ? a1 === 'LaunchRequest' ? 'alexa_launch' : a2 === 'AddItemIntent' ? 'alexa_add' : null
      : a2 === 'read'
      ? 'siri_read'
      : a2 === 'add'
      ? 'siri_add'
      : null;
    if (path) (found[path] ??= []).push(Number(ms));
  }
  return found;
}

const s = await stack();
const account = await seed(s);
const sign = await signer();
const r = runner(s, account, sign);
await r.snapshot();
const failures: string[] = [];
const check = (path: string, sample: Sample) => {
  if (!sample.ok && failures.length < 10) failures.push(`${path}: ${sample.detail}`);
  return sample.ms;
};

try {
  const cold: Record<string, number[]> = {};
  const coldSince = new Date().toISOString();
  for (let i = 0; i < coldRuns; i++) {
    for (const path of paths) {
      await coldRuntime(s);
      (cold[path] ??= []).push(check(path, await r.run[path]()));
    }
  }
  for (let i = 0; i < warmup; i++) for (const path of paths) check(path, await r.run[path]());
  const since = new Date().toISOString();
  const warm: Record<string, number[]> = {};
  for (let i = 0; i < warmRuns; i++) {
    for (const path of paths) (warm[path] ??= []).push(check(path, await r.run[path]()));
  }
  const server = await serverMs(s, since);
  const coldServer = coldRuns > 0 ? await serverMs(s, coldSince, since) : {};
  const result = {
    label,
    at: new Date().toISOString(),
    commit: (await sh('git', ['-C', repo, 'rev-parse', '--short', 'HEAD'])).trim(),
    load: (await Deno.readTextFile('/proc/loadavg')).split(' ').slice(0, 3).join(' '),
    failures,
    paths: Object.fromEntries(paths.map((p) => {
      const c = cold[p] ?? [];
      const w = warm[p] ?? [];
      return [p, {
        coldMedian: r1(pct(c, 50)),
        coldMin: r1(Math.min(...c)),
        coldMax: r1(Math.max(...c)),
        warmP50: r1(pct(w, 50)),
        warmP95: r1(pct(w, 95)),
        serverP50: r1(pct(server[p] ?? [], 50)),
        coldServerMedian: r1(pct(coldServer[p] ?? [], 50)),
        cold: c.map(r1),
      }];
    })),
  };
  console.log(JSON.stringify(result));
  console.error(`\n${label} (${result.commit}, load ${result.load})`);
  console.error(
    '| Path | Cold median (min-max) | Cold in handler | Warm p50 | Warm p95 | Warm in handler |',
  );
  console.error('| --- | --- | --- | --- | --- | --- |');
  for (const [p, v] of Object.entries(result.paths)) {
    console.error(
      `| ${p} | ${v.coldMedian} (${v.coldMin}-${v.coldMax}) | ${v.coldServerMedian} | ${v.warmP50} | ${v.warmP95} | ${v.serverP50} |`,
    );
  }
  if (failures.length) console.error(`FAILURES:\n${failures.join('\n')}`);
  if (out) await Deno.writeTextFile(out, JSON.stringify(result, null, 2) + '\n');
} finally {
  await r.close();
  await teardown(s, account);
}
