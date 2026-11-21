// Mock data and the list's state. The fictional Brandt family: an EDEKA and a dm list, and a bank of 15 bought items
// for Recently used. An item's place on the list is derived (store, then `rank`, the walk order), so an item tapped
// back from Recently used lands where it was.
export const stores = [
  { id: 'edeka', name: 'EDEKA' },
  { id: 'dm', name: 'dm' },
];

// price: the row's price in cents (null: none yet).
export const items = [
  { id: 'bananas', store: 'edeka', rank: 1, emoji: '🍌', en: 'Bananas', de: 'Bananen', qty: '6', price: null },
  { id: 'apples', store: 'edeka', rank: 2, emoji: '🍎', en: 'Apples', de: 'Äpfel', qty: '1 kg', price: null },
  { id: 'tomatoes', store: 'edeka', rank: 3, emoji: '🍅', en: 'Tomatoes', de: 'Tomaten', qty: '', price: null },
  { id: 'onions', store: 'edeka', rank: 4, emoji: '🧅', en: 'Onions', de: 'Zwiebeln', qty: '', price: null },
  { id: 'cucumber', store: 'edeka', rank: 5, emoji: '🥒', en: 'Cucumber', de: 'Gurke', qty: '', price: null },
  { id: 'bread', store: 'edeka', rank: 6, emoji: '🍞', en: 'Bread', de: 'Brot', qty: '', price: null },
  { id: 'pretzels', store: 'edeka', rank: 7, emoji: '🥨', en: 'Pretzels', de: 'Brezeln', qty: '4', price: null },
  { id: 'mince', store: 'edeka', rank: 8, emoji: '🥩', en: 'Minced meat', de: 'Hackfleisch', qty: '500 g', price: 499 },
  { id: 'milk', store: 'edeka', rank: 9, emoji: '🥛', en: 'Milk', de: 'Milch', qty: '2', price: null },
  { id: 'oatmilk', store: 'edeka', rank: 10, emoji: '🥤', en: 'Oat milk', de: 'Haferdrink', qty: '', price: null },
  { id: 'butter', store: 'edeka', rank: 11, emoji: '🧈', en: 'Butter', de: 'Butter', qty: '', price: null },
  { id: 'cheese', store: 'edeka', rank: 12, emoji: '🧀', en: 'Cheese', de: 'Käse', qty: '', price: null },
  { id: 'yogurt', store: 'edeka', rank: 13, emoji: '🥣', en: 'Yogurt', de: 'Joghurt', qty: '', price: null },
  { id: 'eggs', store: 'edeka', rank: 14, emoji: '🥚', en: 'Eggs', de: 'Eier', qty: '10', price: null },
  { id: 'pasta', store: 'edeka', rank: 15, emoji: '🍝', en: 'Pasta', de: 'Nudeln', qty: '', price: null },
  { id: 'flour', store: 'edeka', rank: 16, emoji: '🌾', en: 'Flour', de: 'Mehl', qty: '', price: null },
  { id: 'rice', store: 'edeka', rank: 17, emoji: '🍚', en: 'Rice', de: 'Reis', qty: '', price: null },
  { id: 'coffee', store: 'edeka', rank: 18, emoji: '☕', en: 'Coffee', de: 'Kaffee', qty: '', price: null },
  { id: 'chocolate', store: 'edeka', rank: 19, emoji: '🍫', en: 'Chocolate', de: 'Schokolade', qty: '', price: 129 },
  { id: 'pizza', store: 'edeka', rank: 20, emoji: '🍕', en: 'Frozen pizza', de: 'Tiefkühlpizza', qty: '2', price: 498 },
  { id: 'water', store: 'edeka', rank: 21, emoji: '💧', en: 'Sparkling water', de: 'Mineralwasser', qty: '6', price: null },
  { id: 'toothpaste', store: 'dm', rank: 1, emoji: '🪥', en: 'Toothpaste', de: 'Zahnpasta', qty: '', price: null },
  { id: 'shampoo', store: 'dm', rank: 2, emoji: '🧴', en: 'Shampoo', de: 'Shampoo', qty: '', price: 195 },
  { id: 'handcream', store: 'dm', rank: 3, emoji: '🧼', en: 'Hand cream', de: 'Handcreme', qty: '', price: null },
  { id: 'cottonpads', store: 'dm', rank: 4, emoji: null, en: 'Cotton pads', de: 'Wattepads', qty: '', price: null },
  { id: 'toiletpaper', store: 'dm', rank: 5, emoji: '🧻', en: 'Toilet paper', de: 'Toilettenpapier', qty: '', price: null },
];
export const byId = Object.fromEntries(items.map((i) => [i.id, i]));

