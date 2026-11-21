import type { Learner } from './model.ts';

/**
 * Job 347's learner (APPROACHES.md, "Learning"): each key's position moves halfway toward its
 * rank in the trip. Keys of one clump share their mean rank.
 */
export const ema: Learner = {
  name: 'ema',
  learn(stores, segments) {
    const out = new Map<string, Map<string, number>>();
    for (const s of stores) out.set(s.id, new Map(s.prior));
    for (const seg of segments) {
      const pos = out.get(seg.store);
      if (pos === undefined) continue;
      const n = seg.clumps.reduce((a, c) => a + c.length, 0);
      if (n < 2) continue;
      let i = 0;
      for (const clump of seg.clumps) {
        const rank = (i + (clump.length - 1) / 2) / (n - 1);
        for (const key of clump) pos.set(key, 0.5 * (pos.get(key) ?? rank) + 0.5 * rank);
        i += clump.length;
      }
    }
    return out;
  },
};

/**
 * The trip's keys trade places: they take the positions they already hold, sorted, in the order
 * the trip ticked them (a clump shares its slots' mean), and each moves [step] of the way there.
 * A trip covering half the store only reorders that half, unlike a rank over the whole trip.
 */
export function reassign(step = 0.5): Learner {
  return {
    name: `reassign(${step})`,
    learn(stores, segments) {
      const out = new Map<string, Map<string, number>>();
      for (const s of stores) out.set(s.id, new Map(s.prior));
      for (const seg of segments) {
        const pos = out.get(seg.store);
        if (pos === undefined) continue;
        const clumps = seg.clumps.map((c) => c.filter((k) => pos.has(k))).filter((c) => c.length > 0);
        if (clumps.length < 2) continue;
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
      return out;
    },
  };
}
