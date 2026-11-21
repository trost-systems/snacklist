import { FINAL, finalRule, startingRule } from './detect.ts';
import { shuffles } from './learn.ts';
import { orderAccuracy, personas, report, runs, score } from './evaluate.ts';
import { generate } from './generate.ts';
import { reassign } from './learn.ts';
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
} from './model.ts';

function assert(ok: boolean, message: string): void {
  if (!ok) throw new Error(message);
}

const T0 = Date.UTC(2026, 10, 21, 9);

interface Spec {
  readonly at: Ms;
  readonly key?: string;
  readonly item?: string;
  readonly actor?: string;
  readonly store?: string | null;
  readonly source?: Source;
  readonly kind?: 'bought' | 'restored';
  /** Commit time; default a second after [at]. */
  readonly server?: Ms;
  /** Device clock minus true time. */
  readonly skew?: Ms;
  readonly left?: number;
  readonly context?: Context;
}

const store = (id: string, pharmacy = false): Store => ({ id, pharmacy, layout: new Map(), prior: new Map() });

function household(specs: readonly Spec[], stores: readonly Store[] = [store('rewe'), store('aldi')]): Household {
  const ticks: Tick[] = specs.map((s, i) => ({
    id: i + 1,
    item: s.item ?? s.key ?? `i${i}`,
    key: s.key ?? `k${i}`,
    actor: s.actor ?? 'peter',
    source: s.source ?? 'app',
    kind: s.kind ?? 'bought',
    clientAt: T0 + s.at + (s.skew ?? 0),
    serverAt: T0 + (s.server ?? s.at + SECOND),
    store: s.store === undefined ? 'rewe' : s.store,
    storeOpenAfter: s.left ?? 5,
    truth: { visit: null, context: s.context ?? 'walk' },
  }));
  return { name: 'fixture', stores, ticks, visits: [], bought: new Map() };
}

/** [n] ticks [every] apart from [from], keys k<offset>.. */
const run = (n: number, every: Ms, from = 0, extra: Partial<Spec> = {}, offset = 0): Spec[] =>
  Array.from({ length: n }, (_, i) => ({ at: from + i * every, key: `k${offset + i}`, ...extra }));

Deno.test('a walk is a trip that teaches its order', () => {
  const d = finalRule(household(run(6, MINUTE)));
  assert(d.trips.length === 1 && d.trips[0]?.walked === true, 'one walked trip');
  assert(d.segments.length === 1 && d.segments[0]?.clumps.length === 6, 'six steps taught');
});

Deno.test('ticking everything at home afterwards is a trip in history but teaches nothing', () => {
  const d = finalRule(household(run(10, 2 * SECOND)));
  assert(d.trips.length === 1 && d.trips[0]?.walked === false, 'one trip, not walked');
  assert(d.segments.length === 0, 'no order taught');
  const s = startingRule(household(run(10, 2 * SECOND)));
  assert(s.segments.length === 1, 'the starting rule teaches the screen order');
});

Deno.test('three or four quick ticks (checkout, "we still have that") are no trip', () => {
  const d = finalRule(household(run(4, 3 * SECOND)));
  assert(d.trips.length === 0 && d.segments.length === 0, 'nothing detected');
  assert(startingRule(household(run(4, 3 * SECOND))).trips.length === 1, 'the starting rule makes it a trip');
});

Deno.test('a delivery unpacked at home, a tick every 10 s, teaches nothing', () => {
  const d = finalRule(household(run(12, 10 * SECOND)));
  assert(d.segments.length === 0, 'too fast for a walk');
  assert(d.trips.length === 1 && d.trips[0]?.walked === false, 'still a trip in history');
});

