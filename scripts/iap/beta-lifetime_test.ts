import { assert, assertEquals, assertStringIncludes, assertThrows } from 'jsr:@std/assert@^1';
import {
  type Account,
  accountsQuery,
  type Deps,
  parseAccounts,
  parseArgs,
  reconciled,
  run,
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
  opts: { grantFails?: string; reconcileAnswers?: Map<string, number>; revenueCat?: boolean } = {},
) {
  const calls: string[] = [];
  const lines: string[] = [];
  const stored = new Set(accounts.filter((a) => a.stored).map((a) => a.id));
  const deps: Deps = {
    accounts: (c) => {
      assertEquals(c, cutoff);
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
  const tally = await run(f.deps, { cutoff, apply: false, pauseMs: 0 });
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
  const tally = await run(f.deps, { cutoff, apply: false, pauseMs: 0 });
  assertEquals(f.calls, []);
  assertEquals(tally.accounts, 5);
  assertEquals(tally.done + tally.reconcile + tally.grant, 0);
  assertStringIncludes(f.lines.join('\n'), 'RevenueCat not checked');
  assertStringIncludes(f.lines.join('\n'), 'before 2026-12-01T00:00:00.000Z: 5');
});

Deno.test('run --apply grants and reconciles what is missing; a failure is counted and skipped', async () => {
  const { accounts, state } = mixed();
  const f = fake(accounts, state, {
    grantFails: user(4),
    reconcileAnswers: new Map([[user(5), 502]]),
  });
  const tally = await run(f.deps, { cutoff, apply: true, pauseMs: 0 });
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
  const again = await run(rerun.deps, { cutoff, apply: true, pauseMs: 0 });
  assertEquals(rerun.calls, [`grant ${user(4)}`, `reconcile ${user(4)}`, `reconcile ${user(5)}`]);
  assertEquals(again.failed, 0);

  const last = fake(rerun.accountsNow(), state);
  assertEquals((await run(last.deps, { cutoff, apply: true, pauseMs: 0 })).done, 5);
  assertEquals(last.calls, []);
  noIds([...rerun.lines, ...last.lines]);
});

Deno.test('run: a RevenueCat read that fails or times out is counted, the run goes on', async () => {
  const f = fake([{ id: user(1), stored: false }, { id: user(2), stored: false }], new Map());
  const read = f.deps.atRevenueCat;
  if (!read) throw new Error('the fake reads RevenueCat');
  f.deps.atRevenueCat = (id) =>
    id === user(1) ? Promise.reject(new DOMException('slow', 'TimeoutError')) : read(id);
  const tally = await run(f.deps, { cutoff, apply: true, pauseMs: 0 });
  assertEquals(tally.failed, 1);
  assertEquals(f.calls, [`grant ${user(2)}`, `reconcile ${user(2)}`]);
  assertStringIncludes(f.lines.join('\n'), 'read failed: timeout');
});

Deno.test('parseArgs: dry run until now by default; a cutoff needs a zone', () => {
  const now = new Date('2026-11-22T10:00:00Z');
  assertEquals(parseArgs([], now), { cutoff: now, apply: false });
  assertThrows(() => parseArgs(['--apply'], now), Error, '--apply needs --created-before');
  assertEquals(parseArgs(['--apply', '--created-before', '2026-12-01T00:00:00+01:00'], now), {
    cutoff: new Date('2026-11-30T23:00:00Z'),
    apply: true,
  });
  assertThrows(() => parseArgs(['--created-before', '2026-12-01'], now));
  assertThrows(() => parseArgs(['--created-before', '2026-12-01T00:00:00'], now));
  assertThrows(() => parseArgs(['--created-before', '2026-13-45T00:00:00Z'], now));
  assertThrows(() => parseArgs(['--created-before'], now));
  assertThrows(() => parseArgs(['--household', user(1)], now));
});

Deno.test('accountsQuery: confirmed real accounts before the cutoff, with the lifetime row', () => {
  const sql = accountsQuery(new Date('2026-12-01T00:00:00+01:00'));
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
