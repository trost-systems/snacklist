import { FINAL, finalRule, type Params, startingRule } from './detect.ts';
import { generate, type Habits, type Persona } from './generate.ts';
import { ema, reassign } from './learn.ts';
import {
  type Detection,
  type Detector,
  HOUR,
  type Household,
  type Learner,
  MINUTE,
  SECOND,
  type Segment,
} from './model.ts';

const quiet: Habits = {
  walk: 0.85,
  checkout: 0.1,
  offline: 0.05,
  skew: 0,
  accident: 0.03,
  impulse: 0.2,
  homeBefore: 0,
  voice: 0,
  dismiss: 0,
};

const base: Omit<Persona, 'name' | 'seed' | 'members'> = {
  weeks: 12,
  stores: [
    { id: 'rewe', shuffle: 0.25, weight: 0.5 },
    { id: 'aldi', shuffle: 0.35, weight: 0.35 },
    { id: 'ikea', shuffle: 1.2, weight: 0.08 },
    { id: 'apotheke', shuffle: 0.3, weight: 0.07, pharmacy: true },
  ],
  visitsPerWeek: 2.5,
  backToBack: 0.25,
  smallSecondStore: 0.4,
  together: 0.1,
  opposite: 0.5,
  sameStoreAgain: 0.1,
  deliveries: 0,
  longWait: 0.15,
  remoteEdits: 0.15,
  notFound: 0.05,
  shelfBatch: 0.5,
  catchUpGap: [1, 3],
  unpackGap: [4, 20],
};

/** Households with one chaotic habit turned up each; README "Simulation" explains them. */
export const personas: readonly Persona[] = [
  {
    ...base,
    name: 'peter-lea',
    seed: 1,
    members: {
      peter: { ...quiet, walk: 0.85, offline: 0.1, skew: 40 * SECOND, homeBefore: 0.5, voice: 1 },
      lea: { ...quiet, walk: 0.4, checkout: 0.35, homeBefore: 1, voice: 0.5, dismiss: 3 },
    },
  },
  {
    ...base,
    name: 'offline-wrong-clock',
    seed: 2,
    backToBack: 0.4,
    members: { solo: { ...quiet, walk: 0.9, offline: 0.5, skew: -HOUR, accident: 0.06, impulse: 0.6 } },
  },
  {
    ...base,
    name: 'checkout-ticker',
    seed: 3,
    members: { a: { ...quiet, walk: 0.15, checkout: 0.7 }, b: { ...quiet, walk: 0.2, checkout: 0.5 } },
  },
  {
    ...base,
    name: 'home-sweeper',
    seed: 4,
    members: {
      a: { ...quiet, walk: 0.1, checkout: 0.1, homeBefore: 2 },
      b: { ...quiet, walk: 0.5, homeBefore: 1.5 },
    },
  },
  {
    ...base,
    name: 'delivery',
    seed: 5,
    deliveries: 1,
    visitsPerWeek: 1.5,
    members: { a: { ...quiet }, b: { ...quiet, walk: 0.6 } },
  },
  {
    ...base,
    name: 'split-couple',
    seed: 6,
    together: 0.8,
    opposite: 0.5,
    members: { a: { ...quiet }, b: { ...quiet, skew: 2 * MINUTE } },
  },
  {
    ...base,
    name: 'slow-trips',
    seed: 7,
    longWait: 0.6,
    sameStoreAgain: 0.4,
    backToBack: 0.5,
    members: { a: { ...quiet, walk: 0.9 } },
  },
  {
    ...base,
    name: 'slow-unpacker',
    seed: 8,
    deliveries: 1,
    visitsPerWeek: 1.5,
    unpackGap: [15, 60],
    members: { a: { ...quiet }, b: { ...quiet, walk: 0.6 } },
  },
  {
    ...base,
    name: 'slow-catchup',
    seed: 9,
    catchUpGap: [15, 60],
    members: { a: { ...quiet, walk: 0.2, checkout: 0.1 }, b: { ...quiet, walk: 0.5, checkout: 0.1 } },
  },
];

export interface Score {
  readonly visits: number;
  readonly trips: number;
  readonly precision: number;
  readonly recall: number;
  /** Trips with mostly ticks from no store visit (home, delivery). */
  readonly phantom: number;
  /** Visits found as two or more trips. */
  readonly split: number;
  /** Trips whose ticks are from one visit but whose store is wrong. */
  readonly wrongStore: number;
  readonly memoryWrites: number;
  readonly memoryWrong: number;
  /** Keys store memory wrote, and those whose last write is not the store the household buys them at most. */
  readonly memoryKeys: number;
  readonly memoryKeysWrong: number;
  /** Taught pairs (keys in different clumps of a segment) against the real walk order. */
  readonly pairs: number;
  readonly pairsWrong: number;
}

