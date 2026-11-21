// Mock data and the app's sums. Peter's list of t1116u: dm, Lidl, Edeka, IKEA and no store. Sum, StoreTally and
// summaryOf are app/lib/list/subtotals.dart in JS; the options differ only in what they draw from the summary.
import { arb } from './strings.js';

export const stores = [
  { id: 'dm', name: 'dm' },
  { id: 'lidl', name: 'Lidl' },
  { id: 'edeka', name: 'Edeka' },
  { id: 'ikea', name: 'IKEA' },
];

// price: cents per piece, or per kg typed per unit (the planned weight makes it an estimate while open).
export const items = [
  { id: 'toothpaste', store: 'dm', cat: 'categoryHousehold', emoji: '🪥', en: 'Toothpaste', de: 'Zahnpasta', qty: '', price: { cents: 145 } },
  { id: 'milk', store: 'lidl', cat: 'categoryChilled', emoji: '🥛', en: 'Milk', de: 'Milch', qty: '2', price: { cents: 119 } },
  { id: 'bananas', store: 'lidl', cat: 'categoryProduce', emoji: '🍌', en: 'Bananas', de: 'Bananen', qty: '846 g', grams: 846, price: { cents: 179, per: 'kg' } },
  { id: 'bread', store: 'edeka', cat: 'categoryBakery', emoji: '🍞', en: 'Bread', de: 'Brot', qty: '', price: { cents: 249 } },
  { id: 'butter', store: 'edeka', cat: 'categoryChilled', emoji: '🧈', en: 'Butter', de: 'Butter', qty: '', price: { cents: 229 } },
  { id: 'tealights', store: 'ikea', cat: 'categoryHousehold', emoji: '🕯️', en: 'Tealights', de: 'Teelichter', qty: '', price: { cents: 399 } },
  { id: 'batteries', store: null, cat: 'categoryHousehold', emoji: '🔋', en: 'Batteries', de: 'Batterien', qty: '', price: { cents: 499 } },
];
export const catOrder = ['categoryProduce', 'categoryBakery', 'categoryChilled', 'categoryHousehold'];

// The four states of the brief. priced: items with today's price; bought: ticked on the running trip.
export const states = {
  a: { priced: [], bought: [], trip: false },
  b: { priced: ['milk', 'bananas', 'bread'], bought: [], trip: false },
  c: { priced: items.map((i) => i.id), bought: [], trip: false },
  d: { priced: ['milk', 'bananas', 'bread'], bought: ['milk', 'bananas', 'bread'], trip: true },
};
export const stateIds = ['a', 'b', 'c', 'd'];

export const initial = (id = 'b') => ({ ...structuredClone(states[id]), open: false, sheet: false, target: null });

// The live phone's actions: a tap on a row's chip prices it (or takes the price off); a tap on the row ticks it on
// the trip; the option's own controls fold, open the sheet or point at the next item without a price.
export const act = (s, a) => {
  const [verb, arg] = a.split(':');
  const n = { ...s, priced: [...s.priced], bought: [...s.bought], target: null };
  if (verb === 'state') return initial(arg);
  if (verb === 'price') n.priced = n.priced.includes(arg) ? n.priced.filter((x) => x !== arg) : [...n.priced, arg];
  if (verb === 'tick') {
    n.trip = true;
    n.bought = n.bought.includes(arg) ? n.bought.filter((x) => x !== arg) : [...n.bought, arg];
  }
  if (verb === 'fold') n.open = !n.open;
  if (verb === 'sheet') n.sheet = !n.sheet;
  if (verb === 'next') n.target = arg;
  return n;
};

const line = (item) => (item.price.per === 'kg' ? Math.round((item.price.cents * item.grams) / 1000) : item.price.cents * Number(item.qty || 1));

// Sum.of: priced (estimate when a per-kg price sits on the planned weight of an open item), or unpriced.
const sumOf = (item, s) => {
  if (!s.priced.includes(item.id)) return { cents: 0, priced: 0, unpriced: 1, estimate: false };
  return { cents: line(item), priced: 1, unpriced: 0, estimate: item.price.per === 'kg' && !s.bought.includes(item.id) };
};
export const zero = { cents: 0, priced: 0, unpriced: 0, estimate: false };
export const plus = (a, b) => ({ cents: a.cents + b.cents, priced: a.priced + b.priced, unpriced: a.unpriced + b.unpriced, estimate: a.estimate || b.estimate });
export const empty = (sum) => sum.priced === 0;
export const floor = (sum) => sum.unpriced > 0;

// summaryOf: a tally per group in store order, then no store; bought only while a trip runs (then split).
export const summary = (s) => {
  const groups = [...stores.map((x) => x.id), null].map((store) => {
    const mine = items.filter((i) => i.store === store);
    const open = mine.filter((i) => !s.bought.includes(i.id));
    const bought = mine.filter((i) => s.bought.includes(i.id));
    const sum = (list) => list.reduce((acc, i) => plus(acc, sumOf(i, s)), zero);
    return { store, open: sum(open), bought: s.trip ? sum(bought) : null, openCount: open.length, boughtCount: bought.length };
  }).filter((g) => g.openCount > 0 || (s.trip && g.boughtCount > 0));
  for (const g of groups) {
    g.sum = plus(g.open, g.bought ?? zero);
    g.allBought = g.openCount === 0;
  }
  const open = groups.reduce((a, g) => plus(a, g.open), zero);
  const bought = groups.reduce((a, g) => plus(a, g.bought ?? zero), zero);
  return { groups, split: s.trip, open, bought, total: plus(open, bought), perStore: groups.length > 1 };
};

// The open items in list order (store order, then category order): what the list shows.
export const openItems = (s) => [...stores.map((x) => x.id), null].flatMap((store) =>
  catOrder.flatMap((c) => items.filter((i) => i.store === store && i.cat === c && !s.bought.includes(i.id))));
export const firstUnpriced = (s) => openItems(s).find((i) => !s.priced.includes(i.id)) ?? null;
export const lineCents = line;

// Words: ARB strings with their placeholders filled; money as the app writes it (en €6.38, de 6,38 €).
export const w = (lang, key, params = {}) => {
  let t = arb[lang][key];
  const plural = /\{(\w+), plural, ((?:[=\w]+\{[^}]*\}\s*)+)\}/.exec(t);
  if (plural) {
    const n = Number(params[plural[1]]);
    const forms = Object.fromEntries([...plural[2].matchAll(/([=\w]+)\{([^}]*)\}/g)].map((m) => [m[1], m[2]]));
    t = t.replace(plural[0], (forms[`=${n}`] ?? forms.other).replace(`{${plural[1]}}`, String(n)));
  }
  return t.replace(/\{(\w+)\}/g, (_, k) => String(params[k]));
};
export const money = (lang, cents) => {
  const v = (cents / 100).toFixed(2);
  return lang === 'de' ? `${v.replace('.', ',')} €` : `€${v}`;
};
// The amount with its marks, as summary_block.dart's _qualified: ≈ for an estimate inside, „at least“ outside it.
export const marked = (lang, sum, { withFloor = true } = {}) => {
  let t = money(lang, sum.cents);
  if (sum.estimate) t = w(lang, 'moneyEstimate', { amount: t });
  if (withFloor && floor(sum)) t = w(lang, 'moneyAtLeast', { amount: t });
  return t;
};
export const groupName = (lang, store) => (store ? stores.find((x) => x.id === store).name : w(lang, 'noStore'));
