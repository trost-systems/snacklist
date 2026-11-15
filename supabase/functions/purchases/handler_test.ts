// The purchases handler against an in-memory ledger that answers like the migration's
// purchase_record, purchase_claim, purchase_revoke and purchase_reinstate.
import { assert, assertEquals, assertRejects } from '@std/assert';
import { AuthError } from '../_shared/auth.ts';
import { OutOfTime } from '../_shared/db.ts';
import type { PurchaseEvent } from '../_shared/purchases.ts';
import type { Subject } from '../_shared/telemetry.ts';
import { createHandler, type Deps, type Ledger, maxBodyBytes, routes } from './handler.ts';
import type { Lifecycle } from './revenuecat.ts';
import type { Claim, LifecycleOutcome, PromotionalOutcome, Recorded, Revoked } from './store.ts';
import { type PromotionalPremium, RevenueCatUnavailable } from './promotional.ts';
import { lifetimeProductId, type Sale, type StorePurchase, webhookPath } from './types.ts';

const PETER = '00000000-0000-4000-8000-0000000043a1';
const LEA = '00000000-0000-4000-8000-0000000043a2';
const HOME = '00000000-0000-4000-8000-00000000a0e1';
const OTHER = '00000000-0000-4000-8000-00000000a0e2';
const INSTALL = '6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b';
const AUTH = 'Bearer rc-webhook-secret-for-tests';
const SIGNING = 'rc-signing-secret-for-tests';
const base = 'http://localhost/functions/v1/purchases';
const DELETIONS_SECRET = 'deletions-secret-for-tests';
const NOW = new Date('2026-10-31T14:00:00Z');

interface Row {
  purchase: StorePurchase;
  user: string | null;
  revoked: boolean;
  sent: boolean;
}

/** The migration's purchase bookkeeping, in memory. */
class Books implements Ledger {
  rows = new Map<string, Row>();
  claims = new Map<string, { user: string; household: string }>();
  eventIds = new Set<string>();
  members = new Map<string, string>([[PETER, HOME], [LEA, HOME]]);
  testers = new Set<string>();
  writes = 0;
  fail: Error | null = null;

  find(store: string, tx: string) {
    return [...this.rows.values()].find((r) =>
      r.purchase.store === store &&
      (r.purchase.transactionId === tx || r.purchase.latestTransactionId === tx)
    );
  }

  record(p: StorePurchase): Promise<Recorded> {
    if (this.fail) return Promise.reject(this.fail);
    this.writes++;
    const key = `${p.store}:${p.transactionId}`;
    const fresh = !this.rows.has(key);
    if (fresh) this.rows.set(key, { purchase: p, user: null, revoked: false, sent: false });
    const row = this.rows.get(key)!;
    const answer = (outcome: Recorded['outcome'], more: Partial<Recorded> = {}): Recorded => ({
      outcome,
      alreadyUnlocked: false,
      householdGone: false,
      internal: row.user !== null && this.testers.has(row.user),
      buyer: null,
      sendCompleted: false,
      secondYearly: false,
      householdId: row.purchase.appUserId,
      ...more,
    });
    if (row.revoked) return Promise.resolve(answer('revoked'));
    if (row.purchase.appUserId !== p.appUserId) {
      return Promise.resolve(answer('used_elsewhere'));
    }
    for (const id of [p.transactionId, p.latestTransactionId]) {
      const c = this.claims.get(`${p.store}:${id}`);
      if (!row.user && c?.household === p.appUserId) {
        row.user = c.user;
        this.claims.delete(`${p.store}:${id}`);
      }
    }
    const send = row.user !== null && !row.sent;
    if (send) row.sent = true;
    return Promise.resolve(answer(fresh ? 'granted' : 'restored', {
      buyer: row.user,
      sendCompleted: send,
      internal: row.user !== null && this.testers.has(row.user),
    }));
  }

  lifecycles: Lifecycle[] = [];

  lifecycle(c: Lifecycle): Promise<LifecycleOutcome> {
    this.writes++;
    this.lifecycles.push(c);
    const row = this.rows.get(`${c.store}:${c.transactionId}`);
    return Promise.resolve(!row ? 'unknown' : row.revoked ? 'revoked' : 'updated');
  }

  revoke(r: { store: 'apple' | 'google'; transactionId: string }): Promise<Revoked | null> {
    this.writes++;
    const row = this.rows.get(`${r.store}:${r.transactionId}`);
    if (!row || row.revoked) return Promise.resolve(null);
    row.revoked = true;
    return Promise.resolve({
      ...row.purchase,
      householdId: row.purchase.appUserId,
      userId: row.user,
      internal: row.user !== null && this.testers.has(row.user),
    });
  }

  reinstate(store: string, tx: string): Promise<boolean> {
    this.writes++;
    const row = this.rows.get(`${store}:${tx}`);
    if (!row?.revoked) return Promise.resolve(false);
    row.revoked = false;
    return Promise.resolve(true);
  }

  /** RevenueCat's promotional premium per household (its API), and the rows we keep of it. */
  granted = new Map<string, PromotionalPremium>();
  promoRows = new Map<string, Date | null>();
  revenueCatDown = false;
  apiReads = 0;

  /** promotional_premium_sync after reading RevenueCat, in memory. */
  promotional(household: string): Promise<PromotionalOutcome> {
    if (![...this.members.values(), OTHER].includes(household)) {
      return Promise.resolve('no_household');
    }
    this.apiReads++;
    if (this.revenueCatDown) return Promise.reject(new RevenueCatUnavailable(500));
    this.writes++;
    const now = this.granted.get(household) ?? { active: false };
    const had = this.promoRows.has(household);
    if (!now.active) {
      this.promoRows.delete(household);
      return Promise.resolve(had ? 'removed' : 'unchanged');
    }
    const same = had && this.promoRows.get(household)?.getTime() === now.expiresAt?.getTime();
    this.promoRows.set(household, now.expiresAt);
    return Promise.resolve(!had ? 'granted' : same ? 'unchanged' : 'updated');
  }

