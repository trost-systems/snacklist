// Job 352: replay_store_order is job 351's learner, to the bit. Random walks (ties, keys the
// store never had, removed sessions, shuffles the gate turns away) go through the TypeScript trade
// of docs/research/351-trip-detection/sim/learn.ts, copied below with job 352's tie spread, and
// through the SQL replay; every position agrees within 1e-9. Positions cross the wire as float8send bytes, not as text. Runs
// against the local stack like add_paths_integration_test.ts (FG_DB_TEST=1, SUPABASE_DB_URL).
import { assert, assertEquals, assertExists } from '@std/assert';
import postgres from 'postgres';
import { asUser, databaseUrl } from './db.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

type Clumps = readonly (readonly string[])[];
type Walk = { readonly clumps: Clumps; readonly removed: boolean };
type Gate = { readonly after: number; readonly min: number };

const GATE: Gate = { after: 3, min: 0.6 };
const STEP = 0.5;

/** learn.ts's trade for one store: the walks in order, from the store's prior. */
function trade(
  prior: ReadonlyMap<string, number>,
  walks: readonly Clumps[],
): { pos: Map<string, number>; rejected: number } {
  const pos = new Map(prior);
  let taught = 0;
  let rejected = 0;
  for (const walk of walks) {
    const clumps = walk.map((c) => c.filter((k) => pos.has(k))).filter((c) => c.length > 0);
    if (clumps.length < 2) continue;
    if (taught >= GATE.after && agreement(clumps, pos) < GATE.min) {
      rejected++;
      continue;
    }
    taught++;
    const slots = clumps.flat().map((k) => pos.get(k) ?? 0).sort((a, b) => a - b);
    let i = 0;
    const target = new Map<string, number>();
    for (const clump of clumps) {
      const mine = slots.slice(i, i + clump.length);
      const at = mine.reduce((a, b) => a + b, 0) / mine.length;
      for (const k of clump) target.set(k, at);
      i += clump.length;
    }
    for (const [k, t] of target) {
      const p = pos.get(k) ?? t;
      pos.set(k, p + STEP * (t - p));
    }
    spreadTies(clumps, pos);
  }
  return { pos, rejected };
}

/**
 * Job 352's change to learn.ts: keys of different steps that the move left on one position (or a
 * rounding error apart) are spread in walk order by a tiny offset; keys of one step stay tied.
 */
function spreadTies(clumps: Clumps, pos: Map<string, number>): void {
  const at = (k: string): number => pos.get(k) ?? 0;
  const order = clumps.flatMap((clump, step) => clump.map((key) => ({ key, step })))
    .sort((a, b) => at(a.key) - at(b.key) || a.step - b.step);
  const p = order.map((o) => at(o.key));
  let from = 0;
  while (from < order.length) {
    let to = from;
    while ((p[to + 1] ?? Infinity) - (p[to] ?? 0) <= Math.abs(p[to] ?? 0) * 1e-14 + 1e-12) to++;
    const cluster = order.slice(from, to + 1);
    const steps = [...new Set(cluster.map((c) => c.step))];
    const first = cluster[0];
    if (steps.length > 1 && first !== undefined) {
      const base = at(first.key);
      const off = Math.abs(base) * 1e-12 + 1e-9;
      for (const { key, step } of cluster) {
        pos.set(key, base + off * steps.filter((s) => s < step).length);
      }
    }
    from = to + 1;
  }
}

function agreement(clumps: Clumps, pos: ReadonlyMap<string, number>): number {
  let pairs = 0;
  let same = 0;
  const seen: number[] = [];
  for (const clump of clumps) {
    const at = clump.map((k) => pos.get(k) ?? 0);
    for (const a of seen) {
      for (const b of at) {
        pairs++;
        if (a < b) same++;
      }
    }
    seen.push(...at);
  }
  return pairs === 0 ? 1 : same / pairs;
}

