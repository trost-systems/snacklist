// Job 352: public.detect_trips finds the trips and walks of job 351's reference rule (finalRule in
// trip_sim/detect.ts) on the same ticks. Every persona of the simulator, two seeds, four weeks each,
// goes into a fresh household (order_mode 'learned', everyone with detection on) as item_events
// rows, loaded with triggers off. A run looks back at most 14 days before the newest tick, so the
// ticks go in by commit time (UTC days) and detect_trips runs after each day, as pg_cron would,
// and in a second variant after each week, so a run catches up on a backlog of 7 days. The
// detected trip_sessions must equal finalRule's trips (store, people, ticks, walked) and walks
// (store, start, steps of keys) on all four weeks as multisets. Each run is one transaction that
// is rolled back, so nothing stays and pg_cron never sees it. Runs like
// add_paths_integration_test.ts (FG_DB_TEST=1, SUPABASE_DB_URL).
//
// Then, on committed rows: switching detection off waits for a running detection and removes what
// it found, pg_cron's command commits each household before the next, and leaving, a removal and
// an account deletion wait for a running detection before they lock the household row (a run's
// trip_sessions inserts need a key share on it while it holds rows they update: a deadlock).
import { assert, assertEquals } from '@std/assert';
import postgres from 'postgres';
import { databaseUrl, type Tx } from './db.ts';
import { finalRule } from './trip_sim/detect.ts';
import { generate } from './trip_sim/generate.ts';
import { DAY, HOUR, type Household, type Tick } from './trip_sim/model.ts';
import { personas } from './trip_sim/personas.ts';

const enabled = Deno.env.get('FG_DB_TEST') === '1';

const WEEKS = 4;
/** Added to each persona's own seed: two households per persona. */
const SEEDS = [0, 100] as const;

type Variant = 'daily' | 'weekly';

/** Microseconds since the epoch: what timestamptz keeps. */
const micros = (ms: number): number => Math.round(ms * 1000);

/** The ISO text of [us], to the microsecond (a JS Date keeps milliseconds only). */
function iso(us: number): string {
  const text = new Date(Math.floor(us / 1000)).toISOString();
  return `${text.slice(0, -1)}${String(us % 1000).padStart(3, '0')}Z`;
}

/** [h] with every time as Postgres stores it, so both sides read the same instants. */
function atMicros(h: Household): Household {
  return {
    ...h,
    ticks: h.ticks.map((t) => ({
      ...t,
      clientAt: micros(t.clientAt) / 1000,
      serverAt: micros(t.serverAt) / 1000,
    })),
  };
}

/** The tap time items_log_event keeps: within 7 days before to 24 hours after the commit. */
const storedClientAt = (t: Tick): boolean =>
  t.serverAt - t.clientAt <= 7 * DAY && t.clientAt - t.serverAt <= 24 * HOUR;

/** The database ids of a simulated household. */
interface Ids {
  readonly household: string;
  readonly list: string;
  readonly category: string;
  readonly stores: ReadonlyMap<string, string>;
  readonly actors: ReadonlyMap<string, string>;
  readonly items: ReadonlyMap<string, string>;
  /** Sim tick id to item_events id (as text, bigint). */
  readonly ticks: Map<number, string>;
}

/** Trips and walks as canonical JSON lines: compared as multisets. */
interface Found {
  readonly trips: readonly string[];
  readonly walks: readonly string[];
}

const tripLine = (store: string | null, actors: string[], ticks: string[], walked: boolean) =>
  JSON.stringify({
    store,
    actors: [...actors].sort(),
    ticks: [...ticks].sort((a, b) => Number(a) - Number(b)),
    walked,
  });

const walkLine = (store: string, at: number, steps: readonly (readonly string[])[]) =>
  JSON.stringify({ store, at, steps: steps.map((s) => [...s].sort()) });

