import { assert, assertEquals } from '@std/assert';
import type { FcmMessage, SendResult } from './fcm.ts';
import { configFrom, createHandler, type Device, SEND_CONCURRENCY, type Store } from './handler.ts';

const SECRET = 'push-secret-for-tests';
const HOUSEHOLD = '00000000-0000-4000-8000-000000000001';
const LIST = '00000000-0000-4000-8000-000000000002';
const OTHER_LIST = '00000000-0000-4000-8000-000000000009';
const ANNA = '00000000-0000-4000-8000-0000000000a1';
const BEN = '00000000-0000-4000-8000-0000000000b1';
const NOW = new Date('2026-11-22T10:00:00Z');
const TITLE = 'Anna hat Milch hinzugefügt';
const BODY = 'Einkaufsliste';

interface Fake {
  sent: FcmMessage[];
  forgotten: Device[];
  logs: string[];
  maxInFlight: number;
  post(
    body: unknown,
    secret?: string | null,
  ): Promise<{ status: number; body: unknown; raw: string }>;
}

function harness(opts: {
  devices?: Device[];
  secret?: string | null;
  fcm?: boolean;
  result?: (token: string) => SendResult;
  failStore?: boolean;
} = {}): Fake {
  const devices = opts.devices ?? [
    { userId: ANNA, token: 'test-token-a' },
    { userId: BEN, token: 'test-token-b' },
  ];
  const fake: Fake = {
    sent: [],
    forgotten: [],
    logs: [],
    maxInFlight: 0,
    async post(body, secret = SECRET) {
      const headers: Record<string, string> = { 'content-type': 'application/json' };
      if (secret !== null) headers['x-push-secret'] = secret;
      const original = console.log;
      console.log = (line: string) => fake.logs.push(line);
      try {
        const res = await handler(
          new Request('http://localhost/functions/v1/push', {
            method: 'POST',
            headers,
            body: typeof body === 'string' ? body : JSON.stringify(body),
          }),
        );
        const raw = await res.text();
        return { status: res.status, body: JSON.parse(raw), raw };
      } finally {
        console.log = original;
      }
    },
  };
  const store: Store = {
    devices(household, list, users) {
      if (opts.failStore) {
        return Promise.reject(Object.assign(new Error('boom'), { code: '57014' }));
      }
      if (household !== HOUSEHOLD || list !== LIST) return Promise.resolve(null);
      return Promise.resolve(devices.filter((d) => users.includes(d.userId)));
    },
    forget(gone) {
      fake.forgotten.push(...gone);
      return Promise.resolve(gone.length);
    },
  };
  let inFlight = 0;
  const handler = createHandler({
    secret: opts.secret === undefined ? SECRET : opts.secret,
    sender: opts.fcm === false ? null : {
      async send(message) {
        inFlight++;
        fake.maxInFlight = Math.max(fake.maxInFlight, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 0));
        inFlight--;
        fake.sent.push(message);
        return opts.result?.(message.token) ?? { outcome: 'sent' };
      },
    },
    store,
    now: () => NOW,
  });
  return fake;
}

const request = (over: Record<string, unknown> = {}) => ({
  household_id: HOUSEHOLD,
  list_id: LIST,
  recipients: [
    { user_id: ANNA, title: TITLE, body: BODY },
    { user_id: BEN, title: 'Anna added milk', body: 'Shopping list' },
  ],
  ...over,
});

/** Nothing the caller sent but the ids of the household and the list leaves in a log line. */
function assertQuietLogs(fake: Fake) {
  for (const line of fake.logs) {
    assert(/^push: [a-z_]+( [0-9A-Z]+)?$/.test(line), `a log line is a fixed code: ${line}`);
  }
}

Deno.test('sends each recipient their own text, on each of their devices, in the documented shape', async () => {
  const fake = harness({
    devices: [
      { userId: ANNA, token: 'test-token-a' },
      { userId: ANNA, token: 'test-token-a2' },
      { userId: BEN, token: 'test-token-b' },
    ],
  });
  const res = await fake.post(request());
  assertEquals(res.status, 200);
  assertEquals(res.body, { status: 'sent', devices: 3, sent: 3, failed: 0, removed: 0 });
  const byToken = Object.fromEntries(fake.sent.map((m) => [m.token, m]));
  assertEquals(byToken['test-token-a'], {
    token: 'test-token-a',
    notification: { title: TITLE, body: BODY },
    data: { kind: 'list', v: '1', household_id: HOUSEHOLD, list_id: LIST },
    android: { priority: 'high', ttl: '86400s' },
    apns: {
      headers: { 'apns-expiration': String(NOW.getTime() / 1000 + 86400) },
      payload: { aps: { sound: 'default' } },
    },
  });
  assertEquals(byToken['test-token-a2']?.notification.title, TITLE);
  assertEquals(byToken['test-token-b']?.notification, {
    title: 'Anna added milk',
    body: 'Shopping list',
  });
  assertEquals(fake.logs, ['push: sent']);
});