export function score(h: Household, d: Detection): Score {
  const storeOf = new Map(h.visits.map((v) => [v.id, v.store]));
  const ticked = new Set(h.ticks.filter((t) => t.source === 'app' && t.kind === 'bought').map((t) => t.truth.visit));
  const pharmacies = new Set(h.stores.filter((s) => s.pharmacy).map((s) => s.id));
  // GL-2: a pharmacy visit is never a trip, so it is not a miss either.
  const visits = h.visits.filter((v) => ticked.has(v.id) && !pharmacies.has(v.store));
  const matched = new Map<string, number>();
  let good = 0;
  let phantom = 0;
  let wrongStore = 0;
  for (const trip of d.trips) {
    const counts = new Map<string | null, number>();
    for (const t of trip.ticks) counts.set(t.truth.visit, (counts.get(t.truth.visit) ?? 0) + 1);
    let best: string | null = null;
    let n = 0;
    for (const [v, c] of counts) if (c > n) [best, n] = [v, c];
    if (best === null) {
      phantom++;
      continue;
    }
    if (n / trip.ticks.length < 0.5) continue;
    if (storeOf.get(best) !== trip.store) {
      wrongStore++;
      continue;
    }
    good++;
    matched.set(best, (matched.get(best) ?? 0) + 1);
  }
  let memoryWrong = 0;
  for (const w of d.storeMemory) {
    const v = w.tick.truth.visit;
    if (v === null || storeOf.get(v) !== w.store) memoryWrong++;
  }
  const usual = new Map<string, Map<string, number>>();
  for (const t of h.ticks) {
    const store = t.truth.visit === null ? undefined : storeOf.get(t.truth.visit);
    if (store === undefined || t.kind !== 'bought') continue;
    const counts = usual.get(t.key) ?? new Map<string, number>();
    counts.set(store, (counts.get(store) ?? 0) + 1);
    usual.set(t.key, counts);
  }
  const last = new Map<string, string>();
  for (const w of [...d.storeMemory].sort((a, b) => a.tick.clientAt - b.tick.clientAt)) last.set(w.key, w.store);
  let memoryKeysWrong = 0;
  for (const [key, store] of last) {
    const counts = [...(usual.get(key) ?? new Map<string, number>())].sort((a, b) => b[1] - a[1]);
    if (counts[0]?.[0] !== store) memoryKeysWrong++;
  }
  const { pairs, wrong } = taught(h, d.segments);
  return {
    visits: visits.length,
    trips: d.trips.length,
    precision: d.trips.length === 0 ? 1 : good / d.trips.length,
    recall: visits.length === 0 ? 1 : matched.size / visits.length,
    phantom,
    split: [...matched.values()].filter((c) => c > 1).length,
    wrongStore,
    memoryWrites: d.storeMemory.length,
    memoryWrong,
    memoryKeys: last.size,
    memoryKeysWrong,
    pairs,
    pairsWrong: wrong,
  };
}

function taught(h: Household, segments: readonly Segment[]): { pairs: number; wrong: number } {
  const layout = new Map(h.stores.map((s) => [s.id, s.layout]));
  let pairs = 0;
  let wrong = 0;
  for (const seg of segments) {
    const l = layout.get(seg.store);
    if (l === undefined) continue;
    const seen: number[] = [];
    for (const clump of seg.clumps) {
      const at = clump.map((k) => l.get(k)).filter((x): x is number => x !== undefined);
      for (const a of seen) {
        for (const b of at) {
          pairs++;
          if (a > b) wrong++;
        }
      }
      seen.push(...at);
    }
  }
  return { pairs, wrong };
}

/** Share of pairs of keys the household bought at a store that [order] puts as the store's aisles do. */
export function orderAccuracy(h: Household, orders: ReadonlyMap<string, ReadonlyMap<string, number>>): number {
  let right = 0;
  let all = 0;
  for (const s of h.stores) {
    if (s.pharmacy) continue;
    const order = orders.get(s.id);
    const keys = [...(h.bought.get(s.id) ?? [])].filter((k) => s.layout.has(k));
    if (order === undefined) continue;
    for (let i = 0; i < keys.length; i++) {
      for (let j = i + 1; j < keys.length; j++) {
        const a = keys[i] ?? '';
        const b = keys[j] ?? '';
        const truth = (s.layout.get(a) ?? 0) < (s.layout.get(b) ?? 0);
        const got = (order.get(a) ?? 0) < (order.get(b) ?? 0);
        all++;
        if (truth === got) right++;
      }
    }
  }
  return all === 0 ? 1 : right / all;
}