const required = <K, V>(map: ReadonlyMap<K, V>, key: K): V => {
  const value = map.get(key);
  if (value === undefined) throw new Error(`no id for ${String(key)}`);
  return value;
};

function expected(h: Household, ids: Ids): Found {
  const d = finalRule(h);
  return {
    trips: d.trips.map((t) =>
      tripLine(
        t.store === null ? null : required(ids.stores, t.store),
        t.actors.map((a) => required(ids.actors, a)),
        t.ticks.map((x) => required(ids.ticks, x.id)),
        t.walked,
      )
    ),
    walks: d.segments.map((s) => walkLine(required(ids.stores, s.store), micros(s.at), s.clumps)),
  };
}

async function household(tx: Tx, h: Household): Promise<Ids> {
  const household = crypto.randomUUID();
  const list = crypto.randomUUID();
  const category = crypto.randomUUID();
  const actors = new Map(
    [...new Set(h.ticks.map((t) => t.actor))].map((a) => [a, crypto.randomUUID()]),
  );
  const stores = new Map(h.stores.map((s) => [s.id, crypto.randomUUID()]));
  const items = new Map<string, string>();
  const itemRows: { id: string; name: string; key: string; store: string | null }[] = [];
  for (const t of h.ticks) {
    if (items.has(t.item)) continue;
    const id = crypto.randomUUID();
    items.set(t.item, id);
    itemRows.push({
      id,
      name: t.key,
      key: t.key,
      store: t.store === null ? null : required(stores, t.store),
    });
  }
  for (const [name, id] of actors) {
    await tx`insert into auth.users (id, email) values (${id}, ${`${name}-${id}@fg-test.invalid`})`;
    await tx`insert into public.trip_detection_settings (user_id, detect_ticks_from) values (${id}, '-infinity')`;
  }
  await tx`insert into public.households (id, name, created_by, order_mode)
    values (${household}, ${`352 ${h.name}`}, ${[...actors.values()][0] ?? null}, 'learned')`;
  let first = true;
  for (const id of actors.values()) {
    await tx`insert into public.household_members (household_id, user_id, role, is_default)
      values (${household}, ${id}, ${first ? 'owner' : 'member'}, true)`;
    first = false;
  }
  await tx`insert into public.categories (id, household_id, name, sort_order)
    values (${category}, ${household}, 'Sim', 0)`;
  await tx`insert into public.lists (id, household_id, name, seed_key) values (${list}, ${household}, 'Sim', 'main')`;
  let order = 0;
  for (const s of h.stores) {
    const name = s.pharmacy ? `Apotheke ${s.id}` : `Sim ${s.id}`;
    await tx`insert into public.stores (id, household_id, name, sort_order)
      values (${required(stores, s.id)}, ${household}, ${name}, ${order++})`;
  }
  await tx`insert into public.items (id, household_id, list_id, name, normalized_name, category_id, store_id, canonical_key)
    select r.id, ${household}, ${list}, r.name, r.name, ${category}, r.store, r.key
    from jsonb_to_recordset(${JSON.stringify(itemRows)}::text::jsonb)
      as r(id uuid, name text, key text, store uuid)`;
  return { household, list, category, stores, actors, items, ticks: new Map() };
}