  claim(user: string, household: string, store: 'apple' | 'google', tx: string): Claim {
    if (this.members.get(user) !== household) throw new AuthError('no_household', 'left');
    const row = this.find(store, tx);
    if (!row) {
      if (!this.claims.has(`${store}:${tx}`)) {
        this.claims.set(`${store}:${tx}`, { user, household });
      }
      return { status: 'waiting', completed: null };
    }
    if (row.purchase.appUserId !== household) return { status: 'elsewhere', completed: null };
    if (row.user && row.user !== user) return { status: 'taken', completed: null };
    row.user = user;
    if (row.sent || row.revoked) return { status: 'recorded', completed: null };
    row.sent = true;
    return {
      status: 'recorded',
      completed: {
        ...row.purchase,
        householdId: row.purchase.appUserId,
        internal: this.testers.has(user),
      },
    };
  }
}

interface World {
  deps: Deps;
  books: Books;
  sent: { name: PurchaseEvent; sale: Sale; subject: Subject }[];
  calls: string[];
  /** A request to [path]; GET without a body. */
  handle(path: string, body?: unknown, headers?: Record<string, string>): Promise<Response>;
  /** RevenueCat's delivery of [event]: authorized, and signed when [signed]. */
  deliver(event: Record<string, unknown>, init?: { signed?: boolean }): Promise<Response>;
}

function world(overrides: Partial<Deps> = {}): World {
  const books = new Books();
  const sent: World['sent'] = [];
  const calls: string[] = [];
  const deps: Deps = {
    webhook: { authorization: AUTH, signingSecret: null },
    local: false,
    region: 'eu-central-1',
    authenticate: (req) => {
      const header = req.headers.get('authorization');
      if (!header) return Promise.reject(new AuthError('missing_token', 'missing'));
      if (header.startsWith('Bearer fgp_')) {
        return Promise.reject(new AuthError('session_required', 'pat'));
      }
      const userId = header === 'Bearer lea' ? LEA : PETER;
      return Promise.resolve({ userId });
    },
    takeCall: (userId) => {
      calls.push(userId);
      return Promise.resolve(true);
    },
    once: async (event, work) => {
      if (books.eventIds.has(event.id)) return null;
      const result = await work(books);
      books.eventIds.add(event.id);
      return result;
    },
    claim: (userId, householdId, store, tx) => {
      try {
        return Promise.resolve(books.claim(userId, householdId, store, tx));
      } catch (e) {
        return Promise.reject(e);
      }
    },
    subject: (userId) =>
      Promise.resolve({ installId: INSTALL, householdId: HOME, internal: userId === 'internal' }),
    event: (name, sale, subject) => {
      sent.push({ name, sale, subject });
      return Promise.resolve();
    },
    deletionsSecret: DELETIONS_SECRET,
    reconcile: (householdId) => books.promotional(householdId),
    deleteDueCustomers: null,
    report: (e) => {
      throw e;
    },
    now: () => NOW,
    ...overrides,
  };
  const handler = createHandler(deps);
  const handle: World['handle'] = (path, body, headers = {}) =>
    handler(
      new Request(`${base}${path}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers: { 'content-type': 'application/json', ...headers },
        body: body === undefined
          ? undefined
          : typeof body === 'string'
          ? body
          : JSON.stringify(body),
      }),
    );
  return {
    deps,
    books,
    sent,
    calls,
    handle,
    deliver: async (event, { signed = false } = {}) => {
      const raw = JSON.stringify({ api_version: '1.0', event });
      const headers: Record<string, string> = { authorization: AUTH };
      if (signed) headers['x-revenuecat-webhook-signature'] = await signature(raw);
      return handle('/revenuecat/webhook', raw, headers);
    },
  };
}

/** RevenueCat's signature header for [raw], computed here independently of the handler's code. */
async function signature(raw: string, t = Math.floor(NOW.getTime() / 1000), secret = SIGNING) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${t}.${raw}`));
  const hex = Array.from(new Uint8Array(mac), (b) => b.toString(16).padStart(2, '0')).join('');
  return `t=${t},v1=${hex}`;
}

/** A NON_RENEWING_PURCHASE as RevenueCat sends it (webhooks/event-types-and-fields). */
function purchase(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: crypto.randomUUID().toUpperCase(),
    type: 'NON_RENEWING_PURCHASE',
    app_id: 'app1a2b3c4d5',
    app_user_id: HOME,
    original_app_user_id: HOME,
    aliases: [HOME],
    store: 'APP_STORE',
    environment: 'SANDBOX',
    product_id: lifetimeProductId,
    entitlement_ids: ['lifetime'],
    period_type: 'NORMAL',
    transaction_id: '2000000812345679',
    original_transaction_id: '2000000812345678',
    purchased_at_ms: NOW.getTime() - 5_000,
    event_timestamp_ms: NOW.getTime(),
    expiration_at_ms: null,
    price: 10.49,
    price_in_purchased_currency: 9.99,
    currency: 'EUR',
    country_code: 'DE',
    takehome_percentage: 0.85,
    is_family_share: false,
    subscriber_attributes: {},
    future_field: { anything: true },
    ...overrides,
  };
}

const flipLast = (s: string) => s.slice(0, -1) + (s.endsWith('0') ? '1' : '0');

const of = (type: string, overrides: Record<string, unknown> = {}) =>
  purchase({ type, ...overrides });

async function expect(res: Response, status: number, body?: Record<string, unknown>) {
  const got = await res.json();
  assertEquals(res.status, status, JSON.stringify(got));
  if (body) assertEquals(got, body);
  return got;
}

/** What the handler logs while [work] runs. */
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

Deno.test('unconfigured, the webhook answers 503; the status says so', async () => {
  const w = world({ webhook: null, local: true });
  await expect(await w.handle(''), 200, { configured: false });
  await expect(await w.deliver(purchase()), 503, { error: 'not_configured' });
  await expect(await w.handle('/test/event', { appUserId: HOME, transactionId: '1' }), 503);
  assertEquals(w.books.writes, 0);
  await expect(await world().handle(''), 200, { configured: true });
});

Deno.test('the webhook takes only the configured Authorization value', async () => {
  const w = world();
  const raw = JSON.stringify({ event: purchase() });
  for (
    const header of [
      undefined,
      '',
      'Bearer rc-webhook-secret-for-testX',
      'Bearer rc-webhook-secret-for-test',
      'rc-webhook-secret-for-tests',
      `${AUTH} `.repeat(2),
    ]
  ) {
    const headers: Record<string, string> = header === undefined ? {} : { authorization: header };
    await expect(await w.handle('/revenuecat/webhook', raw, headers), 401, {
      error: 'invalid_token',
    });
  }
  assertEquals(w.books.writes, 0);
  await expect(await w.handle('/revenuecat/webhook', raw, { authorization: AUTH }), 200, {
    status: 'granted',
  });
});

