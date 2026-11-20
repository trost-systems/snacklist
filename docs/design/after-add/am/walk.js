// The scenarios and each option's way to every outcome, as actions. verify.mjs replays the same paths as clicks
// (and Enter key presses) on the live phone, so a tap count here is what it took there. Typing is not counted.
export const words = {
  exact: { en: 'Pasta', de: 'Nudeln' },
  spelling: { en: 'Apple', de: 'Apfel' },
  brand: { en: 'Oat milk', de: 'Hafermilch' },
  several: { en: 'Milk', de: 'Milch' },
  ticked: { en: 'Eggs', de: 'Eier' },
  none: { en: 'Cinnamon', de: 'Zimt' },
};
const type = (k, lang) => `type:${words[k][lang]}`;

// Outcome → [scenario, actions after typing]. null: the option has no way to it from the sheet.
// tick, merge and new act on the exact match (Pasta, open); back on Eggs (ticked yesterday); add on Cinnamon (no match).
export const paths = {
  AM1: { tick: ['exact', ['tick:o0']], merge: ['exact', ['enter']], new: ['exact', ['new']], back: ['ticked', ['enter']], add: ['none', ['enter']] },
  AM2: { tick: ['exact', ['tick:o0']], merge: ['exact', ['merge:o0']], new: ['exact', ['new']], back: ['ticked', ['enter']], add: ['none', ['enter']] },
  AM3: { tick: ['exact', ['tick:o0']], merge: ['exact', ['enter']], new: ['exact', ['new:o0']], back: ['ticked', ['enter']], add: ['none', ['enter']] },
  AM4: { tick: null, merge: ['exact', ['enter', 'fold']], new: ['exact', ['enter']], back: ['ticked', ['enter', 'fold']], add: ['none', ['enter']] },
  AM5: { tick: ['exact', ['enter']], merge: ['exact', ['merge:o0']], new: ['exact', ['new']], back: ['ticked', ['enter']], add: ['none', ['enter']] },
};
export const outcomes = ['tick', 'merge', 'new', 'back', 'add'];

// What an action did to the list: a new item, the match ticked off, merged (its amount changed), back on the list,
// or nothing (kept: the list as it was).
export const classify = (before, after, id) => {
  const was = before.items.find((i) => i.id === id);
  const now = after.items.find((i) => i.id === id);
  if (after.items.length > before.items.length) return 'new';
  if (was.status === 'open' && now.status === 'ticked') return 'tick';
  if (was.status === 'ticked' && now.status === 'open') return 'back';
  if (was.qty !== now.qty) return 'merge';
  return 'keep';
};

// The different-store case: a separate Oat milk from Lidl. The new item, then AS1's store chip.
const brandNew = { AM1: ['new'], AM2: ['new'], AM3: ['new:o2'], AM4: ['enter'], AM5: ['new'] };

// Frames: [key, actions from the start].
export const frames = (id, lang) => [
  ['exact', [type('exact', lang)]],
  ['exactEnter', [type('exact', lang), 'enter']],
  ['spelling', [type('spelling', lang)]],
  ['brand', [type('brand', lang)]],
  ['brandNew', [type('brand', lang), ...brandNew[id], 'open:store', 'store:lidl']],
  ['several', [type('several', lang)]],
  ['ticked', [type('ticked', lang)]],
  ['tickedEnter', [type('ticked', lang), 'enter']],
  ['none', [type('none', lang)]],
  ['merged', paths[id].merge ? [type('exact', lang), ...paths[id].merge[1]] : null],
  ['tickedOff', paths[id].tick ? [type('exact', lang), ...paths[id].tick[1]] : null],
];

export const verdict = { pick: 'AM2', runner: 'AM1' };