/** Inserts [ticks] (commit order) as item_events, with ids from the table's own sequence. */
async function load(tx: Tx, ids: Ids, ticks: readonly Tick[]): Promise<void> {
  if (ticks.length === 0) return;
  const fresh = await tx<{ id: string }[]>`
    select nextval(pg_get_serial_sequence('public.item_events', 'id'))::text as id
    from generate_series(1, ${ticks.length})`;
  const rows = ticks.map((t, i) => {
    const id = fresh[i]?.id;
    if (id === undefined) throw new Error('too few item_events ids');
    ids.ticks.set(t.id, id);
    return {
      id,
      item: required(ids.items, t.item),
      action: t.kind,
      name: t.key,
      actor: required(ids.actors, t.actor),
      source: t.source,
      created_at: iso(micros(t.serverAt)),
      client_at: storedClientAt(t) ? iso(micros(t.clientAt)) : null,
      store: t.store === null ? null : required(ids.stores, t.store),
      open_after: t.storeOpenAfter,
    };
  });
  await tx`insert into public.item_events (id, household_id, item_id, list_id, action, item_name,
      category_id, actor, source, created_at, client_at, store_id, store_open_after)
    overriding system value
    select r.id, ${ids.household}, r.item, ${ids.list}, r.action, r.name, ${ids.category}, r.actor,
      r.source, r.created_at, r.client_at, r.store, r.open_after
    from jsonb_to_recordset(${JSON.stringify(rows)}::text::jsonb) as r(id bigint, item uuid,
      action text, name text, actor uuid, source text, created_at timestamptz, client_at timestamptz,
      store uuid, open_after integer)`;
}

async function detect(tx: Tx, ids: Ids): Promise<void> {
  await tx`set local session_replication_role = origin`;
  await tx`select public.detect_trips(${ids.household})`;
  await tx`set local session_replication_role = replica`;
}

async function detected(tx: Tx, ids: Ids): Promise<Found> {
  const rows = await tx<
    {
      store_id: string | null;
      detected_by: string[] | null;
      tick_ids: string[] | null;
      walked: boolean | null;
      walks: { store: string; at: string; steps: string[][] }[];
    }[]
  >`
    select s.store_id, s.detected_by, s.tick_ids::text[] as tick_ids, s.walked,
      (select coalesce(jsonb_agg(jsonb_build_object(
          'store', w->>'store_id',
          'at', (extract(epoch from (w->>'at')::timestamptz) * 1000000)::bigint::text,
          'steps', w->'steps')), '[]'::jsonb)
       from jsonb_array_elements(s.walks) w) as walks
    from public.trip_sessions s
    where s.household_id = ${ids.household} and s.source = 'detected' and s.removed_at is null`;
  return {
    trips: rows.map((r) =>
      tripLine(r.store_id, r.detected_by ?? [], r.tick_ids ?? [], r.walked ?? false)
    ),
    walks: rows.flatMap((r) => r.walks.map((w) => walkLine(w.store, Number(w.at), w.steps))),
  };
}

/** Lines of [a] not in [b], counting duplicates. */
function minus(a: readonly string[], b: readonly string[]): string[] {
  const left = new Map<string, number>();
  for (const x of b) left.set(x, (left.get(x) ?? 0) + 1);
  return a.filter((x) => {
    const n = left.get(x) ?? 0;
    left.set(x, n - 1);
    return n <= 0;
  });
}

/** A readable diff: each differing trip or walk with the ticks it names. */
function report(h: Household, ids: Ids, want: Found, got: Found): string {
  const sim = new Map([...ids.ticks].map(([simId, dbId]) => [dbId, simId]));
  const byId = new Map(h.ticks.map((t) => [t.id, t]));
  const tickText = (dbId: string): string => {
    const t = byId.get(sim.get(dbId) ?? -1);
    if (t === undefined) return `  ${dbId} (not this household's)`;
    return `  ${dbId} sim#${t.id} ${t.actor} ${t.kind} ${t.source} ${t.key} store=${t.store} open=${t.storeOpenAfter}` +
      ` server=${iso(micros(t.serverAt))} client=${
        storedClientAt(t) ? iso(micros(t.clientAt)) : 'null'
      }` +
      ` truth=${t.truth.context}/${t.truth.visit}`;
  };
  const trip = (line: string): string => {
    const t = JSON.parse(line) as { ticks: string[] };
    return [line, ...t.ticks.map(tickText)].join('\n');
  };
  const parts: string[] = [];
  const section = (title: string, lines: string[], show: (l: string) => string) => {
    if (lines.length === 0) return;
    parts.push(`${title} (${lines.length}):`, ...lines.slice(0, 4).map(show));
  };
  section('finalRule trips detect_trips lacks', minus(want.trips, got.trips), trip);
  section('detect_trips trips finalRule lacks', minus(got.trips, want.trips), trip);
  section('finalRule walks detect_trips lacks', minus(want.walks, got.walks), (l) => l);
  section('detect_trips walks finalRule lacks', minus(got.walks, want.walks), (l) => l);
  return parts.join('\n');
}