/** mulberry32: the same walks on every run. */
function random(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * A walk over some of [keys] (in the order they hold; a few of them or most) and a key the store
 * never had: mostly the held order with a few swaps, sometimes a shuffle; neighbouring keys tie
 * now and then, or a few keys tie in one step and teach nothing.
 */
function randomWalk(next: () => number, keys: readonly string[]): Walk {
  const density = next();
  const ties = next() * 0.6;
  const picked = [...keys.filter(() => next() < density), 'kein laden kennt mich'];
  const shuffle = next() < 0.3;
  for (let i = picked.length - 1; i > 0; i--) {
    if (!shuffle && next() < 0.7) continue;
    const j = shuffle ? Math.floor(next() * (i + 1)) : i - 1;
    const a = picked[i];
    const b = picked[j];
    if (a === undefined || b === undefined) continue;
    picked[i] = b;
    picked[j] = a;
  }
  const clumps: string[][] = [];
  for (const key of picked) {
    const last = clumps.at(-1);
    if (last !== undefined && next() < ties) last.push(key);
    else clumps.push([key]);
  }
  return { clumps, removed: next() < 0.1 };
}

function float8(hex: string): number {
  const bytes = new Uint8Array(hex.match(/../g)?.map((b) => parseInt(b, 16)) ?? []);
  return new DataView(bytes.buffer).getFloat64(0);
}

const NAMES = [
  'Milch',
  'Joghurt',
  'Butter',
  'Gurke',
  'Tomaten',
  'Brot',
  'Wasser',
  'Bier',
  'Zahnpasta',
  'Kaffee',
  'Reis',
  'Nudeln',
  'Salz',
  'Honig',
];

Deno.test({
  name: 'replay_store_order moves every key where the TypeScript trade does',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const user = crypto.randomUUID();
    try {
      await sql`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
      const { household, store } = await asUser(user, async (tx) => {
        const [h] = await tx<{ id: string }[]>`
          select id from public.create_household(p_name => '352', p_default_stores => false)`;
        assertExists(h);
        const [s] = await tx<{ id: string }[]>`select public.add_store(${h.id}, 'Laden') as id`;
        assertExists(s);
        for (const name of NAMES) {
          await tx`insert into public.items (household_id, name, store_id)
                   values (${h.id}, ${name}, ${s.id})`;
        }
        await tx`update public.items set status = 'bought'
                 where household_id = ${h.id} and name in ('Brot', 'Honig')`;
        await tx`select public.set_order_mode(${h.id}, 'learned')`;
        return { household: h.id, store: s.id };
      });
      const positions = async (column: 'seed_position' | 'position') =>
        new Map(
          (await sql<{ key: string; hex: string }[]>`
            select item_key as key, encode(float8send(${sql(column)}), 'hex') as hex
            from public.item_order_memory where household_id = ${household} and store_id = ${store}`)
            .map((r) => [r.key, float8(r.hex)]),
        );
      const prior = await positions('seed_position');
      assertEquals(prior.size, NAMES.length, 'one key per item');
      const keys = [...prior.keys()].sort((a, b) => (prior.get(a) ?? 0) - (prior.get(b) ?? 0));

      let gated = 0;
      for (let trial = 0; trial < 40; trial++) {
        const next = random(352 + trial);
        const walks = Array.from(
          { length: 1 + Math.floor(next() * 9) },
          () => randomWalk(next, keys),
        );
        await sql`delete from public.trip_sessions where household_id = ${household}`;
        for (const [i, walk] of walks.entries()) {
          const steps = JSON.stringify([{
            store_id: store,
            at: new Date(Date.UTC(2026, 10, 22, 9, i)).toISOString(),
            steps: walk.clumps,
          }]);
          await sql`
            insert into public.trip_sessions (id, household_id, started_at, ended_at, active_seconds,
              end_reason, source, currency, shopped_on, walks, removed_at)
            values (gen_random_uuid(), ${household}, now(), now(), 0, 'user', 'manual', 'EUR',
              current_date, (${steps}::text)::jsonb, ${walk.removed ? new Date() : null})`;
        }
        await sql`select public.replay_store_order(${household}, ${store})`;
        const taught = walks.filter((w) => !w.removed).map((w) => w.clumps);
        const { pos: want, rejected } = trade(prior, taught);
        gated += rejected;
        const have = await positions('position');
        for (const key of keys) {
          const a = have.get(key);
          const b = want.get(key);
          assert(a !== undefined && b !== undefined, `${key} in both`);
          assert(Math.abs(a - b) <= 1e-9, `trial ${trial}, ${key}: replay ${a}, trade ${b}`);
        }
        const [synced] = await sql<{ n: number }[]>`
          select count(*)::int as n from public.items i
          join public.item_order_memory m on m.household_id = i.household_id
            and m.store_id = i.store_id and m.item_key = coalesce(i.canonical_key, public.item_key(i.name))
          where i.household_id = ${household} and i.sort_key is distinct from m.position`;
        assertEquals(
          synced?.n,
          0,
          `trial ${trial}: every item, open or bought, sorts by its position`,
        );
      }
      assert(gated > 5, `the gate turned away ${gated} walks`);
    } finally {
      await sql`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${user})`;
      await sql`delete from auth.users where id = ${user}`;
      await sql.end();
    }
  },
});

Deno.test({
  name: 'place_item checks the stores again once it holds the order lock',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const hold = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const user = crypto.randomUUID();
    try {
      await hold`insert into auth.users (id, email) values (${user}, ${`${user}@fg-test.invalid`})`;
      const { household, other, item, anchor } = await asUser(user, async (tx) => {
        const [h] = await tx<{ id: string }[]>`
          select id from public.create_household(p_name => '352', p_default_stores => false)`;
        assertExists(h);
        const [a] = await tx<{ id: string }[]>`select public.add_store(${h.id}, 'Laden A') as id`;
        const [b] = await tx<{ id: string }[]>`select public.add_store(${h.id}, 'Laden B') as id`;
        assertExists(a);
        assertExists(b);
        const [x] = await tx<{ id: string }[]>`
          insert into public.items (household_id, name, store_id) values (${h.id}, 'Milch', ${a.id}) returning id`;
        const [y] = await tx<{ id: string }[]>`
          insert into public.items (household_id, name, store_id) values (${h.id}, 'Brot', ${a.id}) returning id`;
        assertExists(x);
        assertExists(y);
        await tx`select public.set_order_mode(${h.id}, 'learned')`;
        return { household: h.id, other: b.id, item: x.id, anchor: y.id };
      });
      let release = () => {};
      const released = new Promise<void>((resolve) => {
        release = resolve;
      });
      let locked = () => {};
      const holding = new Promise<void>((resolve) => {
        locked = resolve;
      });
      // Someone else holds the household's order lock, and moves the anchor to Laden B under it.
      const mover = hold.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended('item_order:' || ${household}::text, 0))`;
        locked();
        await released;
        await tx`update public.items set store_id = ${other} where id = ${anchor}`;
      });
      await holding;
      const placing = asUser(
        user,
        (tx) => tx`select public.place_item(${item}, ${anchor}, 'after')`,
      )
        .then(
          () => 'placed',
          (e: unknown) => e instanceof postgres.PostgresError ? e.message : String(e),
        );
      const look = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
      try {
        for (let i = 0; i < 50; i++) {
          const [w] = await look<{ n: number }[]>`
            select count(*)::int as n from pg_locks where locktype = 'advisory' and not granted`;
          if ((w?.n ?? 0) > 0) break;
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      } finally {
        await look.end();
      }
      release();
      await mover;
      assertEquals(
        await placing,
        'anchor_in_other_store',
        "the anchor left the item's store while it waited",
      );
    } finally {
      await hold`delete from public.households where id in (
        select household_id from public.household_members where user_id = ${user})`;
      await hold`delete from auth.users where id = ${user}`;
      await hold.end();
    }
  },
});