Deno.test('with a signing secret, every delivery must be signed over its raw bytes', async () => {
  const w = world({ webhook: { authorization: AUTH, signingSecret: SIGNING } });
  const event = purchase();
  const raw = JSON.stringify({ event });
  const t = Math.floor(NOW.getTime() / 1000);
  const send = (signatureHeader: string | null, body = raw) =>
    w.handle('/revenuecat/webhook', body, {
      authorization: AUTH,
      ...(signatureHeader === null ? {} : { 'x-revenuecat-webhook-signature': signatureHeader }),
    });
  const refused = [
    null,
    '',
    await signature(raw, t, 'another-secret'),
    await signature(raw, t - 301),
    await signature(raw, t + 301),
    flipLast(await signature(raw)),
    `t=${t}`,
  ];
  for (const header of refused) {
    await expect(await send(header), 401, { error: 'bad_signature' });
  }
  // Reformatted JSON is not what was signed.
  await expect(await send(await signature(raw), JSON.stringify({ event }, null, 1)), 401);
  assertEquals(w.books.writes, 0);
  await expect(await send(await signature(raw, t - 299)), 200, { status: 'granted' });
  const second = JSON.stringify({
    event: purchase({ transaction_id: 'b', original_transaction_id: 'b' }),
  });
  await expect(
    await send(`v1=00ff,${(await signature(second)).replace(`t=${t},`, '')},t=${t}`, second),
    200,
  );
});

Deno.test('a body that is no RevenueCat event is a 400', async () => {
  const w = world();
  const headers = { authorization: AUTH };
  for (const body of ['not json', '{}', '{"event":{"type":"TEST"}}', '{"event":{"id":"x"}}']) {
    await expect(await w.handle('/revenuecat/webhook', body, headers), 400, {
      error: 'bad_request',
    });
  }
  const huge = JSON.stringify({ event: purchase({ padding: 'x'.repeat(maxBodyBytes) }) });
  await expect(await w.handle('/revenuecat/webhook', huge, headers), 400);
  assertEquals(w.books.writes, 0);
});

Deno.test('a lifetime purchase is recorded for the household, with what RevenueCat says', async () => {
  const w = world();
  const logs = await logsOf(async () => {
    await expect(await w.deliver(purchase({ app_user_id: HOME.toUpperCase() })), 200, {
      status: 'granted',
    });
  });
  const [row] = w.books.rows.values();
  assertEquals(row.purchase, {
    store: 'apple',
    transactionId: '2000000812345678',
    latestTransactionId: '2000000812345679',
    productId: lifetimeProductId,
    plan: 'lifetime',
    kind: 'premium',
    environment: 'Sandbox',
    purchasedAt: new Date(NOW.getTime() - 5_000),
    eventAt: NOW,
    subscription: null,
    price: 9.99,
    currency: 'EUR',
    country: 'DE',
    appUserId: HOME,
  });
  assertEquals(logs, [JSON.stringify({ fn: 'purchases', region: 'eu-central-1' })]);
});

Deno.test('Play purchases are google, production ones Production; INITIAL_PURCHASE counts', async () => {
  const w = world();
  await expect(
    await w.deliver(purchase({
      type: 'INITIAL_PURCHASE',
      store: 'PLAY_STORE',
      environment: 'PRODUCTION',
      transaction_id: 'GPA.3333-4444-5555-66666',
      original_transaction_id: undefined,
      price_in_purchased_currency: -1,
      currency: 'eur',
      country_code: 'AUT',
    })),
    200,
    { status: 'granted' },
  );
  const [row] = w.books.rows.values();
  assertEquals(
    [row.purchase.store, row.purchase.transactionId, row.purchase.latestTransactionId],
    ['google', 'GPA.3333-4444-5555-66666', 'GPA.3333-4444-5555-66666'],
  );
  assertEquals(
    [row.purchase.environment, row.purchase.price, row.purchase.currency, row.purchase.country],
    ['Production', null, null, null],
  );
});

Deno.test('a duplicate delivery changes nothing', async () => {
  const w = world();
  const event = purchase();
  await expect(await w.deliver(event), 200, { status: 'granted' });
  await expect(await w.deliver(event), 200, { status: 'duplicate' });
  await expect(await w.deliver(of('TEST', { id: 'test-1' })), 200, { status: 'ignored' });
  await expect(await w.deliver(of('TEST', { id: 'test-1' })), 200, { status: 'duplicate' });
  assertEquals(w.books.writes, 1);
  // Another event for the same purchase (a restore) is no new one.
  await expect(await w.deliver(purchase()), 200, { status: 'restored' });
});

Deno.test('a failed write leaves the event unprocessed, so RevenueCat retries it', async () => {
  const w = world();
  const event = purchase();
  w.books.fail = new Error('connection reset');
  await assertRejects(() => w.deliver(event), Error, 'connection reset');
  w.books.fail = null;
  await expect(await w.deliver(event), 200, { status: 'granted' });
});

Deno.test('refused purchases unlock nothing and are logged without ids', async () => {
  const w = world();
  const cases: [Record<string, unknown>, string][] = [
    [purchase({ is_family_share: true }), 'family_share'],
    [purchase({ app_user_id: '$RCAnonymousID:8f3e0a1b2c3d4e5f' }), 'app_user_id'],
    [purchase({ app_user_id: PETER.slice(1) }), 'app_user_id'],
    [purchase({ product_id: 'com.snacklist.app.plus' }), 'product'],
    [purchase({ product_id: 'toString' }), 'product'],
    [purchase({ store: 'STRIPE' }), 'store'],
    // A promotional grant of another entitlement (premium's are read from the API, below).
    [purchase({ store: 'PROMOTIONAL' }), 'entitlement'],
    [purchase({ environment: 'XCODE' }), 'malformed'],
    [purchase({ transaction_id: null, original_transaction_id: null }), 'malformed'],
  ];
  for (const [event, refused] of cases) {
    const logs = await logsOf(async () => {
      await expect(await w.deliver(event), 200, { status: 'ignored' });
    });
    assertEquals(logs.slice(1), [
      JSON.stringify({ fn: 'purchases', event: 'NON_RENEWING_PURCHASE', refused }),
    ]);
  }
  assertEquals(w.books.writes, 0);
  assertEquals(w.books.eventIds.size, cases.length);
});

