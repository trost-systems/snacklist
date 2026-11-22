import {
  DAY,
  type Detection,
  HOUR,
  type Household,
  MINUTE,
  type Ms,
  SECOND,
  type Segment,
  type StoreMemoryWrite,
  type Tick,
  type Trip,
} from './model.ts';
import { shuffles } from './learn.ts';

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
function majority(
  ticks: readonly Timed[],
): { store: string | null; share: number; tagged: number } {
  const counts = new Map<string, number>();
  for (const x of ticks) {
    if (x.tick.store !== null) counts.set(x.tick.store, (counts.get(x.tick.store) ?? 0) + 1);
  }
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
      o.store !== null && o.store === trip.store && trip.start <= o.end + slack &&
      o.start <= trip.end + slack &&
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
  /** `client_at` is stored only within this far before and after the commit, else null (commit time). */
  readonly clientBefore: Ms;
  readonly clientAfter: Ms;
  /** T4a narrowed: store memory only from a walk 75 % one store (3+ tagged ticks), not its edge ticks. */
  readonly narrowMemory: boolean;
  /** A key's store moves once this many walks at that store have proposed it. */
  readonly memoryConfirm: number;
  /** T1a as approved: a run also ends at the tick that leaves its store with no open item. */
  readonly allTickedEnds: boolean;
  /** A walk the order learner's gate turns away as a shuffle writes no store memory either. */
  readonly gateMemory: boolean;
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
  clientBefore: 7 * DAY,
  clientAfter: 24 * HOUR,
  narrowMemory: false,
  memoryConfirm: 2,
  allTickedEnds: false,
  gateMemory: true,
};

/**
 * The device's clock, shifted by its usual difference to the server: the 10th percentile of
 * (commit time - device time) over the person's ticks of the 7 days before and the 36 hours after
 * the tick (what a run at most 36 hours later has seen), which online ticks set and offline ones
 * (later commits) do not.
 */
function corrected(h: Household, p: Params): Timed[] {
  const out: Timed[] = [];
  const stored = (t: Tick): boolean =>
    t.serverAt - t.clientAt <= p.clientBefore && t.clientAt - t.serverAt <= p.clientAfter;
  for (const own of groupBy(h.ticks, (t) => t.actor).values()) {
    for (const tick of own) if (!stored(tick)) out.push({ tick, t: tick.serverAt });
    const sorted = own.filter(stored).sort((a, b) => a.serverAt - b.serverAt);
    let lo = 0;
    let hi = 0;
    for (const tick of sorted) {
      while ((sorted[lo]?.serverAt ?? Infinity) < tick.serverAt - 7 * DAY) lo++;
      while (
        hi < sorted.length && (sorted[hi]?.serverAt ?? Infinity) <= tick.serverAt + 36 * HOUR
      ) hi++;
      const d = sorted.slice(lo, hi).map((o) => o.serverAt - o.clientAt).sort((a, b) => a - b);
      out.push({ tick, t: tick.clientAt + (d[Math.floor(d.length * 0.1)] ?? 0) });
    }
  }
  return out;
}

