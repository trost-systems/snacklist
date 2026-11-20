// Round AM: mock list (the fictional Familie Brandt), the matcher, and one reducer every option shares.
// An option decides which actions its controls send and what Enter sends; never what an action does.
import { copy as asCopy } from '../model.js';

// The app's strings this round uses, each an ARB key (app/l10n/app_*.arb).
export const copy = {
  en: { ...asCopy.en, merged: (i) => `Merged: ${i}`, merge: 'Merge', readd: 'Back on the list', newItem: 'New', ticked: (n) => `${n} ticked off`, tickOff: 'Tap to tick off', already: (n) => `${n} is already on the list` },
  de: { ...asCopy.de, merged: (i) => `Zusammengeführt: ${i}`, merge: 'Zusammenführen', readd: 'Wieder auf die Liste', newItem: 'Neu', ticked: (n) => `${n} abgehakt`, tickOff: 'Tippen hakt ab', already: (n) => `${n} steht schon auf der Liste` },
};
// dedupeMerged, dedupeMerge, readd, newItem, itemTicked, the first half of listHint (a key's screen-reader name), alreadyOnList.

export { stores, categories, storeName, catName } from '../model.js';

// keys: other spellings and plurals the server's canonical_key folds together (job 32a); the matcher needs no more.
const listed = [
  { key: 'pasta', en: 'Pasta', de: 'Nudeln', emoji: '🍝', cat: 'pantry', store: null, qty: '', keys: ['noodle', 'noodles', 'nudel'] },
  { key: 'apples', en: 'Apples', de: 'Äpfel', emoji: '🍎', cat: 'produce', store: 'markt', qty: '1 kg', keys: ['apple', 'apfel'] },
  { key: 'oatmilk', en: 'Oat milk', de: 'Hafermilch', emoji: '🥛', cat: 'drinks', store: 'dm', qty: '2', brand: 'Hafergold', keys: ['oatmilk'] },
  { key: 'milk', en: 'Milk', de: 'Milch', emoji: '🥛', cat: 'chilled', store: 'edeka', qty: '', details: { en: '1.5 %', de: '1,5 %' }, keys: [] },
  { key: 'bananas', en: 'Bananas', de: 'Bananen', emoji: '🍌', cat: 'produce', store: null, qty: '6', keys: ['banana', 'banane'] },
  { key: 'milk', en: 'Milk', de: 'Milch', emoji: '🥛', cat: 'chilled', store: 'lidl', qty: '', details: { en: '3.5 %', de: '3,5 %' }, keys: [] },
];
// Ticked yesterday: in the list's ticked section today.
const ticked = [
  { key: 'eggs', en: 'Eggs', de: 'Eier', emoji: '🥚', cat: 'chilled', store: 'edeka', qty: '10', details: { en: 'free range', de: 'Freiland' }, keys: ['egg', 'ei'] },
  { key: 'milk', en: 'Milk', de: 'Milch', emoji: '🥛', cat: 'chilled', store: null, qty: '', details: { en: 'organic', de: 'Bio' }, keys: [] },
];
// Typing suggestions from the catalog and history (AS-Q5: up to three while typing).
export const catalog = [
  { key: 'cinnamon', en: 'Cinnamon', de: 'Zimt', emoji: '🫙', cat: 'pantry', store: null },
  { key: 'oats', en: 'Oats', de: 'Haferflocken', emoji: '🥣', cat: 'pantry', store: 'edeka' },
  { key: 'bread', en: 'Bread', de: 'Brot', emoji: '🍞', cat: 'bakery', store: 'edeka' },
  { key: 'pesto', en: 'Pesto', de: 'Pesto', emoji: '🫙', cat: 'pantry', store: null },
  { key: 'applejuice', en: 'Apple juice', de: 'Apfelsaft', emoji: '🧃', cat: 'drinks', store: 'edeka' },
  { key: 'eggplant', en: 'Eggplant', de: 'Aubergine', emoji: '🍆', cat: 'produce', store: null },
];

