import { assert, assertEquals, assertStringIncludes, assertThrows } from 'jsr:@std/assert@^1';
import {
  type Account,
  accountsQuery,
  type Deps,
  parseAccounts,
  parseArgs,
  parseLock,
  reconciled,
  run,
  selectionRule,
  stepFor,
  type Tally,
} from './beta-lifetime.ts';
import {
  type PromotionalPremium,
  RevenueCatUnavailable,
} from '../../supabase/functions/purchases/promotional.ts';

const user = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const forGood: PromotionalPremium = { active: true, expiresAt: new Date('2100-01-01T00:00:00Z') };
const none: PromotionalPremium = { active: false };
const cutoff = new Date('2026-12-01T00:00:00Z');
const now = new Date('2026-12-02T09:00:00Z');
const base = { cutoff, usedBefore: null, now, pauseMs: 0 };

Deno.test('stepFor: done only when RevenueCat grants for good and the row is stored', () => {
  assertEquals(stepFor({ active: true, expiresAt: null }, true), 'done');
  assertEquals(stepFor(forGood, false), 'reconcile');
  assertEquals(
    stepFor({ active: true, expiresAt: new Date('2027-06-30T00:00:00Z') }, true),
    'grant',
  );
  assertEquals(stepFor(none, false), 'grant');
  // promotionalOf reports an expired grant as none.
  assertEquals(stepFor(none, true), 'grant');
});

/** A fake RevenueCat and purchases function over [state]; records every write. */
function fake(
  accounts: Account[],
  state: Map<string, PromotionalPremium>,
  opts: {
    grantFails?: string;
    reconcileAnswers?: Map<string, number>;
    revenueCat?: boolean;
    lock?: { on: boolean; since: Date | null };
    usedBefores?: Date[];
  } = {},
) {
  const calls: string[] = [];
  const lines: string[] = [];
  const stored = new Set(accounts.filter((a) => a.stored).map((a) => a.id));
  const deps: Deps = {
    lock: () => Promise.resolve(opts.lock ?? { on: false, since: null }),
    accounts: (c, u) => {
      assertEquals(c, cutoff);
      opts.usedBefores?.push(u);
      return Promise.resolve(accounts.map((a) => ({ id: a.id, stored: stored.has(a.id) })));
    },
    atRevenueCat: opts.revenueCat === false ? null : (id) => Promise.resolve(state.get(id) ?? none),
    grant: (id) => {
      calls.push(`grant ${id}`);
      if (id === opts.grantFails) return Promise.reject(new RevenueCatUnavailable(429));
      state.set(id, forGood);
      return Promise.resolve();
    },
    reconcile: (id) => {
      calls.push(`reconcile ${id}`);
      const status = opts.reconcileAnswers?.get(id) ?? 200;
      if (status === 200 && grantedFor(state.get(id))) stored.add(id);
      return Promise.resolve({ status, stored: status === 200 });
    },
    pause: () => Promise.resolve(),
    log: (line) => lines.push(line),
  };
  return {
    deps,
    calls,
    lines,
    accountsNow: () => accounts.map((a) => ({ ...a, stored: stored.has(a.id) })),
  };
}

const grantedFor = (p: PromotionalPremium | undefined) => p?.active === true;

function mixed() {
  const accounts: Account[] = [
    { id: user(1), stored: true },
    { id: user(2), stored: false },
    { id: user(3), stored: false },
    { id: user(4), stored: false },
    { id: user(5), stored: false },
  ];
  const state = new Map<string, PromotionalPremium>([
    [user(1), forGood],
    [user(2), { active: true, expiresAt: null }],
    [user(3), { active: true, expiresAt: new Date('2027-01-01T00:00:00Z') }],
  ]);
  return { accounts, state };
}

const noIds = (lines: string[]) => {
  for (const line of lines) assert(!/[0-9a-f]{8}-[0-9a-f]{4}-/.test(line), `id in "${line}"`);
};

Deno.test('run: a dry run reads RevenueCat and writes nothing', async () => {
  const { accounts, state } = mixed();
  const f = fake(accounts, state);
  const tally = await run(f.deps, { ...base, apply: false });
  assertEquals(f.calls, []);
  assertEquals(
    tally,
    {
      accounts: 5,
      done: 1,
      reconcile: 1,
      grant: 3,
      granted: 0,
      reconciled: 0,
      failed: 0,
    } satisfies Tally,
  );
  noIds(f.lines);
});