/** T1a's second end: after the tick that ticks the last open item of the store most of the run is at. */
function allTicked(run: readonly Timed[]): Timed[][] {
  const out: Timed[][] = [];
  let current: Timed[] = [];
  for (const x of run) {
    current.push(x);
    if (
      x.tick.store !== null && x.tick.store === majority(current).store &&
      x.tick.storeOpenAfter === 0
    ) {
      out.push(current);
      current = [];
    }
  }
  if (current.length > 0) out.push(current);
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
  const gaps = cs.slice(1).map((c, i) => (c[0]?.t ?? 0) - (cs[i]?.[cs[i].length - 1]?.t ?? 0)).sort(
    (a, b) => a - b,
  );
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
    if (
      last !== undefined &&
      (x.tick.store === null || x.tick.store === last.store || last.store === null)
    ) {
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
  // Job 352 (GL-2, above parity with 351): a pharmacy's ticks are dropped before anything else,
  // so they join no neighbouring store's trip or walk; 351 judged pharmacy per piece by majority.
  const pharmacies = new Set(h.stores.filter((s) => s.pharmacy).map((s) => s.id));
  const ticks = kept(
    (p.clientTime ? corrected(h, p) : h.ticks.map((tick) => ({ tick, t: tick.serverAt })))
      .filter((x) => x.tick.store === null || !pharmacies.has(x.tick.store)),
  );
  const walks: Piece[] = [];
  const pieces: { piece: Piece; walk: boolean }[] = [];
  for (const own of groupBy(ticks, (x) => x.tick.actor).values()) {
    const runs = chains(own, p.gap).flatMap((run) => (p.allTickedEnds ? allTicked(run) : [run]));
    for (const run of runs) {
      for (const xs of byStore(run, p.switchGap)) {
        const { store } = majority(xs);
        const piece = { xs, store, clumps: clumps(xs, p.clump) };
        const first = xs[0];
        const last = xs[xs.length - 1];
        const small = xs.length < 3 && first !== undefined && last !== undefined &&
          store !== null &&
          last.t - first.t <= 5 * MINUTE && majority(xs).share === 1 &&
          last.tick.storeOpenAfter === 0 &&
          xs.every((x) => x.tick.store === store);
        const walked = piece.clumps.length >= p.minClumps && medianGap(piece.clumps) >= p.pace;
        if (walked || small) walks.push(piece);
        pieces.push({ piece, walk: walked || small });
      }
    }
  }

  const segments: Segment[] = [];
  const storeMemory: StoreMemoryWrite[] = [];
  const proposals = new Map<string, number>();
  const trips: { xs: Timed[]; store: string | null; walked: boolean }[] = [];
  for (const w of [...walks].sort((a, b) => (a.xs[0]?.t ?? 0) - (b.xs[0]?.t ?? 0))) {
    if (w.store !== null && w.clumps.length >= 2) {
      segments.push({
        store: w.store,
        at: w.xs[0]?.t ?? 0,
        clumps: w.clumps.map((c) => c.map((x) => x.tick.key)),
      });
    }
    const m = majority(w.xs);
    if (w.store !== null && (!p.narrowMemory || (m.tagged >= 3 && m.share >= 0.75))) {
      w.xs.forEach((x, i) => {
        const inside = !p.narrowMemory || (i > 0 && i < w.xs.length - 1);
        if (w.store === null || !(x.tick.store === null || (x.tick.store !== w.store && inside))) {
          return;
        }
        const proposal = `${x.tick.key}\u0000${w.store}`;
        const n = (proposals.get(proposal) ?? 0) + 1;
        proposals.set(proposal, n);
        if (n >= p.memoryConfirm) {
          storeMemory.push({
            key: x.tick.key,
            store: w.store,
            tick: x.tick,
            walk: w.xs[0]?.t ?? 0,
          });
        }
      });
    }
  }
  // Job 352, TD-Q2 (Peter): a person's next run at the same store within 30 minutes of the trip's
  // last tick continues it, walk or burst, in either order; 351 joined only a walk or a later burst
  // to a walk. A trip with no walk needs 5 ticks (TD-Q1); only walks teach (segments above).
  for (
    const { piece, walk } of [...pieces].sort((a, b) =>
      (a.piece.xs[0]?.t ?? 0) - (b.piece.xs[0]?.t ?? 0)
    )
  ) {
    const actor = piece.xs[0]?.tick.actor;
    const start = piece.xs[0]?.t ?? 0;
    const before = trips.find((t) =>
      t.xs[0]?.tick.actor === actor &&
      (walk ? t.store === piece.store : piece.store === null || piece.store === t.store) &&
      start >= (t.xs[0]?.t ?? 0) && start - (t.xs[t.xs.length - 1]?.t ?? 0) <= p.pause
    );
    if (before !== undefined) {
      before.xs.push(...piece.xs);
      before.walked ||= walk;
    } else trips.push({ xs: [...piece.xs], store: piece.store, walked: walk });
  }
  const history = trips.filter((t) => t.walked || t.xs.length >= p.sweepTrip)
    .map((t) => tripOf(t.xs.sort(byTime), t.store, t.walked));
  const turnedAway = p.gateMemory ? [...shuffles(h.stores, segments)] : [];
  const taughtMemory = storeMemory.filter((w) =>
    !turnedAway.some((s) => s.store === w.store && s.at === w.walk)
  );
  return { trips: mergeHousehold(history, p.gap), segments, storeMemory: taughtMemory };
}
