import {
  type Context,
  DAY,
  HOUR,
  type Household,
  MINUTE,
  type Ms,
  SECOND,
  type Source,
  type Store,
  type Tick,
  type Visit,
} from './model.ts';

/** One member's habits. Probabilities are per visit unless named per tick or per week. */
export interface Habits {
  /** Ticks each item as it goes into the cart. */
  readonly walk: number;
  /** Ticks everything at the checkout or in the car; the rest is catching up at home. */
  readonly checkout: number;
  /** The phone is offline in the store and syncs at the exit. */
  readonly offline: number;
  /** Device clock minus true time. */
  readonly skew: Ms;
  /** Per tick: a stray tick on another row, undone a few seconds later. */
  readonly accident: number;
  /** Adds an unlisted item at the shelf and ticks it. */
  readonly impulse: number;
  /** Per week: ticks 1 to 4 items at home because they are still there. */
  readonly homeBefore: number;
  /** Per week: ticks through Siri or Alexa. */
  readonly voice: number;
  /** Seconds lost to dismissing the trip question after each tick ("Nein, nur abgehakt" asks again). */
  readonly dismiss: number;
}

export interface StoreSpec {
  readonly id: string;
  readonly pharmacy?: boolean;
  /** How far the store's aisle order is from the route order the prior uses: 0 near, 1 unrelated. */
  readonly shuffle: number;
  /** Share of visits that go to this store. */
  readonly weight: number;
}

export interface Persona {
  readonly name: string;
  readonly seed: number;
  readonly weeks: number;
  readonly members: Readonly<Record<string, Habits>>;
  readonly stores: readonly StoreSpec[];
  readonly visitsPerWeek: number;
  /** A second store 3 to 12 minutes after the first. */
  readonly backToBack: number;
  /** That second store has only one or two items. */
  readonly smallSecondStore: number;
  /** Two members shop the same visit and split the list. */
  readonly together: number;
  /** The second shopper starts at the back of the store. */
  readonly opposite: number;
  /** A short second visit to the same store later that day. */
  readonly sameStoreAgain: number;
  /** Per week: a delivery unpacked and ticked at home. */
  readonly deliveries: number;
  /** A 6 to 14 minute wait (deli counter, a call) inside the walk. */
  readonly longWait: number;
  /** A member at home ticks "we have that" while another shops. */
  readonly remoteEdits: number;
  /** Per item: not found, stays on the list. */
  readonly notFound: number;
  /** Neighbouring items picked first and ticked together a second or two apart. */
  readonly shelfBatch: number;
  /** Seconds between ticks when catching up at home: [lo, hi]. */
  readonly catchUpGap: readonly [number, number];
  /** Seconds between ticks when unpacking a delivery: [lo, hi]. */
  readonly unpackGap: readonly [number, number];
}

/** mulberry32: a small seeded generator, so every run of a persona is the same household. */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const CATEGORIES = 12;
const KEYS = 360;

interface Entry {
  readonly item: string;
  readonly key: string;
  readonly store: string | null;
}

interface RawEvent {
  readonly item: string;
  readonly key: string;
  readonly actor: string;
  readonly source: Source;
  readonly kind: 'bought' | 'restored' | 'added';
  readonly at: Ms;
  readonly serverAt: Ms;
  readonly store: string | null;
  readonly visit: string | null;
  readonly context: Context;
}