class Rollback extends Error {}

/** Runs [variant] on [h] in a transaction that is rolled back; returns the diff, empty when equal. */
async function compare(sql: postgres.Sql, h: Household, variant: Variant): Promise<string> {
  let outcome: { want: Found; got: Found; diff: string } | undefined;
  try {
    await sql.begin(async (tx) => {
      await tx`set local session_replication_role = replica`;
      const ids = await household(tx, h);
      const ticks = [...h.ticks].sort((a, b) => a.serverAt - b.serverAt || a.id - b.id);
      const span = variant === 'daily' ? DAY : 7 * DAY;
      const batches = new Map<number, Tick[]>();
      for (const t of ticks) {
        const batch = Math.floor(t.serverAt / span);
        batches.set(batch, [...(batches.get(batch) ?? []), t]);
      }
      for (const batch of batches.values()) {
        await load(tx, ids, batch);
        await detect(tx, ids);
      }
      const want = expected(h, ids);
      const got = await detected(tx, ids);
      outcome = { want, got, diff: report(h, ids, want, got) };
      throw new Rollback();
    });
  } catch (e) {
    if (e instanceof postgres.PostgresError) {
      throw new Error(`${h.name} ${variant}: ${e.message}\n${e.where ?? ''}`, { cause: e });
    }
    if (!(e instanceof Rollback)) throw e;
  }
  if (outcome === undefined) throw new Error('the run ended without a result');
  const { want, got, diff } = outcome;
  console.log(
    `${h.name} ${variant}: finalRule ${want.trips.length} trips ${want.walks.length} walks, ` +
      `detect_trips ${got.trips.length} trips ${got.walks.length} walks`,
  );
  return diff === '' ? '' : `${h.name} ${variant}:\n${diff}`;
}

for (const persona of personas) {
  for (const offset of SEEDS) {
    const seed = persona.seed + offset;
    Deno.test({
      name: `detect_trips finds finalRule's trips and walks: ${persona.name}, seed ${seed}`,
      ignore: !enabled,
      sanitizeResources: false,
      fn: async () => {
        const h = atMicros(generate({ ...persona, seed, weeks: WEEKS }));
        const sql = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
        try {
          const named = { ...h, name: `${persona.name} seed ${seed}` };
          const diffs = [await compare(sql, named, 'daily'), await compare(sql, named, 'weekly')];
          assertEquals(diffs.filter((d) => d !== '').join('\n\n'), '');
        } finally {
          await sql.end();
        }
      },
    });
  }
}