// The open lists: long (EDEKA 8, dm 3) and short (5), and the bought bank, newest first.
export const lists = {
  long: ['cucumber', 'pretzels', 'mince', 'flour', 'rice', 'chocolate', 'pizza', 'water', 'shampoo', 'handcream', 'cottonpads'],
  short: ['cucumber', 'mince', 'chocolate', 'shampoo', 'handcream'],
};
export const bank = ['milk', 'bananas', 'bread', 'butter', 'eggs', 'coffee', 'toiletpaper', 'apples', 'pasta', 'tomatoes', 'cheese', 'yogurt', 'toothpaste', 'onions', 'oatmilk'];
// recentlyUsed() in app/lib/list/model.dart keeps the newest 20.
export const recentLimit = 20;

export const scenarios = ['short-0', 'short-3', 'short-15', 'long-0', 'long-3', 'long-15'];

// The item the frames and the acceptance check tick (priced, mid-EDEKA), and the recent one the back frame returns.
export const tickId = 'mince';
export const backId = 'bananas';

// hi: the item to highlight, in the list (`list`) or in the section (`recent`). folded: the section is closed.
// anim: a static phase of the tick animation for the strip ({ id, phase: 'start' | 'mid' }).
export const initial = (scenario, lang, { folded = false } = {}) => {
  const [size, n] = scenario.split('-');
  return { lang, open: [...lists[size]], recent: bank.slice(0, Number(n)), hi: null, folded, showAll: false, anim: null };
};

export const openIn = (s, store) => s.open.filter((id) => byId[id].store === store).sort((a, b) => byId[a].rank - byId[b].rank);
export const openOrder = (s) => stores.flatMap((x) => openIn(s, x.id));

export const act = (s0, a) => {
  const s = structuredClone(s0);
  const [verb, arg] = a.split(':');
  s.hi = null;
  s.anim = null;
  switch (verb) {
    case 'tick':
      s.open = s.open.filter((x) => x !== arg);
      s.recent = [arg, ...s.recent.filter((x) => x !== arg)].slice(0, recentLimit);
      s.hi = { id: arg, where: 'recent' };
      break;
    case 'back':
      s.recent = s.recent.filter((x) => x !== arg);
      if (!s.open.includes(arg)) s.open.push(arg);
      s.hi = { id: arg, where: 'list' };
      break;
    case 'fold':
      s.folded = !s.folded;
      break;
    case 'showAll':
      s.showAll = !s.showAll;
      break;
    default:
      throw new Error(`unknown action ${a}`);
  }
  return s;
};

// Money as the app writes it (en €6.38, de 6,38 €).
export const money = (lang, cents) => {
  const v = (cents / 100).toFixed(2);
  return lang === 'de' ? `${v.replace('.', ',')} €` : `€${v}`;
};

// TE1's summary of the open items: per store the priced sum and how many have no price.
export const summary = (s) => {
  const groups = stores.map((x) => {
    const mine = openIn(s, x.id);
    const priced = mine.filter((id) => byId[id].price !== null);
    return { store: x.id, name: x.name, cents: priced.reduce((a, id) => a + byId[id].price, 0), priced: priced.length, unpriced: mine.length - priced.length };
  }).filter((g) => g.priced + g.unpriced > 0);
  const total = groups.reduce((a, g) => ({ cents: a.cents + g.cents, priced: a.priced + g.priced, unpriced: a.unpriced + g.unpriced }), { cents: 0, priced: 0, unpriced: 0 });
  return { groups, total };
};
