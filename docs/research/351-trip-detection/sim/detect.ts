import {
  type Detection,
  type Household,
  MINUTE,
  type Ms,
  SECOND,
  type Segment,
  type StoreMemoryWrite,
  type Tick,
  type Trip,
} from './model.ts';

/** A tick with the time a detector believes. */
interface Timed {
  readonly tick: Tick;
  readonly t: Ms;
}

const byTime = (a: Timed, b: Timed): number => a.t - b.t || a.tick.id - b.tick.id;

/** T5a: app ticks only, and a bought tick the same person undid within ten minutes counts as never made. */
function kept(ticks: readonly Timed[]): Timed[] {
  const app = ticks.filter((x) => x.tick.source === 'app').sort(byTime);
  const dropped = new Set<number>();
  app.forEach((x, i) => {
    if (x.tick.kind !== 'restored') return;
    for (let j = i - 1; j >= 0; j--) {
      const y = app[j];
      if (y === undefined || x.t - y.t > 10 * MINUTE) break;
      if (
        y.tick.kind === 'bought' && y.tick.item === x.tick.item && y.tick.actor === x.tick.actor &&
        !dropped.has(y.tick.id)
      ) {
        dropped.add(y.tick.id);
        break;
      }
    }
  });
  return app.filter((x) => x.tick.kind === 'bought' && !dropped.has(x.tick.id));
}

function groupBy<T, K>(xs: readonly T[], key: (x: T) => K): Map<K, T[]> {
  const out = new Map<K, T[]>();
  for (const x of xs) {
    const k = key(x);
    const list = out.get(k);
    if (list === undefined) out.set(k, [x]);
    else list.push(x);
  }
  return out;
}

/** The store most of [ticks] are tagged with; null when none is. */
function majority(ticks: readonly Timed[]): { store: string | null; share: number; tagged: number } {
  const counts = new Map<string, number>();
  for (const x of ticks) if (x.tick.store !== null) counts.set(x.tick.store, (counts.get(x.tick.store) ?? 0) + 1);
  let store: string | null = null;
  let best = 0;
  let tagged = 0;
  for (const [s, n] of counts) {
    tagged += n;
    if (n > best) [store, best] = [s, n];
  }
  return { store, share: tagged === 0 ? 0 : best / tagged, tagged };
}

/** Splits [xs] (one person, time order) wherever two ticks are further apart than [gap]. */
function chains(xs: readonly Timed[], gap: Ms): Timed[][] {
  const out: Timed[][] = [];
  let current: Timed[] = [];
  for (const x of xs) {
    const last = current[current.length - 1];
    if (last !== undefined && x.t - last.t > gap) {
      out.push(current);
      current = [];
    }
    current.push(x);
  }
  if (current.length > 0) out.push(current);
  return out;
}

/** T2a: trips of different people at the same store whose times overlap (plus [slack]) are one household trip. */
function mergeHousehold(trips: readonly Trip[], slack: Ms): Trip[] {
  const out: Trip[] = [];
  for (const trip of [...trips].sort((a, b) => a.start - b.start)) {
    const other = out.find((o) =>
      o.store !== null && o.store === trip.store && trip.start <= o.end + slack && o.start <= trip.end + slack &&
      trip.actors.some((a) => !o.actors.includes(a))
    );
    if (other === undefined) {
      out.push(trip);
      continue;
    }
    out.splice(out.indexOf(other), 1, {
      store: other.store,
      actors: [...new Set([...other.actors, ...trip.actors])],
      start: Math.min(other.start, trip.start),
      end: Math.max(other.end, trip.end),
      ticks: [...other.ticks, ...trip.ticks],
      walked: other.walked || trip.walked,
    });
  }
  return out;
}

const tripOf = (xs: readonly Timed[], store: string | null, walked: boolean): Trip => ({
  store,
  actors: [...new Set(xs.map((x) => x.tick.actor))],
  start: xs[0]?.t ?? 0,
  end: xs[xs.length - 1]?.t ?? 0,
  ticks: xs.map((x) => x.tick),
  walked,
});

/**
 * Peter's approved starting rule, on the data the server has today (commit times).
 * H1, H2, T1a, T2a, T3a, T4a, T5a as written in the job 351 brief.
 */
