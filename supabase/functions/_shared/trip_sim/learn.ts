import type { Segment, Store } from './model.ts';

/**
 * The trip's keys trade places: they take the positions they already hold, sorted, in the order
 * the trip ticked them (a clump shares its slots' mean), and each moves [step] of the way there.
 * A trip covering half the store only reorders that half, unlike a rank over the whole trip.
 * With [gate], once a store has [gate.after] taught walks, a walk whose pairs agree with the
 * store's order less than [gate.min] of the time teaches nothing: a shuffle (a delivery unpacked,
 * a checkout belt), not a walk.
 */
export interface Gate {
  readonly after: number;
  readonly min: number;
}

export const GATE: Gate = { after: 3, min: 0.6 };

/** The walks the learner's gate turns away as shuffles: they teach store memory nothing either. */
export function shuffles(
  stores: readonly Store[],
  segments: readonly Segment[],
  gate: Gate = GATE,
): ReadonlySet<Segment> {
  return trade(stores, segments, 0.5, gate).rejected;
}

function trade(
  stores: readonly Store[],
  segments: readonly Segment[],
  step: number,
  gate: Gate | null,
): { orders: Map<string, Map<string, number>>; rejected: Set<Segment> } {
  const orders = new Map<string, Map<string, number>>();
  const rejected = new Set<Segment>();
  const taught = new Map<string, number>();
  for (const s of stores) orders.set(s.id, new Map(s.prior));
  for (const seg of segments) {
    const pos = orders.get(seg.store);
    if (pos === undefined) continue;
    const clumps = seg.clumps.map((c) => c.filter((k) => pos.has(k))).filter((c) => c.length > 0);
    if (clumps.length < 2) continue;
    const n = taught.get(seg.store) ?? 0;
    if (gate !== null && n >= gate.after && agreement(clumps, pos) < gate.min) {
      rejected.add(seg);
      continue;
    }
    taught.set(seg.store, n + 1);
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
      pos.set(k, p + step * (t - p));
    }
  }
  return { orders, rejected };
}

/** Share of a walk's pairs (keys in different clumps) that [pos] already orders the same way. */
export function agreement(
  clumps: readonly (readonly string[])[],
  pos: ReadonlyMap<string, number>,
): number {
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