Deno.test('run: a dry run without RevenueCat keys only counts the accounts', async () => {
  const { accounts, state } = mixed();
  const f = fake(accounts, state, { revenueCat: false });
  const tally = await run(f.deps, { ...base, apply: false });
  assertEquals(f.calls, []);
  assertEquals(tally.accounts, 5);
  assertEquals(tally.done + tally.reconcile + tally.grant, 0);
  assertStringIncludes(f.lines.join('\n'), 'RevenueCat not checked');
  assertStringIncludes(
    f.lines.join('\n'),
    'before 2026-12-01T00:00:00.000Z or using MCP or the API before 2026-12-02T09:00:00.000Z: 5',
  );
});

Deno.test('run --apply grants and reconciles what is missing; a failure is counted and skipped', async () => {
  const { accounts, state } = mixed();
  const f = fake(accounts, state, {
    grantFails: user(4),
    reconcileAnswers: new Map([[user(5), 502]]),
  });
  const tally = await run(f.deps, { ...base, apply: true });
  assertEquals(f.calls, [
    `reconcile ${user(2)}`,
    `grant ${user(3)}`,
    `reconcile ${user(3)}`,
    `grant ${user(4)}`,
    `grant ${user(5)}`,
    `reconcile ${user(5)}`,
  ]);
  assertEquals(
    tally,
    {
      accounts: 5,
      done: 1,
      reconcile: 1,
      grant: 3,
      granted: 2,
      reconciled: 2,
      failed: 2,
    } satisfies Tally,
  );
  assertStringIncludes(f.lines.join('\n'), 'grant failed: RevenueCat API: 429');
  assertStringIncludes(f.lines.join('\n'), 'reconcile failed: HTTP 502');
  noIds(f.lines);

  const rerun = fake(f.accountsNow(), state);
  const again = await run(rerun.deps, { ...base, apply: true });
  assertEquals(rerun.calls, [`grant ${user(4)}`, `reconcile ${user(4)}`, `reconcile ${user(5)}`]);
  assertEquals(again.failed, 0);

  const last = fake(rerun.accountsNow(), state);
  assertEquals((await run(last.deps, { ...base, apply: true })).done, 5);
  assertEquals(last.calls, []);
  noIds([...rerun.lines, ...last.lines]);
});

Deno.test('run: a RevenueCat read that fails or times out is counted, the run goes on', async () => {
  const f = fake([{ id: user(1), stored: false }, { id: user(2), stored: false }], new Map());
  const read = f.deps.atRevenueCat;
  if (!read) throw new Error('the fake reads RevenueCat');
  f.deps.atRevenueCat = (id) =>
    id === user(1) ? Promise.reject(new DOMException('slow', 'TimeoutError')) : read(id);
  const tally = await run(f.deps, { ...base, apply: true });
  assertEquals(tally.failed, 1);
  assertEquals(f.calls, [`grant ${user(2)}`, `reconcile ${user(2)}`]);
  assertStringIncludes(f.lines.join('\n'), 'read failed: timeout');
});

Deno.test('parseArgs: dry run until now by default; a cutoff needs a zone', () => {
  const now = new Date('2026-11-22T10:00:00Z');
  assertEquals(parseArgs([], now), { cutoff: now, usedBefore: null, apply: false });
  assertThrows(() => parseArgs(['--apply'], now), Error, '--apply needs --created-before');
  assertEquals(parseArgs(['--apply', '--created-before', '2026-12-01T00:00:00+01:00'], now), {
    cutoff: new Date('2026-11-30T23:00:00Z'),
    usedBefore: null,
    apply: true,
  });
  assertEquals(
    parseArgs(['--used-before', '2026-12-01T10:00:00Z'], now).usedBefore,
    new Date('2026-12-01T10:00:00Z'),
  );
  assertThrows(() => parseArgs(['--used-before', '2026-12-01'], now));
  assertThrows(() => parseArgs(['--used-before'], now));
  assertThrows(() => parseArgs(['--created-before', '2026-12-01'], now));
  assertThrows(() => parseArgs(['--created-before', '2026-12-01T00:00:00'], now));
  assertThrows(() => parseArgs(['--created-before', '2026-13-45T00:00:00Z'], now));
  assertThrows(() => parseArgs(['--created-before'], now));
  assertThrows(() => parseArgs(['--household', user(1)], now));
});

Deno.test('accountsQuery: confirmed real accounts before the cutoff, with the lifetime row', () => {
  const sql = accountsQuery(new Date('2026-12-01T00:00:00+01:00'), now);
  assertStringIncludes(sql, `u.created_at < '2026-11-30T23:00:00.000Z'::timestamptz`);
  assertStringIncludes(sql, 'u.is_anonymous is not true');
  assertStringIncludes(sql, 'u.deleted_at is null');
  assertStringIncludes(sql, 'u.confirmed_at is not null');
  assertStringIncludes(sql, `e.kind = 'premium' and e.source = 'promotional'`);
  assertStringIncludes(
    sql,
    `(e.expires_at is null or e.expires_at >= '2100-01-01T00:00:00.000Z'::timestamptz)`,
  );
  assertStringIncludes(sql, 'order by u.created_at');
});