Deno.test('two stores back to back, 3 minutes apart, are two trips and teach no store memory', () => {
  const d = finalRule(household([
    ...run(5, MINUTE, 0, { store: 'aldi' }),
    ...run(5, MINUTE, 7 * MINUTE, { store: 'rewe' }, 10),
  ]));
  assert(d.trips.length === 2, `two trips, got ${d.trips.length}`);
  assert(d.trips.map((t) => t.store).join() === 'aldi,rewe', 'each its store');
  assert(d.storeMemory.length === 0, 'no store moved');
  const s = startingRule(household([
    ...run(5, MINUTE, 0, { store: 'aldi' }),
    ...run(5, MINUTE, 7 * MINUTE, { store: 'rewe' }, 10),
  ]));
  assert(s.trips.length === 1 && s.storeMemory.length === 5, 'the starting rule moves five items to one store');
});

Deno.test('one item at a small store before the big one is its own trip (T3a)', () => {
  const d = finalRule(household([
    { at: 0, key: 'bread', store: 'aldi', left: 0 },
    ...run(5, MINUTE, 4 * MINUTE, { store: 'rewe' }),
  ]));
  assert(d.trips.map((t) => `${t.store}:${t.ticks.length}`).sort().join() === 'aldi:1,rewe:5', 'aldi 1, rewe 5');
  assert(d.storeMemory.length === 0, 'bread stays at aldi');
  const close = finalRule(
    household([...run(5, MINUTE, 0, { store: 'rewe' }), { at: 4.5 * MINUTE, key: 'candles', store: 'ikea', left: 0 }]),
  );
  assert(
    close.trips.length === 1 && close.trips[0]?.store === 'rewe',
    'ticked 30 s after the walk: bought at rewe, no ikea trip',
  );
});

Deno.test('an item bought where it is not tagged moves to that store after the second walk (T4a, confirmed)', () => {
  const walk = (day: number): Spec[] =>
    run(7, MINUTE, day * DAY, {}, day * 10).map((s, i) => (i === 3 ? { ...s, key: 'eggs', store: 'aldi' } : s));
  const once = finalRule(household(walk(0)));
  assert(once.storeMemory.length === 0, 'one walk only proposes');
  const twice = finalRule(household([...walk(0), ...walk(2)]));
  assert(twice.storeMemory.map((w) => `${w.key}:${w.store}`).join() === 'eggs:rewe', 'the second walk moves eggs');
  const immediate = finalRule(household(walk(0)), { ...FINAL, memoryConfirm: 1 });
  assert(immediate.storeMemory.length === 1, 'T4a as approved moves it at once');
  const storeless = finalRule(
    household(run(5, MINUTE).map((s, i) => (i === 4 ? { ...s, store: null } : s))),
    { ...FINAL, memoryConfirm: 1 },
  );
  assert(storeless.storeMemory.length === 1, 'a storeless item joins the store');
});

Deno.test('a last tick tagged to a store with items left stays in the walk', () => {
  const edge = run(7, MINUTE).map((s, i) => (i === 6 ? { ...s, store: 'aldi', left: 3 } : s));
  const d = finalRule(household(edge), { ...FINAL, memoryConfirm: 1 });
  assert(d.trips.length === 1 && d.trips[0]?.ticks.length === 7, 'one trip of seven');
  assert(d.storeMemory.length === 1, 'T4a as approved: it learns rewe');
  const narrowed = finalRule(household(edge), { ...FINAL, memoryConfirm: 1, narrowMemory: true });
  assert(narrowed.storeMemory.length === 0, 'narrowed: the edge tick may be the next store');
});

Deno.test('narrowed T4a needs 75 % of the tagged ticks at one store', () => {
  const mixed = run(6, MINUTE).map((
    s,
    i,
  ) => (i === 1 || i === 3 ? { ...s, store: 'aldi' } : i === 2 ? { ...s, store: null } : s));
  const p = { ...FINAL, memoryConfirm: 1, narrowMemory: true };
  assert(finalRule(household(mixed), p).storeMemory.length === 0, '3 of 5 tagged is not enough');
  const clear = run(6, MINUTE).map((s, i) => (i === 2 ? { ...s, store: null } : s));
  assert(finalRule(household(clear), p).storeMemory.length === 1, '5 of 5 is');
});