/** Every visit teaching its real walk: the ceiling for any detector. */
export function oracle(h: Household): Segment[] {
  const layout = new Map(h.stores.map((s) => [s.id, s.layout]));
  const out: Segment[] = [];
  for (const v of h.visits) {
    const l = layout.get(v.store);
    if (l === undefined || h.stores.find((s) => s.id === v.store)?.pharmacy) continue;
    const keys = [...new Set(h.ticks.filter((t) => t.truth.visit === v.id && t.kind === 'bought').map((t) => t.key))];
    keys.sort((a, b) => (l.get(a) ?? 0) - (l.get(b) ?? 0));
    out.push({ store: v.store, at: v.start, clumps: keys.map((k) => [k]) });
  }
  return out;
}

export interface Run {
  readonly name: string;
  readonly detector: Detector;
  readonly learner: Learner;
}

export const runs: readonly Run[] = [
  { name: 'starting rule + ema', detector: startingRule, learner: ema },
  { name: 'starting rule + final learner', detector: startingRule, learner: reassign() },
  { name: 'final rule + ema', detector: finalRule, learner: ema },
  { name: 'final rule + final learner', detector: finalRule, learner: reassign() },
];

export interface Variant {
  readonly name: string;
  readonly params: Params;
  readonly learner: Learner;
}

const FINAL_VARIANT: Variant = { name: 'final', params: FINAL, learner: reassign() };
const v = (name: string, params: Partial<Params>, learner: Learner = reassign()): Variant => ({
  name,
  params: { ...FINAL, ...params },
  learner,
});

/** The final rule with one knob moved; the first rows put back one approved rule each, or try a rejected fix. */
export const variants: readonly Variant[] = [
  FINAL_VARIANT,
  v('H1 as approved: no pace rule, no clumps', { pace: 0, clump: 0 }),
  v('T1a as approved: all ticked ends the trip, no pause', { allTickedEnds: true, pause: 0 }),
  v('T1a all-ticked end kept (pause stays)', { allTickedEnds: true }),
  v('T3a as approved: no travel time', { switchGap: 0 }),
  v('T4a as approved: immediate, shuffles not gated', { memoryConfirm: 1, gateMemory: false }),
  v('T4a immediate (shuffles gated)', { memoryConfirm: 1 }),
  v('T4a narrowed too: 75 % one store, not the edge ticks', { narrowMemory: true }),
  v('commit times (no tap time)', { clientTime: false }),
  v('store memory not gated by shuffles', { gateMemory: false }),
  v('no outlier gate', {}, reassign(0.5, null)),
  v('no pace rule', { pace: 0 }),
  v('no pace rule, no outlier gate', { pace: 0 }, reassign(0.5, null)),
  v('outlier gate 0.5', {}, reassign(0.5, { after: 3, min: 0.5 })),
  v('outlier gate 0.7', {}, reassign(0.5, { after: 3, min: 0.7 })),
  v('no clumps (each tick its own)', { clump: 0 }),
  v('pace 40 s', { pace: 40 * SECOND }),
  v('clump 3 s', { clump: 3 * SECOND }),
  v('clump 10 s', { clump: 10 * SECOND }),
  v('gap 5 min', { gap: 5 * MINUTE }),
  v('gap 15 min', { gap: 15 * MINUTE }),
  v('no pause merge', { pause: 0 }),
  v('bursts never trips', { sweepTrip: Infinity }),
  v('bursts from 3 ticks', { sweepTrip: 3 }),
];

const pct = (x: number): string => `${Math.round(x * 100)} %`;