/** A learned household with [people] (detection on) and a walk of six ticks each, 40 minutes ago. */
async function committed(sql: postgres.Sql, people: number, id = crypto.randomUUID()) {
  const users = Array.from({ length: people }, () => crypto.randomUUID());
  const store = crypto.randomUUID();
  const category = crypto.randomUUID();
  const list = crypto.randomUUID();
  await sql.begin(async (tx) => {
    await tx`set local session_replication_role = replica`;
    for (const u of users) {
      await tx`insert into auth.users (id, email) values (${u}, ${`${u}@fg-test.invalid`})`;
      await tx`insert into public.trip_detection_settings (user_id, detect_ticks_from) values (${u}, '-infinity')`;
    }
    await tx`insert into public.households (id, name, created_by, order_mode)
      values (${id}, '352 committed', ${users[0] ?? null}, 'learned')`;
    for (const [i, u] of users.entries()) {
      await tx`insert into public.household_members (household_id, user_id, role, is_default)
        values (${id}, ${u}, ${i === 0 ? 'owner' : 'member'}, true)`;
    }
    await tx`insert into public.stores (id, household_id, name, sort_order) values (${store}, ${id}, 'Laden', 0)`;
    await tx`insert into public.categories (id, household_id, name, sort_order) values (${category}, ${id}, 'Sim', 0)`;
    await tx`insert into public.lists (id, household_id, name, seed_key) values (${list}, ${id}, 'Sim', 'main')`;
    for (const [p, u] of users.entries()) {
      for (let i = 0; i < 6; i++) {
        const key = `k${String.fromCharCode(97 + p * 6 + i)}`;
        const item = crypto.randomUUID();
        await tx`insert into public.items (id, household_id, list_id, name, normalized_name, category_id, store_id, canonical_key)
          values (${item}, ${id}, ${list}, ${key}, ${key}, ${category}, ${store}, ${key})`;
        await tx`insert into public.item_events (household_id, item_id, list_id, action, item_name, category_id, actor, source,
            created_at, client_at, store_id, store_open_after)
          values (${id}, ${item}, ${list}, 'bought', ${key}, ${category}, ${u}, 'app',
            now() - interval '40 minutes' + ${i} * interval '1 minute' + ${p} * interval '30 seconds' + interval '1 second',
            now() - interval '40 minutes' + ${i} * interval '1 minute' + ${p} * interval '30 seconds', ${store}, 5)`;
      }
    }
  });
  return { household: id, users };
}

async function forget(
  sql: postgres.Sql,
  household: string,
  users: readonly string[],
): Promise<void> {
  await sql`delete from public.households where id = ${household}`;
  await sql`delete from auth.users where id = any(${users}::uuid[])`;
}

const detectedOf = async (sql: postgres.Sql, household: string, user?: string): Promise<number> => {
  const [row] = await sql<{ n: number }[]>`
    select count(*)::int as n from public.trip_sessions
    where household_id = ${household} and source = 'detected' and removed_at is null
      and (${user ?? null}::uuid is null or ${user ?? null}::uuid = any(detected_by))`;
  return row?.n ?? 0;
};

Deno.test({
  name: 'set_trip_detection(false) waits for a running detection and removes the trips it found',
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const run = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const off = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const { household, users } = await committed(run, 1);
    const [lea] = users;
    if (lea === undefined) throw new Error('no user');
    try {
      let detected = () => {};
      const found = new Promise<void>((resolve) => {
        detected = resolve;
      });
      let finish = () => {};
      const finished = new Promise<void>((resolve) => {
        finish = resolve;
      });
      const detection = run.begin(async (tx) => {
        await tx`select public.detect_trips(${household})`;
        detected();
        await finished;
      });
      await found;
      const switching = off.begin(async (tx) => {
        await tx`select set_config('role', 'authenticated', true),
          set_config('request.jwt.claims', ${
          JSON.stringify({ sub: lea, role: 'authenticated' })
        }, true)`;
        await tx`select public.set_trip_detection(false)`;
      });
      await new Promise((resolve) => setTimeout(resolve, 500));
      finish();
      await detection;
      await switching;
      assertEquals(await detectedOf(run, household, lea), 0, 'no detected trip of hers is left');
    } finally {
      await forget(run, household, users);
      await run.end();
      await off.end();
    }
  },
});