export function generate(p: Persona): Household {
  const r = rng(p.seed);
  const between = (lo: number, hi: number): number => lo + (hi - lo) * r();
  const int = (lo: number, hi: number): number => Math.floor(between(lo, hi + 1));
  const pick = <T>(xs: readonly T[]): T => {
    const x = xs[Math.floor(r() * xs.length)];
    if (x === undefined) throw new Error('pick from an empty list');
    return x;
  };
  const shuffled = <T>(xs: readonly T[]): T[] => {
    const out = [...xs];
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(r() * (i + 1));
      const a = out[i];
      const b = out[j];
      if (a === undefined || b === undefined) continue;
      out[i] = b;
      out[j] = a;
    }
    return out;
  };

  const keys = Array.from({ length: KEYS }, (_, i) => ({
    key: `k${i}`,
    category: i % CATEGORIES,
    generic: r(),
  }));

  const stores: Store[] = p.stores.map((spec) => {
    const route = Array.from({ length: CATEGORIES }, (_, i) => i);
    const aisle = route.map((c) => ({ c, at: c + spec.shuffle * between(-CATEGORIES, CATEGORIES) }))
      .sort((a, b) => a.at - b.at).map((x) => x.c);
    const layout = new Map<string, number>();
    const prior = new Map<string, number>();
    for (const k of shuffled(keys).slice(0, 160)) {
      layout.set(k.key, (aisle.indexOf(k.category) + r()) / CATEGORIES);
      prior.set(k.key, (k.category + k.generic) / CATEGORIES);
    }
    return { id: spec.id, pharmacy: spec.pharmacy ?? false, layout, prior };
  });
  const storeOf = new Map(stores.map((s) => [s.id, s]));
  const layoutOf = (s: string): ReadonlyMap<string, number> => storeOf.get(s)?.layout ?? new Map();
  const repertoire = new Map(stores.map((s) => [s.id, shuffled([...s.layout.keys()]).slice(0, 45)]));
  const members = Object.keys(p.members);
  const habits = (m: string): Habits => {
    const h = p.members[m];
    if (h === undefined) throw new Error(`no habits for ${m}`);
    return h;
  };

  const events: RawEvent[] = [];
  const visits: Visit[] = [];
  const bought = new Map<string, Set<string>>(stores.map((s) => [s.id, new Set<string>()]));
  let items = 0;
  let visitCount = 0;
  const newItem = (key: string, store: string | null): Entry => ({ item: `i${items++}`, key, store });
  const latency = (): Ms => between(0.2, 1.5) * SECOND;
  const tick = (
    e: Entry,
    actor: string,
    at: Ms,
    visit: string | null,
    context: Context,
    serverAt: Ms = at + latency(),
    kind: 'bought' | 'restored' = 'bought',
    source: Source = 'app',
  ): void => {
    events.push({ ...e, actor, source, kind, at, serverAt, visit, context });
  };
  const add = (e: Entry, actor: string, at: Ms): void => {
    events.push({
      ...e,
      actor,
      source: 'app',
      kind: 'added',
      at,
      serverAt: at + latency(),
      visit: null,
      context: 'walk',
    });
  };
  /** Open entries of the household's list that a later week can still tick. */
  const leftOver: Entry[] = [];

  const plan = (store: string, n: number, actor: string, at: Ms): Entry[] => {
    const others = stores.filter((s) => s.id !== store && !s.pharmacy);
    const list = shuffled(repertoire.get(store) ?? []).slice(0, n).map((key) => {
      const u = r();
      const other = others.length > 0 ? pick(others).id : store;
      return newItem(key, u < 0.1 ? null : u < 0.15 ? other : store);
    });
    for (const e of list) add(e, actor, at - between(1, 48) * HOUR);
    return list;
  };

  /** One shopper's part of a visit; returns when they leave the store. */
  const shop = (
    visit: string,
    store: string,
    actor: string,
    list: readonly Entry[],
    start: Ms,
    fromBack: boolean,
  ): Ms => {
    const h = habits(actor);
    const layout = layoutOf(store);
    const pos = (e: Entry): number => layout.get(e.key) ?? 0.5;
    const route = [...list].sort((a, b) => (fromBack ? pos(b) - pos(a) : pos(a) - pos(b)));
    const mode = r() < h.walk ? 'walk' : r() < h.checkout / Math.max(1e-9, 1 - h.walk) ? 'checkout' : 'home-after';
    const offline = mode === 'walk' && r() < h.offline;
    const waitAt = r() < p.longWait ? int(1, Math.max(1, route.length - 2)) : -1;
    const walkSeconds = between(600, 1000);
    let t = start + between(1, 3) * MINUTE;
    let at = fromBack ? 1 : 0;
    const picked: { e: Entry; t: Ms }[] = [];
    const e0: Entry = { item: '', key: '', store: null };
    route.forEach((e, i) => {
      if (i === waitAt) t += between(6, 14) * MINUTE;
      t += 4 * SECOND + Math.abs(pos(e) - at) * walkSeconds * SECOND * between(0.6, 1.5) +
        (r() < 0.5 ? between(5, 25) : between(1.5, 4)) * SECOND;
      at = pos(e);
      if (r() < p.notFound) {
        leftOver.push(e);
        return;
      }
      picked.push({ e, t });
      if (mode === 'walk' && r() < h.impulse / Math.max(1, route.length)) {
        const extra = newItem(pick(repertoire.get(store) ?? [e.key]), store);
        add(extra, actor, t + 10 * SECOND);
        t += between(20, 40) * SECOND;
        picked.push({ e: extra, t });
      }
    });
    const leave = t + between(3, 8) * MINUTE;
    for (const { e } of picked) bought.get(store)?.add(e.key);
    if (mode === 'walk') {
      // Shelf batches: neighbours picked first, then ticked together in the list's order.
      for (let i = 0; i < picked.length - 1;) {
        let j = i;
        while (j + 1 < picked.length && Math.abs(pos(picked[j + 1]?.e ?? e0) - pos(picked[j]?.e ?? e0)) < 0.04) j++;
        if (j > i && r() < p.shelfBatch) {
          const batch = picked.slice(i, j + 1).sort((a, b) => priorPos(a.e) - priorPos(b.e));
          const at = batch.reduce((m, x) => Math.max(m, x.t), 0);
          batch.forEach((x, k) =>
            picked.splice(i + k, 1, { e: x.e, t: at + k * (between(1, 2.5) + h.dismiss) * SECOND })
          );
        }
        i = j + 1;
      }
      picked.forEach(({ e, t: when }, i) => {
        const server = offline ? leave + between(5, 60) * SECOND + i * 0.4 * SECOND : when + latency();
        tick(e, actor, when + h.skew, visit, 'walk', server);
        if (r() < h.accident) {
          const stray = picked[i + 1 + int(0, 3)]?.e;
          if (stray !== undefined) {
            const s1 = offline ? server + 0.1 * SECOND : when + 1.5 * SECOND + latency();
            tick(stray, actor, when + 1.5 * SECOND + h.skew, visit, 'accident', s1);
            const back = when + between(3, 5) * SECOND;
            tick(
              stray,
              actor,
              back + h.skew,
              visit,
              'accident',
              offline ? s1 + 0.1 * SECOND : back + latency(),
              'restored',
            );
          }
        }
      });
      return leave;
    }
    const conveyor = mode === 'checkout' && r() < 0.5;
    const order = conveyor ? shuffled(picked) : [...picked].sort((a, b) => priorPos(a.e) - priorPos(b.e));
    let u = mode === 'checkout' ? leave - between(1, 3) * MINUTE : leave + between(20, 90) * MINUTE;
    for (const { e } of order) {
      u += (mode === 'checkout' ? between(1, 5) : between(...p.catchUpGap)) * SECOND;
      tick(e, actor, u + h.skew, visit, mode);
    }
    return leave;
  };
  const priorPos = (e: Entry): number => {
    const s = e.store === null ? undefined : storeOf.get(e.store);
    return s?.prior.get(e.key) ?? keys[Number(e.key.slice(1))]?.generic ?? 0;
  };

  const storeWeights = p.stores.map((s) => s.weight);
  const weightTotal = storeWeights.reduce((a, b) => a + b, 0);
  const pickStore = (except?: string): string => {
    for (;;) {
      let u = r() * weightTotal;
      for (const s of p.stores) {
        u -= s.weight;
        if (u <= 0) {
          if (s.id !== except) return s.id;
          break;
        }
      }
      if (p.stores.length === 1) return p.stores[0]?.id ?? '';
    }
  };

  const visit = (store: string, shoppers: readonly string[], start: Ms, n: number): Ms => {
    const id = `v${visitCount++}`;
    const list = plan(store, n, shoppers[0] ?? '', start);
    const carried = leftOver.splice(0, leftOver.length).filter((e) => e.store === store);
    const all = [...list, ...carried];
    const home = members.find((m) => !shoppers.includes(m));
    if (home !== undefined && r() < p.remoteEdits && all.length > 4) {
      let t = start + between(2, 15) * MINUTE;
      for (const e of all.splice(0, int(1, 3))) {
        t += between(1, 4) * SECOND;
        tick(e, home, t + habits(home).skew, null, 'home-before');
      }
    }
    let end = start;
    if (shoppers.length === 2) {
      const layout = layoutOf(store);
      const sorted = [...all].sort((a, b) => (layout.get(a.key) ?? 0.5) - (layout.get(b.key) ?? 0.5));
      const half = Math.ceil(sorted.length / 2);
      const back = r() < p.opposite;
      end = Math.max(
        shop(id, store, shoppers[0] ?? '', sorted.slice(0, half), start, false),
        shop(id, store, shoppers[1] ?? '', sorted.slice(half), start, back),
      );
    } else {
      end = shop(id, store, shoppers[0] ?? '', all, start, false);
    }
    visits.push({ id, store, actors: shoppers, start, end });
    return end;
  };

  const t0 = Date.UTC(2026, 8, 7);
  for (let w = 0; w < p.weeks; w++) {
    const week = t0 + w * 7 * DAY;
    const n = Math.max(1, Math.round(p.visitsPerWeek + between(-0.5, 0.5)));
    const days = shuffled([0, 1, 2, 3, 4, 5]).slice(0, Math.min(6, n)).sort();
    for (const d of days) {
      const shopper = pick(members);
      const start = week + d * DAY + between(9, 19) * HOUR;
      const store = pickStore();
      const shoppers = members.length > 1 && r() < p.together
        ? [shopper, ...members.filter((m) => m !== shopper).slice(0, 1)]
        : [shopper];
      let end = visit(store, shoppers, start, int(5, 18));
      if (r() < p.backToBack && p.stores.length > 1) {
        const second = pickStore(store);
        end = visit(
          second,
          [shopper],
          end + between(3, 12) * MINUTE,
          r() < p.smallSecondStore ? int(1, 2) : int(4, 10),
        );
      }
      if (r() < p.sameStoreAgain) visit(store, [shopper], end + between(3, 6) * HOUR, int(2, 4));
    }
    for (let k = 0; k < Math.round(p.deliveries + between(-0.5, 0.5)); k++) {
      const store = pick(stores.filter((s) => !s.pharmacy)).id;
      const actor = pick(members);
      const list = plan(store, int(10, 18), actor, week + 6 * DAY);
      let t = week + 6 * DAY + between(10, 18) * HOUR;
      for (const e of shuffled(list)) {
        t += between(...p.unpackGap) * SECOND;
        tick(e, actor, t + habits(actor).skew, null, 'delivery');
      }
    }
    for (const m of members) {
      const h = habits(m);
      for (let k = 0; k < Math.round(h.homeBefore + between(-0.5, 0.5)); k++) {
        const store = pickStore();
        const list = plan(store, int(1, 4), m, week + 2 * DAY);
        let t = week + int(0, 6) * DAY + between(7, 22) * HOUR;
        for (const e of list) {
          t += between(1, 3) * SECOND;
          tick(e, m, t + h.skew, null, 'home-before');
        }
      }
      for (let k = 0; k < Math.round(h.voice + between(-0.5, 0.5)); k++) {
        const store = pickStore();
        const [e] = plan(store, 1, m, week + 3 * DAY);
        if (e === undefined) continue;
        const t = week + int(0, 6) * DAY + between(7, 22) * HOUR;
        tick(e, m, t, null, 'voice', t + latency(), 'bought', 'voice');
      }
    }
  }

  return { name: p.name, stores, ticks: replay(events), visits, bought };
}

/** Puts the events in commit order, as `item_events` ids are, and counts what each tick leaves open. */
function replay(events: readonly RawEvent[]): Tick[] {
  const open = new Map<string, Set<string>>();
  const bucket = (store: string | null): Set<string> => {
    const k = store ?? '-';
    let s = open.get(k);
    if (s === undefined) open.set(k, s = new Set());
    return s;
  };
  const ticks: Tick[] = [];
  for (const e of [...events].sort((a, b) => a.serverAt - b.serverAt)) {
    const set = bucket(e.store);
    if (e.kind === 'added' || e.kind === 'restored') set.add(e.item);
    else set.delete(e.item);
    if (e.kind === 'added') continue;
    ticks.push({
      id: ticks.length + 1,
      item: e.item,
      key: e.key,
      actor: e.actor,
      source: e.source,
      kind: e.kind,
      clientAt: e.at,
      serverAt: e.serverAt,
      store: e.store,
      storeOpenAfter: set.size,
      truth: { visit: e.visit, context: e.context },
    });
  }
  return ticks;
}