Deno.test('a purchase another household owns is not granted here, and is logged', async () => {
  const w = world();
  await w.deliver(purchase({ app_user_id: OTHER }));
  const logs = await logsOf(async () => {
    await expect(await w.deliver(purchase()), 200, { status: 'used_elsewhere' });
  });
  assertEquals(
    logs[1],
    JSON.stringify({ fn: 'purchases', event: 'NON_RENEWING_PURCHASE', refused: 'used_elsewhere' }),
  );
  assert(!logs.join().includes('2000000812345678') && !logs.join().includes(HOME));
});

Deno.test('TRANSFER never moves an unlock; it is logged by type alone', async () => {
  const w = world();
  await w.deliver(purchase());
  const logs = await logsOf(async () => {
    await expect(
      await w.deliver(of('TRANSFER', { transferred_from: [HOME], transferred_to: [OTHER] })),
      200,
      { status: 'ignored' },
    );
  });
  assertEquals(logs.slice(1), [JSON.stringify({ fn: 'purchases', event: 'TRANSFER' })]);
  assertEquals(w.books.writes, 1);
  assertEquals([...w.books.rows.values()][0].purchase.appUserId, HOME);
});

Deno.test('other event types are acknowledged and ignored', async () => {
  const w = world();
  for (
    const type of [
      'TEST',
      'TEMPORARY_ENTITLEMENT_GRANT',
      'EXPIRATION',
      'UNCANCELLATION',
      'BILLING_ISSUE',
      'SUBSCRIPTION_PAUSED',
      'PRODUCT_CHANGE',
      'SOMETHING_NEW',
    ]
  ) {
    await expect(await w.deliver(of(type)), 200, { status: 'ignored' });
  }
  assertEquals(w.books.writes, 0);
});

Deno.test('a refund takes the unlock away once, with one purchase_refunded', async () => {
  const w = world();
  await w.deliver(purchase());
  await expect(
    await w.handle('/claim', {
      store: 'apple',
      householdId: HOME,
      transactionId: '2000000812345679',
    }, {
      authorization: 'Bearer peter',
    }),
    200,
    { status: 'recorded' },
  );
  const refund = { cancel_reason: 'CUSTOMER_SUPPORT', event_timestamp_ms: NOW.getTime() };
  await expect(await w.deliver(of('CANCELLATION', refund)), 200, { status: 'revoked' });
  await expect(await w.deliver(of('CANCELLATION', refund)), 200, { status: 'unchanged' });
  assertEquals(w.sent.map((e) => e.name), ['purchase_completed', 'purchase_refunded']);
  assertEquals(w.sent[1].sale.transactionId, '2000000812345678');
  await expect(await w.deliver(of('REFUND_REVERSED')), 200, { status: 'reinstated' });
  await expect(await w.deliver(of('REFUND_REVERSED')), 200, { status: 'unchanged' });
  assertEquals(w.sent.length, 2);
  // A refund of a product we don't sell is not ours.
  await expect(await w.deliver(of('CANCELLATION', { product_id: 'other.product' })), 200, {
    status: 'ignored',
  });
});

Deno.test('a refund without a known buyer sends nothing', async () => {
  const w = world();
  await w.deliver(purchase());
  await expect(await w.deliver(of('CANCELLATION')), 200, { status: 'revoked' });
  assertEquals(w.sent, []);
});

Deno.test('the claim needs the app session in the household and a store transaction', async () => {
  const w = world();
  const body = { store: 'apple', householdId: HOME, transactionId: '2000000812345678' };
  await expect(await w.handle('/claim', body), 401, { error: 'missing_token' });
  await expect(await w.handle('/claim', body, { authorization: 'Bearer fgp_x' }), 403, {
    error: 'session_required',
  });
  for (
    const bad of [
      {},
      { store: 'stripe', householdId: HOME, transactionId: '1' },
      { store: 'apple' },
      { store: 'apple', householdId: HOME, transactionId: '' },
      { store: 'apple', householdId: HOME, transactionId: 7 },
      { store: 'google', householdId: HOME, transactionId: 'x'.repeat(201) },
      { store: 'apple', transactionId: '1' },
      { store: 'apple', householdId: 'home', transactionId: '1' },
      { store: 'apple', householdId: HOME.toUpperCase(), transactionId: '1' },
    ]
  ) {
    await expect(await w.handle('/claim', bad, { authorization: 'Bearer peter' }), 400);
  }
  await expect(await w.handle('/claim', 'nope', { authorization: 'Bearer peter' }), 400);
  w.books.members.delete(PETER);
  await expect(await w.handle('/claim', body, { authorization: 'Bearer peter' }), 403, {
    error: 'no_household',
  });
});

Deno.test('the claim names the household the app bought for, not the one the user is in', async () => {
  const asked: string[] = [];
  const w = world();
  const inner = w.books.claim.bind(w.books);
  w.books.claim = (user, household, store, tx) => {
    asked.push(household);
    return inner(user, household, store, tx);
  };
  // Peter bought for OTHER (the fake's membership at the time of buying), then switched to HOME.
  w.books.members.set(PETER, OTHER);
  await w.deliver(purchase({ app_user_id: OTHER }));
  await expect(
    await w.handle('/claim', {
      store: 'apple',
      householdId: OTHER,
      transactionId: '2000000812345678',
    }, {
      authorization: 'Bearer peter',
    }),
    200,
    { status: 'recorded' },
  );
  assertEquals(asked, [OTHER]);
  assertEquals(w.sent.map((e) => [e.name, e.sale.householdId]), [['purchase_completed', OTHER]]);
});

Deno.test('the claim is rate limited', async () => {
  const w = world({ takeCall: () => Promise.resolve(false) });
  await expect(
    await w.handle('/claim', { store: 'google', householdId: HOME, transactionId: 'GPA.1' }, {
      authorization: 'Bearer peter',
    }),
    429,
    { error: 'rate_limited' },
  );
  assertEquals(w.books.claims.size, 0);
});