Deno.test('ttl_seconds sets both expiries', async () => {
  const fake = harness();
  await fake.post(request({ ttl_seconds: 600 }));
  const [first] = fake.sent;
  assertEquals(first?.android.ttl, '600s');
  assertEquals(first?.apns.headers['apns-expiration'], String(NOW.getTime() / 1000 + 600));
});

Deno.test('ids in upper case are sent in lower case', async () => {
  const fake = harness();
  const res = await fake.post(request({ household_id: HOUSEHOLD.toUpperCase() }));
  assertEquals(res.status, 200);
  assertEquals(fake.sent[0]?.data.household_id, HOUSEHOLD);
});

Deno.test('a dry run sends nothing and shows the first message without its token or text', async () => {
  const fake = harness({ fcm: false });
  const res = await fake.post(request({ dry_run: true }));
  assertEquals(res.status, 200);
  assertEquals(res.body, {
    status: 'dry_run',
    devices: 2,
    message: {
      token: '<token>',
      notification: { title: '<title>', body: '<body>' },
      data: { kind: 'list', v: '1', household_id: HOUSEHOLD, list_id: LIST },
      android: { priority: 'high', ttl: '86400s' },
      apns: {
        headers: { 'apns-expiration': String(NOW.getTime() / 1000 + 86400) },
        payload: { aps: { sound: 'default' } },
      },
    },
  });
  assert(!res.raw.includes('test-token'), 'no token in the answer');
  assertEquals(fake.sent, []);
});

Deno.test('a dry run with FCM configured still sends nothing', async () => {
  const fake = harness();
  const res = await fake.post(request({ dry_run: true }));
  assertEquals((res.body as { status: string }).status, 'dry_run');
  assertEquals(fake.sent, []);
});

Deno.test('a dry run for recipients without devices has no message', async () => {
  const fake = harness({ devices: [] });
  const res = await fake.post(request({ dry_run: true }));
  assertEquals(res.body, { status: 'dry_run', devices: 0, message: null });
});

Deno.test('tokens FCM calls unregistered are deleted and counted; other failures are kept', async () => {
  const fake = harness({
    devices: [
      { userId: ANNA, token: 'test-token-a' },
      { userId: ANNA, token: 'test-token-gone' },
      { userId: BEN, token: 'test-token-b' },
    ],
    result: (token) =>
      token === 'test-token-gone'
        ? { outcome: 'unregistered' }
        : token === 'test-token-b'
        ? { outcome: 'failed', status: 503 }
        : { outcome: 'sent' },
  });
  const res = await fake.post(request());
  assertEquals(res.body, { status: 'sent', devices: 3, sent: 1, failed: 2, removed: 1 });
  assertEquals(fake.forgotten, [{ userId: ANNA, token: 'test-token-gone' }]);
  assertEquals(fake.logs.toSorted(), ['push: send_failed 503', 'push: sent']);
  assertQuietLogs(fake);
});

Deno.test(`sends at most ${SEND_CONCURRENCY} messages at once`, async () => {
  const devices = Array.from(
    { length: 30 },
    (_, i) => ({ userId: ANNA, token: `test-token-${i}` }),
  );
  const fake = harness({ devices });
  const res = await fake.post(request());
  assertEquals(res.body, { status: 'sent', devices: 30, sent: 30, failed: 0, removed: 0 });
  assertEquals(fake.maxInFlight, SEND_CONCURRENCY);
});

Deno.test('a list of another household is 422 and sends nothing', async () => {
  const fake = harness();
  const res = await fake.post(request({ list_id: OTHER_LIST }));
  assertEquals([res.status, res.body], [422, { error: 'unknown_list' }]);
  assertEquals(fake.sent, []);
});

Deno.test('only recipients the store finds get anything', async () => {
  const fake = harness({ devices: [{ userId: BEN, token: 'test-token-b' }] });
  const res = await fake.post(request());
  assertEquals(res.body, { status: 'sent', devices: 1, sent: 1, failed: 0, removed: 0 });
});

Deno.test('a wrong or missing secret is 401', async () => {
  for (const secret of ['wrong', '', null]) {
    const fake = harness();
    const res = await fake.post(request(), secret);
    assertEquals([res.status, res.body], [401, { error: 'unauthorized' }]);
    assertEquals(fake.sent, []);
  }
});

Deno.test('without PUSH_SEND_SECRET every request is 503, dry runs too', async () => {
  for (const dryRun of [false, true]) {
    const res = await harness({ secret: null }).post(request({ 'dry_run': dryRun }), 'anything');
    assertEquals([res.status, res.body], [503, { error: 'not_configured' }]);
  }
});

