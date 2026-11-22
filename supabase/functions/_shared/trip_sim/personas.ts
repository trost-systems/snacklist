import type { Habits, Persona } from './generate.ts';
import { HOUR, MINUTE, SECOND } from './model.ts';

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
    members: {
      solo: { ...quiet, walk: 0.9, offline: 0.5, skew: HOUR, accident: 0.06, impulse: 0.6 },
    },
  },
  {
    ...base,
    name: 'checkout-ticker',
    seed: 3,
    members: {
      a: { ...quiet, walk: 0.15, checkout: 0.7 },
      b: { ...quiet, walk: 0.2, checkout: 0.5 },
    },
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
    members: {
      a: { ...quiet, walk: 0.2, checkout: 0.1 },
      b: { ...quiet, walk: 0.5, checkout: 0.1 },
    },
  },
];
