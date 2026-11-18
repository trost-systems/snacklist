import { assert, assertEquals, assertExists, assertMatch } from '@std/assert';
import {
  configFrom,
  CONFIRM_RETRY_MS,
  createHandler,
  LIMITS,
  MAX_BODY,
  randomRef,
  type Report,
  type Store,
  type Stored,
} from './handler.ts';
import type { Mail, Mailer } from '../_shared/resend.ts';

const PROXY = 'proxy-secret-for-tests';
const T0 = new Date('2026-11-16T13:05:00Z');
const HOUR = 3600_000;
const REF = /^M-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;

interface Row extends Report {
  id: string;
  ref: string;
  createdAt: Date;
  confirmationSentAt: Date | null;
}

/** content_report_submit's rules over an array, enough to drive the handler. */
class FakeStore implements Store {
  rows: Row[] = [];
  calls = 0;
  failWith: unknown = null;

  submit(r: Report, now: Date, limits: typeof LIMITS): Promise<Stored | null> {
    this.calls++;
    if (this.failWith) return Promise.reject(this.failWith);
    const lastHour = this.rows.filter((x) => x.createdAt.getTime() > now.getTime() - HOUR);
    if (lastHour.length >= limits.perHour) return Promise.resolve(null);
    const row: Row = {
      ...r,
      id: crypto.randomUUID(),
      ref: `M-AAAA-${String(this.rows.length).padStart(4, '0')}`,
      createdAt: now,
      confirmationSentAt: null,
    };
    this.rows.push(row);
    return Promise.resolve({
      id: row.id,
      ref: row.ref,
      confirm: !!r.email,
    });
  }

  confirmationSent(id: string, now: Date): Promise<boolean> {
    const row = this.rows.find((x) => x.id === id);
    if (row) row.confirmationSentAt = now;
    return Promise.resolve(!!row);
  }
}

interface Sent {
  to: string;
  mail: Mail;
  key: string;
}

