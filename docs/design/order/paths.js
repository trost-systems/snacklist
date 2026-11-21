// Each option's way to fix the scenario (Eggs sit with the milk; at this EDEKA they stand next to the flour), as the
// taps a person makes. The frames show these states, and verify.mjs replays every path on the live phone by clicking
// and counts the clicks. A drag counts as one tap. IO2 has no path: its trip ticks are the shopping itself.
import { act, byId, categorical, fix, initial, movesBetween, orderOf, storeKey, walk } from './model.js';
import { options } from './options.js';

export const fixPath = (id, s) => {
  const o = options[id];
  if (o.fix === 'category') return ['hold:eggs', 'menu:cat', 'setCat:pantry', 'done'];
  if (o.fix === 'nextTo') return ['hold:eggs', 'menu:place', `nextTo:${fix.after}`, 'done'];
  if (o.fix === 'drag') return ['sortMode', `drop:${fix.item}:${fix.after}`, 'sortMode'];
  if (o.fix === 'step') {
    const path = ['hold:eggs'];
    let st = act(s, 'hold:eggs');
    for (let k = 0; k < 20; k += 1) {
      const seq = orderOf(st, o.kind, 'edeka');
      if (seq.indexOf(fix.item) === seq.indexOf(fix.after) + 1) break;
      const dir = seq.indexOf(fix.item) < seq.indexOf(fix.after) ? 'down' : 'up';
      path.push(`step:${dir}`);
      st = act(st, `step:${dir}`);
    }
    return [...path, 'done'];
  }
  return [];
};

export const run = (s, path) => path.reduce((st, a) => act(st, a), s);

// Where Eggs end up: right after Flour, or (with a category pick) at the end of Pantry.
export const eggsAfter = (st, id) => {
  const seq = orderOf(st, options[id].kind, 'edeka');
  return seq[seq.indexOf(fix.item) - 1];
};

// Taps to put a whole IKEA list (first trip, today's order) into the order the household walks it.
export const ikeaCost = (id, lang) => {
  const o = options[id];
  const s = initial(o.kind, lang);
  const today = categorical(s, walk.ikea, 'ikea');
  const moves = movesBetween(today, walk.ikea);
  if (o.fix === 'category') return { taps: null, moves };
  if (o.kind === 'learned') return { taps: 0, moves, trips: 1, manual: o.fix === 'nextTo' ? 4 * moves : null };
  if (o.fix === 'drag') return { taps: 2 + moves, moves };
  // Move up / Move down, greedily: for each place from the top, hold the item that belongs there, step it up, done.
  let st = s;
  let taps = 0;
  for (let i = 0; i < walk.ikea.length; i += 1) {
    const want = walk.ikea[i];
    let seq = orderOf(st, o.kind, 'ikea');
    if (seq[i] === want) continue;
    st = act(st, `hold:${want}`);
    taps += 1;
    while ((seq = orderOf(st, o.kind, 'ikea')).indexOf(want) > i) {
      st = act(st, 'step:up');
      taps += 1;
    }
    st = act(st, 'done');
    taps += 1;
  }
  const done = orderOf(st, o.kind, 'ikea').join() === walk.ikea.join();
  return { taps: done ? taps : null, moves };
};

export const storeOf = (id) => storeKey(byId[id].store);