Deno.test('the claim is 503 busy for an account being deleted and for claims still waiting', async () => {
  const busy = Object.assign(new Error('lock'), { name: 'PostgresError', code: '55P03' });
  for (
    const overrides of [
      { takeCall: () => Promise.reject(busy) },
      { claim: () => Promise.reject(new OutOfTime()) },
    ] satisfies Partial<Deps>[]
  ) {
    const w = world(overrides);
    await expect(
      await w.handle('/claim', { store: 'google', householdId: HOME, transactionId: 'GPA.1' }, {
        authorization: 'Bearer peter',
      }),
      503,
      { error: 'busy' },
    );
    assertEquals(w.books.claims.size, 0);
    assertEquals(w.sent, []);
  }
});

Deno.test('the claim works while the webhook is not configured', async () => {
  const w = world({ webhook: null });
  await expect(
    await w.handle('/claim', { store: 'apple', householdId: HOME, transactionId: '1' }, {
      authorization: 'Bearer peter',
    }),
    200,
    { status: 'waiting' },
  );
});

Deno.test('purchase_completed goes out once: claim first, then the webhook', async () => {
  const w = world();
  const claim = (who: string, tx = '2000000812345679') =>
    w.handle('/claim', { store: 'apple', householdId: HOME, transactionId: tx }, {
      authorization: `Bearer ${who}`,
    });
  await expect(await claim('peter'), 200, { status: 'waiting' });
  assertEquals(w.sent, []);
  await expect(await w.deliver(purchase()), 200, { status: 'granted' });
  await expect(await w.deliver(purchase()), 200, { status: 'restored' });
  await expect(await claim('peter'), 200, { status: 'recorded' });
  await expect(await claim('lea', '2000000812345678'), 200, { status: 'taken' });
  assertEquals(w.sent.map((e) => [e.name, e.sale.transactionId, e.subject]), [[
    'purchase_completed',
    '2000000812345678',
    { installId: INSTALL, householdId: HOME, internal: true },
  ]]);
  assertEquals([w.sent[0].sale.price, w.sent[0].sale.currency], [9.99, 'EUR']);
});

Deno.test('purchase_completed goes out once: the webhook first, then the claim', async () => {
  const w = world();
  const claim = () =>
    w.handle('/claim', { store: 'apple', householdId: HOME, transactionId: '2000000812345679' }, {
      authorization: 'Bearer lea',
    });
  await expect(await w.deliver(purchase()), 200, { status: 'granted' });
  assertEquals(w.sent, []);
  await expect(await claim(), 200, { status: 'recorded' });
  await expect(await claim(), 200, { status: 'recorded' });
  await expect(await w.deliver(purchase()), 200, { status: 'restored' });
  assertEquals(w.sent.map((e) => [e.name, e.sale.householdId]), [['purchase_completed', HOME]]);
  assertEquals(w.calls, [LEA, LEA]);
});

Deno.test("a claim for another household's purchase is not its buyer", async () => {
  const w = world();
  await w.deliver(purchase({ app_user_id: OTHER }));
  await expect(
    await w.handle('/claim', {
      store: 'apple',
      householdId: HOME,
      transactionId: '2000000812345678',
    }, {
      authorization: 'Bearer peter',
    }),
    200,
    { status: 'elsewhere' },
  );
  assertEquals(w.sent, []);
});

Deno.test("production purchases are revenue, unless a tester's", async () => {
  const w = world();
  const claim = () =>
    w.handle('/claim', { store: 'apple', householdId: HOME, transactionId: '2000000812345678' }, {
      authorization: 'Bearer peter',
    });
  await w.deliver(purchase({ environment: 'PRODUCTION' }));
  await claim();
  w.books.testers.add(PETER);
  const tx = { transaction_id: 't2', original_transaction_id: 't2' };
  await w.deliver(purchase({ environment: 'PRODUCTION', ...tx }));
  await w.handle('/claim', { store: 'apple', householdId: HOME, transactionId: 't2' }, {
    authorization: 'Bearer peter',
  });
  await w.deliver(of('CANCELLATION', { environment: 'PRODUCTION', ...tx }));
  assertEquals(w.sent.map((e) => [e.name, e.subject.internal]), [
    ['purchase_completed', false],
    ['purchase_completed', true],
    ['purchase_refunded', true],
  ]);
});

Deno.test('the claim before the webhook makes the buyer a tester: internal', async () => {
  const w = world();
  w.books.testers.add(PETER);
  await w.handle(
    '/claim',
    { store: 'apple', householdId: HOME, transactionId: '2000000812345678' },
    {
      authorization: 'Bearer peter',
    },
  );
  await w.deliver(purchase({ environment: 'PRODUCTION' }));
  assertEquals(w.sent.map((e) => e.subject.internal), [true]);
});

Deno.test('no event for a buyer without analytics consent', async () => {
  const w = world({ subject: () => Promise.resolve(null) });
  await w.deliver(purchase());
  await w.handle(
    '/claim',
    { store: 'apple', householdId: HOME, transactionId: '2000000812345678' },
    {
      authorization: 'Bearer peter',
    },
  );
  assertEquals(w.sent, []);
});

Deno.test('analytics failing never fails the purchase', async () => {
  const reported: unknown[] = [];
  const w = world({
    event: () => Promise.reject(new Error('posthog down')),
    report: (e) => reported.push(e),
  });
  await w.deliver(purchase());
  await expect(
    await w.handle('/claim', {
      store: 'apple',
      householdId: HOME,
      transactionId: '2000000812345678',
    }, {
      authorization: 'Bearer peter',
    }),
    200,
    { status: 'recorded' },
  );
  assertEquals(reported.length, 1);
});