Deno.test({
  name: "pg_cron's detection commits each household before it starts the next",
  ignore: !enabled,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const [first, second] = [crypto.randomUUID(), crypto.randomUUID()].sort();
    if (first === undefined || second === undefined) throw new Error('no ids');
    const hold = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const cron = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const look = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
    const a = await committed(look, 1, first);
    const b = await committed(look, 1, second);
    try {
      let release = () => {};
      const released = new Promise<void>((resolve) => {
        release = resolve;
      });
      let locked = () => {};
      const holding = new Promise<void>((resolve) => {
        locked = resolve;
      });
      const holder = hold.begin(async (tx) => {
        await tx`select public.lock_trip_detection(${second})`;
        locked();
        await released;
      });
      await holding;
      const [job] = await look<
        { command: string }[]
      >`select command from cron.job where jobname = 'detect-trips'`;
      if (job === undefined) throw new Error('no detect-trips job');
      const running = cron.unsafe(job.command).simple().execute();
      let seen = false;
      for (let i = 0; i < 50 && !seen; i++) {
        await new Promise((resolve) => setTimeout(resolve, 200));
        seen = await detectedOf(look, first) > 0;
      }
      release();
      await holder;
      await running;
      assert(seen, "the first household's trip is committed while the second one waits");
      assertEquals(await detectedOf(look, second), 1, 'and the second is detected after');
    } finally {
      await forget(look, a.household, a.users);
      await forget(look, b.household, b.users);
      await Promise.all([hold.end(), cron.end(), look.end()]);
    }
  },
});

/** Waits up to 5 s for backend [pid] to wait on an advisory lock. */
async function waitsOnAdvisory(look: postgres.Sql, pid: number): Promise<boolean> {
  for (let i = 0; i < 50; i++) {
    const [row] = await look<{ n: number }[]>`
      select count(*)::int as n from pg_stat_activity
      where pid = ${pid} and wait_event_type = 'Lock' and wait_event = 'advisory'`;
    if ((row?.n ?? 0) > 0) return true;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return false;
}

const memberExits: readonly {
  readonly name: string;
  readonly run: (tx: Tx, household: string, owner: string, member: string) => Promise<unknown>;
}[] = [
  {
    name: 'leaving',
    run: (tx, household, _owner, member) =>
      tx`select public.leave_household_as(${member}, ${household}, false)`,
  },
  {
    name: 'a removal',
    run: async (tx, household, owner, member) => {
      await tx`select set_config('role', 'authenticated', true),
        set_config('request.jwt.claims', ${
        JSON.stringify({ sub: owner, role: 'authenticated' })
      }, true)`;
      return tx`select public.remove_member(${household}, ${member})`;
    },
  },
  {
    name: 'an account deletion',
    run: (tx, _household, _owner, member) => tx`select public.delete_account(${member})`,
  },
];

for (const exit of memberExits) {
  Deno.test({
    name: `${exit.name} waits for a running detection before it locks the household`,
    ignore: !enabled,
    sanitizeResources: false,
    sanitizeOps: false,
    fn: async () => {
      const hold = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
      const act = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
      const look = postgres(databaseUrl(), { max: 1, prepare: false, onnotice: () => {} });
      const { household, users } = await committed(look, 2);
      const [owner, member] = users;
      if (owner === undefined || member === undefined) throw new Error('no users');
      try {
        let release = () => {};
        const released = new Promise<void>((resolve) => {
          release = resolve;
        });
        let locked = () => {};
        const holding = new Promise<void>((resolve) => {
          locked = resolve;
        });
        const holder = hold.begin(async (tx) => {
          await tx`select public.lock_trip_detection(${household})`;
          locked();
          await released;
        });
        await holding;
        const [me] = await act<{ pid: number }[]>`select pg_backend_pid() as pid`;
        if (me === undefined) throw new Error('no pid');
        const exiting = act.begin((tx) => exit.run(tx, household, owner, member));
        const waits = await waitsOnAdvisory(look, me.pid);
        const free = await look.begin(async (tx) => {
          const rows =
            await tx`select from public.households where id = ${household} for update skip locked`;
          return rows.length === 1;
        });
        release();
        await holder;
        await exiting;
        assert(waits, 'it waits for the detection lock');
        assert(free, 'before it locks the household row');
      } finally {
        await forget(look, household, users);
        await Promise.all([hold.end(), act.end(), look.end()]);
      }
    },
  });
}