const loc = (v, lang) => (v && typeof v === 'object' ? v[lang] : (v ?? ''));
export const initial = (lang = 'en') => ({
  items: [
    ...listed.map((c, i) => ({ id: `o${i}`, ...c, brand: c.brand ?? '', details: loc(c.details, lang), status: 'open' })),
    ...ticked.map((c, i) => ({ id: `t${i}`, ...c, brand: '', details: loc(c.details, lang), status: 'ticked' })),
  ],
  added: [],
  cur: null,
  text: '',
  open: null,
  sheet: true,
  seq: 0,
  focus: null,
  offer: null,
  note: null,
});

export const t = (lang) => copy[lang];
export const curItem = (s) => s.items.find((i) => i.id === s.cur) ?? null;
export const byId = (s, id) => s.items.find((i) => i.id === id);
// Behind the sheet (AS1): the last two items this sheet added, nothing else. An item that was on the list before
// never shows there (Peter t1077u): what happens to a match is told inside the sheet.
export const lastTwo = (s) => [...new Set(s.added)].slice(-2).map((id) => byId(s, id)).filter(Boolean);

// Case, accents and umlauts fold (ä → a here; the server folds further).
export const fold = (x) => x.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

// A match is an item on the list (open) or ticked that is the typed item: 'exact' (same name) or 'spelling' (another
// form the canonical key folds: plural, umlaut, the other language). A compound that only contains the word (Oat milk
// for Milk) is a different product and no match (review 0): it is not offered to merge into.
export const matches = (s, lang) => {
  const q = fold(s.text);
  if (q.length < 3) return [];
  const out = [];
  for (const i of s.items) {
    if (i.status === 'new') continue;
    const name = fold(i[lang]);
    const forms = [fold(i.en), fold(i.de), ...i.keys.map(fold)];
    let kind = null;
    if (i[lang].toLowerCase() === s.text.trim().toLowerCase()) kind = 'exact';
    else if (name === q || forms.includes(q)) kind = 'spelling';
    if (kind) out.push({ item: i, kind });
  }
  // Open ones first, the oldest first among them (the one Enter acts on), then ticked ones.
  return out.sort((a, b) => (a.item.status === 'open' ? 0 : 1) - (b.item.status === 'open' ? 0 : 1)).slice(0, 3);
};
export const sameItem = (s, lang) => matches(s, lang)[0] ?? null;

// Catalog suggestions while typing; an item that already matches is not suggested again.
export const suggestions = (s, lang, room = 3) => {
  const q = fold(s.text);
  if (!q) return [];
  const shown = new Set(matches(s, lang).map((m) => m.item.key));
  return catalog.filter((c) => !shown.has(c.key) && (fold(c[lang]).startsWith(q) || fold(c.en).startsWith(q))).slice(0, room);
};

// The app's merge_quantities for the cases on this list: no amount counts as one piece; a weight plus no amount stays.
export const mergeQty = (kept, other) => {
  const n = (q) => (q === '' ? 1 : /^\d+$/.test(q) ? Number(q) : null);
  if (n(kept) !== null && n(other) !== null) return String(n(kept) + n(other));
  return kept || other;
};

// The app's stepQuantity for whole amounts: the unit stays ("1 kg" → "2 kg"); none counts as one.
const step = (qty, up) => {
  const m = /^(\d+)(.*)$/.exec(qty === '' ? '1' : qty);
  if (!m) return qty;
  const next = Number(m[1]) + (up ? 1 : -1);
  if (next < 1) return qty;
  return next === 1 && !m[2].trim() ? '' : `${next}${m[2]}`;
};
const patch = (s, id, f) => ({ ...s, items: s.items.map((i) => (i.id === id ? { ...i, ...f(i) } : i)) });
const touched = (s, id, more = {}) => ({ ...s, added: [...s.added.filter((x) => x !== id), id], text: '', open: null, focus: null, note: null, ...more });
// A match acted on: the list behind stays as it was; the sheet says what happened in the chips' place.
const told = (s, kind, id) => ({ ...s, text: '', open: null, focus: null, offer: null, cur: null, note: { kind, id } });

const create = (s, lang, from) => {
  const name = s.text.trim();
  const id = `n${s.seq}`;
  // The classifier and the learned store give a new item what its namesake had; brand and details stay empty.
  const base = from ?? catalog.find((c) => fold(c[lang]) === fold(name)) ?? { emoji: '⬡', cat: 'pantry', store: null };
  const item = { id, key: `${base.key ?? name}#${s.seq}`, en: name, de: name, emoji: base.emoji, cat: base.cat, store: base.store, qty: '', brand: '', details: '', keys: [], status: 'open' };
  return { s: { ...s, items: [...s.items, item], seq: s.seq + 1 }, id };
};