function setup(over: { mailer?: Mailer | null; env?: Record<string, string> } = {}) {
  const store = new FakeStore();
  const sent: Sent[] = [];
  const deferred: (() => Promise<void>)[] = [];
  const clock = { now: T0 };
  const waits: number[] = [];
  const { config } = configFrom(
    new Map(Object.entries(over.env ?? { WAITLIST_PROXY_SECRET: PROXY })),
  );
  const mailer: Mailer | null = over.mailer !== undefined ? over.mailer : {
    send(to, mail, key) {
      sent.push({ to, mail, key });
      return Promise.resolve();
    },
  };
  const handler = createHandler({
    config,
    store,
    mailer,
    now: () => clock.now,
    random: (n) => new Uint8Array(n).map((_, i) => i * 37),
    defer: (work) => {
      deferred.push(work);
    },
    sleep: (ms) => {
      waits.push(ms);
      return Promise.resolve();
    },
  });
  const call = (
    body: unknown,
    init: { path?: string; method?: string; headers?: Record<string, string> } = {},
  ) =>
    handler(
      new Request(`http://localhost${init.path ?? '/report'}`, {
        method: init.method ?? 'POST',
        headers: { 'x-waitlist-proxy-secret': PROXY, ...init.headers },
        ...(init.method === 'GET'
          ? {}
          : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
      }),
    );
  /** Runs what the function does after its answer, as EdgeRuntime.waitUntil would. */
  const flush = async () => {
    for (let work = deferred.shift(); work; work = deferred.shift()) await work();
  };
  return { store, sent, deferred, clock, waits, call, flush };
}

const form = (extra: Record<string, unknown> = {}) => ({
  locale: 'de',
  category: 'hate',
  location: 'Haushalt "WG Lindenstraße", Liste Einkauf, Eintrag "…"',
  reason: 'Der Eintrag beleidigt mich mit meinem vollen Namen.',
  name: 'Anna Beispiel',
  email: 'test+report@snacklist.app',
  good_faith: true,
  website: '',
  ...extra,
});

/** Captures console.log while [work] runs. */
async function logsOf(work: () => Promise<unknown>): Promise<string[]> {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => lines.push(args.join(' '));
  try {
    await work();
  } finally {
    console.log = original;
  }
  return lines;
}

function only<T>(items: readonly T[]): T {
  assertEquals(items.length, 1);
  const [item] = items;
  assertExists(item);
  return item;
}

Deno.test('a report is stored trimmed and answered 201 with its ref; the confirmation follows the answer', async () => {
  const { store, sent, deferred, call, flush } = setup();
  const res = await call(form({
    location: '  Liste Einkauf\nEintrag Nr. 3  ',
    reason: '\t' + form().reason + '\n',
    name: ' Anna Beispiel ',
    email: ' test+report@snacklist.app ',
    unknown_key: 'ignored',
  }));
  assertEquals(res.status, 201);
  assertEquals(res.headers.get('cache-control'), 'no-store');
  const { ref } = await res.json();
  const row = only(store.rows);
  assertEquals(ref, row.ref);
  assertEquals(
    [row.locale, row.category, row.location, row.reason, row.name, row.email],
    [
      'de',
      'hate',
      'Liste Einkauf\nEintrag Nr. 3',
      form().reason,
      'Anna Beispiel',
      'test+report@snacklist.app',
    ],
  );
  assertEquals(sent.length, 0, 'no mail before the answer is out');
  assertEquals(deferred.length, 1);
  await flush();
  const mail = only(sent);
  assertEquals(mail.to, 'test+report@snacklist.app');
  assertEquals(mail.key, `report-confirm/${row.id}`);
  assertEquals(mail.mail.subject, `Deine Meldung an Snacklist ist eingegangen (${row.ref})`);
  assert(
    mail.mail.text.startsWith(
      'Hallo Anna Beispiel, danke für deine Meldung vom 16.11.2026, 14:05 Uhr',
    ),
  );
  assertEquals(row.confirmationSentAt, T0, 'the mail counts toward the address limit');
});

Deno.test('an empty name and address are stored as null and nothing is mailed', async () => {
  const { store, deferred, call } = setup();
  const res = await call(form({ name: '  ', email: '' }));
  assertEquals(res.status, 201);
  const row = only(store.rows);
  assertEquals([row.name, row.email], [null, null]);
  assertEquals(deferred.length, 0);
});

Deno.test('name and email may be left out', async () => {
  const { store, call } = setup();
  const { name: _n, email: _e, website: _w, ...rest } = form();
  assertEquals((await call(rest)).status, 201);
  assertEquals([only(store.rows).name, only(store.rows).email], [null, null]);
});

Deno.test('a filled honeypot gets a 201 with a ref of the same shape; nothing is stored or mailed', async () => {
  const { store, deferred, call } = setup();
  const res = await call(form({ website: 'https://spam.example' }));
  assertEquals(res.status, 201);
  assertMatch((await res.json()).ref, REF);
  assertEquals([store.calls, deferred.length], [0, 0]);
});

Deno.test('randomRef: Crockford base32 without I L O U, from every byte value', () => {
  const all = new Uint8Array(256).map((_, i) => i);
  for (let i = 0; i < 256; i += 8) assertMatch(randomRef(all.slice(i, i + 8)), REF);
  assertEquals(randomRef(new Uint8Array([0, 1, 31, 32, 18, 21, 24, 27])), 'M-01Z0-JNRV');
});

Deno.test('invalid bodies answer 400 invalid_request and store nothing', async (t) => {
  const twenty = '😀'.repeat(20);
  const cases: [string, unknown][] = [
    ['locale', form({ locale: 'fr' })],
    ['category', form({ category: 'spam' })],
    ['no category', form({ category: undefined })],
    ['good_faith false', form({ good_faith: false })],
    ['good_faith "true"', form({ good_faith: 'true' })],
    ['empty location', form({ location: '   ' })],
    ['location too long', form({ location: 'x'.repeat(2001) })],
    ['location not a string', form({ location: 5 })],
    ['location with a NUL', form({ location: 'Liste\u0000' })],
    ['reason of 19 code points', form({ reason: '😀'.repeat(19) })],
    ['reason padded to 20', form({ reason: ` ${'x'.repeat(19)} ` })],
    ['reason of 5001 code points', form({ reason: 'x'.repeat(5001) })],
    ['reason with an escape character', form({ reason: twenty + '\u001b' })],
    ['name too long', form({ name: 'n'.repeat(201) })],
    ['name with a line break', form({ name: 'Anna\nBeispiel' })],
    ['name not a string', form({ name: null })],
    ['email without a dot', form({ email: 'a@b' })],
    ['email with a one-letter tld', form({ email: 'a@b.c' })],
    ['email too long', form({ email: `${'a'.repeat(245)}@snacklist.app` })],
    ['email with a space', form({ email: 'a b@snacklist.app' })],
    ['not json', '{"locale":'],
    ['an array', [form()]],
    ['too big', form({ padding: 'x'.repeat(MAX_BODY) })],
  ];
  for (const [name, body] of cases) {
    await t.step(name, async () => {
      const { store, call } = setup();
      const res = await call(body);
      assertEquals(res.status, 400);
      assertEquals(await res.json(), { error: 'invalid_request' });
      assertEquals(store.calls, 0);
    });
  }
});

Deno.test('lengths count code points, as char_length does: 20 emoji and 5000 letters pass', async () => {
  const { store, call } = setup();
  assertEquals((await call(form({ reason: '😀'.repeat(20) }))).status, 201);
  assertEquals(
    (await call(form({ reason: 'x'.repeat(5000), location: 'y'.repeat(2000) }))).status,
    201,
  );
  assertEquals((await call(form({ name: 'n'.repeat(200) }))).status, 201);
  assertEquals(store.rows.length, 3);
});

Deno.test('a reason and location may hold line breaks and tabs', async () => {
  const { call } = setup();
  assertEquals(
    (await call(form({ reason: 'Zeile eins ist da,\r\n\tZeile zwei auch.' }))).status,
    201,
  );
});

Deno.test('over the hourly limit: 429 rate_limited, nothing stored or mailed; an hour later it works', async () => {
  const { store, deferred, clock, call } = setup();
  for (let i = 0; i < LIMITS.perHour; i++) {
    assertEquals((await call(form({ email: '' }))).status, 201);
  }
  let res = new Response();
  const logs = await logsOf(async () => {
    res = await call(form());
  });
  assertEquals(res.status, 429);
  assertEquals(await res.json(), { error: 'rate_limited' });
  assertEquals(logs, ['report: global_cap_hit', 'report 429'], 'the circuit breaker names itself');
  assertEquals([store.rows.length, deferred.length], [LIMITS.perHour, 0]);
  clock.now = new Date(T0.getTime() + HOUR);
  assertEquals((await call(form())).status, 201);
});

Deno.test('every report with an address gets its confirmation, however many that address sent (N-241)', async () => {
  const { store, sent, call, flush } = setup();
  for (let i = 0; i < 6; i++) {
    assertEquals(
      (await call(
        form({ email: i % 2 ? 'Test+Report@snacklist.app' : 'test+report@snacklist.app' }),
      )).status,
      201,
    );
    await flush();
  }
  assertEquals(store.rows.length, 6);
  assertEquals(sent.length, 6);
  assert(store.rows.every((r) => r.confirmationSentAt !== null), 'each marked as sent');
});

Deno.test('the secret, path and method gate everything: 404 not_found', async () => {
  const { store, call } = setup();
  const statuses = [
    await call(form(), { headers: { 'x-waitlist-proxy-secret': 'wrong' } }),
    await call(form(), { headers: { 'x-waitlist-proxy-secret': '' } }),
    await call(form(), { path: '/report/extra' }),
    await call(form(), { path: '/waitlist/signup' }),
    await call(form(), { method: 'GET' }),
    await call(form(), { method: 'PUT' }),
  ];
  for (const res of statuses) {
    assertEquals(res.status, 404);
    assertEquals(await res.json(), { error: 'not_found' });
  }
  assertEquals(store.calls, 0);
  assertEquals((await call(form(), { path: '/functions/v1/report' })).status, 201);
});

Deno.test('without WAITLIST_PROXY_SECRET every request is 404', async () => {
  const { store, call } = setup({ env: { RESEND_API_KEY: 're_test' } });
  assertEquals((await call(form())).status, 404);
  assertEquals(store.calls, 0);
});

Deno.test('a store failure answers 503 and logs the SQLSTATE only', async () => {
  const { store, call } = setup();
  store.failWith = Object.assign(new Error('new row violates check: test+report@snacklist.app'), {
    code: '23514',
  });
  let res: Response | undefined;
  const logs = await logsOf(async () => {
    res = await call(form());
  });
  assertEquals(res?.status, 503);
  assertEquals(await res?.json(), { error: 'unavailable' });
  assertEquals(logs, ['report: failed 23514', 'report 503']);
});

Deno.test('logs are fixed codes: no address, name, ref or body', async () => {
  const { call, flush } = setup();
  const logs = await logsOf(async () => {
    await call(form());
    await flush();
    await call(form({ reason: 'zu kurz' }));
    await call(form({ website: 'x' }));
  });
  assertEquals(logs, [
    'report: stored',
    'report: confirmation_sent',
    'report 400',
    'report: honeypot',
  ]);
});

Deno.test('without RESEND_API_KEY the report is stored, the mail skipped with a code', async () => {
  const { store, call, flush } = setup({ mailer: null });
  const logs = await logsOf(async () => {
    assertEquals((await call(form())).status, 201);
    await flush();
  });
  assertEquals(logs, ['report: stored', 'report: mail_unconfigured']);
  assertEquals(only(store.rows).confirmationSentAt, null);
});

Deno.test('a send that keeps failing is tried three times with backoff, logged with fixed codes and not marked sent', async () => {
  const keys: string[] = [];
  const { store, waits, call, flush } = setup({
    mailer: {
      send: (_to, _mail, key) => {
        keys.push(key);
        return Promise.reject(Object.assign(new Error('to x@y'), { code: 'nope' }));
      },
    },
  });
  const logs = await logsOf(async () => {
    assertEquals((await call(form())).status, 201);
    await flush();
  });
  assertEquals(logs, [
    'report: stored',
    'report: mail_retry',
    'report: mail_retry',
    'report: mail_failed',
  ]);
  assertEquals(waits, CONFIRM_RETRY_MS);
  const row = only(store.rows);
  assertEquals(keys, Array(3).fill(`report-confirm/${row.id}`), 'one key, so Resend sends it once');
  assertEquals(row.confirmationSentAt, null, 'notify.ts --confirmations finds it');
});

Deno.test('a send that fails once goes out on the retry and is marked sent', async () => {
  let tries = 0;
  const { store, waits, call, flush } = setup({
    mailer: { send: () => ++tries === 1 ? Promise.reject(new Error('503')) : Promise.resolve() },
  });
  const logs = await logsOf(async () => {
    assertEquals((await call(form())).status, 201);
    await flush();
  });
  assertEquals(logs, ['report: stored', 'report: mail_retry', 'report: confirmation_sent']);
  assertEquals([tries, waits.length], [2, 1]);
  assert(only(store.rows).confirmationSentAt !== null);
});