export function startingRule(h: Household): Detection {
  const pharmacies = new Set(h.stores.filter((s) => s.pharmacy).map((s) => s.id));
  const ticks = kept(h.ticks.map((tick) => ({ tick, t: tick.serverAt })));
  const trips: Trip[] = [];
  const segments: Segment[] = [];
  const storeMemory: StoreMemoryWrite[] = [];
  for (const own of groupBy(ticks, (x) => x.tick.actor).values()) {
    for (const quiet of chains(own, 10 * MINUTE)) {
      // T1a: a trip also ends once every item of its store is ticked.
      const parts: Timed[][] = [];
      let current: Timed[] = [];
      for (const x of quiet) {
        current.push(x);
        const { store } = majority(current);
        if (x.tick.store !== null && x.tick.store === store && x.tick.storeOpenAfter === 0) {
          parts.push(current);
          current = [];
        }
      }
      if (current.length > 0) parts.push(current);
      for (const part of parts) {
        const { store, tagged } = majority(part);
        const h1 = part.some((x, i) => {
          const b = part[i + 1];
          const c = part[i + 2];
          return b !== undefined && c !== undefined && b.t - x.t < 5 * MINUTE && c.t - b.t < 5 * MINUTE;
        });
        const first = part[0];
        const last = part[part.length - 1];
        const t3a = part.length < 3 && first !== undefined && last !== undefined && last.t - first.t <= 5 * MINUTE &&
          tagged === part.length && majority(part).share === 1 && last.tick.storeOpenAfter === 0;
        if (!h1 && !t3a) continue;
        if (store !== null && pharmacies.has(store)) continue;
        trips.push(tripOf(part, store, true));
        if (store === null) continue;
        segments.push({ store, at: first?.t ?? 0, clumps: part.map((x) => [x.tick.key]) });
        for (const x of part) if (x.tick.store !== store) storeMemory.push({ key: x.tick.key, store, tick: x.tick });
      }
    }
  }
  return { trips: mergeHousehold(trips, 0), segments: segments.sort((a, b) => a.at - b.at), storeMemory };
}

export interface Params {
  /** Ticks further apart than this end a run (T1a's ten minutes). */
  readonly gap: Ms;
  /** Ticks closer than this are one clump: same shelf, or a batch. */
  readonly clump: Ms;
  /** A walk needs this many clumps (H1's three, counted in clumps instead of ticks). */
  readonly minClumps: number;
  /** A walk's median gap between clumps is at least this: people walk between shelves. */
  readonly pace: Ms;
  /** Two runs of one person at one store this close are one trip in history (a pause). */
  readonly pause: Ms;
  /** A change of store splits a run only after this long without a tick: getting there takes time. */
  readonly switchGap: Ms;
  /** A burst without a walk becomes a trip in history from this many ticks; Infinity: never. */
  readonly sweepTrip: number;
  /** Times from the device's clock, corrected by its usual offset; else commit times. */
  readonly clientTime: boolean;
}

export const FINAL: Params = {
  gap: 10 * MINUTE,
  clump: 6 * SECOND,
  minClumps: 3,
  pace: 20 * SECOND,
  pause: 30 * MINUTE,
  switchGap: 2 * MINUTE,
  sweepTrip: 5,
  clientTime: true,
};

/**
 * The device's clock, shifted by its usual difference to the server: the 10th percentile of
 * (commit time - device time) over the person's ticks, which online ticks set and offline ones
 * (later commits) do not.
 */
function corrected(h: Household): Timed[] {
  const out: Timed[] = [];
  for (const own of groupBy(h.ticks, (t) => t.actor).values()) {
    const d = own.map((t) => t.serverAt - t.clientAt).sort((a, b) => a - b);
    const offset = d[Math.floor(d.length * 0.1)] ?? 0;
    for (const tick of own) out.push({ tick, t: tick.clientAt + offset });
  }
  return out;
}

interface Piece {
  readonly xs: readonly Timed[];
  readonly store: string | null;
  readonly clumps: readonly (readonly Timed[])[];
}

function clumps(xs: readonly Timed[], window: Ms): Timed[][] {
  const out: Timed[][] = [];
  for (const x of xs) {
    const current = out[out.length - 1];
    const last = current?.[current.length - 1];
    if (current !== undefined && last !== undefined && x.t - last.t < window) current.push(x);
    else out.push([x]);
  }
  return out;
}

function medianGap(cs: readonly (readonly Timed[])[]): Ms {
  const gaps = cs.slice(1).map((c, i) => (c[0]?.t ?? 0) - (cs[i]?.[cs[i].length - 1]?.t ?? 0)).sort((a, b) => a - b);
  return gaps[Math.floor(gaps.length / 2)] ?? 0;
}

/**
 * Splits one run where the person moved to another store: blocks of one store in a row, a block
 * sandwiched by another store's ticks belongs to that store (an item bought where it was not
 * tagged), and a lone tick at either end joins its neighbour unless it finishes its store's items.
 */