export const act = (s, a, lang, opt) => {
  const i = a.indexOf(':');
  const verb = i < 0 ? a : a.slice(0, i);
  const arg = i < 0 ? undefined : a.slice(i + 1);
  switch (verb) {
    case 'type':
      return { ...s, text: arg ?? '', open: null, offer: arg ? null : s.offer, note: arg ? null : s.note };
    case 'enter': {
      if (!s.text.trim()) return { ...s, sheet: false, open: null };
      return act(s, opt.enter(s, lang), lang, opt);
    }
    // Tick off: the open item leaves the list (into the ticked section), nothing is added.
    case 'tick':
      return told(patch(s, arg, () => ({ status: 'ticked' })), 'tick', arg);
    // Merge into the open item: amounts add up (merge_quantities), its name, store, brand and details stay.
    case 'merge':
      if (byId(s, arg).status === 'ticked') return act(s, `back:${arg}`, lang, opt);
      return told(patch(s, arg, (x) => ({ qty: mergeQty(x.qty, '') })), 'merge', arg);
    // Back on the list: the ticked item opens again with its amount, store, brand and details.
    case 'back':
      return told(patch(s, arg, () => ({ status: 'open' })), 'back', arg);
    // Keep (AM2's Enter): nothing changes, as today's refusal; the sheet says it is already on the list.
    case 'keep':
      return told(s, 'already', arg);
    // A separate item under the typed name. `new:<id>` copies the match's category and store as the server would.
    case 'new': {
      const m = arg ? byId(s, arg) : sameItem(s, lang)?.item;
      const { s: s2, id } = create(s, lang, m && { emoji: m.emoji, cat: m.cat, store: m.store, key: m.key });
      return touched(s2, id, { cur: id });
    }
    // AM4: Enter always adds; the match is offered afterwards.
    case 'add': {
      const m = sameItem(s, lang)?.item;
      const { s: s2, id } = create(s, lang, m && { emoji: m.emoji, cat: m.cat, store: m.store, key: m.key });
      return touched(s2, id, { cur: id, offer: m ? { added: id, match: m.id } : null });
    }
    // AM4's offer: fold the new item into the match (merge, or back on the list for a ticked one).
    case 'fold': {
      const { added, match } = s.offer;
      const m = byId(s, match);
      const gone = { ...s, items: s.items.filter((x) => x.id !== added), added: s.added.filter((x) => x !== added), offer: null, cur: null };
      return m.status === 'ticked' ? act(gone, `back:${match}`, lang, opt) : act(gone, `merge:${match}`, lang, opt);
    }
    case 'take': {
      const c = suggestions(s, lang)[Number(arg)];
      const { s: s2, id } = create({ ...s, text: c[lang] }, lang, c);
      return touched(s2, id, { cur: id });
    }
    case 'focus':
      return { ...s, focus: arg };
    case 'edit':
      return s.sheet && lastTwo(s).some((x) => x.id === arg) && byId(s, arg).status === 'open' ? { ...s, cur: arg, open: null, text: '', offer: null, note: null } : s;
    case 'qty+':
    case 'qty-':
      return patch(s, s.cur, (x) => ({ qty: step(x.qty, verb === 'qty+') }));
    case 'open':
      return { ...s, open: s.open === arg ? null : arg, text: '' };
    case 'store':
      return { ...patch(s, s.cur, () => ({ store: arg === 'none' ? null : arg })), open: null };
    case 'cat':
      return { ...patch(s, s.cur, () => ({ cat: arg })), open: null };
    case 'details':
      return patch(s, s.cur, () => ({ details: arg ?? '' }));
    case 'noop':
      return s;
    case 'dismiss':
      return { ...s, sheet: false, open: null, text: '', offer: null };
    default:
      throw new Error(`unknown action ${a}`);
  }
};

export const run = (actions, lang, opt, from = initial(lang)) => actions.reduce((s, a) => act(s, a, lang, opt), from);

// What the list holds, for the checks: every item's status and amount, and how many share a name.
export const summary = (s, lang) => s.items.map((i) => ({ id: i.id, name: i[lang], status: i.status, qty: i.qty, store: i.store }));