Deno.test('offline: the commit times are a sync burst, the device times are the walk', () => {
  const specs = run(8, 90 * SECOND).map((s, i) => ({ ...s, server: 13 * MINUTE + i * 400 }));
  const online = run(3, 20 * MINUTE, 2 * HOUR, {}, 20);
  const d = finalRule(household([...specs, ...online]));
  assert(d.segments.length === 1 && d.segments[0]?.clumps.length === 8, 'the walk taught from device times');
  assert(
    startingRule(household([...specs, ...online])).segments[0]?.clumps.length === 8,
    'starting rule: one session…',
  );
  assert(
    finalRule(household([...specs, ...online]), { ...FINAL, clientTime: false }).segments.length === 0,
    '…but commit times alone see a burst',
  );
});

Deno.test('a device clock an hour off is corrected by its usual offset', () => {
  const d = finalRule(household(run(6, MINUTE, 0, { skew: -HOUR })));
  assert(d.trips.length === 1 && d.trips[0]?.start === T0 + SECOND, 'trip at the true time');
});

Deno.test('a stray tick undone within seconds does not count', () => {
  const d = finalRule(household([
    ...run(5, MINUTE),
    { at: 2 * MINUTE + 2 * SECOND, key: 'stray', item: 'stray' },
    { at: 2 * MINUTE + 5 * SECOND, key: 'stray', item: 'stray', kind: 'restored' },
  ]));
  assert(d.trips[0]?.ticks.every((t) => t.key !== 'stray') === true, 'stray left out');
});

Deno.test('a 12-minute wait at the deli is one trip, taught as two walks', () => {
  const d = finalRule(household([...run(4, MINUTE), ...run(4, MINUTE, 15 * MINUTE, {}, 4)]));
  assert(d.trips.length === 1, `one trip, got ${d.trips.length}`);
  assert(d.segments.length === 2, 'two segments');
  assert(
    startingRule(household([...run(4, MINUTE), ...run(4, MINUTE, 15 * MINUTE, {}, 4)])).trips.length === 2,
    'starting rule: two',
  );
});

Deno.test('the same store again in the evening is a new trip', () => {
  const d = finalRule(household([...run(4, MINUTE), ...run(4, MINUTE, 5 * HOUR, {}, 4)]));
  assert(d.trips.length === 2, 'two trips');
});

Deno.test('catching up on forgotten ticks in the car joins the trip without teaching', () => {
  const d = finalRule(household([...run(5, MINUTE), ...run(3, 2 * SECOND, 20 * MINUTE, {}, 5)]));
  assert(d.trips.length === 1 && d.trips[0]?.ticks.length === 8, 'one trip of eight');
  assert(d.segments.length === 1 && d.segments[0]?.clumps.length === 5, 'only the walk taught');
});

Deno.test('a partner ticking "we have that" at home stays out of the trip', () => {
  const d = finalRule(household([...run(6, MINUTE), ...run(2, 3 * SECOND, 2 * MINUTE, { actor: 'lea' }, 10)]));
  assert(d.trips.length === 1 && d.trips[0]?.actors.join() === 'peter', 'only peter');
});

Deno.test('two people splitting the list in one store are one household trip, two walks', () => {
  const d = finalRule(household([...run(5, MINUTE), ...run(5, 70 * SECOND, 30 * SECOND, { actor: 'lea' }, 10)]));
  assert(d.trips.length === 1 && d.trips[0]?.actors.length === 2, 'one trip, both');
  assert(d.segments.length === 2, 'both walks teach');
});

Deno.test('Siri, Alexa and agent ticks never start or extend a trip', () => {
  const d = finalRule(household(run(6, MINUTE, 0, { source: 'voice' })));
  assert(d.trips.length === 0, 'no trip from voice');
});

Deno.test('neighbours ticked together are one step of the walk', () => {
  const d = finalRule(
    household([...run(3, MINUTE), ...run(3, 1500, 3 * MINUTE, {}, 3), ...run(2, MINUTE, 4 * MINUTE, {}, 6)]),
  );
  assert(
    d.segments[0]?.clumps.map((c) => c.length).join() === '1,1,1,3,1,1',
    `clumps ${d.segments[0]?.clumps.map((c) => c.length)}`,
  );
});