Deno.test('accountsQuery: an account that used MCP or the API is selected whenever it was created', () => {
  const sql = accountsQuery(new Date('2026-12-01T00:00:00Z'), now);
  assertStringIncludes(
    sql,
    `t.kind in ('pat', 'api') and t.last_used_at < '2026-12-02T09:00:00.000Z'::timestamptz`,
  );
  assertStringIncludes(sql, 's.oauth_client_id is not null');
  assertStringIncludes(sql, `s.created_at < '2026-12-02T09:00:00.000Z'::timestamptz`);
  assertStringIncludes(sql, `r.refilled_at < '2026-12-02T09:00:00.000Z'::timestamptz`);
  assertStringIncludes(
    sql,
    `d.day < ('2026-12-02T09:00:00.000Z'::timestamptz at time zone 'UTC')::date`,
  );
  assertStringIncludes(sql, 'public.mcp_rate r where r.user_id = u.id');
  assertStringIncludes(sql, 'public.account_days d\n               where d.user_id = u.id');
  // The creation cut-off and the use signals are alternatives, the account checks apply to both.
  assertStringIncludes(
    sql,
    `where (u.created_at < '2026-12-01T00:00:00.000Z'::timestamptz\n    or exists`,
  );
  assertStringIncludes(sql, `)\n  and u.is_anonymous is not true`);
});

Deno.test('run: a dry run prints the selection rule and counts, no id', async () => {
  const { accounts, state } = mixed();
  const f = fake(accounts, state);
  await run(f.deps, { ...base, apply: false });
  assertStringIncludes(f.lines.join('\n'), selectionRule);
  assertStringIncludes(f.lines.join('\n'), 'dry run: 1 done, 1 to reconcile, 3 to grant');
  noIds(f.lines);
});

Deno.test('parseAccounts: a malformed row stops the run without echoing it', () => {
  assertEquals(parseAccounts([{ id: user(1), stored: false }]), [{ id: user(1), stored: false }]);
  for (const row of [{ id: 'peter@example.com', stored: false }, { id: user(1) }, null]) {
    const e = assertThrows(() => parseAccounts([row]));
    assert(e instanceof Error && !e.message.includes('example') && !e.message.includes(user(1)));
  }
});

Deno.test('reconciled: stored only on 200 with an outcome that keeps the premium', () => {
  assertEquals(reconciled(200, '{"status":"granted"}').stored, true);
  assertEquals(reconciled(200, '{"status":"unchanged"}').stored, true);
  assertEquals(reconciled(200, '{"status":"no_user"}').stored, false);
  assertEquals(reconciled(503, '{"error":"unavailable"}').stored, false);
  assertEquals(reconciled(200, 'not json').stored, false);
});

Deno.test('run: --apply refuses while integration_lock is on, before reading or granting', async () => {
  const { accounts, state } = mixed();
  const f = fake(accounts, state, { lock: { on: true, since: new Date('2026-12-01T12:00:00Z') } });
  const e = await run(f.deps, { ...base, apply: true }).catch((x: unknown) => x);
  assert(e instanceof Error);
  assertStringIncludes(e.message, 'integration_lock is on');
  assertEquals(f.calls, []);
});

Deno.test('run: use counts before --used-before, else the lock flip time, else now', async () => {
  const flip = new Date('2026-12-01T12:00:00Z');
  const explicit = new Date('2026-12-01T06:00:00Z');
  const cases: [Parameters<typeof fake>[2], Date | null, Date][] = [
    [{ lock: { on: true, since: flip } }, null, flip],
    [{ lock: { on: true, since: flip } }, explicit, explicit],
    [{ lock: { on: false, since: flip } }, null, now],
  ];
  for (const [opts, usedBefore, want] of cases) {
    const seen: Date[] = [];
    const { accounts, state } = mixed();
    const f = fake(accounts, state, { ...opts, usedBefores: seen });
    await run(f.deps, { ...base, usedBefore, apply: false });
    assertEquals(seen, [want]);
  }
});

Deno.test('parseLock: no row is off; a malformed row stops the run', () => {
  assertEquals(parseLock([]), { on: false, since: null });
  assertEquals(parseLock([{ enabled: true, changed_at: '2026-12-01T12:00:00+00:00' }]), {
    on: true,
    since: new Date('2026-12-01T12:00:00Z'),
  });
  assertThrows(() => parseLock([{ enabled: 'yes', changed_at: '2026-12-01T12:00:00Z' }]));
  assertThrows(() => parseLock([{ enabled: true, changed_at: 'x' }]));
});