export function report(seeds = 5): string {
  const lines: string[] = [];
  const households = personas.flatMap((p) =>
    Array.from({ length: seeds }, (_, i) => generate({ ...p, seed: p.seed * 1000 + i }))
  );
  const named = (p: string): Household[] => households.filter((h) => h.name === p);

  lines.push(
    '| Household | Rule | Visits | Trips | Precision | Recall | Phantom | Split | Wrong store | Store memory writes wrong | Store memory keys wrong at the end | Walk pairs wrong | Order accuracy |',
    '| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |',
  );
  for (const p of personas) {
    const hs = named(p.name);
    const prior = mean(hs.map((h) => orderAccuracy(h, new Map(h.stores.map((s) => [s.id, s.prior])))));
    const ceiling = mean(hs.map((h) => orderAccuracy(h, reassign(0.5, null).learn(h.stores, oracle(h)))));
    for (const run of runs) {
      const scores = hs.map((h) => score(h, run.detector(h)));
      const acc = mean(hs.map((h) => orderAccuracy(h, run.learner.learn(h.stores, run.detector(h).segments))));
      lines.push(row(p.name, run.name, scores, acc));
    }
    lines.push(
      `| ${p.name} | prior only / every visit taught | | | | | | | | | | | ${pct(prior)} / ${pct(ceiling)} |`,
    );
  }
  lines.push(
    '',
    '| Variant of the final rule | Precision | Recall | Phantom | Split | Store memory writes wrong | Store memory keys wrong at the end | Walk pairs wrong | Order accuracy | Most affected household: final → variant |',
    '| --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |',
  );
  interface Look {
    readonly acc: number;
    readonly recall: number;
    readonly memory: number;
    readonly pairs: number;
  }
  const measured = new Map<Variant, Map<Household, { s: Score; acc: number }>>();
  const measure = (k: Variant, h: Household): { s: Score; acc: number } => {
    let byHousehold = measured.get(k);
    if (byHousehold === undefined) measured.set(k, byHousehold = new Map());
    let m = byHousehold.get(h);
    if (m === undefined) {
      const d = finalRule(h, k.params);
      m = { s: score(h, d), acc: orderAccuracy(h, k.learner.learn(h.stores, d.segments)) };
      byHousehold.set(h, m);
    }
    return m;
  };
  const look = (k: Variant, hs: readonly Household[]): Look & { s: Score } => {
    const ms = hs.map((h) => measure(k, h));
    const s = sum(ms.map((m) => m.s));
    const acc = mean(ms.map((m) => m.acc));
    return {
      s,
      acc,
      recall: s.recall,
      memory: s.memoryKeysWrong / Math.max(1, s.memoryKeys),
      pairs: s.pairsWrong / Math.max(1, s.pairs),
    };
  };
  const reference = new Map(personas.map((p) => [p.name, look(variants[0] ?? FINAL_VARIANT, named(p.name))]));
  for (const k of variants) {
    const all = look(k, households);
    let most = '';
    let delta = 0.005;
    for (const p of personas) {
      const ref = reference.get(p.name);
      if (ref === undefined || k === variants[0]) continue;
      const v = look(k, named(p.name));
      const d = Math.abs(v.acc - ref.acc) + Math.abs(v.recall - ref.recall) + Math.abs(v.memory - ref.memory) +
        Math.abs(v.pairs - ref.pairs);
      if (d > delta) {
        delta = d;
        most = `${p.name}: order ${pct(ref.acc)} → ${pct(v.acc)}, recall ${pct(ref.recall)} → ${
          pct(v.recall)
        }, memory keys wrong ${pct(ref.memory)} → ${pct(v.memory)}, pairs wrong ${pct(ref.pairs)} → ${pct(v.pairs)}`;
      }
    }
    const s = all.s;
    lines.push(
      `| ${k.name} | ${pct(s.precision)} | ${
        pct(s.recall)
      } | ${s.phantom} | ${s.split} | ${s.memoryWrong}/${s.memoryWrites} | ${s.memoryKeysWrong}/${s.memoryKeys} | ${
        pct(all.pairs)
      } | ${pct(all.acc)} | ${k === variants[0] ? '' : most || 'none'} |`,
    );
  }
  return lines.join('\n');
}

function mean(xs: readonly number[]): number {
  return xs.reduce((a, b) => a + b, 0) / Math.max(1, xs.length);
}

/** Totals over households; precision and recall pooled over all their trips and visits. */
function sum(scores: readonly Score[]): Score & { precision: number; recall: number } {
  const total = (f: (s: Score) => number): number => scores.reduce((a, s) => a + f(s), 0);
  const trips = total((s) => s.trips);
  const visits = total((s) => s.visits);
  return {
    visits,
    trips,
    precision: trips === 0 ? 1 : total((s) => s.precision * s.trips) / trips,
    recall: visits === 0 ? 1 : total((s) => s.recall * s.visits) / visits,
    phantom: total((s) => s.phantom),
    split: total((s) => s.split),
    wrongStore: total((s) => s.wrongStore),
    memoryWrites: total((s) => s.memoryWrites),
    memoryWrong: total((s) => s.memoryWrong),
    memoryKeys: total((s) => s.memoryKeys),
    memoryKeysWrong: total((s) => s.memoryKeysWrong),
    pairs: total((s) => s.pairs),
    pairsWrong: total((s) => s.pairsWrong),
  };
}

function row(household: string, rule: string, scores: readonly Score[], acc: number): string {
  const s = sum(scores);
  return `| ${household} | ${rule} | ${s.visits} | ${s.trips} | ${pct(s.precision)} | ${
    pct(s.recall)
  } | ${s.phantom} | ${s.split} | ${s.wrongStore} | ${s.memoryWrong}/${s.memoryWrites} | ${s.memoryKeysWrong}/${s.memoryKeys} | ${
    pct(s.pairsWrong / Math.max(1, s.pairs))
  } | ${pct(acc)} |`;
}

if (import.meta.main) console.log(report(Number(Deno.args[0] ?? 5)));