Deno.test('a pharmacy is never a trip and teaches nothing (GL-2)', () => {
  const d = finalRule(household(run(6, MINUTE, 0, { store: 'apo' }), [store('apo', true)]));
  assert(d.trips.length === 0 && d.segments.length === 0 && d.storeMemory.length === 0, 'nothing');
});

Deno.test('simulation: the final rule beats the starting rule in every household', () => {
  const starting = runs.find((r) => r.name === 'starting rule + ema');
  assert(starting !== undefined, 'starting run');
  let wrongNow = 0;
  let keysNow = 0;
  let wrongBefore = 0;
  let keysBefore = 0;
  for (const p of personas) {
    for (let i = 0; i < 2; i++) {
      const h = generate({ ...p, seed: p.seed * 1000 + i });
      const final = finalRule(h);
      const before = orderAccuracy(h, starting?.learner.learn(h.stores, starting.detector(h).segments) ?? new Map());
      const after = orderAccuracy(h, reassign().learn(h.stores, final.segments));
      assert(after >= before, `${p.name} #${i}: order ${after.toFixed(3)} < ${before.toFixed(3)}`);
      const s = score(h, final);
      const was = score(h, starting?.detector(h) ?? final);
      wrongNow += s.memoryKeysWrong;
      keysNow += s.memoryKeys;
      wrongBefore += was.memoryKeysWrong;
      keysBefore += was.memoryKeys;
    }
  }
  assert(
    wrongNow / keysNow < wrongBefore / keysBefore,
    `store memory keys wrong ${wrongNow}/${keysNow}, starting rule ${wrongBefore}/${keysBefore}`,
  );
});

Deno.test('the tables in README.md are the simulator output', async () => {
  const readme = await Deno.readTextFile(new URL('../README.md', import.meta.url));
  const inside = readme.split('<!-- sim:begin -->\n')[1]?.split('\n<!-- sim:end -->')[0];
  assert(inside === report(5), 'README tables are stale: paste `deno run sim/evaluate.ts 5` between the sim markers');
});

const ordered = (id: string, n: number): Store => {
  const prior = new Map(Array.from({ length: n }, (_, i) => [`k${i}`, i / n]));
  return { id, pharmacy: false, layout: prior, prior };
};

Deno.test('once a store is learned, a walk that shuffles its order teaches neither order nor store memory', () => {
  const walks = [0, 1, 2].flatMap((day) => run(6, MINUTE, day * DAY));
  const shuffle = run(6, 40 * SECOND, 3 * DAY).reverse().map((s, i) => ({ ...s, at: 3 * DAY + i * 40 * SECOND }));
  shuffle.push({ at: 3 * DAY + 6 * 40 * SECOND, key: 'k10', store: null });
  const h = household([...walks, ...shuffle], [ordered('rewe', 20), store('aldi')]);
  const p = { ...FINAL, memoryConfirm: 1 };
  const d = finalRule(h, p);
  assert(d.segments.length === 4, 'four walks offered');
  assert(shuffles(h.stores, d.segments).size === 1, 'the reversed one is turned away');
  assert(d.storeMemory.length === 0, 'k10 does not move');
  assert(finalRule(h, { ...p, gateMemory: false }).storeMemory.length === 1, 'without the gate it would');
  const order = reassign().learn(h.stores, d.segments).get('rewe');
  assert((order?.get('k0') ?? 1) < (order?.get('k5') ?? 0), 'the order stays k0 before k5');
});

Deno.test('the clock offset comes from online ticks even when most ticks were offline', () => {
  const offline = run(6, 90 * SECOND, 0, { skew: -HOUR }).map((s, i) => ({ ...s, server: 20 * MINUTE + i * 400 }));
  const online = run(4, 3 * HOUR, 2 * HOUR, { skew: -HOUR }, 10);
  const d = finalRule(household([...offline, ...online]));
  assert(
    Math.abs((d.trips[0]?.start ?? 0) - T0) <= 2 * SECOND,
    `the walk at its true time, got ${((d.trips[0]?.start ?? 0) - T0) / MINUTE} min`,
  );
});