Deno.test('without FCM only a dry run works', async () => {
  const res = await harness({ fcm: false }).post(request());
  assertEquals([res.status, res.body], [503, { error: 'not_configured' }]);
});

Deno.test('a body that does not parse is 400, after the secret', async () => {
  const bad: unknown[] = [
    'not json',
    {},
    request({ household_id: 'not-a-uuid' }),
    request({ recipients: [] }),
    request({
      recipients: Array.from({ length: 51 }, (_, i) => ({
        user_id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
        title: 't',
        body: '',
      })),
    }),
    request({ recipients: [{ user_id: ANNA, title: '', body: '' }] }),
    request({ recipients: [{ user_id: ANNA, title: 'x'.repeat(101), body: '' }] }),
    request({ recipients: [{ user_id: ANNA, title: 't', body: 'x'.repeat(401) }] }),
    request({ recipients: [{ user_id: ANNA, title: 't' }] }),
    request({
      recipients: [{ user_id: ANNA, title: 't', body: '' }, {
        user_id: ANNA,
        title: 'u',
        body: '',
      }],
    }),
    request({ dry_run: 'yes' }),
    request({ ttl_seconds: 59 }),
    request({ ttl_seconds: 86401 }),
    request({ ttl_seconds: 600.5 }),
  ];
  for (const body of bad) {
    const fake = harness();
    const res = await fake.post(body);
    assertEquals([res.status, res.body], [400, { error: 'invalid_request' }], JSON.stringify(body));
  }
  const res = await harness().post('not json', 'wrong');
  assertEquals(res.status, 401);
});

Deno.test('50 recipients and the bounds of the texts are fine', async () => {
  const recipients = Array.from({ length: 50 }, (_, i) => ({
    user_id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
    title: 'x'.repeat(100),
    body: 'y'.repeat(400),
  }));
  const res = await harness().post(request({ recipients, ttl_seconds: 60 }));
  assertEquals(res.status, 200);
});

Deno.test('a database failure is 500 with the SQLSTATE in the log only', async () => {
  const fake = harness({ failStore: true });
  const res = await fake.post(request());
  assertEquals([res.status, res.body], [500, { error: 'failed' }]);
  assertEquals(fake.logs, ['push: db_error 57014']);
});

Deno.test('other paths and methods are 404', async () => {
  const handler = createHandler({
    secret: SECRET,
    sender: null,
    store: { devices: () => Promise.resolve([]), forget: () => Promise.resolve(0) },
    now: () => NOW,
  });
  for (
    const req of [
      new Request('http://localhost/functions/v1/push', { method: 'GET' }),
      new Request('http://localhost/functions/v1/push/x', { method: 'POST' }),
    ]
  ) {
    const res = await handler(req);
    assertEquals(res.status, 404);
    await res.body?.cancel();
  }
});

Deno.test('answers and logs never carry a token, a user id or a text', async () => {
  const fake = harness({
    result: (token) => token === 'test-token-a' ? { outcome: 'unregistered' } : { outcome: 'sent' },
  });
  const answers = [
    (await fake.post(request())).raw,
    (await fake.post(request({ dry_run: true }))).raw.replace(TITLE, '').replace(BODY, ''),
    (await fake.post(request({ list_id: OTHER_LIST }))).raw,
    (await fake.post(request({ household_id: 'x' }))).raw,
  ];
  for (const text of [...answers, ...fake.logs]) {
    for (const secret of ['test-token', ANNA, BEN, 'Anna added milk', 'Shopping list']) {
      assert(!text.includes(secret), `${secret} leaked: ${text}`);
    }
  }
  assertQuietLogs(fake);
});

Deno.test('configFrom reads the secret and builds a sender only from a valid account', () => {
  const env = (vars: Record<string, string>) => ({ get: (k: string) => vars[k] });
  assertEquals(configFrom(env({})), { secret: null, sender: null });
  const original = console.log;
  const logs: string[] = [];
  console.log = (line: string) => logs.push(line);
  try {
    assertEquals(configFrom(env({ FCM_SERVICE_ACCOUNT_JSON: '{' })).sender, null);
    assertEquals(configFrom(env({ FCM_SERVICE_ACCOUNT_JSON: '{"project_id":"p"}' })).sender, null);
  } finally {
    console.log = original;
  }
  assertEquals(logs, ['push: fcm_config_invalid', 'push: fcm_config_invalid']);
  const config = configFrom(env({
    PUSH_SEND_SECRET: 's',
    FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
      project_id: 'snacklist-test',
      client_email: 'push@snacklist-test.iam.gserviceaccount.com',
      private_key: 'not read until the first send',
      token_uri: 'https://oauth2.googleapis.com/token',
    }),
  }));
  assertEquals(config.secret, 's');
  assert(config.sender !== null);
});