Deno.test('test events exist only inside a local stack', async () => {
  const body = { appUserId: HOME, transactionId: 'fake-1' };
  await expect(await world().handle('/test/event', body), 404, { error: 'not_found' });
  await expect(await world().handle('/test/sign', body), 404);
  const w = world({ local: true });
  await expect(await w.handle('/test/event', body), 200, { status: 'granted' });
  await expect(await w.handle('/test/event', body), 200, { status: 'restored' });
  await expect(await w.handle('/test/event', { ...body, type: 'CANCELLATION' }), 200, {
    status: 'revoked',
  });
  await expect(await w.handle('/test/event', { ...body, type: 'REFUND_REVERSED' }), 200, {
    status: 'reinstated',
  });
  await expect(await w.handle('/test/event', { ...body, type: 'TRANSFER' }), 200, {
    status: 'ignored',
  });
  await expect(
    await w.handle('/test/event', {
      appUserId: OTHER,
      transactionId: 'fake-2',
      store: 'PLAY_STORE',
      environment: 'PRODUCTION',
    }),
    200,
    { status: 'granted' },
  );
  const play = w.books.rows.get('google:fake-2')!.purchase;
  assertEquals([play.environment, play.appUserId, play.price], ['Production', OTHER, 29.99]);
  await expect(
    await w.handle('/test/event', { ...body, isFamilyShare: true, transactionId: 'f3' }),
    200,
    {
      status: 'ignored',
    },
  );
  await expect(await w.handle('/test/event', { ...body, appUserId: 'not-a-household' }), 200, {
    status: 'ignored',
  });
  for (
    const bad of [
      {},
      { appUserId: HOME },
      { ...body, type: 'TEST' },
      { ...body, store: 'STRIPE' },
      { ...body, environment: 'XCODE' },
      { ...body, isFamilyShare: 'yes' },
    ]
  ) {
    await expect(await w.handle('/test/event', bad), 400);
  }
});

Deno.test('unknown routes and methods are 404', async () => {
  const w = world();
  await expect(await w.handle('/verify', {}), 404);
  await expect(await w.handle('/apple/notifications', {}), 404);
  await expect(await w.handle('/claim'), 404);
});

Deno.test('the webhook lives at /purchases/revenuecat/webhook only (ADDENDUM 6)', async () => {
  const w = world();
  const raw = JSON.stringify({ api_version: '1.0', event: purchase() });
  await expect(await w.handle('', raw, { authorization: AUTH }), 404, { error: 'not_found' });
  await expect(await w.handle('/revenuecat/webhook', raw, { authorization: AUTH }), 200, {
    status: 'granted',
  });
});

Deno.test("the deletion route skips without RevenueCat's key, and reports a failed run", async () => {
  const cron = { 'x-deletions-secret': DELETIONS_SECRET };
  await expect(await world().handle('/revenuecat/deletions', {}, cron), 200, {
    status: 'not_configured',
  });
  const ok = { due: 1, deleted: 1, pending: 0, failed: 0 };
  const done = world({ deleteDueCustomers: () => Promise.resolve(ok) });
  await expect(await done.handle('/revenuecat/deletions', {}, cron), 200, ok);
  const failed = { due: 1, deleted: 0, pending: 0, failed: 1 };
  const broken = world({ deleteDueCustomers: () => Promise.resolve(failed) });
  await expect(await broken.handle('/revenuecat/deletions', {}, cron), 502, failed);
});

Deno.test('the deletion route runs only with the cron secret, and not at all without one', async () => {
  let runs = 0;
  const run = () => {
    runs++;
    return Promise.resolve({ due: 0, deleted: 0, pending: 0, failed: 0 });
  };
  const w = world({ deleteDueCustomers: run });
  await expect(await w.handle('/revenuecat/deletions', {}), 401, { error: 'invalid_token' });
  await expect(
    await w.handle('/revenuecat/deletions', {}, { 'x-deletions-secret': `${DELETIONS_SECRET}x` }),
    401,
    { error: 'invalid_token' },
  );
  await expect(
    await w.handle('/revenuecat/deletions', {}, { authorization: `Bearer ${DELETIONS_SECRET}` }),
    401,
  );
  assertEquals(runs, 0);
  await expect(
    await w.handle('/revenuecat/deletions', {}, { 'x-deletions-secret': DELETIONS_SECRET }),
    200,
  );
  assertEquals(runs, 1);
  const unset = world({ deleteDueCustomers: run, deletionsSecret: null });
  await expect(await unset.handle('/revenuecat/deletions', {}, { 'x-deletions-secret': '' }), 503, {
    error: 'not_configured',
  });
  assertEquals(runs, 1);
});

Deno.test('routes match exactly: the documented webhook path reaches the webhook, near misses do not', async () => {
  assertEquals(routes.webhook, webhookPath);
  const raw = JSON.stringify({ api_version: '1.0', event: purchase() });
  const at = (url: string) =>
    createHandler(world().deps)(
      new Request(url, { method: 'POST', headers: { authorization: AUTH }, body: raw }),
    );
  await expect(await at(`http://localhost/functions/v1${webhookPath}`), 200, { status: 'granted' });
  await expect(await at(`http://localhost${webhookPath}`), 200, { status: 'granted' });
  await expect(await at(`http://localhost/functions/v1${webhookPath}/`), 200, {
    status: 'granted',
  });
  for (
    const miss of [
      `/functions/v1${webhookPath}s`,
      `/functions/v1${webhookPath}/x`,
      `/functions/v1/x${webhookPath}`,
      `/functions/v1/purchases/purchases/revenuecat/webhook`,
      `/functions/v1/purchases/revenuecat/Webhook`,
      `/functions/v1/purchases/revenuecat`,
    ]
  ) {
    await expect(await at(`http://localhost${miss}`), 404, { error: 'not_found' });
  }
});

/** A yearly subscription event as RevenueCat sends it. */
function yearly(type: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return purchase({
    type,
    product_id: 'com.snacklist.app.yearly',
    entitlement_ids: ['premium'],
    transaction_id: '2000000900000002',
    original_transaction_id: '2000000900000001',
    expiration_at_ms: NOW.getTime() + 365 * 86_400_000,
    ...overrides,
  });
}

Deno.test('a yearly plan is recorded with its end; entitlement ids old or new both work', async () => {
  const w = world();
  for (const ids of [['premium'], ['lifetime'], []]) {
    const id = `tx-${ids.join('')}`;
    await expect(
      await w.deliver(yearly('INITIAL_PURCHASE', {
        entitlement_ids: ids,
        original_transaction_id: id,
      })),
      200,
      { status: 'granted' },
    );
    const p = w.books.rows.get(`apple:${id}`)!.purchase;
    assertEquals([p.plan, p.kind, p.productId], ['yearly', 'premium', 'com.snacklist.app.yearly']);
    assertEquals(p.subscription, {
      expiresAt: new Date(NOW.getTime() + 365 * 86_400_000),
      autoRenew: true,
      billingIssue: false,
    });
  }
});