function byStore(run: readonly Timed[], switchGap: Ms): Timed[][] {
  const blocks: { store: string | null; xs: Timed[] }[] = [];
  for (const x of run) {
    const last = blocks[blocks.length - 1];
    if (last !== undefined && (x.tick.store === null || x.tick.store === last.store || last.store === null)) {
      last.xs.push(x);
      if (last.store === null) last.store = x.tick.store;
    } else blocks.push({ store: x.tick.store, xs: [x] });
  }
  const join = (i: number, into: number): void => {
    const a = blocks[i];
    const b = blocks[into];
    if (a === undefined || b === undefined) return;
    b.xs = [...b.xs, ...a.xs].sort(byTime);
    blocks.splice(i, 1);
  };
  for (let changed = true; changed;) {
    changed = false;
    for (let i = 0; i < blocks.length; i++) {
      const prev = blocks[i - 1];
      const block = blocks[i];
      const next = blocks[i + 1];
      if (block === undefined) continue;
      if (prev !== undefined && next !== undefined && prev.store === next.store) {
        join(i, i - 1);
        join(i, i - 1);
        changed = true;
        break;
      }
      const edge = prev === undefined || next === undefined;
      const lone = block.xs.length === 1 && block.xs[0]?.tick.storeOpenAfter !== 0;
      if (edge && lone && blocks.length > 1) {
        join(i, prev === undefined ? i + 1 : i - 1);
        changed = true;
        break;
      }
      if (prev !== undefined && prev.store === block.store) {
        join(i, i - 1);
        changed = true;
        break;
      }
    }
  }
  for (let i = 1; i < blocks.length;) {
    const prev = blocks[i - 1];
    const block = blocks[i];
    if (prev === undefined || block === undefined) break;
    if ((block.xs[0]?.t ?? 0) - (prev.xs[prev.xs.length - 1]?.t ?? 0) < switchGap) join(i, i - 1);
    else i++;
  }
  return blocks.map((b) => b.xs);
}

/** The proposed rule (README "Final rule"); [p] lets the evaluator move one knob at a time. */
export function finalRule(h: Household, p: Params = FINAL): Detection {
  const pharmacies = new Set(h.stores.filter((s) => s.pharmacy).map((s) => s.id));
  const ticks = kept(p.clientTime ? corrected(h) : h.ticks.map((tick) => ({ tick, t: tick.serverAt })));
  const walks: Piece[] = [];
  const bursts: Piece[] = [];
  for (const own of groupBy(ticks, (x) => x.tick.actor).values()) {
    for (const run of chains(own, p.gap)) {
      for (const xs of byStore(run, p.switchGap)) {
        const { store } = majority(xs);
        if (store !== null && pharmacies.has(store)) continue;
        const piece = { xs, store, clumps: clumps(xs, p.clump) };
        const first = xs[0];
        const last = xs[xs.length - 1];
        const small = xs.length < 3 && first !== undefined && last !== undefined && store !== null &&
          last.t - first.t <= 5 * MINUTE && majority(xs).share === 1 && last.tick.storeOpenAfter === 0 &&
          xs.every((x) => x.tick.store === store);
        const walked = piece.clumps.length >= p.minClumps && medianGap(piece.clumps) >= p.pace;
        (walked || small ? walks : bursts).push(piece);
      }
    }
  }

  const segments: Segment[] = [];
  const storeMemory: StoreMemoryWrite[] = [];
  const trips: { xs: Timed[]; store: string | null; walked: boolean }[] = [];
  for (const w of [...walks].sort((a, b) => (a.xs[0]?.t ?? 0) - (b.xs[0]?.t ?? 0))) {
    if (w.store !== null && w.clumps.length >= 2) {
      segments.push({ store: w.store, at: w.xs[0]?.t ?? 0, clumps: w.clumps.map((c) => c.map((x) => x.tick.key)) });
    }
    const m = majority(w.xs);
    if (w.store !== null && m.tagged >= 3 && m.share >= 0.75) {
      w.xs.forEach((x, i) => {
        const inside = i > 0 && i < w.xs.length - 1;
        if (x.tick.store === null || (x.tick.store !== w.store && inside)) {
          storeMemory.push({ key: x.tick.key, store: w.store ?? '', tick: x.tick });
        }
      });
    }
    const actor = w.xs[0]?.tick.actor;
    const start = w.xs[0]?.t ?? 0;
    const before = trips.find((t) =>
      t.walked && t.store === w.store && t.xs[0]?.tick.actor === actor &&
      start - (t.xs[t.xs.length - 1]?.t ?? 0) <= p.pause && start >= (t.xs[0]?.t ?? 0)
    );
    if (before !== undefined) before.xs.push(...w.xs);
    else trips.push({ xs: [...w.xs], store: w.store, walked: true });
  }
  for (const b of bursts) {
    const actor = b.xs[0]?.tick.actor;
    const start = b.xs[0]?.t ?? 0;
    const after = trips.find((t) =>
      t.walked && t.xs[0]?.tick.actor === actor && (b.store === null || b.store === t.store) &&
      start >= (t.xs[t.xs.length - 1]?.t ?? 0) && start - (t.xs[t.xs.length - 1]?.t ?? 0) <= p.pause
    );
    if (after !== undefined) after.xs.push(...b.xs);
    else if (b.xs.length >= p.sweepTrip) trips.push({ xs: [...b.xs], store: b.store, walked: false });
  }
  const history = trips.map((t) => tripOf(t.xs.sort(byTime), t.store, t.walked));
  return { trips: mergeHousehold(history, p.gap), segments, storeMemory };
}