Deno.test('the clock offset uses the last week only: a phone set right later is not shifted back', () => {
  const wrong = run(4, 3 * HOUR, 0, { skew: HOUR });
  const right = run(6, MINUTE, 10 * DAY, {}, 10);
  const d = finalRule(household([...wrong, ...right]));
  const walk = d.trips.find((t) => t.walked);
  assert(walk?.start === T0 + 10 * DAY + SECOND, 'the later walk keeps its time');
});

Deno.test("T1a as approved: ticking the store's last item ends the trip", () => {
  const specs = run(6, MINUTE).map((s, i) => (i === 2 ? { ...s, left: 0 } : s));
  assert(finalRule(household(specs)).trips.length === 1, 'final: one trip');
  assert(finalRule(household(specs), { ...FINAL, allTickedEnds: true }).trips.length === 1, 'the pause joins them');
  assert(
    finalRule(household(specs), { ...FINAL, allTickedEnds: true, pause: 0 }).trips.length === 2,
    'approved (no pause): two',
  );
});

Deno.test('a phone clock an hour ahead is corrected too, offline walks included', () => {
  const offline = run(6, 90 * SECOND, 0, { skew: HOUR }).map((s, i) => ({ ...s, server: 20 * MINUTE + i * 400 }));
  const online = run(4, 3 * HOUR, 2 * HOUR, { skew: HOUR }, 10);
  const d = finalRule(household([...offline, ...online]));
  assert(Math.abs((d.trips[0]?.start ?? 0) - T0) <= 2 * SECOND, 'the walk at its true time');
  assert(d.segments[0]?.clumps.length === 6, 'and taught from the tap times');
});

Deno.test('a tap time beyond the stored bounds falls back to the commit time', () => {
  const offline = run(6, 90 * SECOND, 0, { skew: 2 * DAY }).map((s, i) => ({ ...s, server: 20 * MINUTE + i * 400 }));
  const d = finalRule(household(offline));
  assert(d.segments.length === 0, 'two days ahead: commit times, a sync burst, nothing taught');
  const near = run(6, 90 * SECOND, 0, { skew: HOUR }).map((s, i) => ({ ...s, server: 20 * MINUTE + i * 400 }));
  assert(finalRule(household(near)).segments.length === 1, 'an hour ahead: within the bounds');
  assert(
    finalRule(household(near), { ...FINAL, clientAfter: 5 * MINUTE }).segments.length === 0,
    'the first proposal (5 min ahead) would have dropped it',
  );
});

Deno.test('two slow steps at a store with items left are no walk (H1: three steps)', () => {
  const d = finalRule(household(run(2, MINUTE)));
  assert(d.trips.length === 0 && d.segments.length === 0, 'nothing');
});

Deno.test('a 7-minute gap inside a walk keeps one walk (the run gap is 10 minutes)', () => {
  const d = finalRule(household([...run(4, MINUTE), ...run(4, MINUTE, 10 * MINUTE, {}, 4)]));
  assert(d.segments.length === 1 && d.segments[0]?.clumps.length === 8, 'one walk of eight');
});

Deno.test('steps 30 s apart are a walk (pace 20 s)', () => {
  const d = finalRule(household(run(6, 30 * SECOND)));
  assert(d.segments.length === 1, 'taught');
});

Deno.test('a walk synced three days later keeps its tap times', () => {
  const late = run(6, 90 * SECOND).map((s, i) => ({ ...s, server: 3 * DAY + i * 400 }));
  const online = run(4, 3 * HOUR, 4 * DAY, {}, 10);
  const d = finalRule(household([...late, ...online]));
  assert(
    d.segments[0]?.clumps.length === 6 && Math.abs((d.trips[0]?.start ?? 0) - T0) <= 2 * SECOND,
    'taught at its time',
  );
});