Deno.test("Play's subscription:basePlan id is the yearly plan; another base plan is ignored", async () => {
  const w = world();
  await expect(
    await w.deliver(yearly('INITIAL_PURCHASE', {
      store: 'PLAY_STORE',
      product_id: 'com.snacklist.app.yearly:yearly',
      original_transaction_id: 'GPA.1234-5678-9012-34567',
      transaction_id: 'GPA.1234-5678-9012-34567',
    })),
    200,
    { status: 'granted' },
  );
  assertEquals(
    w.books.rows.get('google:GPA.1234-5678-9012-34567')!.purchase.productId,
    'com.snacklist.app.yearly',
  );
  const logs = await logsOf(async () => {
    await expect(
      await w.deliver(
        yearly('INITIAL_PURCHASE', { product_id: 'com.snacklist.app.yearly:monthly' }),
      ),
      200,
      { status: 'ignored' },
    );
  });
  assertEquals(logs.slice(1), [
    JSON.stringify({ fn: 'purchases', event: 'INITIAL_PURCHASE', refused: 'product' }),
  ]);
});

Deno.test('a renewal is a record of the same transaction, never a second purchase_completed', async () => {
  const w = world();
  await w.deliver(yearly('INITIAL_PURCHASE'));
  await w.handle('/claim', {
    store: 'apple',
    householdId: HOME,
    transactionId: '2000000900000001',
  }, { authorization: 'Bearer peter' });
  assertEquals(w.sent.map((e) => e.name), ['purchase_completed']);
  await expect(
    await w.deliver(yearly('RENEWAL', { transaction_id: '2000000900000003' })),
    200,
    { status: 'restored' },
  );
  assertEquals(w.sent.map((e) => e.name), ['purchase_completed']);
  assertEquals(w.books.rows.size, 1);
});

Deno.test('lifecycle events update the plan by transaction and log no reasons (H-87)', async () => {
  const w = world();
  await w.deliver(yearly('INITIAL_PURCHASE'));
  const logs = await logsOf(async () => {
    for (
      const reason of [
        'UNSUBSCRIBE',
        'BILLING_ERROR',
        'DEVELOPER_INITIATED',
        'PRICE_INCREASE',
        'UNKNOWN',
      ]
    ) {
      await expect(await w.deliver(yearly('CANCELLATION', { cancel_reason: reason })), 200, {
        status: 'updated',
      });
    }
    await expect(
      await w.deliver(yearly('EXPIRATION', { expiration_reason: 'BILLING_ERROR' })),
      200,
      { status: 'updated' },
    );
  });
  assertEquals(w.books.lifecycles.length, 6);
  assert(w.books.lifecycles.slice(0, 5).every((c) => c.state.autoRenew === false));
  assert(logs.every((l) => !/UNSUBSCRIBE|BILLING_ERROR|reason/.test(l)), logs.join('\n'));
  assertEquals(w.sent, []);
});

Deno.test('a lifecycle event for an unknown transaction writes nothing and grants nothing', async () => {
  const w = world();
  const old = yearly('EXPIRATION', { event_timestamp_ms: NOW.getTime() - 3 * 3_600_000 });
  const logs = await logsOf(async () => {
    await expect(await w.deliver(old), 200, { status: 'unknown' });
  });
  assertEquals(logs.slice(1), [
    JSON.stringify({ fn: 'purchases', event: 'EXPIRATION', lifecycle: 'unknown' }),
  ]);
  assertEquals(w.books.rows.size, 0);
  await expect(await w.deliver(old), 200, { status: 'duplicate' });
});

Deno.test('a recent lifecycle event before its purchase is refused unstored, so RevenueCat delivers it again', async () => {
  const w = world();
  const billing = yearly('BILLING_ISSUE', { event_timestamp_ms: NOW.getTime() - 3_600_000 });
  const logs = await logsOf(async () => {
    await expect(await w.deliver(billing), 503, { error: 'not_recorded_yet' });
  });
  assertEquals(logs.slice(1), [
    JSON.stringify({ fn: 'purchases', event: 'BILLING_ISSUE', lifecycle: 'not_recorded_yet' }),
  ]);
  assertEquals(w.books.eventIds.has(billing.id as string), false);
  await w.deliver(yearly('INITIAL_PURCHASE', { event_timestamp_ms: NOW.getTime() - 7_200_000 }));
  await expect(await w.deliver(billing), 200, { status: 'updated' });
  assertEquals(w.books.lifecycles.at(-1)?.state.billingIssue, true);
});

Deno.test('a refund of the yearly plan (CUSTOMER_SUPPORT) revokes it with purchase_refunded', async () => {
  const w = world();
  await w.deliver(yearly('INITIAL_PURCHASE'));
  await w.handle('/claim', {
    store: 'apple',
    householdId: HOME,
    transactionId: '2000000900000001',
  }, { authorization: 'Bearer peter' });
  await expect(
    await w.deliver(yearly('CANCELLATION', { cancel_reason: 'CUSTOMER_SUPPORT' })),
    200,
    {
      status: 'revoked',
    },
  );
  assertEquals(w.sent.map((e) => [e.name, e.sale.plan]), [
    ['purchase_completed', 'yearly'],
    ['purchase_refunded', 'yearly'],
  ]);
});

Deno.test('a second yearly plan in a household is recorded and flagged in the log', async () => {
  const w = world();
  w.books.record = (p) =>
    Promise.resolve({
      outcome: 'granted',
      alreadyUnlocked: true,
      householdGone: false,
      internal: false,
      buyer: null,
      sendCompleted: false,
      secondYearly: p.plan === 'yearly',
      householdId: p.appUserId,
    });
  const logs = await logsOf(async () => {
    await expect(await w.deliver(yearly('INITIAL_PURCHASE')), 200, { status: 'granted' });
  });
  assertEquals(logs.slice(1), [
    JSON.stringify({ fn: 'purchases', event: 'INITIAL_PURCHASE', flag: 'second_yearly' }),
  ]);
});

Deno.test('TRANSFER of a yearly plan moves nothing', async () => {
  const w = world();
  await w.deliver(yearly('INITIAL_PURCHASE'));
  await expect(
    await w.deliver(yearly('TRANSFER', { transferred_from: [HOME], transferred_to: [OTHER] })),
    200,
    { status: 'ignored' },
  );
  assertEquals(w.books.writes, 1);
  assertEquals(w.books.lifecycles, []);
});

/** A promotional grant's event as RevenueCat sends it: no app_id, no price, period PROMOTIONAL. */
function promo(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: crypto.randomUUID().toUpperCase(),
    type: 'NON_RENEWING_PURCHASE',
    app_user_id: HOME,
    original_app_user_id: HOME,
    aliases: [HOME],
    store: 'PROMOTIONAL',
    environment: 'PRODUCTION',
    product_id: 'rc_promo_premium_custom',
    entitlement_ids: ['premium'],
    period_type: 'PROMOTIONAL',
    transaction_id: null,
    original_transaction_id: null,
    purchased_at_ms: NOW.getTime() - 5_000,
    event_timestamp_ms: NOW.getTime(),
    expiration_at_ms: NOW.getTime() + 30 * 86_400_000,
    price: 0,
    currency: null,
    subscriber_attributes: {},
    ...overrides,
  };
}

Deno.test('a promotional premium grant stores what RevenueCat has now, no purchase, no event', async () => {
  const w = world();
  const until = new Date(NOW.getTime() + 30 * 86_400_000);
  w.books.granted.set(HOME, { active: true, expiresAt: until });
  await expect(await w.deliver(promo()), 200, { status: 'granted' });
  assertEquals(w.books.promoRows.get(HOME), until);
  assertEquals(w.books.rows.size, 0);
  assertEquals(w.sent, []);
  // A lifetime grant (no end) replaces it; the payload's own expiry is never trusted.
  w.books.granted.set(HOME, { active: true, expiresAt: null });
  await expect(await w.deliver(promo({ expiration_at_ms: until.getTime() })), 200, {
    status: 'updated',
  });
  assertEquals(w.books.promoRows.get(HOME), null);
});

Deno.test('a promotional grant revoked or expired ends premium, whatever the event says', async () => {
  for (const [type, reason] of [['CANCELLATION', 'DEVELOPER_INITIATED'], ['EXPIRATION', null]]) {
    const w = world();
    w.books.granted.set(HOME, { active: true, expiresAt: null });
    await expect(await w.deliver(promo()), 200, { status: 'granted' });
    w.books.granted.set(HOME, { active: false });
    await expect(await w.deliver(promo({ type, cancel_reason: reason })), 200, {
      status: 'removed',
    });
    assertEquals(w.books.promoRows.has(HOME), false, String(type));
    // A grant delivered late, after RevenueCat revoked it, grants nothing.
    await expect(await w.deliver(promo()), 200, { status: 'unchanged' });
    assertEquals(w.books.promoRows.has(HOME), false);
  }
});

Deno.test("another entitlement's promotional grant and a non-household id are ignored unread", async () => {
  const w = world();
  w.books.granted.set(HOME, { active: true, expiresAt: null });
  await expect(await w.deliver(promo({ entitlement_ids: ['pro'] })), 200, { status: 'ignored' });
  await expect(await w.deliver(promo({ app_user_id: '$RCAnonymousID:8d1f0c2b' })), 200, {
    status: 'ignored',
  });
  await expect(await w.deliver(promo({ app_user_id: 'peter@example.com' })), 200, {
    status: 'ignored',
  });
  assertEquals(w.books.apiReads, 0);
  assertEquals(w.books.promoRows.size, 0);
});

Deno.test('a promotional event is idempotent, and for an unknown household stores nothing', async () => {
  const w = world();
  w.books.granted.set(HOME, { active: true, expiresAt: null });
  const e = promo();
  await expect(await w.deliver(e), 200, { status: 'granted' });
  await expect(await w.deliver(e), 200, { status: 'duplicate' });
  assertEquals(w.books.apiReads, 1);
  const gone = '00000000-0000-4000-8000-00000000dead';
  await expect(await w.deliver(promo({ app_user_id: gone })), 200, { status: 'no_household' });
  assertEquals(w.books.promoRows.has(gone), false);
});

Deno.test("RevenueCat's API down or its key unset: 502/503 and the event is delivered again", async () => {
  const w = world();
  w.books.granted.set(HOME, { active: true, expiresAt: null });
  w.books.revenueCatDown = true;
  const e = promo();
  await expect(await w.deliver(e), 502, { error: 'revenuecat_unavailable' });
  assertEquals(w.books.promoRows.size, 0);
  w.books.revenueCatDown = false;
  await expect(await w.deliver(e), 200, { status: 'granted' });
  const unset = world({ reconcile: null });
  await expect(await unset.deliver(promo()), 503, { error: 'not_configured' });
  assertEquals(unset.books.apiReads, 0);
  // A store purchase doesn't need the key.
  await expect(await unset.deliver(purchase()), 200, { status: 'granted' });
});

Deno.test('the promotional webhook keeps the signature check', async () => {
  const w = world({ webhook: { authorization: AUTH, signingSecret: SIGNING } });
  w.books.granted.set(HOME, { active: true, expiresAt: null });
  await expect(await w.deliver(promo()), 401, { error: 'bad_signature' });
  assertEquals(w.books.apiReads, 0);
  await expect(await w.deliver(promo(), { signed: true }), 200, { status: 'granted' });
});

Deno.test('the reconcile route: only with the Ops secret, a household id, and the key', async () => {
  const ops = { 'x-deletions-secret': DELETIONS_SECRET };
  const w = world();
  w.books.granted.set(HOME, { active: true, expiresAt: null });
  await expect(await w.handle('/revenuecat/reconcile', { householdId: HOME }), 401, {
    error: 'invalid_token',
  });
  await expect(
    await w.handle('/revenuecat/reconcile', { householdId: HOME }, { authorization: AUTH }),
    401,
  );
  assertEquals(w.books.apiReads, 0);
  await expect(await w.handle('/revenuecat/reconcile', { householdId: 'x' }, ops), 400);
  await expect(await w.handle('/revenuecat/reconcile', { householdId: HOME }, ops), 200, {
    status: 'granted',
  });
  await expect(await w.handle('/revenuecat/reconcile', { householdId: HOME }, ops), 200, {
    status: 'unchanged',
  });
  w.books.revenueCatDown = true;
  await expect(await w.handle('/revenuecat/reconcile', { householdId: HOME }, ops), 502);
  await expect(
    await world({ reconcile: null }).handle('/revenuecat/reconcile', { householdId: HOME }, ops),
    503,
  );
  await expect(
    await world({ deletionsSecret: null }).handle('/revenuecat/reconcile', { householdId: HOME }, {
      'x-deletions-secret': '',
    }),
    503,
  );
});
